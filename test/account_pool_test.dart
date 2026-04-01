import 'package:flutter_test/flutter_test.dart';
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/data/models/oauth_tokens.dart';
import 'package:kick/proxy/account_pool/account_pool.dart';

void main() {
  OAuthTokens sampleTokens() => OAuthTokens(
    accessToken: 'token',
    refreshToken: 'refresh',
    expiry: DateTime.now().add(const Duration(hours: 1)),
    tokenType: 'Bearer',
    scope: null,
  );

  test('prefers highest priority tier and then least recently used', () {
    final pool = GeminiAccountPool([
      ProxyRuntimeAccount(
        id: 'a',
        label: 'A',
        email: 'a@example.com',
        projectId: 'proj-a',
        provider: AccountProvider.gemini,
        enabled: true,
        priority: 5,
        notSupportedModels: [],
        lastUsedAt: DateTime.now(),
        usageCount: 2,
        errorCount: 0,
        cooldownUntil: null,
        lastQuotaSnapshot: null,
        tokenRef: 'a',
        tokens: sampleTokens(),
      ),
      ProxyRuntimeAccount(
        id: 'b',
        label: 'B',
        email: 'b@example.com',
        projectId: 'proj-b',
        provider: AccountProvider.gemini,
        enabled: true,
        priority: 5,
        notSupportedModels: [],
        lastUsedAt: DateTime.now().subtract(const Duration(hours: 1)),
        usageCount: 1,
        errorCount: 0,
        cooldownUntil: null,
        lastQuotaSnapshot: null,
        tokenRef: 'b',
        tokens: sampleTokens(),
      ),
      ProxyRuntimeAccount(
        id: 'c',
        label: 'C',
        email: 'c@example.com',
        projectId: 'proj-c',
        provider: AccountProvider.gemini,
        enabled: true,
        priority: 1,
        notSupportedModels: [],
        lastUsedAt: null,
        usageCount: 0,
        errorCount: 0,
        cooldownUntil: null,
        lastQuotaSnapshot: null,
        tokenRef: 'c',
        tokens: sampleTokens(),
      ),
    ]);

    final selected = pool.select('gemini-2.5-flash', provider: AccountProvider.gemini);

    expect(selected?.id, 'b');
  });

  test('treats model aliases as the same capability when filtering accounts', () {
    final pool = GeminiAccountPool([
      ProxyRuntimeAccount(
        id: 'alias',
        label: 'Alias blocked',
        email: 'alias@example.com',
        projectId: 'proj-alias',
        provider: AccountProvider.gemini,
        enabled: true,
        priority: 5,
        notSupportedModels: ['gemini-3-flash-preview'],
        lastUsedAt: null,
        usageCount: 0,
        errorCount: 0,
        cooldownUntil: null,
        lastQuotaSnapshot: null,
        tokenRef: 'alias',
        tokens: sampleTokens(),
      ),
    ]);

    expect(pool.select('gemini-3-flash', provider: AccountProvider.gemini), isNull);
  });

  test('prefers account without recent quota warning inside same priority tier', () {
    final pool = GeminiAccountPool([
      ProxyRuntimeAccount(
        id: 'quota-hit',
        label: 'Quota hit',
        email: 'quota@example.com',
        projectId: 'proj-quota',
        provider: AccountProvider.gemini,
        enabled: true,
        priority: 5,
        notSupportedModels: [],
        lastUsedAt: DateTime.now().subtract(const Duration(hours: 2)),
        usageCount: 0,
        errorCount: 1,
        cooldownUntil: null,
        lastQuotaSnapshot: 'Quota exhausted recently.',
        tokenRef: 'quota-hit',
        tokens: sampleTokens(),
      ),
      ProxyRuntimeAccount(
        id: 'healthy',
        label: 'Healthy',
        email: 'healthy@example.com',
        projectId: 'proj-healthy',
        provider: AccountProvider.gemini,
        enabled: true,
        priority: 5,
        notSupportedModels: [],
        lastUsedAt: DateTime.now().subtract(const Duration(minutes: 30)),
        usageCount: 5,
        errorCount: 0,
        cooldownUntil: null,
        lastQuotaSnapshot: null,
        tokenRef: 'healthy',
        tokens: sampleTokens(),
      ),
    ]);

    final selected = pool.select('gemini-2.5-flash', provider: AccountProvider.gemini);

    expect(selected?.id, 'healthy');
  });

  test('clears stale quota warning after a successful request', () {
    final account = ProxyRuntimeAccount(
      id: 'quota-hit',
      label: 'Quota hit',
      email: 'quota@example.com',
      projectId: 'proj-quota',
      provider: AccountProvider.gemini,
      enabled: true,
      priority: 5,
      notSupportedModels: [],
      lastUsedAt: null,
      usageCount: 0,
      errorCount: 1,
      cooldownUntil: null,
      lastQuotaSnapshot: 'Quota exhausted recently.',
      tokenRef: 'quota-hit',
      tokens: sampleTokens(),
    );
    final pool = GeminiAccountPool([account]);

    final changed = pool.markSuccess(account);

    expect(changed, isTrue);
    expect(account.lastQuotaSnapshot, isNull);
  });
}
