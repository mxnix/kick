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
    List<UnifiedToolDeclaration>? tools,
    int? maxOutputTokens,
  }) {
    return UnifiedPromptRequest(
      requestId: 'req-1',
      model: model ?? 'kiro/claude-sonnet-4',
      stream: false,
      source: 'chat.completions',
      turns:
          turns ??
          [
            const UnifiedTurn(role: 'user', parts: [UnifiedPart.text('Hello')]),
          ],
      tools: tools ?? [],
      systemInstruction: systemInstruction,
      toolChoice: null,
      temperature: null,
      topP: null,
      maxOutputTokens: maxOutputTokens,
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

  test('maps public Claude aliases to Kiro upstream model ids', () async {
    late Map<String, Object?> capturedBody;
    final client = KiroCodeAssistClient(
      httpClient: QueueHttpClient([
        (request) async {
          final typedRequest = request as http.Request;
          capturedBody = (jsonDecode(typedRequest.body) as Map).cast<String, Object?>();
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"content":"Hello from Kiro"}')),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(model: 'kiro/claude-opus-4-7'),
    );

    final conversationState = (capturedBody['conversationState'] as Map).cast<String, Object?>();
    final currentMessage = (conversationState['currentMessage'] as Map).cast<String, Object?>();
    final userInputMessage = (currentMessage['userInputMessage'] as Map).cast<String, Object?>();

    expect(userInputMessage['modelId'], 'claude-opus-4.7');
  });

  test('maps auto to the Kiro simple task model', () async {
    late Map<String, Object?> capturedBody;
    final client = KiroCodeAssistClient(
      httpClient: QueueHttpClient([
        (request) async {
          final typedRequest = request as http.Request;
          capturedBody = (jsonDecode(typedRequest.body) as Map).cast<String, Object?>();
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"content":"Hello from Kiro"}')),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(model: 'kiro/auto'),
    );

    final conversationState = (capturedBody['conversationState'] as Map).cast<String, Object?>();
    final currentMessage = (conversationState['currentMessage'] as Map).cast<String, Object?>();
    final userInputMessage = (currentMessage['userInputMessage'] as Map).cast<String, Object?>();

    expect(userInputMessage['modelId'], 'simple-task');
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
          return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
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
    expect(OpenAiResponseMapper.currentFinishReason(response), 'stop');
  });

  test('marks Kiro content-only streams as length-truncated', () async {
    final client = KiroCodeAssistClient(
      httpClient: QueueHttpClient([
        (request) async {
          expect(request.url.path, '/generateAssistantResponse');
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"content":"Partial Kiro output"}')),
            200,
          );
        },
      ]),
    );

    final response = await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(),
    );

    expect(OpenAiResponseMapper.currentText(response), 'Partial Kiro output');
    expect(OpenAiResponseMapper.currentFinishReason(response), 'length');
    final metadata = (response['kiroMetadata'] as Map).cast<String, Object?>();
    expect(metadata['stream_completed_normally'], isFalse);
    expect(metadata['content_truncated'], isTrue);
  });

  test('uses Kiro usage events as normal stream completion signals', () async {
    final client = KiroCodeAssistClient(
      httpClient: QueueHttpClient([
        (request) async {
          expect(request.url.path, '/generateAssistantResponse');
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable([
              utf8.encode('\u0000\u0000{"content":"Done."}'),
              utf8.encode('\u0000\u0000{"followupPrompt":"next?"}'),
              utf8.encode('\u0000\u0000{"usage":{"credits":1}}'),
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
    expect(OpenAiResponseMapper.currentFinishReason(response), 'stop');
    final metadata = (response['kiroMetadata'] as Map).cast<String, Object?>();
    expect(metadata['usage_seen'], isTrue);
    expect(metadata['followup_prompt_seen'], isTrue);
    expect(metadata['content_truncated'], isFalse);
  });

  test('trims oversized Kiro history payloads before sending upstream', () async {
    late String capturedBody;
    final client = KiroCodeAssistClient(
      httpClient: QueueHttpClient([
        (request) async {
          final typedRequest = request as http.Request;
          capturedBody = typedRequest.body;
          expect(utf8.encode(capturedBody).length, lessThanOrEqualTo(600000));
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable([
              utf8.encode('{"content":"Trimmed."}'),
              utf8.encode('{"contextUsagePercentage":1}'),
            ]),
            200,
          );
        },
      ]),
    );
    final largeText = List.filled(20000, 'x').join();
    final turns = <UnifiedTurn>[
      for (var index = 0; index < 70; index += 1)
        UnifiedTurn(
          role: index.isEven ? 'user' : 'assistant',
          parts: [UnifiedPart.text('history-$index $largeText')],
        ),
      const UnifiedTurn(role: 'user', parts: [UnifiedPart.text('current')]),
    ];

    final response = await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(model: 'kiro/deepseek-3.2', turns: turns),
    );

    final decoded = (jsonDecode(capturedBody) as Map).cast<String, Object?>();
    final conversationState = (decoded['conversationState'] as Map).cast<String, Object?>();
    final history = (conversationState['history'] as List?) ?? const [];
    expect(history.length, lessThan(turns.length - 1));
    expect(OpenAiResponseMapper.currentText(response), 'Trimmed.');
  });

  test('inlines orphaned Kiro tool results instead of sending structured toolResults', () async {
    late Map<String, Object?> capturedBody;
    final client = KiroCodeAssistClient(
      httpClient: QueueHttpClient([
        (request) async {
          final typedRequest = request as http.Request;
          capturedBody = (jsonDecode(typedRequest.body) as Map).cast<String, Object?>();
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable([
              utf8.encode('{"content":"OK"}'),
              utf8.encode('{"contextUsagePercentage":1}'),
            ]),
            200,
          );
        },
      ]),
    );
    const tools = [
      UnifiedToolDeclaration(name: 'lookup', description: '', parameters: {'type': 'object'}),
    ];

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(
        tools: tools,
        turns: const [
          UnifiedTurn(
            role: 'user',
            parts: [
              UnifiedPart.functionResponse(
                callId: 'missing-call',
                name: 'lookup',
                arguments: {'result': 'orphaned'},
              ),
            ],
          ),
        ],
      ),
    );

    final conversationState = (capturedBody['conversationState'] as Map).cast<String, Object?>();
    final currentMessage = (conversationState['currentMessage'] as Map).cast<String, Object?>();
    final userInputMessage = (currentMessage['userInputMessage'] as Map).cast<String, Object?>();
    final context = (userInputMessage['userInputMessageContext'] as Map).cast<String, Object?>();

    expect(userInputMessage['content'], contains('[Tool Result: lookup]'));
    expect(userInputMessage['content'], contains('orphaned'));
    expect(context['tools'], isA<List>());
    expect(context.containsKey('toolResults'), isFalse);
  });

  test('keeps paired Kiro tool results structured', () async {
    late Map<String, Object?> capturedBody;
    final client = KiroCodeAssistClient(
      httpClient: QueueHttpClient([
        (request) async {
          final typedRequest = request as http.Request;
          capturedBody = (jsonDecode(typedRequest.body) as Map).cast<String, Object?>();
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable([
              utf8.encode('{"content":"OK"}'),
              utf8.encode('{"contextUsagePercentage":1}'),
            ]),
            200,
          );
        },
      ]),
    );
    const tools = [
      UnifiedToolDeclaration(name: 'lookup', description: '', parameters: {'type': 'object'}),
    ];

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(
        tools: tools,
        turns: const [
          UnifiedTurn(
            role: 'assistant',
            parts: [
              UnifiedPart.functionCall(callId: 'call-1', name: 'lookup', arguments: {'q': 'x'}),
            ],
          ),
          UnifiedTurn(
            role: 'user',
            parts: [
              UnifiedPart.functionResponse(
                callId: 'call-1',
                name: 'lookup',
                arguments: {'result': 'paired'},
              ),
            ],
          ),
        ],
      ),
    );

    final conversationState = (capturedBody['conversationState'] as Map).cast<String, Object?>();
    final currentMessage = (conversationState['currentMessage'] as Map).cast<String, Object?>();
    final userInputMessage = (currentMessage['userInputMessage'] as Map).cast<String, Object?>();
    final context = (userInputMessage['userInputMessageContext'] as Map).cast<String, Object?>();
    final toolResults = (context['toolResults'] as List).cast<Map>();

    expect(userInputMessage['content'], isNot(contains('[Tool Result: lookup]')));
    expect(toolResults.single['toolUseId'], 'call-1');
  });

  test('rejects Kiro tool declarations with names longer than Kiro accepts', () async {
    final client = KiroCodeAssistClient(httpClient: QueueHttpClient([]));
    final longName = List.filled(65, 'a').join();

    await expectLater(
      client.generateContent(
        account: sampleAccount(),
        request: sampleRequest(
          tools: [
            UnifiedToolDeclaration(
              name: longName,
              description: '',
              parameters: const {'type': 'object'},
            ),
          ],
        ),
      ),
      throwsA(
        isA<GeminiGatewayException>()
            .having((error) => error.provider, 'provider', AccountProvider.kiro)
            .having((error) => error.kind, 'kind', GeminiGatewayFailureKind.invalidRequest)
            .having((error) => error.statusCode, 'statusCode', 400),
      ),
    );
  });

  test('exposes Kiro reasoning output separately from response text', () async {
    final client = KiroCodeAssistClient(
      httpClient: QueueHttpClient([
        (request) async {
          expect(request.url.path, '/generateAssistantResponse');
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable([
              utf8.encode('\u0000\u0000{"contextUsagePercentage":17.136499404907227}'),
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
    expect(OpenAiResponseMapper.currentReasoningText(response), 'Plan first.');
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

  test('streams Kiro reasoning as OpenAI reasoning deltas by default', () async {
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

    final stream = await client.generateContentStream(
      account: sampleAccount(),
      request: sampleRequest(),
    );
    final deltas = <Map<String, Object?>>[];
    var includeRole = true;
    var previousText = '';
    var previousReasoningText = '';
    var previousToolCallCount = 0;

    await for (final payload in stream) {
      deltas.addAll(
        OpenAiResponseMapper.toChatStreamDeltas(
          requestId: 'req-1',
          model: 'kiro/claude-sonnet-4',
          payload: payload,
          includeRole: includeRole,
          previousText: previousText,
          previousReasoningText: previousReasoningText,
          previousToolCallCount: previousToolCallCount,
        ),
      );
      includeRole = false;
      previousText = OpenAiResponseMapper.currentText(payload);
      previousReasoningText = OpenAiResponseMapper.currentReasoningText(payload);
      previousToolCallCount = OpenAiResponseMapper.currentToolCallCount(payload);
    }

    final deltaObjects = deltas
        .map(
          (event) =>
              (((event['choices'] as List).single as Map)['delta'] as Map).cast<String, Object?>(),
        )
        .toList();

    expect(deltaObjects.where((delta) => delta.containsKey('reasoning_content')).toList(), [
      {'reasoning_content': 'Plan first.'},
    ]);
    expect(deltaObjects.where((delta) => delta.containsKey('content')).toList(), [
      {'content': 'Done.'},
    ]);
    expect(
      deltaObjects.any(
        (delta) => delta['content'] == '[Upstream returned an empty response. Please retry.]',
      ),
      isFalse,
    );
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

  test('maps Kiro payment-required quota responses to quota failures', () {
    final error = decodeKiroGatewayError(
      402,
      jsonEncode({'message': 'Usage limit exceeded for this account.'}),
    );

    expect(error.provider, AccountProvider.kiro);
    expect(error.kind, GeminiGatewayFailureKind.quota);
    expect(error.detail, GeminiGatewayFailureDetail.quotaExhausted);
    expect(error.quotaSnapshot, 'Usage limit exceeded for this account.');
    expect(error.retryAfter, isNotNull);
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
