import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/oauth_tokens.dart';
import '../../data/repositories/secret_store.dart';
import 'gemini_auth_constants.dart';

typedef OAuthUrlLauncher = Future<bool> Function(Uri url, {required LaunchMode mode});
typedef LaunchModeSupportChecker = Future<bool> Function(LaunchMode mode);
typedef PlatformCheck = bool Function();
typedef CodeExchangeHandler =
    Future<OAuthTokens> Function({
      required String code,
      required String redirectUri,
      required String codeVerifier,
    });
typedef ProfileFetcher = Future<Map<String, String>> Function(String accessToken);

class AuthenticatedGoogleAccount {
  const AuthenticatedGoogleAccount({
    required this.email,
    required this.displayName,
    required this.tokens,
  });

  final String email;
  final String displayName;
  final OAuthTokens tokens;
}

class GeminiOAuthService {
  GeminiOAuthService({
    required SecretStore secretStore,
    http.Client? httpClient,
    OAuthUrlLauncher? launchUrlDelegate,
    LaunchModeSupportChecker? supportsLaunchModeDelegate,
    PlatformCheck? isAndroid,
    CodeExchangeHandler? exchangeCodeForTokens,
    ProfileFetcher? fetchProfile,
    Duration authorizationTimeout = const Duration(minutes: 5),
  }) : _secretStore = secretStore,
       _http = httpClient ?? http.Client(),
       _launchUrl = launchUrlDelegate ?? ((url, {required mode}) => launchUrl(url, mode: mode)),
       _supportsLaunchMode = supportsLaunchModeDelegate ?? supportsLaunchMode,
       _isAndroid = isAndroid ?? _defaultIsAndroid,
       _exchangeCodeForTokensDelegate = exchangeCodeForTokens,
       _fetchProfileDelegate = fetchProfile,
       _authorizationTimeout = authorizationTimeout;

  final SecretStore _secretStore;
  final http.Client _http;
  final OAuthUrlLauncher _launchUrl;
  final LaunchModeSupportChecker _supportsLaunchMode;
  final PlatformCheck _isAndroid;
  final CodeExchangeHandler? _exchangeCodeForTokensDelegate;
  final ProfileFetcher? _fetchProfileDelegate;
  final Duration _authorizationTimeout;

