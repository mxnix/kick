import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kick/proxy/gemini/gemini_code_assist_client.dart';
import 'package:kick/proxy/luma/luma_realm_client.dart';
import 'package:kick/proxy/luma/luma_realm_models.dart';
import 'package:kick/proxy/luma/luma_session.dart';

void main() {
  const session = LumaSession(
    cookies: {'wos-session': 'cookie-blob', 'workos-access-token': 'access-blob'},
    email: 'tester@example.com',
  );

  group('LumaRealmClient', () {
    test('readPrimaryTeam returns the first accepted team', () async {
      var receivedCookie = '';
      final client = LumaRealmClient(
        httpClient: MockClient((request) async {
          expect(request.url.host, 'app.lumalabs.ai');
          expect(request.url.path, '/api/vespa/teams');
          expect(request.method, 'GET');
          receivedCookie = request.headers['cookie'] ?? '';
          return http.Response(
            jsonEncode({
              'accepted': [
                {
                  'team': {'id': 'team-1', 'name': 'My Team'},
                  'membership': {
                    'user': {'uuid': 'user-1', 'email': 'tester@example.com'},
                    'role': 'owner',
                  },
                  'subscription': {'tier': 'free'},
                  'tier_display_name': 'Luma Trial',
                },
              ],
              'pending': <Object?>[],
            }),
            200,
          );
        }),
      );

      final team = await client.readPrimaryTeam(session);

      expect(team, isNotNull);
      expect(team!.teamId, 'team-1');
      expect(team.tier, 'free');
      expect(team.userEmail, 'tester@example.com');
      expect(receivedCookie, contains('wos-session=cookie-blob'));
      expect(receivedCookie, contains('workos-access-token=access-blob'));

      client.close();
    });

    test('listRealms parses the array response', () async {
      final client = LumaRealmClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/vespa/teams/team-1/realms');
          return http.Response(
            jsonEncode([
              {'id': 'realm-1', 'name': 'KiCk'},
              {'id': 'realm-2', 'name': 'Other'},
            ]),
            200,
          );
        }),
      );

      final realms = await client.listRealms(session, 'team-1');

      expect(realms.map((r) => r.name).toList(), ['KiCk', 'Other']);
      client.close();
    });

    test('createRealm posts the requested name', () async {
      String? receivedBody;
      final client = LumaRealmClient(
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          receivedBody = request.body;
          return http.Response(jsonEncode({'id': 'realm-new', 'name': 'KiCk'}), 200);
        }),
      );

      final realm = await client.createRealm(session, teamId: 'team-1', name: 'KiCk');

      expect(realm.id, 'realm-new');
      expect(realm.name, 'KiCk');
      expect(jsonDecode(receivedBody!), {'name': 'KiCk'});
      client.close();
    });

    test('preflightAction parses output specs and credit estimates', () async {
      final client = LumaRealmClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/vespa/realms/realm-1/actions/preflight');
          final body = jsonDecode(request.body) as Map<String, Object?>;
          expect(body['type'], 'create_image_nano_banana_pro');
          return http.Response(
            jsonEncode({
              'output_specs': [
                {
                  'key': 'image',
                  'artifact_type': 'image/png',
                  'count': 1,
                  'width': 2304,
                  'height': 1296,
                  'display_tags': {'model': 'Nano Banana Pro'},
                },
              ],
              'estimated_seconds': 35.5,
              'estimated_queue_seconds': 2.1,
              'estimated_credits': 35.0,
              'availability': null,
            }),
            200,
          );
        }),
      );

      final preflight = await client.preflightAction(
        session,
        realmId: 'realm-1',
        type: 'create_image_nano_banana_pro',
        fields: const {'prompt': 'cat', 'aspect_ratio': '16:9', 'resolution': '2K'},
      );

      expect(preflight.estimatedCredits, 35);
      expect(preflight.estimatedSeconds, closeTo(35.5, 1e-9));
      expect(preflight.outputSpecs.first.artifactType, 'image/png');
      expect(preflight.outputSpecs.first.width, 2304);
      client.close();
    });

    test('submitAction includes optimistic_output_ids', () async {
      String? receivedBody;
      final client = LumaRealmClient(
        httpClient: MockClient((request) async {
          receivedBody = request.body;
          return http.Response(
            jsonEncode({
              'action': {
                'id': 'act-1',
                'type': 'create_image_nano_banana_pro',
                'state': 'pending',
                'params': {'prompt': 'cat'},
                'estimated_credits': 35,
              },
              'output_artifacts': {
                'image': ['nlJWU0Uz'],
              },
            }),
            200,
          );
        }),
      );

      final submission = await client.submitAction(
        session,
        realmId: 'realm-1',
        type: 'create_image_nano_banana_pro',
        fields: const {'prompt': 'cat'},
        optimisticOutputIds: const ['nlJWU0Uz'],
      );

      expect(submission.actionId, 'act-1');
      expect(submission.outputArtifactIds, {
        'image': ['nlJWU0Uz'],
      });
      expect(jsonDecode(receivedBody!), {
        'type': 'create_image_nano_banana_pro',
        'fields': {'prompt': 'cat'},
        'optimistic_output_ids': ['nlJWU0Uz'],
      });
      client.close();
    });

    test('reserveArtifact returns a presigned URL or fails clearly', () async {
      final client = LumaRealmClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'id': 'NNovDQGu',
              'realm_id': 'realm-1',
              'type': 'image/png',
              'state': 'pending',
              'meta': {'width': 100, 'height': 80},
              'object_ref': 'realm-1/NNovDQGu.png',
              'presigned_url': 'https://s3.example/upload',
            }),
            200,
          );
        }),
      );

      final artifact = await client.reserveArtifact(
        session,
        realmId: 'realm-1',
        contentType: 'image/png',
        name: 'sample',
        width: 100,
        height: 80,
      );

      expect(artifact.id, 'NNovDQGu');
      expect(artifact.presignedUrl, 'https://s3.example/upload');
      client.close();
    });

    test('requestDownloads returns the file URL list', () async {
      final client = LumaRealmClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'mode': 'direct',
              'files': [
                {
                  'url': 'https://cdn.example/abc.png?sig=opaque',
                  'filename': 'abc.png',
                  'size_bytes': 123,
                  'artifact_id': 'abc',
                },
              ],
            }),
            200,
          );
        }),
      );

      final files = await client.requestDownloads(
        session,
        realmId: 'realm-1',
        artifactIds: const ['abc'],
      );

      expect(files, hasLength(1));
      expect(files.first.url, contains('abc.png'));
      expect(files.first.artifactId, 'abc');
      client.close();
    });

    test('maps HTTP 401 to an auth gateway error', () async {
      final client = LumaRealmClient(
        httpClient: MockClient((request) async {
          return http.Response(jsonEncode({'detail': 'missing session'}), 401);
        }),
      );

      try {
        await client.readPrimaryTeam(session);
        fail('expected GeminiGatewayException');
      } on GeminiGatewayException catch (e) {
        expect(e.kind, GeminiGatewayFailureKind.auth);
        expect(e.statusCode, 401);
        expect(e.message, contains('missing session'));
      }
      client.close();
    });

    test('refuses to call without a session cookie', () async {
      final client = LumaRealmClient(
        httpClient: MockClient((_) async {
          fail('should not hit network without a session');
        }),
      );

      const empty = LumaSession(cookies: {});
      try {
        await client.readPrimaryTeam(empty);
        fail('expected GeminiGatewayException');
      } on GeminiGatewayException catch (e) {
        expect(e.kind, GeminiGatewayFailureKind.auth);
      }
      client.close();
    });
  });

  test('LumaRealmSignature.isStale uses a 60-second safety window', () {
    final fresh = LumaRealmSignature(
      queryParams: '',
      cdnUrl: '',
      wsUrl: '',
      wsToken: '',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
    expect(fresh.isStale, isFalse);

    final almostStale = LumaRealmSignature(
      queryParams: '',
      cdnUrl: '',
      wsUrl: '',
      wsToken: '',
      expiresAt: DateTime.now().add(const Duration(seconds: 30)),
    );
    expect(almostStale.isStale, isTrue);

    const noExpiry = LumaRealmSignature(
      queryParams: '',
      cdnUrl: '',
      wsUrl: '',
      wsToken: '',
      expiresAt: null,
    );
    expect(noExpiry.isStale, isFalse);
  });
}
