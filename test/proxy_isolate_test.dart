import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kick/core/accounts/account_runtime_notice.dart';
import 'package:kick/data/models/oauth_tokens.dart';
import 'package:kick/proxy/account_pool/account_pool.dart';
import 'package:kick/proxy/engine/proxy_isolate.dart';
import 'package:kick/proxy/gemini/gemini_code_assist_client.dart';

void main() {
  OAuthTokens sampleTokens() => OAuthTokens(
    accessToken: 'token',
    refreshToken: 'refresh',
    expiry: DateTime.now().add(const Duration(hours: 1)),
    tokenType: 'Bearer',
    scope: null,
  );

  ProxyRuntimeAccount sampleAccount() => ProxyRuntimeAccount(
    id: 'account-1',
    label: 'Primary',
    email: 'user@example.com',
    projectId: 'project-1',
    enabled: true,
    priority: 0,
    notSupportedModels: <String>[],
    lastUsedAt: null,
    usageCount: 0,
    errorCount: 0,
    cooldownUntil: null,
    lastQuotaSnapshot: null,
    tokenRef: 'token-ref',
    tokens: sampleTokens(),
  );

  test('normalizeOpenAiCompatRequest injects google web search from headers', () {
    final normalized = normalizeOpenAiCompatRequest(
      body: {
        'model': 'gemini-3-flash-preview',
        'messages': [
          {'role': 'user', 'content': 'Find fresh Flutter news'},
        ],
      },
      headers: {'x-kick-web-search': 'true'},
    );

    expect(((normalized['extra_body'] as Map?)?['google'] as Map?)?['web_search'], isTrue);
  });

  test('normalizeOpenAiCompatRequest keeps explicit body setting over headers', () {
    final normalized = normalizeOpenAiCompatRequest(
      body: {'model': 'gemini-3-flash-preview', 'web_search': false},
      headers: {'x-kick-web-search': 'true'},
    );

    expect(((normalized['extra_body'] as Map?)?['google'] as Map?)?['web_search'], isFalse);
  });

  test('normalizeOpenAiCompatRequest applies default google web search when request is silent', () {
    final normalized = normalizeOpenAiCompatRequest(
      body: {
        'model': 'gemini-3-flash-preview',
        'messages': [
          {'role': 'user', 'content': 'Find fresh Flutter news'},
        ],
      },
      headers: const {},
      defaultGoogleWebSearchEnabled: true,
    );

    expect(((normalized['extra_body'] as Map?)?['google'] as Map?)?['web_search'], isTrue);
  });

  test('normalizeOpenAiCompatRequest does not apply default search when tools are present', () {
    final normalized = normalizeOpenAiCompatRequest(
      body: {
        'model': 'gemini-3-flash-preview',
        'tools': [
          {
            'type': 'function',
            'function': {
              'name': 'lookupWeather',
              'parameters': {'type': 'object'},
            },
          },
        ],
      },
      headers: const {},
      defaultGoogleWebSearchEnabled: true,
    );

    expect(normalized['extra_body'], isNull);
  });

  test('retryProxyPortBind retries transient bind races until the port is released', () async {
    var attempts = 0;

    final result = await retryProxyPortBind(() async {
      attempts += 1;
      if (attempts < 3) {
        throw const SocketException(
          'Failed to create server socket (OS Error: The shared flag to bind() needs to be '
          '`true` if binding multiple times on the same (address, port) combination.)',
        );
      }
      return 'bound';
    }, retryDelays: const <Duration>[Duration.zero, Duration.zero]);

    expect(result, 'bound');
    expect(attempts, 3);
  });

  test('retryProxyPortBind does not retry unrelated bind failures', () async {
    var attempts = 0;

    await expectLater(
      () => retryProxyPortBind(() async {
        attempts += 1;
        throw StateError('unexpected bind failure');
      }),
      throwsStateError,
    );

    expect(attempts, 1);
  });

  test('looksLikeProxyPortInUseError recognizes socket reuse failures', () {
    expect(
      looksLikeProxyPortInUseError(
        'Failed to create server socket: The shared flag to bind() needs to be true.',
      ),
      isTrue,
    );
    expect(looksLikeProxyPortInUseError('Permission denied while opening socket'), isFalse);
  });

  test('applyProxyAccountFailurePolicy does not cooldown accounts for transport failures', () {
    final account = sampleAccount();
    final pool = GeminiAccountPool([account]);

    applyProxyAccountFailurePolicy(
      pool: pool,
      account: account,
      requestedModel: 'gemini-3.1-pro-preview',
      error: GeminiGatewayException(
        kind: GeminiGatewayFailureKind.serviceUnavailable,
        message: 'Gemini request timed out while contacting Gemini Code Assist.',
        statusCode: 503,
        source: GeminiGatewayFailureSource.transport,
      ),
      mark429AsUnhealthy: false,
    );

    expect(account.errorCount, 1);
    expect(account.cooldownUntil, isNull);
  });

  test('applyProxyAccountFailurePolicy keeps upstream service unavailable cooldowns', () {
    final account = sampleAccount();
    final pool = GeminiAccountPool([account]);

    applyProxyAccountFailurePolicy(
      pool: pool,
      account: account,
      requestedModel: 'gemini-3.1-pro-preview',
      error: GeminiGatewayException(
        kind: GeminiGatewayFailureKind.serviceUnavailable,
        message: 'Service unavailable.',
        statusCode: 503,
        source: GeminiGatewayFailureSource.upstream,
      ),
      mark429AsUnhealthy: false,
    );

    expect(account.errorCount, 1);
    expect(account.cooldownUntil, isNotNull);
  });

  test(
    'applyProxyAccountFailurePolicy marks indefinite resource exhausted as pending ban check',
    () {
      final account = sampleAccount();
      final pool = GeminiAccountPool([account]);

      applyProxyAccountFailurePolicy(
        pool: pool,
        account: account,
        requestedModel: 'gemini-3.1-pro-preview',
        error: GeminiGatewayException(
          kind: GeminiGatewayFailureKind.quota,
          detail: GeminiGatewayFailureDetail.indefiniteQuotaExhausted,
          message: 'Resource has been exhausted (e.g. check quota).',
          statusCode: 429,
        ),
        mark429AsUnhealthy: false,
      );

      expect(account.errorCount, 0);
      expect(account.cooldownUntil, isNull);
      expect(account.lastQuotaSnapshot, buildBanCheckPendingSnapshot());
    },
  );
}