  Future<AuthenticatedGoogleAccount> authenticate() async {
    final callbackServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${callbackServer.port}/oauth2callback';
    final state = _randomToken();
    final codeVerifier = _randomCodeVerifier();
    final codeChallenge = _buildCodeChallenge(codeVerifier);
    final completer = Completer<Map<String, String>>();

    callbackServer.listen((request) async {
      try {
        if (request.uri.path != '/oauth2callback') {
          request.response
            ..statusCode = HttpStatus.movedPermanently
            ..headers.set(
              HttpHeaders.locationHeader,
              'https://developers.google.com/gemini-code-assist/auth_failure_gemini',
            );
          await request.response.close();
          return;
        }

        final params = request.uri.queryParameters;
        if (params['state'] != state) {
          await _respondHtml(
            request,
            title: 'Authorization failed',
            message: 'State mismatch. You can close this tab.',
            isSuccess: false,
          );
          if (!completer.isCompleted) {
            completer.completeError(StateError('OAuth state mismatch. Please try again.'));
          }
          return;
        }

        if (params.containsKey('error')) {
          await _respondHtml(
            request,
            title: 'Authorization failed',
            message: 'Google returned an error. You can close this tab.',
            isSuccess: false,
          );
          if (!completer.isCompleted) {
            completer.completeError(
              StateError(
                'Google OAuth error: ${params['error']} ${params['error_description'] ?? ''}'
                    .trim(),
              ),
            );
          }
          return;
        }

        final code = params['code'];
        if (code == null || code.isEmpty) {
          await _respondHtml(
            request,
            title: 'Authorization failed',
            message: 'No code was received. You can close this tab.',
            isSuccess: false,
          );
          if (!completer.isCompleted) {
            completer.completeError(StateError('No authorization code received from Google.'));
          }
          return;
        }

        await _respondHtml(
          request,
          title: 'Authorization complete',
          message: 'KiCk received the login. You can close this tab.',
          isSuccess: true,
        );
        if (!completer.isCompleted) {
          completer.complete({'code': code, 'redirect_uri': redirectUri});
        }
      } catch (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      }
    });

    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': geminiOAuthClientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'access_type': 'offline',
      'prompt': 'consent select_account',
      'scope': geminiOAuthScopes.join(' '),
      'state': state,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    });

    try {
      final launched = await _launchUrl(authUrl, mode: await _resolveLaunchMode());
      if (!launched) {
        throw StateError('Could not open the browser for Google OAuth.');
      }

      final callback = await completer.future.timeout(
        _authorizationTimeout,
        onTimeout: () => throw TimeoutException('Google OAuth timed out.'),
      );

      final exchangeCodeForTokens = _exchangeCodeForTokensDelegate ?? _exchangeCodeForTokens;
      final fetchProfile = _fetchProfileDelegate ?? _fetchProfile;
      final tokens = await exchangeCodeForTokens(
        code: callback['code']!,
        redirectUri: callback['redirect_uri']!,
        codeVerifier: codeVerifier,
      );
      final profile = await fetchProfile(tokens.accessToken);
      return AuthenticatedGoogleAccount(
        email: profile['email'] ?? '',
        displayName: profile['name'] ?? profile['email'] ?? 'Google account',
        tokens: tokens,
      );
    } finally {
      await callbackServer.close(force: true);
    }
  }

  Future<OAuthTokens> refreshTokens(OAuthTokens tokens) async {
    final response = await _http.post(
      Uri.https('oauth2.googleapis.com', '/token'),
      headers: {HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded'},
      body: {
        'client_id': geminiOAuthClientId,
        'client_secret': geminiOAuthClientSecret,
        'refresh_token': tokens.refreshToken,
        'grant_type': 'refresh_token',
      },
    );

    if (response.statusCode >= 400) {
      throw StateError(
        'Failed to refresh Google OAuth tokens: ${response.statusCode} ${response.body}',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return OAuthTokens(
      accessToken: payload['access_token'] as String? ?? '',
      refreshToken: tokens.refreshToken,
      expiry: DateTime.now().add(Duration(seconds: payload['expires_in'] as int? ?? 3600)),
      tokenType: payload['token_type'] as String? ?? 'Bearer',
      scope: payload['scope'] as String?,
    );
  }

  Future<void> persistTokens(String tokenRef, OAuthTokens tokens) {
    return _secretStore.writeOAuthTokens(tokenRef, tokens);
  }

  Future<OAuthTokens?> readTokens(String tokenRef) {
    return _secretStore.readOAuthTokens(tokenRef);
  }

  Future<OAuthTokens> _exchangeCodeForTokens({
    required String code,
    required String redirectUri,
    required String codeVerifier,
  }) async {
    final response = await _http.post(
      Uri.https('oauth2.googleapis.com', '/token'),
      headers: {HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded'},
      body: {
        'code': code,
        'client_id': geminiOAuthClientId,
        'client_secret': geminiOAuthClientSecret,
        'code_verifier': codeVerifier,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
      },
    );

    if (response.statusCode >= 400) {
      throw StateError(
        'Failed to exchange authorization code: ${response.statusCode} ${response.body}',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return OAuthTokens(
      accessToken: payload['access_token'] as String? ?? '',
      refreshToken: payload['refresh_token'] as String? ?? '',
      expiry: DateTime.now().add(Duration(seconds: payload['expires_in'] as int? ?? 3600)),
      tokenType: payload['token_type'] as String? ?? 'Bearer',
      scope: payload['scope'] as String?,
    );
  }

  Future<Map<String, String>> _fetchProfile(String accessToken) async {
    final response = await _http.get(
      Uri.https('www.googleapis.com', '/oauth2/v2/userinfo'),
      headers: {HttpHeaders.authorizationHeader: 'Bearer $accessToken'},
    );
    if (response.statusCode >= 400) {
      throw StateError(
        'Failed to fetch Google account profile: ${response.statusCode} ${response.body}',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return payload.map((key, value) => MapEntry(key, value?.toString() ?? ''));
  }

  Future<LaunchMode> _resolveLaunchMode() async {
    if (!_isAndroid()) {
      return LaunchMode.externalApplication;
    }

    try {
      final supportsInAppBrowser = await _supportsLaunchMode(LaunchMode.inAppBrowserView);
      if (supportsInAppBrowser) {
        // Keep Android auth inside a custom tab so the app stays active while
        // waiting for the loopback callback on devices with aggressive backgrounding.
        return LaunchMode.inAppBrowserView;
      }
    } catch (_) {
      // Fall back to the external browser flow if launch mode detection fails.
    }

    return LaunchMode.externalApplication;
  }

  Future<void> _respondHtml(
    HttpRequest request, {
    required String title,
    required String message,
    required bool isSuccess,
  }) async {
    request.response.headers.contentType = ContentType.html;
    request.response.write('''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>$title</title>
    <style>
      body { font-family: Arial, sans-serif; background: #1d120f; color: #fff2eb; display:flex; align-items:center; justify-content:center; min-height:100vh; margin:0; }
      .card { max-width: 440px; padding: 24px; border-radius: 24px; background: #2d1e1a; box-shadow: 0 20px 60px rgba(0,0,0,0.25); }
      h1 { margin-top: 0; }
      p { line-height: 1.5; color: #f7d8cc; }
      .dot { width: 12px; height: 12px; border-radius: 999px; display:inline-block; margin-right: 8px; background: ${isSuccess ? '#00c26f' : '#ff6a5e'}; }
    </style>
  </head>
  <body>
    <div class="card">
      <h1><span class="dot"></span>$title</h1>
      <p>$message</p>
    </div>
  </body>
</html>
''');
    await request.response.close();
  }

  String _randomToken() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < 32; index++) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  String _randomCodeVerifier() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < 64; index++) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  String _buildCodeChallenge(String codeVerifier) {
    final digest = sha256.convert(utf8.encode(codeVerifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  static bool _defaultIsAndroid() {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }
}
