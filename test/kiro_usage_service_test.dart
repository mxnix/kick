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
        'authMethod': builderIdKiroAuthMethod,
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
            expect(request.url.path, '/getUsageLimits');
            expect(request.url.queryParameters['origin'], 'AI_EDITOR');
            expect(request.url.queryParameters['resourceType'], 'AGENTIC_REQUEST');
            expect(request.url.queryParameters['isEmailRequired'], 'true');
            expect(request.url.queryParameters.containsKey('profileArn'), isFalse);
            return http.Response(
              jsonEncode({
                'nextDateReset': 1790812800,
                'subscriptionInfo': {'subscriptionTitle': 'Kiro Pro'},
                'usageBreakdownList': [
                  {
                    'resourceType': 'AGENTIC_REQUEST',
                    'displayName': 'Agentic requests',
                    'unit': 'requests',
                    'currentUsage': 3,
                    'usageLimit': 10,
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
    expect(snapshot.subscriptionTitle, 'Kiro Pro');
    expect(snapshot.buckets, hasLength(1));
    final bucket = snapshot.buckets.single;
    expect(bucket.modelId, 'Agentic requests');
    expect(bucket.tokenType, 'REQUESTS');
    expect(bucket.currentUsage, 3);
    expect(bucket.usageLimit, 10);
    expect(bucket.remainingFraction, closeTo(0.7, 0.001));
    expect(bucket.health, GeminiUsageBucketHealth.healthy);
    expect(
      bucket.resetAt,
      DateTime.fromMillisecondsSinceEpoch(1790812800 * 1000, isUtc: true).toLocal(),
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
