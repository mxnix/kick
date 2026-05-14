import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kick/features/home/silly_tavern_push_service.dart';

void main() {
  test('keeps SillyTavern signed session cookie when Set-Cookie headers are folded', () async {
    const foldedCookies =
        'session-abc=session-value; path=/; expires=Sun, 13 Jun 2027 18:44:55 GMT; samesite=lax; httponly,'
        'session-abc.sig=signature-value; path=/; expires=Sun, 13 Jun 2027 18:44:55 GMT; samesite=lax; httponly';
    final cookiesByPath = <String, String?>{};
    Map<String, Object?>? savedSettings;

    final service = SillyTavernPushService(
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/csrf-token':
            return http.Response(
              jsonEncode({'token': 'csrf-token'}),
              200,
              headers: {'set-cookie': foldedCookies},
            );
          case '/api/secrets/write':
            cookiesByPath[request.url.path] = request.headers['cookie'];
            expect(request.headers['x-csrf-token'], 'csrf-token');
            expect(jsonDecode(request.body), {'key': 'api_key_custom', 'value': 'kick-api-key'});
            return http.Response(jsonEncode({'id': 'secret-id'}), 200);
          case '/api/settings/get':
            cookiesByPath[request.url.path] = request.headers['cookie'];
            return http.Response(jsonEncode({'settings': <String, Object?>{}}), 200);
          case '/api/settings/save':
            cookiesByPath[request.url.path] = request.headers['cookie'];
            savedSettings = (jsonDecode(request.body) as Map).cast<String, Object?>();
            return http.Response(jsonEncode({'result': 'ok'}), 200);
        }

        throw StateError('Unexpected request: ${request.url}');
      }),
    );
    addTearDown(service.dispose);

    final result = await service.pushProfile(
      sillyTavernUrl: 'http://127.0.0.1:8000',
      proxyEndpoint: 'http://localhost:3000/v1',
      apiKey: 'kick-api-key',
      profileName: 'KiCk',
      model: 'google/gemini-3.1-pro-preview',
    );

    expect(result.profileName, 'KiCk');
    expect(
      cookiesByPath.values,
      everyElement(equals('session-abc=session-value; session-abc.sig=signature-value')),
    );
    expect(savedSettings, isNotNull);
    expect(savedSettings!['main_api'], 'openai');
    expect(savedSettings!['chat_completion_source'], isNull);

    final oaiSettings = (savedSettings!['oai_settings'] as Map).cast<String, Object?>();
    expect(oaiSettings['chat_completion_source'], 'custom');
    expect(oaiSettings['custom_url'], 'http://localhost:3000/v1');
    expect(oaiSettings['custom_model'], 'google/gemini-3.1-pro-preview');
    expect(oaiSettings['bypass_status_check'], isTrue);
    expect(oaiSettings['custom_prompt_post_processing'], 'merge');

    final extensionSettings = (savedSettings!['extension_settings'] as Map).cast<String, Object?>();
    final manager = (extensionSettings['connectionManager'] as Map).cast<String, Object?>();
    final profiles = manager['profiles'] as List<Object?>;
    expect(manager['selectedProfile'], result.profileId);
    expect(profiles, hasLength(1));
    expect(profiles.single, containsPair('secret-id', 'secret-id'));
  });
}
