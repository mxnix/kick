import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/data/models/oauth_tokens.dart';
import 'package:kick/proxy/account_pool/account_pool.dart';
import 'package:kick/proxy/gemini/gemini_auth_constants.dart';
import 'package:kick/proxy/gemini/gemini_client_fingerprint.dart';
import 'package:kick/proxy/gemini/gemini_code_assist_client.dart';
import 'package:kick/proxy/gemini/gemini_installation_identity.dart';
import 'package:kick/proxy/openai/openai_request_parser.dart';
import 'package:kick/proxy/openai/openai_response_mapper.dart';

void main() {
  String expectedMetadataPlatform() {
    final expectedPlatform = Platform.isWindows
        ? 'win32'
        : Platform.isMacOS
        ? 'darwin'
        : Platform.operatingSystem;
    final currentAbi = Abi.current().toString();
    final separatorIndex = currentAbi.indexOf('_');
    final expectedArchitecture = separatorIndex == -1 || separatorIndex == currentAbi.length - 1
        ? currentAbi
        : currentAbi.substring(separatorIndex + 1);

    if (expectedPlatform == 'darwin' && expectedArchitecture == 'x64') {
      return 'DARWIN_AMD64';
    }
    if (expectedPlatform == 'darwin' && expectedArchitecture == 'arm64') {
      return 'DARWIN_ARM64';
    }
    if (expectedPlatform == 'linux' && expectedArchitecture == 'x64') {
      return 'LINUX_AMD64';
    }
    if (expectedPlatform == 'linux' && expectedArchitecture == 'arm64') {
      return 'LINUX_ARM64';
    }
    if (expectedPlatform == 'win32' && expectedArchitecture == 'x64') {
      return 'WINDOWS_AMD64';
    }
    return 'PLATFORM_UNSPECIFIED';
  }

  ProxyRuntimeAccount sampleAccount({String projectId = 'project-1', OAuthTokens? tokens}) =>
      ProxyRuntimeAccount(
        id: 'account-1',
        label: 'Primary',
        email: 'user@example.com',
        projectId: projectId,
        provider: AccountProvider.gemini,
        enabled: true,
        priority: 0,
        notSupportedModels: const [],
        lastUsedAt: null,
        usageCount: 0,
        errorCount: 0,
        cooldownUntil: null,
        lastQuotaSnapshot: null,
        tokenRef: 'token-ref',
        tokens:
            tokens ??
            OAuthTokens(
              accessToken: 'access-token',
              refreshToken: 'refresh-token',
              expiry: DateTime.now().add(const Duration(hours: 1)),
              tokenType: 'Bearer',
              scope: null,
            ),
      );

  UnifiedPromptRequest sampleRequest({
    String requestId = 'req123',
    String model = 'gemini-2.5-pro',
    bool stream = false,
    int? maxOutputTokens = 256,
    List<UnifiedTurn>? turns,
    List<UnifiedToolDeclaration> tools = const [],
    List<String>? stopSequences,
    String? reasoningEffort,
    Map<String, Object?>? googleThinkingConfig,
    List<String>? responseModalities,
  }) {
    return UnifiedPromptRequest(
      requestId: requestId,
      model: model,
      stream: stream,
      source: 'chat.completions',
      turns:
          turns ??
          const [
            UnifiedTurn(role: 'user', parts: [UnifiedPart.text('Hello')]),
          ],
      tools: tools,
      systemInstruction: 'You are helpful.',
      toolChoice: null,
      temperature: 0.2,
      topP: null,
      maxOutputTokens: maxOutputTokens,
      stopSequences: stopSequences,
      reasoningEffort: reasoningEffort,
      googleThinkingConfig: googleThinkingConfig,
      googleWebSearchEnabled: false,
      responseModalities: responseModalities,
      jsonMode: false,
      responseSchema: null,
    );
  }

  test('discovers Gemini models from retrieveUserQuota buckets', () async {
    Map<String, Object?>? requestBody;
    Map<String, String>? requestHeaders;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          expect(request.url.path, '/v1internal:retrieveUserQuota');
          requestHeaders = request.headers;
          requestBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'buckets': [
                {'modelId': 'models/gemini-3.1-pro-preview'},
                {'modelId': 'gemini-2.5-flash'},
                {'modelId': 'gemini-2.5-flash'},
                {'modelId': ''},
              ],
            }),
            200,
          );
        },
      ]),
    );

    final models = await client.listModels(account: sampleAccount());

    expect(models, ['gemini-2.5-flash', 'gemini-3.1-pro-preview']);
    expect(requestBody, {'project': 'project-1'});
    expect(
      requestHeaders?[HttpHeaders.userAgentHeader],
      contains('/$geminiCodeAssistAuxiliaryHeaderModel '),
    );
  });

  test('returns an empty Gemini discovery list when retrieveUserQuota omits buckets', () async {
    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          expect(request.url.path, '/v1internal:retrieveUserQuota');
          return http.Response('{}', 200);
        },
      ]),
    );

    final models = await client.listModels(account: sampleAccount());

    expect(models, isEmpty);
  });

  test('builds Code Assist session and prompt identifiers', () async {
    Map<String, Object?>? capturedBody;
    Map<String, String>? capturedHeaders;
    String? capturedPath;
    const sessionId = '11111111-1111-4111-8111-111111111111';

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      createSessionId: () => sessionId,
      privilegedUserIdLoader: GeminiInstallationIdLoader(createUuid: () => 'privileged-user-1'),
      httpClient: QueueHttpClient([
        (request) async {
          capturedPath = request.url.path;
          capturedHeaders = request.headers;
          final body = await request.finalize().bytesToString();
          capturedBody = jsonDecode(body) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'Hi'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(requestId: 'abc123'),
    );

    expect(capturedPath, '/v1internal:generateContent');
    expect(capturedBody?['user_prompt_id'], '$sessionId########0');
    final nestedRequest = (capturedBody?['request'] as Map?)?.cast<String, Object?>();
    expect(nestedRequest?['session_id'], sessionId);
    expect(capturedBody?['project'], 'project-1');
    final expectedPlatform = Platform.isWindows
        ? 'win32'
        : Platform.isMacOS
        ? 'darwin'
        : Platform.operatingSystem;
    final currentAbi = Abi.current().toString();
    final separatorIndex = currentAbi.indexOf('_');
    final expectedArchitecture = separatorIndex == -1 || separatorIndex == currentAbi.length - 1
        ? currentAbi
        : currentAbi.substring(separatorIndex + 1);
    expect(
      capturedHeaders?[HttpHeaders.userAgentHeader],
      '$geminiCodeAssistUserAgentPrefix/$geminiCodeAssistCliVersion/gemini-2.5-pro '
      '($expectedPlatform; $expectedArchitecture; ${determineGeminiCliSurface()}) '
      'google-api-nodejs-client/$geminiCodeAssistGoogleApiNodeClientVersion',
    );
    expect(capturedBody?.containsKey('metadata'), isFalse);
    expect(capturedHeaders?['x-goog-api-client'], geminiCodeAssistGoogApiClientHeader);
    expect(capturedHeaders?.containsKey('x-gemini-api-privileged-user-id'), isFalse);
  });

  test('starts the prompt turn counter from zero for each new session', () async {
    final capturedBodies = <Map<String, Object?>>[];
    final sessionIds = <String>[
      '44444444-4444-4444-8444-444444444444',
      '55555555-5555-4555-8555-555555555555',
    ];
    var sessionIndex = 0;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      createSessionId: () => sessionIds[sessionIndex++],
      httpClient: QueueHttpClient([
        (request) async {
          capturedBodies.add(
            jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>,
          );
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
        (request) async {
          capturedBodies.add(
            jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>,
          );
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(requestId: 'first'),
    );
    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(requestId: 'second'),
    );

    expect(capturedBodies, hasLength(2));
    expect(capturedBodies[0]['user_prompt_id'], '${sessionIds[0]}########0');
    expect(capturedBodies[1]['user_prompt_id'], '${sessionIds[1]}########0');
    expect(((capturedBodies[0]['request'] as Map)['session_id']), sessionIds[0]);
    expect(((capturedBodies[1]['request'] as Map)['session_id']), sessionIds[1]);
  });

  test('sends a health-check setup payload when probing account restrictions', () async {
    Map<String, Object?>? loadCodeAssistBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          expect(request.url.path, '/v1internal:loadCodeAssist');
          loadCodeAssistBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'currentTier': {'id': 'standard-tier'},
            }),
            200,
          );
        },
      ]),
    );

    final violation = await client.probeTermsOfServiceViolation(account: sampleAccount());

    expect(violation, isNull);
    expect(loadCodeAssistBody, {
      'cloudaicompanionProject': 'project-1',
      'metadata': {
        'ideType': geminiCodeAssistIdeType,
        'platform': geminiCodeAssistPlatformUnspecified,
        'pluginType': geminiCodeAssistPluginType,
        'duetProject': 'project-1',
      },
      'mode': 'HEALTH_CHECK',
    });
  });

  test('auto-discovers and persists project id before unary generation', () async {
    final seenPaths = <String>[];
    final resolvedProjectIds = <String>[];
    final account = sampleAccount(projectId: '');

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      onProjectIdResolved: (account, projectId) async {
        resolvedProjectIds.add(projectId);
      },
      warmupEnabled: false,
      httpClient: QueueHttpClient([
        (request) async {
          seenPaths.add(request.url.path);
          expect(request.url.path, '/v1internal:loadCodeAssist');
          expect(jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>, {
            'metadata': {
              'ideType': geminiCodeAssistIdeType,
              'platform': geminiCodeAssistPlatformUnspecified,
              'pluginType': geminiCodeAssistPluginType,
            },
          });
          return http.Response(
            jsonEncode({
              'allowedTiers': [
                {'id': 'free-tier', 'isDefault': true},
              ],
            }),
            200,
          );
        },
        (request) async {
          seenPaths.add(request.url.path);
          expect(request.url.path, '/v1internal:onboardUser');
          expect(jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>, {
            'tierId': 'free-tier',
            'metadata': {
              'ideType': geminiCodeAssistIdeType,
              'platform': geminiCodeAssistPlatformUnspecified,
              'pluginType': geminiCodeAssistPluginType,
            },
          });
          return http.Response(
            jsonEncode({
              'done': true,
              'response': {
                'cloudaicompanionProject': {'id': 'autodiscovered-project'},
              },
            }),
            200,
          );
        },
        (request) async {
          seenPaths.add(request.url.path);
          final body = jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          expect(request.url.path, '/v1internal:generateContent');
          expect(body['project'], 'autodiscovered-project');
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'Discovered'},
                      ],
                    },
                    'finishReason': 'STOP',
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    final response = await client.generateContent(account: account, request: sampleRequest());

    expect(account.projectId, 'autodiscovered-project');
    expect(resolvedProjectIds, ['autodiscovered-project']);
    expect(seenPaths, [
      '/v1internal:loadCodeAssist',
      '/v1internal:onboardUser',
      '/v1internal:generateContent',
    ]);
    expect(OpenAiResponseMapper.currentText(response), 'Discovered');
  });

  test('polls getOperation after onboardUser returns a long-running operation', () async {
    final waits = <Duration>[];
    final seenPaths = <String>[];
    final account = sampleAccount(projectId: '');

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      wait: (delay) async {
        waits.add(delay);
      },
      warmupEnabled: false,
      httpClient: QueueHttpClient([
        (request) async {
          seenPaths.add(request.url.path);
          return http.Response(
            jsonEncode({
              'allowedTiers': [
                {'id': 'free-tier', 'isDefault': true},
              ],
            }),
            200,
          );
        },
        (request) async {
          seenPaths.add(request.url.path);
          return http.Response(jsonEncode({'name': 'operations/onboard-123', 'done': false}), 200);
        },
        (request) async {
          seenPaths.add(request.url.path);
          return http.Response(jsonEncode({'name': 'operations/onboard-123', 'done': false}), 200);
        },
        (request) async {
          seenPaths.add(request.url.path);
          return http.Response(
            jsonEncode({
              'name': 'operations/onboard-123',
              'done': true,
              'response': {
                'cloudaicompanionProject': {'id': 'operation-project'},
              },
            }),
            200,
          );
        },
        (request) async {
          seenPaths.add(request.url.path);
          final body = jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          expect(body['project'], 'operation-project');
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'Resolved via operation'},
                      ],
                    },
                    'finishReason': 'STOP',
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    final response = await client.generateContent(account: account, request: sampleRequest());

    expect(account.projectId, 'operation-project');
    expect(waits, [const Duration(seconds: 2), const Duration(seconds: 2)]);
    expect(seenPaths, [
      '/v1internal:loadCodeAssist',
      '/v1internal:onboardUser',
      '/v1internal/operations/onboard-123',
      '/v1internal/operations/onboard-123',
      '/v1internal:generateContent',
    ]);
    expect(OpenAiResponseMapper.currentText(response), 'Resolved via operation');
  });

  test('sends warmup choreography once before the first generate request', () async {
    final seenPaths = <String>[];
    final seenBodies = <Map<String, Object?>>[];

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      warmupEnabled: true,
      httpClient: QueueHttpClient([
        (request) async {
          seenPaths.add(request.url.path);
          seenBodies.add(
            jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>,
          );
          return http.Response('{}', 200);
        },
        (request) async {
          seenPaths.add(request.url.path);
          seenBodies.add(
            jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>,
          );
          return http.Response('{}', 200);
        },
        (request) async {
          seenPaths.add(request.url.path);
          seenBodies.add(
            jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>,
          );
          return http.Response('{}', 200);
        },
        (request) async {
          seenPaths.add(request.url.path);
          seenBodies.add(
            jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>,
          );
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'Hi'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
        (request) async {
          seenPaths.add(request.url.path);
          seenBodies.add(
            jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>,
          );
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'Again'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(requestId: 'warmup-1'),
    );
    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(requestId: 'warmup-2'),
    );

    expect(seenPaths, [
      '/v1internal:loadCodeAssist',
      '/v1internal:listExperiments',
      '/v1internal:fetchAdminControls',
      '/v1internal:generateContent',
      '/v1internal:generateContent',
    ]);

    expect((seenBodies[0]['metadata'] as Map?)?.cast<String, Object?>(), {
      'ideType': geminiCodeAssistIdeType,
      'platform': geminiCodeAssistPlatformUnspecified,
      'pluginType': geminiCodeAssistPluginType,
    });

    expect(seenBodies[1]['project'], 'project-1');
    expect((seenBodies[1]['metadata'] as Map?)?.cast<String, Object?>(), {
      'ideName': geminiCodeAssistIdeName,
      'pluginType': geminiCodeAssistPluginType,
      'ideVersion': geminiCodeAssistCliVersion,
      'platform': expectedMetadataPlatform(),
      'updateChannel': geminiCodeAssistUpdateChannel,
      'duetProject': 'project-1',
    });

    expect(seenBodies[2], {'project': 'project-1'});
    expect(seenBodies[3]['model'], 'gemini-2.5-pro');
    expect(seenBodies[4]['model'], 'gemini-2.5-pro');
  });

  test('fails fast when the Gemini request times out', () async {
    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      requestTimeout: const Duration(milliseconds: 10),
      retryPolicy: const GeminiRetryPolicy(maxRetries: 0),
      httpClient: QueueHttpClient([
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return http.Response('{}', 200);
        },
      ]),
    );

    await expectLater(
      client.generateContent(account: sampleAccount(), request: sampleRequest()),
      throwsA(
        isA<GeminiGatewayException>()
            .having((error) => error.kind, 'kind', GeminiGatewayFailureKind.serviceUnavailable)
            .having((error) => error.statusCode, 'statusCode', 503)
            .having(
              (error) => error.message,
              'message',
              'Gemini request timed out while contacting Gemini Code Assist.',
            ),
      ),
    );
  });

  test(
    'allows unary generation to finish after the request timeout once the stream is open',
    () async {
      final client = GeminiCodeAssistClient(
        onTokensUpdated: (account, tokens) async {},
        requestTimeout: const Duration(milliseconds: 10),
        retryPolicy: const GeminiRetryPolicy(maxRetries: 0),
        httpClient: QueueHttpClient([
          (_) async {
            return http.StreamedResponse(
              Stream<List<int>>.fromFuture(
                Future<List<int>>.delayed(
                  const Duration(milliseconds: 40),
                  () => utf8.encode(
                    jsonEncode({
                      'response': {
                        'candidates': [
                          {
                            'content': {
                              'parts': [
                                {'text': 'Recovered after slow body'},
                              ],
                            },
                            'finishReason': 'STOP',
                          },
                        ],
                      },
                    }),
                  ),
                ),
              ),
              200,
            );
          },
        ]),
      );

      final response = await client.generateContent(
        account: sampleAccount(),
        request: sampleRequest(),
      );

      expect(OpenAiResponseMapper.currentText(response), 'Recovered after slow body');
      expect(OpenAiResponseMapper.currentFinishReason(response), 'stop');
    },
  );

  test('retries quota failures using retry hint before succeeding', () async {
    final waits = <Duration>[];
    var attempts = 0;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      wait: (delay) async {
        waits.add(delay);
      },
      httpClient: QueueHttpClient([
        (request) async {
          attempts += 1;
          return http.Response(
            jsonEncode({
              'error': {
                'message':
                    'You have exhausted your capacity on this model. Your quota will reset after 49s.',
              },
            }),
            429,
          );
        },
        (request) async {
          attempts += 1;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'Recovered'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    final response = await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(),
    );

    expect(attempts, 2);
    expect(waits, [const Duration(seconds: 49)]);
    expect((response['response'] as Map)['candidates'], isNotEmpty);
  });

  test('reports retry metadata through the retry callback', () async {
    final events = <GeminiRetryEvent>[];

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      wait: (_) async {},
      httpClient: QueueHttpClient([
        (request) async {
          return http.Response(
            jsonEncode({
              'error': {
                'message':
                    'You have exhausted your capacity on this model. Your quota will reset after 12s.',
              },
            }),
            429,
          );
        },
        (request) async {
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'Recovered'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(),
      onRetry: events.add,
    );

    expect(events, hasLength(1));
    expect(events.single.attempt, 1);
    expect(events.single.maxRetries, defaultGeminiRequestMaxRetries);
    expect(events.single.delay, const Duration(seconds: 12));
    expect(events.single.error.kind, GeminiGatewayFailureKind.quota);
    expect(events.single.error.statusCode, 429);
  });

  test('honors configured retry limit for quota failures', () async {
    final waits = <Duration>[];
    var attempts = 0;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      retryPolicy: const GeminiRetryPolicy(maxRetries: 1, default429Delay: Duration(seconds: 17)),
      wait: (delay) async {
        waits.add(delay);
      },
      httpClient: QueueHttpClient([
        (request) async {
          attempts += 1;
          return http.Response(
            jsonEncode({
              'error': {'message': 'Too Many Requests'},
            }),
            429,
          );
        },
        (request) async {
          attempts += 1;
          return http.Response(
            jsonEncode({
              'error': {'message': 'Too Many Requests'},
            }),
            429,
          );
        },
      ]),
    );

    await expectLater(
      () => client.generateContent(account: sampleAccount(), request: sampleRequest()),
      throwsA(
        isA<GeminiGatewayException>()
            .having((error) => error.kind, 'kind', GeminiGatewayFailureKind.quota)
            .having((error) => error.statusCode, 'statusCode', 429),
      ),
    );

    expect(attempts, 2);
    expect(waits, [const Duration(seconds: 17)]);
  });

  test('retries 429 no-capacity failures up to the configured retry limit', () async {
    final waits = <Duration>[];
    var attempts = 0;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      retryPolicy: const GeminiRetryPolicy(maxRetries: 4),
      wait: (delay) async {
        waits.add(delay);
      },
      httpClient: QueueHttpClient([
        (request) async {
          attempts += 1;
          return http.Response(
            jsonEncode({
              'error': {'message': 'There is no capacity available for this request.'},
            }),
            429,
          );
        },
        (request) async {
          attempts += 1;
          return http.Response(
            jsonEncode({
              'error': {'message': 'There is no capacity available for this request.'},
            }),
            429,
          );
        },
        (request) async {
          attempts += 1;
          return http.Response(
            jsonEncode({
              'error': {'message': 'There is no capacity available for this request.'},
            }),
            429,
          );
        },
        (request) async {
          attempts += 1;
          return http.Response(
            jsonEncode({
              'error': {'message': 'There is no capacity available for this request.'},
            }),
            429,
          );
        },
        (request) async {
          attempts += 1;
          return http.Response(
            jsonEncode({
              'error': {'message': 'There is no capacity available for this request.'},
            }),
            429,
          );
        },
      ]),
    );

    await expectLater(
      () => client.generateContent(account: sampleAccount(), request: sampleRequest()),
      throwsA(
        isA<GeminiGatewayException>()
            .having((error) => error.kind, 'kind', GeminiGatewayFailureKind.capacity)
            .having((error) => error.statusCode, 'statusCode', 429),
      ),
    );

    expect(attempts, 5);
    expect(waits, List.filled(4, const Duration(seconds: 30)));
  });

  test(
    'retries no-capacity failures up to the configured retry limit regardless of status',
    () async {
      final waits = <Duration>[];
      var attempts = 0;

      final client = GeminiCodeAssistClient(
        onTokensUpdated: (account, tokens) async {},
        retryPolicy: const GeminiRetryPolicy(maxRetries: 4),
        wait: (delay) async {
          waits.add(delay);
        },
        httpClient: QueueHttpClient([
          (request) async {
            attempts += 1;
            return http.Response(
              jsonEncode({
                'error': {'message': 'There is no capacity available for this request.'},
              }),
              503,
            );
          },
          (request) async {
            attempts += 1;
            return http.Response(
              jsonEncode({
                'error': {'message': 'There is no capacity available for this request.'},
              }),
              503,
            );
          },
          (request) async {
            attempts += 1;
            return http.Response(
              jsonEncode({
                'error': {'message': 'There is no capacity available for this request.'},
              }),
              503,
            );
          },
          (request) async {
            attempts += 1;
            return http.Response(
              jsonEncode({
                'error': {'message': 'There is no capacity available for this request.'},
              }),
              503,
            );
          },
          (request) async {
            attempts += 1;
            return http.Response(
              jsonEncode({
                'response': {
                  'candidates': [
                    {
                      'content': {
                        'parts': [
                          {'text': 'Recovered'},
                        ],
                      },
                    },
                  ],
                },
              }),
              200,
            );
          },
        ]),
      );

      final response = await client.generateContent(
        account: sampleAccount(),
        request: sampleRequest(),
      );

      expect(attempts, 5);
      expect(waits, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
      ]);
      expect((response['response'] as Map)['candidates'], isNotEmpty);
    },
  );

  test('keeps non-no-capacity transient capacity failures capped at three retries', () async {
    final waits = <Duration>[];
    var attempts = 0;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      retryPolicy: const GeminiRetryPolicy(maxRetries: 10),
      wait: (delay) async {
        waits.add(delay);
      },
      httpClient: QueueHttpClient([
        (request) async {
          attempts += 1;
          return http.Response(
            jsonEncode({
              'error': {'message': 'Server overloaded. Please try again later.'},
            }),
            503,
          );
        },
        (request) async {
          attempts += 1;
          return http.Response(
            jsonEncode({
              'error': {'message': 'Server overloaded. Please try again later.'},
            }),
            503,
          );
        },
        (request) async {
          attempts += 1;
          return http.Response(
            jsonEncode({
              'error': {'message': 'Server overloaded. Please try again later.'},
            }),
            503,
          );
        },
        (request) async {
          attempts += 1;
          return http.Response(
            jsonEncode({
              'error': {'message': 'Server overloaded. Please try again later.'},
            }),
            503,
          );
        },
      ]),
    );

    await expectLater(
      () => client.generateContent(account: sampleAccount(), request: sampleRequest()),
      throwsA(
        isA<GeminiGatewayException>()
            .having((error) => error.kind, 'kind', GeminiGatewayFailureKind.capacity)
            .having((error) => error.statusCode, 'statusCode', 503),
      ),
    );

    expect(attempts, 4);
    expect(waits, const [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4)]);
  });

  test('does not retry 429 quota failures when retry hint is one minute or longer', () async {
    final waits = <Duration>[];
    var attempts = 0;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      wait: (delay) async {
        waits.add(delay);
      },
      httpClient: QueueHttpClient([
        (request) async {
          attempts += 1;
          return http.Response(
            jsonEncode({
              'error': {'message': 'QUOTA_EXHAUSTED. Please retry in 2h 15m.'},
            }),
            429,
          );
        },
      ]),
    );

    await expectLater(
      () => client.generateContent(account: sampleAccount(), request: sampleRequest()),
      throwsA(
        isA<GeminiGatewayException>()
            .having((error) => error.kind, 'kind', GeminiGatewayFailureKind.quota)
            .having((error) => error.statusCode, 'statusCode', 429)
            .having(
              (error) => error.retryAfter,
              'retryAfter',
              const Duration(hours: 2, minutes: 15),
            ),
      ),
    );

    expect(attempts, 1);
    expect(waits, isEmpty);
  });

  test('builds Gemini multimodal parts and merges adjacent turns with the same role', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: UnifiedPromptRequest(
        requestId: 'req_media',
        model: 'gemini-2.5-pro',
        stream: false,
        source: 'chat.completions',
        turns: const [
          UnifiedTurn(role: 'user', parts: [UnifiedPart.text('Hello')]),
          UnifiedTurn(
            role: 'user',
            parts: [UnifiedPart.inlineData(mimeType: 'image/png', data: 'ZmFrZQ==')],
          ),
          UnifiedTurn(
            role: 'assistant',
            parts: [
              UnifiedPart.fileData(
                mimeType: 'application/pdf',
                fileUri: 'https://example.com/spec.pdf',
              ),
            ],
          ),
        ],
        tools: const [],
        systemInstruction: null,
        toolChoice: null,
        temperature: null,
        topP: null,
        maxOutputTokens: null,
        stopSequences: null,
        reasoningEffort: null,
        googleThinkingConfig: null,
        googleWebSearchEnabled: false,
        responseModalities: null,
        jsonMode: false,
        responseSchema: null,
      ),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final contents = (requestMap['contents'] as List).cast<Map>();

    expect(contents, hasLength(2));
    expect(contents[0]['role'], 'user');
    expect(contents[1]['role'], 'model');
    expect(contents[0]['parts'], [
      {'text': 'Hello'},
      {
        'inlineData': {'mimeType': 'image/png', 'data': 'ZmFrZQ=='},
      },
    ]);
    expect(contents[1]['parts'], [
      {
        'fileData': {'mimeType': 'application/pdf', 'fileUri': 'https://example.com/spec.pdf'},
      },
    ]);
  });

  test('preserves requested model id and builds advanced Gemini generation config', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(
        model: 'gemini-3-flash',
        reasoningEffort: 'high',
        stopSequences: const ['END'],
      ),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final generationConfig = (requestMap['generationConfig'] as Map).cast<String, Object?>();

    expect(capturedBody?['model'], 'gemini-3-flash');
    expect(generationConfig['topK'], 64);
    expect(generationConfig['stopSequences'], ['END']);
    expect((generationConfig['thinkingConfig'] as Map).cast<String, Object?>(), {
      'thinkingLevel': 'HIGH',
      'includeThoughts': true,
    });
    expect(requestMap.containsKey('safetySettings'), isFalse);
  });

  test('maps Gemini 3 flash reasoning effort none to minimal thinking', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(model: 'gemini-3-flash', reasoningEffort: 'none'),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final generationConfig = (requestMap['generationConfig'] as Map).cast<String, Object?>();

    expect((generationConfig['thinkingConfig'] as Map).cast<String, Object?>(), {
      'thinkingLevel': 'MINIMAL',
      'includeThoughts': false,
    });
  });

  test('maps Gemini 3 pro reasoning effort medium to high thinking', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(model: 'gemini-3.1-pro-preview', reasoningEffort: 'medium'),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final generationConfig = (requestMap['generationConfig'] as Map).cast<String, Object?>();

    expect((generationConfig['thinkingConfig'] as Map).cast<String, Object?>(), {
      'thinkingLevel': 'HIGH',
      'includeThoughts': true,
    });
  });

  test('uses explicit Google thinking config for Gemini 3', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(
        model: 'gemini-3-flash',
        googleThinkingConfig: const {'thinking_level': 'minimal', 'include_thoughts': false},
      ),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final generationConfig = (requestMap['generationConfig'] as Map).cast<String, Object?>();

    expect((generationConfig['thinkingConfig'] as Map).cast<String, Object?>(), {
      'thinkingLevel': 'MINIMAL',
      'includeThoughts': false,
    });
  });

  test('uses google thinking config and text response modality for Gemini 2.5', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(
        model: 'gemini-2.5-flash-preview',
        googleThinkingConfig: const {'thinking_budget': 2048},
      ),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final generationConfig = (requestMap['generationConfig'] as Map).cast<String, Object?>();

    expect(capturedBody?['model'], 'gemini-2.5-flash-preview');
    expect(generationConfig['responseModalities'], ['TEXT']);
    expect((generationConfig['thinkingConfig'] as Map).cast<String, Object?>(), {
      'thinkingBudget': 2048,
      'includeThoughts': true,
    });
  });

  test('defaults Gemini 2.5 text-only requests to thinkingBudget 8192', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(model: 'gemini-2.5-flash'),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final generationConfig = (requestMap['generationConfig'] as Map).cast<String, Object?>();

    expect(generationConfig['responseModalities'], ['TEXT']);
    expect((generationConfig['thinkingConfig'] as Map).cast<String, Object?>(), {
      'thinkingBudget': 8192,
      'includeThoughts': false,
    });
  });

  test('uses Gemini 2.5 Pro default thinking budget for text-only requests', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(model: 'gemini-2.5-pro'),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final generationConfig = (requestMap['generationConfig'] as Map).cast<String, Object?>();

    expect(generationConfig['responseModalities'], ['TEXT']);
    expect((generationConfig['thinkingConfig'] as Map).cast<String, Object?>(), {
      'thinkingBudget': 8192,
      'includeThoughts': false,
    });
  });

  test('respects explicit reasoning effort on Gemini 2.5', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(model: 'gemini-2.5-flash', reasoningEffort: 'high'),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final generationConfig = (requestMap['generationConfig'] as Map).cast<String, Object?>();

    expect((generationConfig['thinkingConfig'] as Map).cast<String, Object?>(), {
      'thinkingBudget': 24576,
      'includeThoughts': true,
    });
  });

  test('does not add forced text modality when tools are present', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(
        model: 'gemini-2.5-flash',
        tools: const [
          UnifiedToolDeclaration(
            name: 'lookupWeather',
            description: 'Weather lookup',
            parameters: {'type': 'object'},
          ),
        ],
      ),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final generationConfig = (requestMap['generationConfig'] as Map).cast<String, Object?>();

    expect(generationConfig.containsKey('responseModalities'), isFalse);
    expect((generationConfig['thinkingConfig'] as Map).cast<String, Object?>(), {
      'thinkingBudget': 8192,
      'includeThoughts': false,
    });
  });

  test('uses Gemini CLI wire-format for tools and structured JSON output', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': '{}'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: UnifiedPromptRequest(
        requestId: 'req_json_tools',
        model: 'gemini-3-flash',
        stream: false,
        source: 'chat.completions',
        turns: const [
          UnifiedTurn(role: 'user', parts: [UnifiedPart.text('Return JSON weather')]),
        ],
        tools: const [
          UnifiedToolDeclaration(
            name: 'lookupWeather',
            description: 'Weather lookup',
            parameters: {
              'type': 'object',
              'properties': {
                'city': {'type': 'string'},
              },
            },
          ),
        ],
        systemInstruction: null,
        toolChoice: null,
        temperature: null,
        topP: null,
        maxOutputTokens: 256,
        stopSequences: null,
        reasoningEffort: null,
        googleThinkingConfig: null,
        googleWebSearchEnabled: false,
        responseModalities: null,
        jsonMode: true,
        responseSchema: const {
          'type': 'object',
          'properties': {
            'weather': {'type': 'string'},
          },
        },
      ),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final generationConfig = (requestMap['generationConfig'] as Map).cast<String, Object?>();
    final tools = (requestMap['tools'] as List).cast<Map>();
    final functionDeclarations = (tools.single['functionDeclarations'] as List)
        .cast<Map<String, Object?>>();

    expect(generationConfig['responseMimeType'], 'application/json');
    expect(generationConfig['responseJsonSchema'], {
      'type': 'object',
      'properties': {
        'weather': {'type': 'string'},
      },
    });
    expect(generationConfig.containsKey('responseSchema'), isFalse);
    expect(functionDeclarations.single['parametersJsonSchema'], {
      'type': 'object',
      'properties': {
        'city': {'type': 'string'},
      },
    });
    expect(functionDeclarations.single.containsKey('parameters'), isFalse);
    expect(requestMap.containsKey('safetySettings'), isFalse);
  });

  test('adds googleSearch built-in tool without function calling config', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: UnifiedPromptRequest(
        requestId: 'req_search',
        model: 'gemini-3-flash',
        stream: false,
        source: 'chat.completions',
        turns: const [
          UnifiedTurn(role: 'user', parts: [UnifiedPart.text('Find fresh Flutter news')]),
        ],
        tools: const [],
        systemInstruction: null,
        toolChoice: null,
        temperature: null,
        topP: null,
        maxOutputTokens: 256,
        stopSequences: null,
        reasoningEffort: null,
        googleThinkingConfig: null,
        googleWebSearchEnabled: true,
        responseModalities: null,
        jsonMode: false,
        responseSchema: null,
      ),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final tools = (requestMap['tools'] as List).cast<Map>();

    expect(tools, [
      {'googleSearch': <String, Object?>{}},
    ]);
    expect(requestMap.containsKey('toolConfig'), isFalse);
  });

  test('sends function tools together with googleSearch built-in tool', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: UnifiedPromptRequest(
        requestId: 'req_search_tools',
        model: 'gemini-3-flash',
        stream: false,
        source: 'chat.completions',
        turns: const [
          UnifiedTurn(
            role: 'user',
            parts: [UnifiedPart.text('Find fresh Flutter news and call a tool if needed')],
          ),
        ],
        tools: const [
          UnifiedToolDeclaration(
            name: 'lookupWeather',
            description: 'Weather lookup',
            parameters: {
              'type': 'object',
              'properties': {
                'city': {'type': 'string'},
              },
            },
          ),
        ],
        systemInstruction: null,
        toolChoice: 'required',
        temperature: null,
        topP: null,
        maxOutputTokens: 256,
        stopSequences: null,
        reasoningEffort: null,
        googleThinkingConfig: null,
        googleWebSearchEnabled: true,
        responseModalities: null,
        jsonMode: false,
        responseSchema: null,
      ),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final tools = (requestMap['tools'] as List).cast<Map<String, Object?>>();

    expect(tools, hasLength(2));
    expect((tools.first['functionDeclarations'] as List).single, {
      'name': 'lookupWeather',
      'description': 'Weather lookup',
      'parametersJsonSchema': {
        'type': 'object',
        'properties': {
          'city': {'type': 'string'},
        },
      },
    });
    expect(tools.last, {'googleSearch': <String, Object?>{}});
    expect(requestMap['toolConfig'], {
      'functionCallingConfig': {'mode': 'ANY'},
    });
  });

  test('uses Gemini 2.5 default thinking budget for multimodal requests', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(
        model: 'gemini-2.5-flash',
        turns: const [
          UnifiedTurn(
            role: 'user',
            parts: [
              UnifiedPart.text('Describe this image'),
              UnifiedPart.fileData(
                mimeType: 'image/png',
                fileUri: 'https://example.com/example.png',
              ),
            ],
          ),
        ],
      ),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final generationConfig = (requestMap['generationConfig'] as Map).cast<String, Object?>();

    expect(generationConfig['responseModalities'], ['TEXT']);
    expect((generationConfig['thinkingConfig'] as Map).cast<String, Object?>(), {
      'thinkingBudget': 8192,
      'includeThoughts': false,
    });
  });

  test('passes assistant thought signatures through to Gemini request parts', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(
        model: 'gemini-3-flash',
        turns: const [
          UnifiedTurn(
            role: 'assistant',
            parts: [
              UnifiedPart.thought(text: 'Need weather lookup.', thoughtSignature: 'sig_weather'),
              UnifiedPart.functionCall(
                callId: 'call_weather',
                name: 'lookupWeather',
                arguments: {'city': 'Moscow'},
              ),
            ],
          ),
          UnifiedTurn(role: 'user', parts: [UnifiedPart.text('Continue')]),
        ],
      ),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final contents = (requestMap['contents'] as List).cast<Map>();
    final assistantTurn = contents.first.cast<String, Object?>();
    final assistantParts = (assistantTurn['parts'] as List).cast<Map>();

    expect(assistantTurn['role'], 'model');
    expect(assistantParts.first, {
      'thought': true,
      'text': 'Need weather lookup.',
      'thoughtSignature': 'sig_weather',
    });
    expect((assistantParts[1]['functionCall'] as Map)['name'], 'lookupWeather');
    expect(assistantParts[1]['thoughtSignature'], 'sig_weather');
  });

  test('adds Gemini 3 fallback thought signatures to model function calls', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(
        model: 'gemini-3.1-pro-preview',
        turns: const [
          UnifiedTurn(
            role: 'assistant',
            parts: [
              UnifiedPart.functionCall(
                callId: 'call_read',
                name: 'default_api:read_file',
                arguments: {'path': 'README.md'},
              ),
            ],
          ),
          UnifiedTurn(role: 'user', parts: [UnifiedPart.text('Continue')]),
        ],
      ),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final contents = (requestMap['contents'] as List).cast<Map>();
    final assistantTurn = contents.first.cast<String, Object?>();
    final assistantParts = (assistantTurn['parts'] as List).cast<Map>();

    expect(assistantTurn['role'], 'model');
    expect((assistantParts.single['functionCall'] as Map)['name'], 'default_api:read_file');
    expect(assistantParts.single['thoughtSignature'], 'skip_thought_signature_validator');
  });

  test('keeps trailing system prompts as the final user turn for Gemini requests', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'Memory book'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    final parsed = OpenAiRequestParser.parseChatRequest({
      'model': 'gemini-3.1-pro-preview',
      'messages': [
        {'role': 'system', 'content': 'You are a roleplay director.'},
        {'role': 'assistant', 'content': 'Previous character reply.'},
        {'role': 'user', 'content': 'Привет!'},
        {'role': 'assistant', 'content': '<think>'},
        {'role': 'system', 'content': 'Pause roleplay and write the memory book.'},
      ],
    }, requestId: 'req_trailing_system_regression');

    await client.generateContent(account: sampleAccount(), request: parsed);

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final contents = (requestMap['contents'] as List).cast<Map>();

    expect((requestMap['systemInstruction'] as Map)['parts'], [
      {'text': 'You are a roleplay director.'},
    ]);
    expect(contents.map((entry) => entry['role']).toList(), ['model', 'user', 'model', 'user']);
    expect((contents.last['parts'] as List).single, {
      'text': 'Pause roleplay and write the memory book.',
    });
  });

  test('defaults short Gemini 3 flash text-only requests to high thinking', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(model: 'gemini-3-flash', maxOutputTokens: 64),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final generationConfig = (requestMap['generationConfig'] as Map).cast<String, Object?>();

    expect((generationConfig['thinkingConfig'] as Map).cast<String, Object?>(), {
      'thinkingLevel': 'HIGH',
      'includeThoughts': false,
    });
  });

  test('defaults short Gemini 3 pro text-only requests to high thinking', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(model: 'gemini-3.1-pro-preview', maxOutputTokens: 64),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final generationConfig = (requestMap['generationConfig'] as Map).cast<String, Object?>();

    expect((generationConfig['thinkingConfig'] as Map).cast<String, Object?>(), {
      'thinkingLevel': 'HIGH',
      'includeThoughts': false,
    });
  });

  test('defaults large Gemini 3 text-only requests to high thinking', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(model: 'gemini-3-flash', maxOutputTokens: 512),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final generationConfig = (requestMap['generationConfig'] as Map).cast<String, Object?>();

    expect((generationConfig['thinkingConfig'] as Map).cast<String, Object?>(), {
      'thinkingLevel': 'HIGH',
      'includeThoughts': false,
    });
  });

  test('omits max output token budget when the client omits it', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(maxOutputTokens: null),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();
    final generationConfig = (requestMap['generationConfig'] as Map).cast<String, Object?>();

    expect(generationConfig.containsKey('maxOutputTokens'), isFalse);
  });

  test('omits toolConfig for default AUTO tool choice', () async {
    Map<String, Object?>? capturedBody;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          capturedBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(
        tools: const [
          UnifiedToolDeclaration(
            name: 'lookupWeather',
            description: 'Weather lookup',
            parameters: {
              'type': 'object',
              'properties': {
                'city': {'type': 'string'},
              },
            },
          ),
        ],
      ),
    );

    final requestMap = (capturedBody?['request'] as Map).cast<String, Object?>();

    expect(requestMap.containsKey('toolConfig'), isFalse);
  });

  test('refreshes tokens and retries unary generation once after a 401', () async {
    final seenTokens = <String>[];
    final persistedTokens = <OAuthTokens>[];

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {
        persistedTokens.add(tokens);
      },
      httpClient: QueueHttpClient([
        (request) async {
          seenTokens.add(request.headers[HttpHeaders.authorizationHeader] ?? '');
          expect(request.url.path, '/v1internal:generateContent');
          return http.Response(
            jsonEncode({
              'error': {'code': 401, 'message': 'Unauthorized.'},
            }),
            401,
          );
        },
        (request) async {
          expect(request.url.path, '/token');
          return http.Response(
            jsonEncode({
              'access_token': 'fresh-access-token',
              'expires_in': 3600,
              'token_type': 'Bearer',
            }),
            200,
          );
        },
        (request) async {
          seenTokens.add(request.headers[HttpHeaders.authorizationHeader] ?? '');
          expect(request.url.path, '/v1internal:generateContent');
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'Hi'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    final response = await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(),
    );

    expect(OpenAiResponseMapper.currentText(response), 'Hi');
    expect(seenTokens, ['Bearer access-token', 'Bearer fresh-access-token']);
    expect(persistedTokens, hasLength(1));
    expect(persistedTokens.single.accessToken, 'fresh-access-token');
  });

  test('refreshes tokens and retries streaming generation once after a 401', () async {
    final seenTokens = <String>[];
    final persistedTokens = <OAuthTokens>[];

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {
        persistedTokens.add(tokens);
      },
      httpClient: QueueHttpClient([
        (request) async {
          seenTokens.add(request.headers[HttpHeaders.authorizationHeader] ?? '');
          expect(request.url.path, '/v1internal:streamGenerateContent');
          return http.Response(
            jsonEncode({
              'error': {'code': 401, 'message': 'Unauthorized.'},
            }),
            401,
          );
        },
        (request) async {
          expect(request.url.path, '/token');
          return http.Response(
            jsonEncode({
              'access_token': 'fresh-stream-token',
              'expires_in': 3600,
              'token_type': 'Bearer',
            }),
            200,
          );
        },
        (request) async {
          seenTokens.add(request.headers[HttpHeaders.authorizationHeader] ?? '');
          expect(request.url.path, '/v1internal:streamGenerateContent');
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                'data: {"response":{"candidates":[{"content":{"parts":[{"text":"Hello"}]},"finishReason":"STOP"}]}}\n\n',
              ),
            ),
            200,
          );
        },
      ]),
    );

    final stream = await client.generateContentStream(
      account: sampleAccount(),
      request: sampleRequest(stream: true),
    );
    final payloads = await stream.toList();

    expect(payloads, hasLength(1));
    expect(OpenAiResponseMapper.currentText(payloads.single), 'Hello');
    expect(seenTokens, ['Bearer access-token', 'Bearer fresh-stream-token']);
    expect(persistedTokens, hasLength(1));
    expect(persistedTokens.single.accessToken, 'fresh-stream-token');
  });

  test('continues unary generation when Gemini stops on max tokens', () async {
    final seenBodies = <Map<String, Object?>>[];
    const sessionId = '22222222-2222-4222-8222-222222222222';
    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      createSessionId: () => sessionId,
      httpClient: QueueHttpClient([
        (request) async {
          seenBodies.add(
            jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>,
          );
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'Hello'},
                      ],
                    },
                    'finishReason': 'MAX_TOKENS',
                  },
                ],
              },
            }),
            200,
          );
        },
        (request) async {
          seenBodies.add(
            jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>,
          );
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': ' world'},
                      ],
                    },
                    'finishReason': 'STOP',
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    final response = await client.generateContent(
      account: sampleAccount(),
      request: sampleRequest(maxOutputTokens: 5),
    );

    final responseMap = (response['response'] as Map).cast<String, Object?>();
    final candidate = ((responseMap['candidates'] as List).single as Map).cast<String, Object?>();
    final content = (candidate['content'] as Map).cast<String, Object?>();
    final parts = (content['parts'] as List).cast<Map>();

    expect(parts.single['text'], 'Hello world');
    expect(seenBodies, hasLength(2));
    final continuationContents = (((seenBodies[1]['request'] as Map)['contents']) as List)
        .cast<Map>();
    expect(((seenBodies[0]['request'] as Map)['session_id']), sessionId);
    expect(((seenBodies[1]['request'] as Map)['session_id']), sessionId);
    expect(seenBodies[0].containsKey('metadata'), isFalse);
    expect(seenBodies[1].containsKey('metadata'), isFalse);
    expect(seenBodies[0]['user_prompt_id'], '$sessionId########0');
    expect(seenBodies[1]['user_prompt_id'], '$sessionId########1');
    expect(continuationContents[1]['role'], 'model');
    expect(((continuationContents[1]['parts'] as List).single as Map)['text'], 'Hello');
    expect(
      ((continuationContents[2]['parts'] as List).single as Map)['text'],
      contains('Please continue from where you left off.'),
    );
  });

  test(
    'unary continuation excludes thought text from merged visible text and prompt suffix',
    () async {
      final seenBodies = <Map<String, Object?>>[];
      final client = GeminiCodeAssistClient(
        onTokensUpdated: (account, tokens) async {},
        httpClient: QueueHttpClient([
          (request) async {
            seenBodies.add(
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>,
            );
            return http.Response(
              jsonEncode({
                'response': {
                  'candidates': [
                    {
                      'content': {
                        'parts': [
                          {'thought': true, 'text': 'Drafting a plan.'},
                          {'text': 'Hello'},
                        ],
                      },
                      'finishReason': 'MAX_TOKENS',
                    },
                  ],
                },
              }),
              200,
            );
          },
          (request) async {
            seenBodies.add(
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>,
            );
            return http.Response(
              jsonEncode({
                'response': {
                  'candidates': [
                    {
                      'content': {
                        'parts': [
                          {'text': ' world'},
                        ],
                      },
                      'finishReason': 'STOP',
                    },
                  ],
                },
              }),
              200,
            );
          },
        ]),
      );

      final response = await client.generateContent(
        account: sampleAccount(),
        request: sampleRequest(maxOutputTokens: 5),
      );

      final responseMap = (response['response'] as Map).cast<String, Object?>();
      final candidate = ((responseMap['candidates'] as List).single as Map).cast<String, Object?>();
      final content = (candidate['content'] as Map).cast<String, Object?>();
      final parts = (content['parts'] as List).cast<Map>();
      final continuationContents = (((seenBodies[1]['request'] as Map)['contents']) as List)
          .cast<Map>();
      final continuationPrompt =
          ((continuationContents[2]['parts'] as List).single as Map)['text'] as String;

      expect(parts, [
        {'text': 'Hello world'},
      ]);
      expect(((continuationContents[1]['parts'] as List).single as Map)['text'], 'Hello');
      expect(continuationPrompt, contains('Hello'));
      expect(continuationPrompt, isNot(contains('Drafting a plan.')));
    },
  );

  test('continues streaming generation when Gemini stops on max tokens', () async {
    final seenBodies = <Map<String, Object?>>[];
    const sessionId = '33333333-3333-4333-8333-333333333333';
    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      createSessionId: () => sessionId,
      httpClient: QueueHttpClient([
        (request) async {
          seenBodies.add(
            jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>,
          );
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                'data: {"response":{"candidates":[{"content":{"parts":[{"text":"Hello"}]},"finishReason":"MAX_TOKENS"}]}}\n\n',
              ),
            ),
            200,
          );
        },
        (request) async {
          seenBodies.add(
            jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>,
          );
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                'data: {"response":{"candidates":[{"content":{"parts":[{"text":" world"}]},"finishReason":"STOP"}]}}\n\n',
              ),
            ),
            200,
          );
        },
      ]),
    );

    final stream = await client.generateContentStream(
      account: sampleAccount(),
      request: sampleRequest(stream: true, maxOutputTokens: 5),
    );
    final payloads = await stream.toList();

    expect(payloads, hasLength(2));
    expect(
      (((payloads[0]['response'] as Map)['candidates'] as List).single as Map)['finishReason'],
      'MAX_TOKENS',
    );
    expect(
      ((((payloads[1]['response'] as Map)['candidates'] as List).single as Map)['content']
          as Map)['parts'],
      [
        {'text': 'Hello world'},
      ],
    );
    expect(seenBodies, hasLength(2));
    final continuationContents = (((seenBodies[1]['request'] as Map)['contents']) as List)
        .cast<Map>();
    expect(((seenBodies[0]['request'] as Map)['session_id']), sessionId);
    expect(((seenBodies[1]['request'] as Map)['session_id']), sessionId);
    expect(seenBodies[0]['user_prompt_id'], '$sessionId########0');
    expect(seenBodies[1]['user_prompt_id'], '$sessionId########1');
    expect(
      ((continuationContents[2]['parts'] as List).single as Map)['text'],
      contains('Please continue from where you left off.'),
    );
  });

  test('stream continuation keeps thought parts separate from merged visible text', () async {
    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                'data: {"response":{"candidates":[{"content":{"parts":[{"thought":true,"text":"Drafting a plan."},{"text":"Hello"}]},"finishReason":"MAX_TOKENS"}]}}\n\n',
              ),
            ),
            200,
          );
        },
        (request) async {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                'data: {"response":{"candidates":[{"content":{"parts":[{"thought":true,"text":"Continuing."},{"text":" world"}]},"finishReason":"STOP"}]}}\n\n',
              ),
            ),
            200,
          );
        },
      ]),
    );

    final payloads = await (await client.generateContentStream(
      account: sampleAccount(),
      request: sampleRequest(stream: true, maxOutputTokens: 5),
    )).toList();

    expect(payloads, hasLength(2));
    expect(OpenAiResponseMapper.currentReasoningText(payloads[0]), 'Drafting a plan.');
    expect(OpenAiResponseMapper.currentText(payloads[0]), 'Hello');
    expect(OpenAiResponseMapper.currentReasoningText(payloads[1]), 'Continuing.');
    expect(OpenAiResponseMapper.currentText(payloads[1]), 'Hello world');
  });

  test('stream continuation emits cumulative text instead of restarted prefixes', () async {
    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                'data: {"response":{"candidates":[{"content":{"parts":[{"text":"Seraphina smiles warmly, her amber eyes glowing with"}]},"finishReason":"MAX_TOKENS"}]}}\n\n',
              ),
            ),
            200,
          );
        },
        (request) async {
          return http.StreamedResponse(
            Stream.fromIterable([
              utf8.encode(
                'data: {"response":{"candidates":[{"content":{"parts":[{"text":"Seraphina smiles warmly, her amber eyes"}]},"finishReason":"MAX_TOKENS"}]}}\n\n',
              ),
              utf8.encode(
                'data: {"response":{"candidates":[{"content":{"parts":[{"text":"Seraphina smiles warmly, her amber eyes glowing with a gentle light."}]},"finishReason":"STOP"}]}}\n\n',
              ),
            ]),
            200,
          );
        },
      ]),
    );

    final stream = await client.generateContentStream(
      account: sampleAccount(),
      request: sampleRequest(stream: true, maxOutputTokens: 5),
    );
    final payloads = await stream.toList();

    expect(
      OpenAiResponseMapper.currentText(payloads[0]),
      'Seraphina smiles warmly, her amber eyes glowing with',
    );
    expect(
      OpenAiResponseMapper.currentText(payloads[1]),
      'Seraphina smiles warmly, her amber eyes glowing with',
    );
    expect(
      OpenAiResponseMapper.currentText(payloads[2]),
      'Seraphina smiles warmly, her amber eyes glowing with a gentle light.',
    );
  });

  test('stream continuation keeps previous text when next pass restarts differently', () async {
    final streamClient = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                'data: {"response":{"candidates":[{"content":{"parts":[{"text":"*A soft, radiant smile spreads across Seraphina"}]},"finishReason":"MAX_TOKENS"}]}}\n\n',
              ),
            ),
            200,
          );
        },
        (request) async {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                'data: {"response":{"candidates":[{"content":{"parts":[{"text":"radiant smile spreads across Seraphina"}]},"finishReason":"MAX_TOKENS"}]}}\n\n',
              ),
            ),
            200,
          );
        },
      ]),
    );

    final payloads = await (await streamClient.generateContentStream(
      account: sampleAccount(),
      request: sampleRequest(stream: true, maxOutputTokens: 5),
    )).toList();

    expect(payloads, hasLength(2));
    expect(
      OpenAiResponseMapper.currentText(payloads[0]),
      '*A soft, radiant smile spreads across Seraphina',
    );
    expect(
      OpenAiResponseMapper.currentText(payloads[1]),
      '*A soft, radiant smile spreads across Seraphina',
    );
  });

  test('stream continuation restores missing spaces across continuation passes', () async {
    final streamClient = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                'data: {"response":{"candidates":[{"content":{"parts":[{"text":"Hello there"}]},"finishReason":"MAX_TOKENS"}]}}\n\n',
              ),
            ),
            200,
          );
        },
        (request) async {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                'data: {"response":{"candidates":[{"content":{"parts":[{"text":"traveler. It is good to hear your voice"}]},"finishReason":"MAX_TOKENS"}]}}\n\n',
              ),
            ),
            200,
          );
        },
        (request) async {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                'data: {"response":{"candidates":[{"content":{"parts":[{"text":"voiceand see you awake."}]},"finishReason":"STOP"}]}}\n\n',
              ),
            ),
            200,
          );
        },
      ]),
    );

    final payloads = await (await streamClient.generateContentStream(
      account: sampleAccount(),
      request: sampleRequest(stream: true, maxOutputTokens: 5),
    )).toList();

    expect(payloads, hasLength(3));
    expect(
      OpenAiResponseMapper.currentText(payloads.last),
      'Hello there traveler. It is good to hear your voice and see you awake.',
    );
  });

  test('cancels upstream Gemini stream when consumer stops listening', () async {
    final upstreamCanceled = Completer<void>();
    final upstream = StreamController<List<int>>(
      onCancel: () {
        if (!upstreamCanceled.isCompleted) {
          upstreamCanceled.complete();
        }
      },
    );
    addTearDown(() async {
      if (!upstream.isClosed) {
        await upstream.close();
      }
    });

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([(request) async => http.StreamedResponse(upstream.stream, 200)]),
    );

    final stream = await client.generateContentStream(
      account: sampleAccount(),
      request: sampleRequest(stream: true, maxOutputTokens: 5),
    );
    final firstPayload = Completer<Map<String, Object?>>();
    final subscription = stream.listen((payload) {
      if (!firstPayload.isCompleted) {
        firstPayload.complete(payload);
      }
    });

    upstream.add(
      utf8.encode(
        'data: {"response":{"candidates":[{"content":{"parts":[{"text":"Hello"}]},"finishReason":"MAX_TOKENS"}]}}\n\n',
      ),
    );

    final payload = await firstPayload.future.timeout(const Duration(seconds: 1));
    expect(OpenAiResponseMapper.currentText(payload), 'Hello');

    await subscription.cancel();
    await upstreamCanceled.future.timeout(const Duration(seconds: 1));
  });

  test('stops retrying Gemini stream when consumer cancels during retry backoff', () async {
    final waits = <Duration>[];
    final firstAttempt = Completer<void>();
    var attempts = 0;

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      wait: (delay) async {
        waits.add(delay);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      httpClient: QueueHttpClient([
        (request) async {
          attempts += 1;
          if (!firstAttempt.isCompleted) {
            firstAttempt.complete();
          }
          return http.Response(
            jsonEncode({
              'error': {
                'message':
                    'You have exhausted your capacity on this model. Your quota will reset after 30s.',
              },
            }),
            429,
          );
        },
        (request) async {
          attempts += 1;
          return http.Response(
            jsonEncode({
              'response': {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'late retry'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        },
      ]),
    );

    final stream = await client.generateContentStream(
      account: sampleAccount(),
      request: sampleRequest(stream: true),
    );
    final subscription = stream.listen((_) {});

    await firstAttempt.future.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await subscription.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(attempts, 1);
    expect(waits, [const Duration(seconds: 30)]);
  });

  test('aborts in-flight Gemini stream request when consumer cancels before first chunk', () async {
    final requestStarted = Completer<void>();
    final requestAborted = Completer<void>();

    final client = GeminiCodeAssistClient(
      onTokensUpdated: (account, tokens) async {},
      httpClient: QueueHttpClient([
        (request) {
          if (!requestStarted.isCompleted) {
            requestStarted.complete();
          }
          if (request is http.Abortable && request.abortTrigger != null) {
            unawaited(
              request.abortTrigger!.then((_) {
                if (!requestAborted.isCompleted) {
                  requestAborted.complete();
                }
              }),
            );
          }
          return Completer<http.BaseResponse>().future;
        },
      ]),
    );

    final stream = await client.generateContentStream(
      account: sampleAccount(),
      request: sampleRequest(stream: true),
    );
    final subscription = stream.listen((_) {});

    await requestStarted.future.timeout(const Duration(seconds: 1));
    await subscription.cancel();

    await requestAborted.future.timeout(const Duration(seconds: 1));
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

    final responseFuture = _handlers
        .removeAt(0)(request)
        .then((response) => _toStreamedResponse(response, request));
    if (request is http.Abortable && request.abortTrigger != null) {
      return Future.any<http.StreamedResponse>([
        responseFuture,
        request.abortTrigger!.then<http.StreamedResponse>(
          (_) => throw http.RequestAbortedException(request.url),
        ),
      ]);
    }
    return responseFuture;
  }

  http.StreamedResponse _toStreamedResponse(http.BaseResponse response, http.BaseRequest request) {
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
