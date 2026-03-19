import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/proxy/gemini/gemini_auth_constants.dart';
import 'package:kick/proxy/gemini/gemini_play_telemetry_service.dart';

void main() {
  AccountProfile sampleAccount(String id, {String? email}) => AccountProfile(
    id: id,
    label: 'Gemini $id',
    email: email ?? '$id@example.com',
    projectId: 'project-$id',
    enabled: true,
    priority: 0,
    notSupportedModels: const [],
    lastUsedAt: null,
    usageCount: 0,
    errorCount: 0,
    cooldownUntil: null,
    lastQuotaSnapshot: null,
    tokenRef: 'token-ref-$id',
  );

  test('sends a one-shot start_session and api_request payload', () async {
    var requestCount = 0;
    Uri? requestUri;
    Map<String, String>? requestHeaders;
    List<Object?>? requestBody;

    final uuids = <String>[
      '5fdc8783-6f5a-4abf-9d55-592e8f33f68b',
      '723a3ec1-e647-4ad8-83d3-cb54b5d53d6d',
    ];

    final service = GeminiPlayTelemetryService(
      createUuid: () => uuids.removeAt(0),
      clock: () => DateTime.parse('2026-03-19T12:00:00Z'),
      httpClient: QueueHttpClient([
        (request) async {
          requestCount += 1;
          requestUri = request.url;
          requestHeaders = request.headers;
          requestBody = jsonDecode(await request.finalize().bytesToString()) as List<Object?>;
          return http.Response('[1000]', 200);
        },
      ]),
    );

    await service.sendSessionTelemetryOnce(
      accounts: [sampleAccount('1'), sampleAccount('2')],
      apiRequestModel: 'gemini-3.1-pro-preview',
    );
    await service.sendSessionTelemetryOnce(accounts: [sampleAccount('1')]);

    expect(requestCount, 1);
    expect(requestUri.toString(), geminiPlayTelemetryEndpoint);
    expect(requestHeaders?[HttpHeaders.userAgentHeader], 'node');
    expect(requestHeaders?[HttpHeaders.contentTypeHeader], 'application/json');

    final envelope = (requestBody?.single as Map<Object?, Object?>).cast<String, Object?>();
    expect(envelope['log_source_name'], geminiPlayTelemetrySourceName);
    final events = (envelope['log_event'] as List).whereType<List>().toList(growable: false);
    expect(events, hasLength(2));

    final startSession = _decodeTelemetryEvent(events[0]);
    expect(startSession['event_name'], 'start_session');
    expect(startSession['client_email'], '1@example.com');
    expect(startSession.containsKey('client_install_id'), isFalse);

    final startSessionMetadata = _metadataValues(startSession);
    expect(startSessionMetadata[1], geminiPlayTelemetryStartSessionModel);
    expect(startSessionMetadata[40], '5fdc8783-6f5a-4abf-9d55-592e8f33f68b');
    expect(startSessionMetadata[35], '5fdc8783-6f5a-4abf-9d55-592e8f33f68b');
    expect(startSessionMetadata[37], '2');
    expect(startSessionMetadata[36], '"oauth-personal"');
    expect(startSessionMetadata[83], geminiCodeAssistNodeRuntimeVersion);
    expect(startSessionMetadata[54], geminiCodeAssistCliVersion);
    expect(startSessionMetadata[55], geminiCodeAssistCliGitCommitHash);

    final apiRequest = _decodeTelemetryEvent(events[1]);
    expect(apiRequest['event_name'], 'api_request');
    expect(apiRequest['client_email'], '1@example.com');
    final apiRequestMetadata = _metadataValues(apiRequest);
    expect(apiRequestMetadata[20], '"gemini-3.1-pro-preview"');
    expect(apiRequestMetadata[35], '5fdc8783-6f5a-4abf-9d55-592e8f33f68b########0');
    expect(apiRequestMetadata[40], '5fdc8783-6f5a-4abf-9d55-592e8f33f68b');
  });

  test('persists installation id when no account email is available', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick-telemetry-test-');
    addTearDown(() async {
      await tempDirectory.delete(recursive: true);
    });

    final installationIdPath = '${tempDirectory.path}\\installation_id';
    final uuids = <String>[
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
    ];
    final capturedEvents = <Map<String, Object?>>[];

    final service = GeminiPlayTelemetryService(
      installationIdPath: installationIdPath,
      createUuid: () => uuids.removeAt(0),
      clock: () => DateTime.parse('2026-03-19T12:00:00Z'),
      httpClient: QueueHttpClient([
        (request) async {
          final body = jsonDecode(await request.finalize().bytesToString()) as List<Object?>;
          final envelope = (body.single as Map<Object?, Object?>).cast<String, Object?>();
          final events = (envelope['log_event'] as List).whereType<List>();
          capturedEvents.addAll(events.map(_decodeTelemetryEvent));
          return http.Response('[1000]', 200);
        },
      ]),
    );

    await service.sendSessionTelemetryOnce(accounts: [sampleAccount('1', email: ' ')]);

    expect(await File(installationIdPath).readAsString(), '22222222-2222-4222-8222-222222222222');
    expect(capturedEvents, hasLength(2));
    expect(capturedEvents[0]['client_install_id'], '22222222-2222-4222-8222-222222222222');
    expect(capturedEvents[0].containsKey('client_email'), isFalse);
    expect(capturedEvents[1]['client_install_id'], '22222222-2222-4222-8222-222222222222');
  });
}

Map<String, Object?> _decodeTelemetryEvent(List<Object?> eventGroup) {
  final entry = (eventGroup.single as Map<Object?, Object?>).cast<String, Object?>();
  return (jsonDecode(entry['source_extension_json'] as String) as Map<Object?, Object?>)
      .cast<String, Object?>();
}

Map<int, String> _metadataValues(Map<String, Object?> event) {
  final metadata = ((event['event_metadata'] as List).single as List).whereType<Map>().toList();
  return {
    for (final item in metadata)
      (item['gemini_cli_key'] as num).toInt(): item['value']?.toString() ?? '',
  };
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
