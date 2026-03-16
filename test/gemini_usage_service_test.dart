import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/data/models/oauth_tokens.dart';
import 'package:kick/proxy/gemini/gemini_code_assist_client.dart';
import 'package:kick/proxy/gemini/gemini_usage_models.dart';
import 'package:kick/proxy/gemini/gemini_usage_service.dart';

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

  test('parses buckets in bundled model order and computes total usage', () {
    final snapshot = GeminiUsageSnapshot.fromApi({
      'buckets': [
        {
          'modelId': 'gemini-3.1-pro-preview',
          'remainingFraction': 0.95,
          'resetTime': '2026-03-16T15:21:00Z',
        },
        {
          'modelId': 'gemini-2.5-flash-preview',
          'remainingFraction': 0.97,
          'resetTime': '2026-03-16T13:56:00Z',
        },
      ],
    }, fetchedAt: DateTime.parse('2026-03-15T12:00:00Z'));

    expect(snapshot.buckets.map((bucket) => bucket.modelId), [
      'gemini-2.5-flash',
      'gemini-3.1-pro-preview',
    ]);
    expect(snapshot.totalUsed, closeTo(8, 0.001));
    expect(snapshot.totalLimit, 200);
    expect(snapshot.totalPercent, closeTo(4, 0.001));
    expect(snapshot.nextResetAt, DateTime.parse('2026-03-16T13:56:00Z').toLocal());
  });

  test('refreshes expired tokens before retrieveUserQuota request', () async {
    final persisted = <OAuthTokens>[];
    Map<String, Object?>? requestBody;
    Map<String, String>? requestHeaders;

    final service = GeminiUsageService(
      readTokens: (_) async => expiredTokens(),
      refreshTokens: (tokens) async => activeTokens(accessToken: 'fresh-token'),
      persistTokens: (_, tokens) async => persisted.add(tokens),
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
                },
              ],
            }),
            200,
          );
        },
      ]),
    );

    final snapshot = await service.fetchUsage(sampleAccount());

    expect(snapshot.buckets, hasLength(1));
    expect(requestBody, {'project': 'project-1'});
    expect(requestHeaders?[HttpHeaders.authorizationHeader], 'Bearer fresh-token');
    expect(persisted, hasLength(1));
    expect(persisted.single.accessToken, 'fresh-token');
  });

  test('retries usage request after auth failure with refreshed token', () async {
    var refreshCalls = 0;
    final persisted = <OAuthTokens>[];
    final seenTokens = <String>[];

    final service = GeminiUsageService(
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
                  'modelId': 'gemini-2.5-pro',
                  'remainingFraction': 1,
                  'resetTime': '2026-03-16T15:21:00Z',
                },
              ],
            }),
            200,
          );
        },
      ]),
    );

    final snapshot = await service.fetchUsage(sampleAccount());

    expect(snapshot.buckets.single.modelId, 'gemini-2.5-pro');
    expect(refreshCalls, 1);
    expect(persisted, hasLength(1));
    expect(seenTokens, ['Bearer stale-token', 'Bearer renewed-token']);
  });

  test('does not refresh tokens when quota lookup requires account verification', () async {
    var refreshCalls = 0;
    final seenTokens = <String>[];

    final service = GeminiUsageService(
      readTokens: (_) async => activeTokens(accessToken: 'active-token'),
      refreshTokens: (tokens) async {
        refreshCalls += 1;
        return activeTokens(accessToken: 'unexpected-refresh');
      },
      persistTokens: (_, tokens) async {},
      httpClient: QueueHttpClient([
        (request) async {
          seenTokens.add(request.headers[HttpHeaders.authorizationHeader] ?? '');
          return http.Response(
            jsonEncode({
              'error': {
                'code': 403,
                'message': 'Verify your account to continue.',
                'status': 'PERMISSION_DENIED',
                'details': [
                  {
                    '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
                    'reason': 'VALIDATION_REQUIRED',
                    'domain': 'cloudcode-pa.googleapis.com',
                    'metadata': {'validation_error_message': 'Verify your account to continue.'},
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
      service.fetchUsage(sampleAccount()),
      throwsA(
        isA<GeminiGatewayException>()
            .having((error) => error.kind, 'kind', GeminiGatewayFailureKind.auth)
            .having(
              (error) => error.detail,
              'detail',
              GeminiGatewayFailureDetail.accountVerificationRequired,
            ),
      ),
    );

    expect(refreshCalls, 0);
    expect(seenTokens, ['Bearer active-token']);
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
