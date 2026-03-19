import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/data/models/oauth_tokens.dart';
import 'package:kick/proxy/gemini/gemini_auth_constants.dart';
import 'package:kick/proxy/gemini/gemini_code_assist_client.dart';
import 'package:kick/proxy/gemini/gemini_project_diagnostics_service.dart';

void main() {
  AccountProfile sampleAccount() => const AccountProfile(
    id: 'account-1',
    label: 'Gemini',
    email: 'user@example.com',
    projectId: 'project-1',
    enabled: true,
    priority: 0,
    notSupportedModels: [],
    lastUsedAt: null,
    usageCount: 0,
    errorCount: 0,
    cooldownUntil: null,
    lastQuotaSnapshot: null,
    tokenRef: 'token-ref',
  );

  OAuthTokens activeTokens({String accessToken = 'access-token'}) => OAuthTokens(
    accessToken: accessToken,
    refreshToken: 'refresh-token',
    expiry: DateTime.now().add(const Duration(hours: 1)),
    tokenType: 'Bearer',
    scope: null,
  );

  OAuthTokens expiredTokens() => OAuthTokens(
    accessToken: 'expired-token',
    refreshToken: 'refresh-token',
    expiry: DateTime.now().subtract(const Duration(minutes: 1)),
    tokenType: 'Bearer',
    scope: null,
  );

  test('uses retrieveUserQuota for project diagnostics', () async {
    Map<String, Object?>? requestBody;
    Map<String, String>? requestHeaders;

    final service = GeminiProjectDiagnosticsService(
      readTokens: (_) async => activeTokens(),
      refreshTokens: (tokens) async => tokens,
      persistTokens: (_, tokens) async {},
      createDiagnosticId: () => '87f1ce57-30fe-4c1a-bb46-9fc68395ed86',
      httpClient: QueueHttpClient([
        (request) async {
          requestHeaders = request.headers;
          requestBody =
              jsonDecode(await request.finalize().bytesToString()) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'buckets': [
                {
                  'modelId': 'gemini-2.5-flash',
                  'remainingFraction': 0.97,
                  'resetTime': '2026-03-16T13:56:00Z',
                  'tokenType': 'REQUESTS',
                },
              ],
              'traceId': 'trace-1',
            }),
            200,
          );
        },
      ]),
    );

    final snapshot = await service.diagnose(sampleAccount());

    expect(snapshot.modelId, GeminiProjectDiagnosticsService.probeHeaderModelId);
    expect(snapshot.modelVersion, isNull);
    expect(snapshot.responseId, '87f1ce57-30fe-4c1a-bb46-9fc68395ed86');
    expect(snapshot.traceId, 'trace-1');
    expect(snapshot.probeText, isNull);
    expect(requestHeaders?[HttpHeaders.authorizationHeader], 'Bearer access-token');
    expect(requestHeaders?['x-goog-api-client'], geminiCodeAssistGoogApiClientHeader);
    expect(
      requestHeaders?[HttpHeaders.userAgentHeader],
      contains('/${GeminiProjectDiagnosticsService.probeHeaderModelId} '),
    );
    expect(requestHeaders?[HttpHeaders.acceptHeader], 'application/json');
    expect(requestBody?['project'], 'project-1');
    expect(requestBody, {'project': 'project-1'});
  });

  test('refreshes expired tokens before project diagnostics request', () async {
    final persisted = <OAuthTokens>[];
    final seenTokens = <String>[];

    final service = GeminiProjectDiagnosticsService(
      readTokens: (_) async => expiredTokens(),
      refreshTokens: (tokens) async => activeTokens(accessToken: 'fresh-token'),
      persistTokens: (_, tokens) async => persisted.add(tokens),
      httpClient: QueueHttpClient([
        (request) async {
          seenTokens.add(request.headers[HttpHeaders.authorizationHeader] ?? '');
          return http.Response(
            jsonEncode({
              'buckets': [
                {
                  'modelId': 'gemini-2.5-flash',
                  'remainingFraction': 0.82,
                },
              ],
            }),
            200,
          );
        },
      ]),
    );

    await service.diagnose(sampleAccount());

    expect(seenTokens, ['Bearer fresh-token']);
    expect(persisted, hasLength(1));
    expect(persisted.single.accessToken, 'fresh-token');
  });

  test('retries project diagnostics after auth failure with refreshed token', () async {
    var refreshCalls = 0;
    final persisted = <OAuthTokens>[];
    final seenTokens = <String>[];

    final service = GeminiProjectDiagnosticsService(
      readTokens: (_) async => activeTokens(accessToken: 'stale-token'),
      refreshTokens: (tokens) async {
        refreshCalls += 1;
        return activeTokens(accessToken: 'renewed-token');
      },
      persistTokens: (_, tokens) async => persisted.add(tokens),
      httpClient: QueueHttpClient([
        (request) async {
          seenTokens.add(request.headers[HttpHeaders.authorizationHeader] ?? '');
          return http.Response(
            jsonEncode({
              'error': {'code': 401, 'message': 'Unauthorized.'},
            }),
            401,
          );
        },
        (request) async {
          seenTokens.add(request.headers[HttpHeaders.authorizationHeader] ?? '');
          return http.Response(
            jsonEncode({
              'buckets': [
                {
                  'modelId': 'gemini-2.5-flash',
                  'remainingFraction': 0.82,
                },
              ],
            }),
            200,
          );
        },
      ]),
    );

    await service.diagnose(sampleAccount());

    expect(refreshCalls, 1);
    expect(persisted, hasLength(1));
    expect(seenTokens, ['Bearer stale-token', 'Bearer renewed-token']);
  });

  test('surfaces project configuration failures from the quota probe', () async {
    final service = GeminiProjectDiagnosticsService(
      readTokens: (_) async => activeTokens(accessToken: 'active-token'),
      refreshTokens: (tokens) async => activeTokens(accessToken: 'unexpected-refresh'),
      persistTokens: (_, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 403,
                'message': 'Gemini for Google Cloud API has not been used in project xz before.',
                'status': 'PERMISSION_DENIED',
                'details': [
                  {
                    '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
                    'reason': 'SERVICE_DISABLED',
                    'domain': 'googleapis.com',
                    'metadata': {
                      'activationUrl':
                          'https://console.developers.google.com/apis/api/cloudaicompanion.googleapis.com/overview?project=xz',
                    },
                  },
                ],
              },
            }),
            403,
          );
        },
      ]),
    );

    await expectLater(
      service.diagnose(sampleAccount().copyWith(projectId: 'xz')),
      throwsA(
        isA<GeminiGatewayException>()
            .having(
              (error) => error.detail,
              'detail',
              GeminiGatewayFailureDetail.projectConfiguration,
            )
            .having((error) => error.upstreamReason, 'upstreamReason', 'SERVICE_DISABLED')
            .having(
              (error) => error.actionUrl,
              'actionUrl',
              'https://console.developers.google.com/apis/api/cloudaicompanion.googleapis.com/overview?project=xz',
            ),
      ),
    );
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
