import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:kick/data/models/oauth_tokens.dart';
import 'package:kick/data/repositories/secret_store.dart';
import 'package:kick/proxy/gemini/gemini_oauth_service.dart';
import 'package:test/test.dart';
import 'package:url_launcher/url_launcher.dart';

import 'support/real_http_client.dart';

void main() {
  OAuthTokens sampleTokens({String accessToken = 'access-token'}) => OAuthTokens(
    accessToken: accessToken,
    refreshToken: 'refresh-token',
    expiry: DateTime.now().add(const Duration(hours: 1)),
    tokenType: 'Bearer',
    scope: null,
  );

  test('uses in-app browser on Android and survives stray loopback requests', () async {
    final launchedModes = <LaunchMode>[];
    var browserFlow = Future<void>.value();

    final service = GeminiOAuthService(
      secretStore: const SecretStore(),
      isAndroid: () => true,
      supportsLaunchModeDelegate: (mode) async => mode == LaunchMode.inAppBrowserView,
      launchUrlDelegate: (url, {required mode}) async {
        launchedModes.add(mode);
        final redirectUri = Uri.parse(url.queryParameters['redirect_uri']!);
        final state = url.queryParameters['state']!;
        browserFlow = _simulateBrowserFlow(redirectUri: redirectUri, state: state);
        return true;
      },
      exchangeCodeForTokens: ({required code, required redirectUri, required codeVerifier}) async {
        expect(code, 'oauth-code');
        expect(redirectUri, startsWith('http://127.0.0.1:'));
        expect(codeVerifier, isNotEmpty);
        return sampleTokens();
      },
      fetchProfile: (accessToken) async {
        expect(accessToken, 'access-token');
        return const GoogleAccountProfile(
          email: 'user@example.com',
          displayName: 'Test User',
          googleSubjectId: 'google-subject-1',
          avatarUrl: 'https://example.com/avatar.png',
        );
      },
    );

    final result = await service.authenticate();
    await browserFlow;

    expect(launchedModes, [LaunchMode.inAppBrowserView]);
    expect(result.email, 'user@example.com');
    expect(result.displayName, 'Test User');
    expect(result.googleSubjectId, 'google-subject-1');
    expect(result.avatarUrl, 'https://example.com/avatar.png');
  });

  test('falls back to external browser when custom tabs are unavailable', () async {
    final launchedModes = <LaunchMode>[];
    var browserFlow = Future<void>.value();

    final service = GeminiOAuthService(
      secretStore: const SecretStore(),
      isAndroid: () => true,
      supportsLaunchModeDelegate: (_) async => false,
      launchUrlDelegate: (url, {required mode}) async {
        launchedModes.add(mode);
        final redirectUri = Uri.parse(url.queryParameters['redirect_uri']!);
        final state = url.queryParameters['state']!;
        browserFlow = _simulateCallback(redirectUri: redirectUri, state: state);
        return true;
      },
      exchangeCodeForTokens: ({required code, required redirectUri, required codeVerifier}) async {
        return sampleTokens(accessToken: 'fallback-token');
      },
      fetchProfile: (accessToken) async {
        expect(accessToken, 'fallback-token');
        return const GoogleAccountProfile(
          email: 'fallback@example.com',
          displayName: 'Fallback User',
          googleSubjectId: 'fallback-subject',
        );
      },
    );

    final result = await service.authenticate();
    await browserFlow;

    expect(launchedModes, [LaunchMode.externalApplication]);
    expect(result.email, 'fallback@example.com');
    expect(result.googleSubjectId, 'fallback-subject');
  });

  test('closes the loopback server when OAuth times out', () async {
    Uri? redirectUri;

    final service = GeminiOAuthService(
      secretStore: const SecretStore(),
      isAndroid: () => true,
      supportsLaunchModeDelegate: (_) async => true,
      launchUrlDelegate: (url, {required mode}) async {
        redirectUri = Uri.parse(url.queryParameters['redirect_uri']!);
        return true;
      },
      authorizationTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(service.authenticate(), throwsA(isA<TimeoutException>()));
    expect(redirectUri, isNotNull);

    await expectLater(
      runWithRealHttpClient(() async {
        final client = HttpClient();
        try {
          final request = await client.getUrl(
            redirectUri!.replace(queryParameters: {'state': 's', 'code': 'c'}),
          );
          await request.close();
        } finally {
          client.close(force: true);
        }
      }),
      throwsA(isA<SocketException>()),
    );
  });

  test('times out stalled token refresh requests', () async {
    final service = GeminiOAuthService(
      secretStore: const SecretStore(),
      requestTimeout: const Duration(milliseconds: 10),
      httpClient: QueueHttpClient([
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return http.Response('{}', 200);
        },
      ]),
    );

    await expectLater(
      service.refreshTokens(sampleTokens()),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'message',
          'Google OAuth token refresh timed out.',
        ),
      ),
    );
  });
}

Future<void> _simulateBrowserFlow({required Uri redirectUri, required String state}) async {
  final strayResponse = await _fetchUri(redirectUri.replace(path: '/'), followRedirects: false);
  expect(strayResponse.statusCode, HttpStatus.movedPermanently);
  expect(
    strayResponse.location,
    'https://developers.google.com/gemini-code-assist/auth_failure_gemini',
  );

  final callbackResponse = await _fetchUri(
    redirectUri.replace(queryParameters: {'state': state, 'code': 'oauth-code'}),
  );
  expect(callbackResponse.statusCode, HttpStatus.ok);
  expect(callbackResponse.body, contains('Успешная авторизация'));
  expect(callbackResponse.body, contains('Вы можете закрыть вкладку.'));
}

Future<void> _simulateCallback({required Uri redirectUri, required String state}) async {
  final callbackResponse = await _fetchUri(
    redirectUri.replace(queryParameters: {'state': state, 'code': 'oauth-code'}),
  );
  expect(callbackResponse.statusCode, HttpStatus.ok);
}

Future<_ResponseSnapshot> _fetchUri(Uri uri, {bool followRedirects = true}) async {
  return runWithRealHttpClient(() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = followRedirects;
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      return _ResponseSnapshot(
        statusCode: response.statusCode,
        body: body,
        location: response.headers.value(HttpHeaders.locationHeader),
      );
    } finally {
      client.close(force: true);
    }
  });
}

class _ResponseSnapshot {
  const _ResponseSnapshot({required this.statusCode, required this.body, required this.location});

  final int statusCode;
  final String body;
  final String? location;
}

class QueueHttpClient extends http.BaseClient {
  QueueHttpClient(this._handlers);

  final List<Future<http.BaseResponse> Function(http.BaseRequest request)> _handlers;
  var _index = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_index >= _handlers.length) {
      throw StateError('No queued HTTP response for ${request.method} ${request.url}.');
    }

    final response = await _handlers[_index++](request);
    if (response is http.StreamedResponse) {
      return response;
    }
    if (response is http.Response) {
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
        reasonPhrase: response.reasonPhrase,
      );
    }
    throw StateError('Unsupported HTTP response type: ${response.runtimeType}.');
  }
}
