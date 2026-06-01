import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kick/proxy/gemini/gemini_code_assist_client.dart';
import 'package:kick/proxy/luma/luma_image_engine.dart';
import 'package:kick/proxy/luma/luma_realm_client.dart';
import 'package:kick/proxy/luma/luma_session.dart';

void main() {
  const session = LumaSession(
    cookies: {'wos-session': 'cookie-blob'},
    teamId: 'team-1',
    realmId: 'realm-abc',
    email: 'tester@example.com',
  );

  http.Client cdnClient({int notReadyAttempts = 0}) {
    var calls = 0;
    return MockClient((request) async {
      if (request.method == 'HEAD' && request.url.host.startsWith('cdn.')) {
        calls += 1;
        if (calls <= notReadyAttempts) {
          return http.Response('', 403);
        }
        return http.Response('', 200);
      }
      return http.Response('not found', 404);
    });
  }

  group('LumaImageEngine.generate', () {
    test('advertised public models all map to Luma actions', () {
      expect(lumaPublicImageModels, isNot(contains('uni-1')));
      for (final model in lumaPublicImageModels) {
        expect(lumaImageModelActions[model], isNotNull, reason: model);
      }
    });

    test('submits create_image action and returns the signed URL when the CDN is ready', () async {
      final requests = <Map<String, Object?>>[];
      final realmClient = LumaRealmClient(
        httpClient: MockClient((request) async {
          requests.add({'method': request.method, 'path': request.url.path, 'body': request.body});
          if (request.url.path == '/api/vespa/realms/realm-abc/actions') {
            return http.Response(
              jsonEncode({
                'action': {
                  'id': 'action-1',
                  'type': 'create_image_nano_banana_pro',
                  'state': 'pending',
                  'estimated_credits': 35,
                  'params': <String, Object?>{},
                },
                'output_artifacts': {
                  'image': ['ARTIFACT1'],
                },
                'estimated_seconds': 30,
              }),
              200,
            );
          }
          if (request.url.path == '/api/vespa/realms/realm-abc/downloads') {
            return http.Response(
              jsonEncode({
                'files': [
                  {
                    'url': 'https://cdn.example.test/ARTIFACT1.png',
                    'filename': 'ARTIFACT1.png',
                    'artifact_id': 'ARTIFACT1',
                    'size_bytes': 12345,
                  },
                ],
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final engine = LumaImageEngine(client: realmClient, httpClient: cdnClient());

      final result = await engine.generate(
        session: session,
        prompt: 'A cat',
        size: '1920x1080',
        resolution: '4K',
      );

      expect(result.url, 'https://cdn.example.test/ARTIFACT1.png');
      expect(result.artifactId, 'ARTIFACT1');
      expect(result.creditsUsed, 35);
      expect(result.model, 'nano-banana-pro');

      final submitRequest = requests.firstWhere(
        (r) => r['path'] == '/api/vespa/realms/realm-abc/actions',
      );
      final body = jsonDecode(submitRequest['body'] as String) as Map<String, Object?>;
      expect(body['type'], 'create_image_nano_banana_pro');
      final fields = (body['fields'] as Map).cast<String, Object?>();
      expect(fields['prompt'], 'A cat');
      expect(fields['aspect_ratio'], '16:9');
      expect(fields['resolution'], '4K');
      engine.close();
    });

    test('keeps references on create_image actions when no source is provided', () async {
      Map<String, Object?>? submittedBody;
      final realmClient = LumaRealmClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/vespa/realms/realm-abc/actions') {
            submittedBody = jsonDecode(request.body) as Map<String, Object?>;
            return http.Response(
              jsonEncode({
                'action': {
                  'id': 'action-1',
                  'type': 'create_image_nano_banana_pro',
                  'state': 'pending',
                  'estimated_credits': 35,
                  'params': <String, Object?>{},
                },
                'output_artifacts': {
                  'image': ['ARTIFACT3'],
                },
              }),
              200,
            );
          }
          if (request.url.path == '/api/vespa/realms/realm-abc/downloads') {
            return http.Response(
              jsonEncode({
                'files': [
                  {
                    'url': 'https://cdn.example.test/ARTIFACT3.png',
                    'filename': 'a.png',
                    'artifact_id': 'ARTIFACT3',
                    'size_bytes': 1,
                  },
                ],
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final engine = LumaImageEngine(client: realmClient, httpClient: cdnClient());
      await engine.generate(
        session: session,
        prompt: 'Use these as style references',
        referenceArtifactIds: const ['REF1', ' ', 'REF2'],
      );

      expect(submittedBody, isNotNull);
      expect(submittedBody!['type'], 'create_image_nano_banana_pro');
      final fields = (submittedBody!['fields'] as Map).cast<String, Object?>();
      expect(fields['references'], const ['REF1', 'REF2']);
      expect(fields.containsKey('source'), isFalse);
      engine.close();
    });

    test('uses Luma source/references fields for modify_image actions', () async {
      Map<String, Object?>? submittedBody;
      final realmClient = LumaRealmClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/vespa/realms/realm-abc/actions') {
            submittedBody = jsonDecode(request.body) as Map<String, Object?>;
            return http.Response(
              jsonEncode({
                'action': {
                  'id': 'action-1',
                  'type': 'modify_image_nano_banana_pro',
                  'state': 'pending',
                  'estimated_credits': 35,
                  'params': <String, Object?>{},
                },
                'output_artifacts': {
                  'image': ['ARTIFACT2'],
                },
              }),
              200,
            );
          }
          if (request.url.path == '/api/vespa/realms/realm-abc/downloads') {
            return http.Response(
              jsonEncode({
                'files': [
                  {
                    'url': 'https://cdn.example.test/ARTIFACT2.png',
                    'filename': 'a.png',
                    'artifact_id': 'ARTIFACT2',
                    'size_bytes': 1,
                  },
                ],
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      final engine = LumaImageEngine(client: realmClient, httpClient: cdnClient());
      await engine.generate(
        session: session,
        prompt: 'Make it pop',
        primarySourceArtifactId: 'SRC123',
        referenceArtifactIds: const ['REF1', 'REF2'],
      );

      expect(submittedBody, isNotNull);
      expect(submittedBody!['type'], 'modify_image_nano_banana_pro');
      final fields = (submittedBody!['fields'] as Map).cast<String, Object?>();
      expect(fields['source'], 'SRC123');
      expect(fields['references'], const ['REF1', 'REF2']);
      expect(fields.containsKey('aspect_ratio'), isFalse);
      expect(fields.containsKey('source_artifact_id'), isFalse);
      expect(fields.containsKey('reference_artifact_ids'), isFalse);
      engine.close();
    });

    test('rejects unknown models with unsupportedModel', () async {
      final engine = LumaImageEngine(
        client: LumaRealmClient(httpClient: MockClient((_) async => http.Response('{}', 200))),
        httpClient: cdnClient(),
      );

      await expectLater(
        engine.generate(session: session, prompt: 'x', model: 'bogus'),
        throwsA(
          isA<GeminiGatewayException>().having(
            (e) => e.kind,
            'kind',
            GeminiGatewayFailureKind.unsupportedModel,
          ),
        ),
      );
      engine.close();
    });

    test('rejects sessions without a realm id', () async {
      final engine = LumaImageEngine(
        client: LumaRealmClient(httpClient: MockClient((_) async => http.Response('{}', 200))),
        httpClient: cdnClient(),
      );

      const sessionWithoutRealm = LumaSession(cookies: {'wos-session': 'x'}, teamId: 'team');
      await expectLater(
        engine.generate(session: sessionWithoutRealm, prompt: 'x'),
        throwsA(
          isA<GeminiGatewayException>().having(
            (e) => e.kind,
            'kind',
            GeminiGatewayFailureKind.invalidRequest,
          ),
        ),
      );
      engine.close();
    });
  });
}
