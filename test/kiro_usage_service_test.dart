import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/proxy/gemini/gemini_usage_models.dart';
import 'package:kick/proxy/kiro/kiro_auth_source.dart';
import 'package:kick/proxy/kiro/kiro_code_assist_client.dart';
import 'package:kick/proxy/kiro/kiro_usage_service.dart';

void main() {
  test('fetches Kiro usage limits and maps usage breakdowns to quota buckets', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick_kiro_usage');
    addTearDown(() => tempDirectory.delete(recursive: true));
    final sourceFile = File('${tempDirectory.path}${Platform.pathSeparator}kiro-auth-test.json');
    await sourceFile.writeAsString(
      jsonEncode({
        'accessToken': 'access-token',
        'refreshToken': 'refresh-token',
        'expiresAt': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String(),
        'region': defaultKiroRegion,
        'authMethod': socialKiroAuthMethod,
        'provider': 'Github',
        'profileArn': 'arn:aws:codewhisperer:us-east-1:123456789012:profile/test',
      }),
    );

    Map<String, String>? requestHeaders;
    final service = KiroUsageService(
      client: KiroCodeAssistClient(
        httpClient: QueueHttpClient([
          (request) async {
            requestHeaders = request.headers;
            expect(request.method, 'GET');
            expect(request.url.host, 'q.us-east-1.amazonaws.com');
            expect(request.url.path, '/getUsageLimits');
            expect(request.url.queryParameters['origin'], 'AI_EDITOR');
            expect(request.url.queryParameters.containsKey('isEmailRequired'), isFalse);
            expect(request.url.queryParameters['resourceType'], 'AGENTIC_REQUEST');
            expect(
              request.url.queryParameters['profileArn'],
              'arn:aws:codewhisperer:us-east-1:123456789012:profile/test',
            );
            return http.Response(
              jsonEncode({
                'nextDateReset': 1790812800,
                'subscriptionInfo': {
                  'subscriptionTitle': 'KIRO PRO',
                  'type': 'Q_DEVELOPER_STANDALONE_PRO',
                },
                'usageBreakdownList': [
                  {
                    'resourceType': 'CREDIT',
                    'displayName': 'Credit',
                    'displayNamePlural': 'Credits',
                    'unit': 'INVOCATIONS',
                    'currentUsage': 557,
                    'currentUsageWithPrecision': 557.13,
                    'usageLimit': 1000,
                    'usageLimitWithPrecision': 1000.0,
                    'nextDateReset': 1790812800,
                  },
                ],
              }),
              200,
            );
          },
        ]),
      ),
    );
    addTearDown(service.dispose);

    final snapshot = await service.fetchUsage(
      AccountProfile(
        id: 'kiro-1',
        label: 'Kiro',
        email: 'AWS Builder ID',
        projectId: '',
        provider: AccountProvider.kiro,
        providerRegion: defaultKiroRegion,
        credentialSourcePath: sourceFile.path,
        enabled: true,
        priority: 0,
        notSupportedModels: const [],
        lastUsedAt: null,
        usageCount: 0,
        errorCount: 0,
        cooldownUntil: null,
        lastQuotaSnapshot: null,
        tokenRef: 'kiro-token',
      ),
    );

    expect(requestHeaders?[HttpHeaders.authorizationHeader], 'Bearer access-token');
    expect(requestHeaders?[HttpHeaders.connectionHeader], 'close');
    expect(requestHeaders?['amz-sdk-request'], 'attempt=1; max=1');
    expect(requestHeaders?[HttpHeaders.userAgentHeader] ?? '', contains('KiroIDE-'));

    expect(snapshot.subscriptionTitle, 'KIRO PRO');
    expect(snapshot.buckets, hasLength(1));
    final bucket = snapshot.buckets.single;
    expect(bucket.modelId, 'Credit');
    expect(bucket.tokenType, 'INVOCATIONS');
    expect(bucket.currentUsage, 557.13);
    expect(bucket.usageLimit, 1000);
    expect(bucket.remainingFraction, closeTo((1000 - 557.13) / 1000, 0.001));
    expect(bucket.health, GeminiUsageBucketHealth.healthy);
    expect(
      bucket.resetAt,
      DateTime.fromMillisecondsSinceEpoch(1790812800 * 1000, isUtc: true).toLocal(),
    );
  });

  test('refreshes a stale access token when Kiro responds with Invalid token', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick_kiro_usage_401');
    addTearDown(() => tempDirectory.delete(recursive: true));
    final sourceFile = File('${tempDirectory.path}${Platform.pathSeparator}kiro-auth-401.json');
    await sourceFile.writeAsString(
      jsonEncode({
        'accessToken': 'stale-token',
        'refreshToken': 'refresh-token',
        'expiresAt': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String(),
        'region': defaultKiroRegion,
        'authMethod': socialKiroAuthMethod,
        'provider': 'Github',
        'profileArn': 'arn:aws:codewhisperer:us-east-1:123456789012:profile/test',
      }),
    );

    final observedAuthHeaders = <String>[];
    final service = KiroUsageService(
      client: KiroCodeAssistClient(
        managedSourcePathChecker: (_) async => false,
        httpClient: QueueHttpClient([
          (request) async {
            expect(request.url.path, '/getUsageLimits');
            observedAuthHeaders.add(request.headers[HttpHeaders.authorizationHeader] ?? '');
            return http.Response(jsonEncode({'message': 'Invalid token', 'reason': null}), 403);
          },
          (request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/refreshToken');
            expect(request.url.host, 'prod.us-east-1.auth.desktop.kiro.dev');
            return http.Response(
              jsonEncode({
                'accessToken': 'fresh-token',
                'refreshToken': 'rotated-refresh',
                'expiresIn': 3600,
                'profileArn': 'arn:aws:codewhisperer:us-east-1:123456789012:profile/test',
              }),
              200,
            );
          },
          (request) async {
            expect(request.url.path, '/getUsageLimits');
            observedAuthHeaders.add(request.headers[HttpHeaders.authorizationHeader] ?? '');
            return http.Response(
              jsonEncode({
                'nextDateReset': 1790812800,
                'subscriptionInfo': {
                  'subscriptionTitle': 'KIRO PRO',
                  'type': 'Q_DEVELOPER_STANDALONE_PRO',
                },
                'usageBreakdownList': [
                  {
                    'resourceType': 'CREDIT',
                    'displayName': 'Credit',
                    'displayNamePlural': 'Credits',
                    'unit': 'INVOCATIONS',
                    'currentUsage': 0,
                    'currentUsageWithPrecision': 0.0,
                    'usageLimit': 1000,
                    'usageLimitWithPrecision': 1000.0,
                    'nextDateReset': 1790812800,
                  },
                ],
              }),
              200,
            );
          },
        ]),
      ),
    );
    addTearDown(service.dispose);

    final snapshot = await service.fetchUsage(
      AccountProfile(
        id: 'kiro-1',
        label: 'Kiro',
        email: 'AWS Builder ID',
        projectId: '',
        provider: AccountProvider.kiro,
        providerRegion: defaultKiroRegion,
        credentialSourcePath: sourceFile.path,
        enabled: true,
        priority: 0,
        notSupportedModels: const [],
        lastUsedAt: null,
        usageCount: 0,
        errorCount: 0,
        cooldownUntil: null,
        lastQuotaSnapshot: null,
        tokenRef: 'kiro-token',
      ),
    );

    expect(observedAuthHeaders, ['Bearer stale-token', 'Bearer fresh-token']);
    expect(snapshot.subscriptionTitle, 'KIRO PRO');
    expect(snapshot.buckets, hasLength(1));
    expect(snapshot.buckets.single.usageLimit, 1000);
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
