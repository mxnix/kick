import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/data/models/oauth_tokens.dart';
import 'package:kick/proxy/account_pool/account_pool.dart';
import 'package:kick/proxy/gemini/gemini_code_assist_client.dart';
import 'package:kick/proxy/kiro/kiro_auth_source.dart';
import 'package:kick/proxy/kiro/kiro_code_assist_client.dart';
import 'package:kick/proxy/kiro/kiro_embedded_system_prompt.dart';
import 'package:kick/proxy/openai/openai_request_parser.dart';
import 'package:kick/proxy/openai/openai_response_mapper.dart';

void main() {
  ProxyRuntimeAccount sampleAccount() {
    return ProxyRuntimeAccount(
      id: 'kiro-1',
      label: 'Kiro',
      email: 'Kiro local session',
      projectId: '',
      provider: AccountProvider.kiro,
      providerRegion: defaultKiroRegion,
      providerProfileArn: 'arn:aws:codewhisperer:us-east-1:123456789012:profile/test',
      enabled: true,
      priority: 0,
      notSupportedModels: const [],
      lastUsedAt: null,
      usageCount: 0,
      errorCount: 0,
      cooldownUntil: null,
      lastQuotaSnapshot: null,
      tokenRef: 'kiro-ref',
      tokens: OAuthTokens(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiry: DateTime.now().add(const Duration(hours: 1)),
        tokenType: 'Bearer',
        scope: null,
      ),
    );
  }

  UnifiedPromptRequest sampleRequest({
    String? model,
    String? systemInstruction,
    String? reasoningEffort,
    Map<String, Object?>? googleThinkingConfig,
    List<UnifiedTurn>? turns,
  }) {
    return UnifiedPromptRequest(
      requestId: 'req-1',
      model: model ?? 'kiro/claude-sonnet-4',
      stream: false,
      source: 'chat.completions',
      turns:
          turns ??
          [
            UnifiedTurn(role: 'user', parts: [UnifiedPart.text('Hello')]),
          ],
      tools: [],
      systemInstruction: systemInstruction,
      toolChoice: null,
      temperature: null,
      topP: null,
      maxOutputTokens: null,
      stopSequences: null,
      reasoningEffort: reasoningEffort,
      googleThinkingConfig: googleThinkingConfig,
      googleWebSearchEnabled: false,
      responseModalities: null,
      jsonMode: false,
      responseSchema: null,
    );
  }

  test('retries Kiro model discovery after a retryable HTTP error', () async {
    final waits = <Duration>[];
    var attempts = 0;
    final client = KiroCodeAssistClient(
      wait: (delay) async {
        waits.add(delay);
      },
      retryPolicy: const GeminiRetryPolicy(maxRetries: 1),
      httpClient: QueueHttpClient([
        (request) async {
          attempts += 1;
          expect(request.url.path, '/ListAvailableModels');
          expect(request.url.queryParameters['origin'], 'AI_EDITOR');
          expect(
            request.url.queryParameters['profileArn'],
            'arn:aws:codewhisperer:us-east-1:123456789012:profile/test',
          );
          return http.Response(jsonEncode({'message': 'Please retry in 12 seconds.'}), 429);
        },
        (request) async {
          attempts += 1;
          expect(request.url.path, '/ListAvailableModels');
          expect(request.url.queryParameters['origin'], 'AI_EDITOR');
          expect(
            request.url.queryParameters['profileArn'],
            'arn:aws:codewhisperer:us-east-1:123456789012:profile/test',
          );
          return http.Response(
            jsonEncode({
              'defaultModel': {'modelId': 'auto'},
              'models': [
                {'modelId': 'claude-sonnet-4'},
              ],
            }),
            200,
          );
        },
      ]),
    );

    final models = await client.listModels(account: sampleAccount());

    expect(models, ['auto', 'claude-sonnet-4']);
    expect(attempts, 2);
    expect(waits, [const Duration(seconds: 12)]);
  });

  test('persists refreshed desktop tokens for app-managed Kiro sources', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick_kiro_refresh_managed');
    addTearDown(() => tempDirectory.delete(recursive: true));
    final sourceFile = File('${tempDirectory.path}${Platform.pathSeparator}kiro-auth-managed.json');
    await sourceFile.writeAsString(
      jsonEncode({
        'accessToken': 'old-access',
        'refreshToken': 'old-refresh',
        'expiresAt': '2020-01-01T00:00:00Z',
        'region': defaultKiroRegion,
      }),
    );

    KiroAuthSourceSnapshot? persistedSnapshot;
    String? persistedPath;
    final client = KiroCodeAssistClient(
      managedSourcePathChecker: (_) async => true,
      authSourcePersister: (snapshot, {outputPath}) async {
        persistedSnapshot = snapshot;
        persistedPath = outputPath;
        return snapshot;
      },
      httpClient: QueueHttpClient([
        (request) async {
          expect(request.url.path, '/refreshToken');
          return http.Response(
            jsonEncode({'accessToken': 'new-access', 'refreshToken': 'new-refresh'}),
            200,
          );
        },
        (request) async {
          expect(request.url.path, '/ListAvailableModels');
          expect(request.headers['authorization'], 'Bearer new-access');
          return http.Response(
            jsonEncode({
              'models': [
                {'modelId': 'claude-sonnet-4'},
              ],
            }),
            200,
          );
        },
      ]),
    );
    final account = sampleAccount()
      ..credentialSourcePath = sourceFile.path
      ..tokens = OAuthTokens(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        expiry: DateTime.fromMillisecondsSinceEpoch(0),
        tokenType: 'Bearer',
        scope: null,
      );

    final models = await client.listModels(account: account);

    expect(models, ['claude-sonnet-4']);
    expect(account.tokens.accessToken, 'new-access');
    expect(account.tokens.refreshToken, 'new-refresh');
    expect(persistedPath, sourceFile.path);
    expect(persistedSnapshot?.accessToken, 'new-access');
    expect(persistedSnapshot?.refreshToken, 'new-refresh');
  });

  test('does not persist refreshed desktop tokens for external Kiro sources', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick_kiro_refresh_external');
    addTearDown(() => tempDirectory.delete(recursive: true));
    final sourceFile = File('${tempDirectory.path}${Platform.pathSeparator}external.json');
    await sourceFile.writeAsString(
      jsonEncode({
        'accessToken': 'old-access',
        'refreshToken': 'old-refresh',
        'expiresAt': '2020-01-01T00:00:00Z',
        'region': defaultKiroRegion,
      }),
    );

    var persistCount = 0;
    final client = KiroCodeAssistClient(
      managedSourcePathChecker: (_) async => false,
      authSourcePersister: (snapshot, {outputPath}) async {
        persistCount += 1;
        return snapshot;
      },
      httpClient: QueueHttpClient([
        (request) async {
          expect(request.url.path, '/refreshToken');
          return http.Response(
            jsonEncode({'accessToken': 'new-access', 'refreshToken': 'new-refresh'}),
            200,
          );
        },
        (request) async {
          expect(request.url.path, '/ListAvailableModels');
          return http.Response(
            jsonEncode({
              'models': [
                {'modelId': 'claude-sonnet-4'},
              ],
            }),
            200,
          );
        },
      ]),
    );
    final account = sampleAccount()
      ..credentialSourcePath = sourceFile.path
      ..tokens = OAuthTokens(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        expiry: DateTime.fromMillisecondsSinceEpoch(0),
        tokenType: 'Bearer',
        scope: null,
      );

    await client.listModels(account: account);

    expect(persistCount, 0);
    expect(jsonDecode(await sourceFile.readAsString())['accessToken'], 'old-access');
  });

  test(
    'maps background isolate messenger failures during Kiro refresh to a gateway error',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp('kick_kiro_refresh_isolate');
      addTearDown(() => tempDirectory.delete(recursive: true));
      final sourceFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}kiro-auth-managed.json',
      );
      await sourceFile.writeAsString(
        jsonEncode({
          'accessToken': 'old-access',
          'refreshToken': 'old-refresh',
          'expiresAt': '2020-01-01T00:00:00Z',
          'region': defaultKiroRegion,
        }),
      );

      final client = KiroCodeAssistClient(
        managedSourcePathChecker: (_) async {
          throw StateError(
            'Bad state: The BackgroundIsolateBinaryMessenger.instance value is invalid until '
            'BackgroundIsolateBinaryMessenger.ensureInitialized is executed.',
          );
        },
        httpClient: QueueHttpClient([
          (request) async {
            expect(request.url.path, '/refreshToken');
            return http.Response(
              jsonEncode({'accessToken': 'new-access', 'refreshToken': 'new-refresh'}),
              200,
            );
          },
        ]),
      );
      final account = sampleAccount()
        ..credentialSourcePath = sourceFile.path
        ..tokens = OAuthTokens(
          accessToken: 'old-access',
          refreshToken: 'old-refresh',
          expiry: DateTime.fromMillisecondsSinceEpoch(0),
          tokenType: 'Bearer',
          scope: null,
        );

      await expectLater(
        client.generateContent(account: account, request: sampleRequest()),
        throwsA(
          isA<GeminiGatewayException>()
              .having((error) => error.provider, 'provider', AccountProvider.kiro)
              .having((error) => error.kind, 'kind', GeminiGatewayFailureKind.serviceUnavailable)
              .having((error) => error.statusCode, 'statusCode', 503)
              .having(
                (error) => error.message,
                'message',
                'Kiro credential storage is unavailable in the proxy runtime.',
              ),
        ),
      );
    },
  );

  test(
    'returns an empty discovery list instead of a stale fallback when Kiro omits models',
    () async {
      final client = KiroCodeAssistClient(
        httpClient: QueueHttpClient([
          (request) async {
            expect(request.url.path, '/ListAvailableModels');
            return http.Response(jsonEncode({'models': <Object?>[]}), 200);
          },
        ]),
      );

      final models = await client.listModels(account: sampleAccount());

      expect(models, isEmpty);
    },
  );

  test('merges paginated Kiro model discovery results', () async {
    final client = KiroCodeAssistClient(
      httpClient: QueueHttpClient([
        (request) async {
          expect(request.url.path, '/ListAvailableModels');
          expect(request.url.queryParameters['origin'], 'AI_EDITOR');
          expect(request.url.queryParameters['nextToken'], isNull);
          return http.Response(
            jsonEncode({
              'defaultModel': {'modelId': 'auto'},
              'models': [
                {'modelId': 'claude-sonnet-4'},
              ],
              'nextToken': 'page-2',
            }),
            200,
          );
        },
        (request) async {
          expect(request.url.path, '/ListAvailableModels');
          expect(request.url.queryParameters['origin'], 'AI_EDITOR');
          expect(request.url.queryParameters['nextToken'], 'page-2');
          return http.Response(
            jsonEncode({
              'models': [
                {'modelId': 'claude-sonnet-4.5'},
                {'modelId': 'deepseek-3.2'},
              ],
            }),
            200,
          );
        },
      ]),
    );

    final models = await client.listModels(account: sampleAccount());

    expect(models, ['auto', 'claude-sonnet-4', 'claude-sonnet-4.5', 'deepseek-3.2']);
  });

  test('retries Kiro generation after upstream service unavailable', () async {
    final waits = <Duration>[];
    var attempts = 0;
    final client = KiroCodeAssistClient(
      wait: (delay) async {
        waits.add(delay);
      },
      retryPolicy: const GeminiRetryPolicy(maxRetries: 1, baseDelay: Duration(seconds: 2)),
      httpClient: QueueHttpClient([
        (request) async {
          attempts += 1;
          expect(request.url.path, '/generateAssistantResponse');
          return http.Response(jsonEncode({'message': 'service unavailable'}), 503);
        },
        (request) async {
          attempts += 1;
          expect(request.url.path, '/generateAssistantResponse');
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"content":"Hello from Kiro"}')),
            200,
          );
        },
      ]),
    );

    final response = await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(),
    );

    expect(OpenAiResponseMapper.currentText(response), 'Hello from Kiro');
    expect(attempts, 2);
    expect(waits, [const Duration(seconds: 2)]);
  });

  test('fails Kiro generation when upstream closes without output', () async {
    final client = KiroCodeAssistClient(
      httpClient: QueueHttpClient([
        (request) async {
          expect(request.url.path, '/generateAssistantResponse');
          return http.StreamedResponse(Stream<List<int>>.empty(), 200);
        },
      ]),
    );

    await expectLater(
      client.generateContent(account: sampleAccount(), request: sampleRequest()),
      throwsA(
        isA<GeminiGatewayException>()
            .having((error) => error.kind, 'kind', GeminiGatewayFailureKind.serviceUnavailable)
            .having((error) => error.statusCode, 'statusCode', 502)
            .having(
              (error) => error.message,
              'message',
              'Kiro streaming request completed without response data.',
            ),
      ),
    );
  });

  test('injects the hardcoded Kiro prompt only for Claude models', () async {
    late Map<String, Object?> capturedBody;
    final client = KiroCodeAssistClient(
      httpClient: QueueHttpClient([
        (request) async {
          final typedRequest = request as http.Request;
          capturedBody = (jsonDecode(typedRequest.body) as Map).cast<String, Object?>();
          expect(request.url.path, '/generateAssistantResponse');
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"content":"Hello from Kiro"}')),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(systemInstruction: 'Follow repository conventions.'),
    );

    final conversationState = (capturedBody['conversationState'] as Map).cast<String, Object?>();
    final currentMessage = (conversationState['currentMessage'] as Map).cast<String, Object?>();
    final userInputMessage = (currentMessage['userInputMessage'] as Map).cast<String, Object?>();
    final content = userInputMessage['content'] as String;
    final embeddedPrompt = kiroEmbeddedSystemPrompt.trim();

    expect(content, contains(embeddedPrompt));
    expect(
      content.indexOf('Follow repository conventions.'),
      lessThan(content.indexOf(embeddedPrompt)),
    );
    expect(content.indexOf(embeddedPrompt), lessThan(content.indexOf('Hello')));
  });

  test('does not inject the hardcoded Kiro prompt for non-Claude models', () async {
    late Map<String, Object?> capturedBody;
    final client = KiroCodeAssistClient(
      httpClient: QueueHttpClient([
        (request) async {
          final typedRequest = request as http.Request;
          capturedBody = (jsonDecode(typedRequest.body) as Map).cast<String, Object?>();
          expect(request.url.path, '/generateAssistantResponse');
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"content":"Hello from Kiro"}')),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(
        model: 'kiro/deepseek-3.2',
        systemInstruction: 'Follow repository conventions.',
      ),
    );

    final conversationState = (capturedBody['conversationState'] as Map).cast<String, Object?>();
    final currentMessage = (conversationState['currentMessage'] as Map).cast<String, Object?>();
    final userInputMessage = (currentMessage['userInputMessage'] as Map).cast<String, Object?>();
    final content = userInputMessage['content'] as String;
    final embeddedPrompt = kiroEmbeddedSystemPrompt.trim();

    expect(content, contains('Follow repository conventions.'));
    expect(content, contains('Hello'));
    expect(content, isNot(contains(embeddedPrompt)));
  });

  test('does not inject the hardcoded Kiro prompt for auto model', () async {
    late Map<String, Object?> capturedBody;
    final client = KiroCodeAssistClient(
      httpClient: QueueHttpClient([
        (request) async {
          final typedRequest = request as http.Request;
          capturedBody = (jsonDecode(typedRequest.body) as Map).cast<String, Object?>();
          expect(request.url.path, '/generateAssistantResponse');
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"content":"Hello from Kiro"}')),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(
        model: 'kiro/auto',
        systemInstruction: 'Follow repository conventions.',
      ),
    );

    final conversationState = (capturedBody['conversationState'] as Map).cast<String, Object?>();
    final currentMessage = (conversationState['currentMessage'] as Map).cast<String, Object?>();
    final userInputMessage = (currentMessage['userInputMessage'] as Map).cast<String, Object?>();
    final content = userInputMessage['content'] as String;
    final embeddedPrompt = kiroEmbeddedSystemPrompt.trim();

    expect(content, contains('Follow repository conventions.'));
    expect(content, contains('Hello'));
    expect(content, isNot(contains(embeddedPrompt)));
  });

  test('derives usage metadata from Kiro context usage events', () async {
    final client = KiroCodeAssistClient(
      httpClient: QueueHttpClient([
        (request) async {
          expect(request.url.path, '/generateAssistantResponse');
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable([
              utf8.encode('\u0000\u0000{"content":"Hello from Kiro"}'),
              utf8.encode('\u0000\u0000{"contextUsagePercentage":17.136499404907227}'),
            ]),
            200,
          );
        },
      ]),
    );

    final response = await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(),
    );

    expect(OpenAiResponseMapper.currentText(response), 'Hello from Kiro');
    expect(OpenAiResponseMapper.currentPromptTokenCount(response), greaterThan(0));
    expect(OpenAiResponseMapper.currentCompletionTokenCount(response), greaterThan(0));
    expect(
      OpenAiResponseMapper.currentTotalTokenCount(response),
      greaterThan(OpenAiResponseMapper.currentCompletionTokenCount(response)!),
    );
    expect(OpenAiResponseMapper.currentCachedTokenCount(response), 0);
    expect(OpenAiResponseMapper.currentReasoningTokenCount(response), 0);
  });

  test('suppresses Kiro reasoning output unless reasoning is explicitly requested', () async {
    final client = KiroCodeAssistClient(
      httpClient: QueueHttpClient([
        (request) async {
          expect(request.url.path, '/generateAssistantResponse');
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable([
              utf8.encode('\u0000\u0000{"text":"Plan first.","signature":"sig-1"}'),
              utf8.encode('\u0000\u0000{"content":"Done."}'),
            ]),
            200,
          );
        },
      ]),
    );

    final response = await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(),
    );

    expect(OpenAiResponseMapper.currentText(response), 'Done.');
    expect(OpenAiResponseMapper.currentReasoningText(response), isEmpty);
    expect(OpenAiResponseMapper.currentReasoningTokenCount(response), greaterThan(0));

    final chatCompletion = OpenAiResponseMapper.toChatCompletion(
      requestId: 'req-1',
      model: 'kiro/claude-sonnet-4',
      payload: response,
    );
    final choices = (chatCompletion['choices'] as List).cast<Map<String, Object?>>();
    final message = (choices.single['message'] as Map).cast<String, Object?>();

    expect(message.containsKey('reasoning_content'), isFalse);
    expect(message.containsKey('reasoning_signature'), isFalse);
    expect(message['content'], 'Done.');
  });

  test('maps Kiro reasoning stream events when reasoning effort is enabled', () async {
    final client = KiroCodeAssistClient(
      httpClient: QueueHttpClient([
        (request) async {
          expect(request.url.path, '/generateAssistantResponse');
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable([
              utf8.encode('\u0000\u0000{"text":"Plan first.","signature":"sig-1"}'),
              utf8.encode('\u0000\u0000{"content":"Done."}'),
            ]),
            200,
          );
        },
      ]),
    );

    final response = await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(reasoningEffort: 'high'),
    );

    expect(OpenAiResponseMapper.currentReasoningText(response), 'Plan first.');
    expect(OpenAiResponseMapper.currentText(response), 'Done.');
    expect(OpenAiResponseMapper.currentReasoningTokenCount(response), greaterThan(0));

    final chatCompletion = OpenAiResponseMapper.toChatCompletion(
      requestId: 'req-1',
      model: 'kiro/claude-sonnet-4',
      payload: response,
    );
    final choices = (chatCompletion['choices'] as List).cast<Map<String, Object?>>();
    final message = (choices.single['message'] as Map).cast<String, Object?>();

    expect(message['reasoning_content'], 'Plan first.');
    expect(message['reasoning_signature'], 'sig-1');
    expect(message['content'], 'Done.');
  });

  test('keeps Kiro total token usage at least as large as completion usage', () async {
    final client = KiroCodeAssistClient(
      httpClient: QueueHttpClient([
        (request) async {
          expect(request.url.path, '/generateAssistantResponse');
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable([
              utf8.encode('\u0000\u0000{"content":"Hello from Kiro"}'),
              utf8.encode('\u0000\u0000{"contextUsagePercentage":0.001}'),
            ]),
            200,
          );
        },
      ]),
    );

    final response = await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(),
    );
    final completionTokens = OpenAiResponseMapper.currentCompletionTokenCount(response)!;

    expect(OpenAiResponseMapper.currentPromptTokenCount(response), 0);
    expect(OpenAiResponseMapper.currentTotalTokenCount(response), completionTokens);
  });
}

class QueueHttpClient extends http.BaseClient {
  QueueHttpClient(this._handlers);

  final List<Future<http.BaseResponse> Function(http.BaseRequest request)> _handlers;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_handlers.isEmpty) {
      throw StateError('No queued HTTP responses left.');
    }

    final response = await _handlers.removeAt(0)(request);
    if (response is http.StreamedResponse) {
      return response;
    }
    if (response is http.Response) {
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
        reasonPhrase: response.reasonPhrase,
        request: request,
      );
    }
    throw StateError('Unsupported response type: ${response.runtimeType}');
  }
}
