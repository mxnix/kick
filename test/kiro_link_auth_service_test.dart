import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kick/proxy/kiro/kiro_auth_source.dart';
import 'package:kick/proxy/kiro/kiro_link_auth_service.dart';

void main() {
  test('starts and completes builder id authorization', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick_kiro_link_auth');
    addTearDown(() => tempDirectory.delete(recursive: true));

    var tokenPolls = 0;
    final service = KiroLinkAuthService(
      httpClient: MockClient((request) async {
        if (request.url.path == '/client/register') {
          return http.Response(
            jsonEncode({'clientId': 'client-id', 'clientSecret': 'client-secret'}),
            200,
          );
        }
        if (request.url.path == '/device_authorization') {
          return http.Response(
            jsonEncode({
              'deviceCode': 'device-code',
              'userCode': 'USER-CODE',
              'verificationUri': 'https://device.example/verify',
              'verificationUriComplete': 'https://device.example/verify?user_code=USER-CODE',
              'interval': 1,
              'expiresIn': 120,
            }),
            200,
          );
        }
        if (request.url.path == '/token') {
          tokenPolls += 1;
          if (tokenPolls == 1) {
            return http.Response(jsonEncode({'error': 'authorization_pending'}), 400);
          }
          return http.Response(
            jsonEncode({
              'accessToken': 'access-token',
              'refreshToken': 'refresh-token',
              'expiresIn': 3600,
              'profileArn': 'arn:aws:iam::123456789012:user/demo',
            }),
            200,
          );
        }

        throw StateError('Unexpected request: ${request.url}');
      }),
      supportDirectoryProvider: () async => tempDirectory,
      wait: (_) async {},
    );

    final request = await service.startBuilderIdAuthorization();
    final snapshot = await service.completeBuilderIdAuthorization(request);

    expect(request.clientId, 'client-id');
    expect(request.clientSecret, 'client-secret');
    expect(request.userCode, 'USER-CODE');
    expect(tokenPolls, 2);
    expect(snapshot.sourceType, builderIdKiroCredentialSourceType);
    expect(snapshot.authMethod, builderIdKiroAuthMethod);
    expect(snapshot.accessToken, 'access-token');
    expect(snapshot.refreshToken, 'refresh-token');
    expect(snapshot.profileArn, 'arn:aws:iam::123456789012:user/demo');
    expect(File(snapshot.sourcePath).existsSync(), isTrue);
  });
}
