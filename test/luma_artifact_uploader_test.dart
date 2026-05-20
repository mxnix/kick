import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kick/proxy/gemini/gemini_code_assist_client.dart';
import 'package:kick/proxy/luma/luma_artifact_uploader.dart';
import 'package:kick/proxy/luma/luma_realm_client.dart';
import 'package:kick/proxy/luma/luma_session.dart';

void main() {
  const session = LumaSession(
    cookies: {'wos-session': 'cookie-blob'},
    teamId: 'team-1',
    realmId: 'realm-abc',
  );

  test('upload reserves, PUTs, and completes', () async {
    var presignedHits = 0;
    var completionHits = 0;

    final realmClient = LumaRealmClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/vespa/realms/realm-abc/artifacts' &&
            request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          expect(body['type'], 'image/png');
          expect(body['name'], 'test.png');
          return http.Response(
            jsonEncode({
              'id': body['id'],
              'realm_id': 'realm-abc',
              'type': 'image/png',
              'state': 'pending',
              'presigned_url': 'https://s3.example.test/upload?token=abc',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/complete') && request.method == 'POST') {
          completionHits += 1;
          final segments = request.url.pathSegments;
          final id = segments[segments.length - 2];
          return http.Response(
            jsonEncode({'id': id, 'realm_id': 'realm-abc', 'type': 'image/png', 'state': 'ready'}),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );

    final uploadHttp = MockClient((request) async {
      if (request.method == 'PUT' && request.url.host == 's3.example.test') {
        presignedHits += 1;
        expect(request.headers['content-type'], 'image/png');
        expect(request.bodyBytes, equals(Uint8List.fromList([1, 2, 3, 4])));
        return http.Response('', 200);
      }
      return http.Response('not found', 404);
    });

    final uploader = LumaArtifactUploader(client: realmClient, httpClient: uploadHttp);
    final artifact = await uploader.upload(
      session: session,
      realmId: 'realm-abc',
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      contentType: 'image/png',
      name: 'test.png',
      width: 800,
      height: 600,
    );

    expect(presignedHits, 1);
    expect(completionHits, 1);
    expect(artifact.state, 'ready');
    expect(artifact.id, isNotEmpty);
    uploader.close();
  });

  test('rejects empty payloads', () async {
    final uploader = LumaArtifactUploader(
      client: LumaRealmClient(httpClient: MockClient((_) async => http.Response('{}', 200))),
      httpClient: MockClient((_) async => http.Response('', 200)),
    );

    await expectLater(
      uploader.upload(
        session: session,
        realmId: 'realm-abc',
        bytes: Uint8List(0),
        contentType: 'image/png',
        name: 'empty.png',
      ),
      throwsA(isA<GeminiGatewayException>()),
    );
    uploader.close();
  });
}
