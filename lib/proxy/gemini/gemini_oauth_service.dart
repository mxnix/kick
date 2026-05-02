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
import '../../l10n/kick_localizations.dart';
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
typedef ProfileFetcher = Future<GoogleAccountProfile> Function(String accessToken);

class GoogleAccountProfile {
  const GoogleAccountProfile({
    required this.email,
    required this.displayName,
    this.googleSubjectId,
    this.avatarUrl,
  });

  final String email;
  final String displayName;
  final String? googleSubjectId;
  final String? avatarUrl;
}

class AuthenticatedGoogleAccount {
  const AuthenticatedGoogleAccount({
    required this.email,
    required this.displayName,
    this.googleSubjectId,
    this.avatarUrl,
    required this.tokens,
  });

  final String email;
  final String displayName;
  final String? googleSubjectId;
  final String? avatarUrl;
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
    KickLocalizations Function()? localizationsProvider,
    Duration authorizationTimeout = const Duration(minutes: 5),
    Duration requestTimeout = const Duration(seconds: 15),
  }) : _secretStore = secretStore,
       _http = httpClient ?? http.Client(),
       _launchUrl = launchUrlDelegate ?? ((url, {required mode}) => launchUrl(url, mode: mode)),
       _supportsLaunchMode = supportsLaunchModeDelegate ?? supportsLaunchMode,
       _isAndroid = isAndroid ?? _defaultIsAndroid,
       _exchangeCodeForTokensDelegate = exchangeCodeForTokens,
       _fetchProfileDelegate = fetchProfile,
       _localizationsProvider = localizationsProvider ?? lookupKickLocalizations,
       _authorizationTimeout = authorizationTimeout,
       _requestTimeout = requestTimeout > Duration.zero
           ? requestTimeout
           : const Duration(seconds: 15);

  final SecretStore _secretStore;
  final http.Client _http;
  final OAuthUrlLauncher _launchUrl;
  final LaunchModeSupportChecker _supportsLaunchMode;
  final PlatformCheck _isAndroid;
  final CodeExchangeHandler? _exchangeCodeForTokensDelegate;
  final ProfileFetcher? _fetchProfileDelegate;
  final KickLocalizations Function() _localizationsProvider;
  final Duration _authorizationTimeout;
  final Duration _requestTimeout;

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
        final l10n = _localizationsProvider();
        if (params['state'] != state) {
          await _respondHtml(
            request,
            l10n: l10n,
            title: l10n.oauthPageTitleError,
            message: l10n.oauthPageStateMismatchMessage,
            isSuccess: false,
          );
          if (!completer.isCompleted) {
            completer.completeError(StateError('Google OAuth state mismatch.'));
          }
          return;
        }

        if (params.containsKey('error')) {
          await _respondHtml(
            request,
            l10n: l10n,
            title: l10n.oauthPageTitleError,
            message: l10n.oauthPageGoogleErrorMessage,
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
            l10n: l10n,
            title: l10n.oauthPageTitleError,
            message: l10n.oauthPageCodeMissingMessage,
            isSuccess: false,
          );
          if (!completer.isCompleted) {
            completer.completeError(
              StateError('Google OAuth did not return an authorization code.'),
            );
          }
          return;
        }

        await _respondHtml(
          request,
          l10n: l10n,
          title: l10n.oauthPageTitleSuccess,
          message: l10n.oauthPageCloseTabMessage,
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
      final tokens = await _runWithRequestTimeout(
        () => exchangeCodeForTokens(
          code: callback['code']!,
          redirectUri: callback['redirect_uri']!,
          codeVerifier: codeVerifier,
        ),
        'Google OAuth token exchange',
      );
      final profile = await _runWithRequestTimeout(
        () => fetchProfile(tokens.accessToken),
        'Google profile lookup',
      );
      return AuthenticatedGoogleAccount(
        email: profile.email,
        displayName: profile.displayName,
        googleSubjectId: profile.googleSubjectId,
        avatarUrl: profile.avatarUrl,
        tokens: tokens,
      );
    } finally {
      await callbackServer.close(force: true);
    }
  }

  Future<OAuthTokens> refreshTokens(OAuthTokens tokens) async {
    final response = await _runWithRequestTimeout(
      () => _http.post(
        Uri.https('oauth2.googleapis.com', '/token'),
        headers: {HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded'},
        body: {
          'client_id': geminiOAuthClientId,
          'client_secret': geminiOAuthClientSecret,
          'refresh_token': tokens.refreshToken,
          'grant_type': 'refresh_token',
        },
      ),
      'Google OAuth token refresh',
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
    final response = await _runWithRequestTimeout(
      () => _http.post(
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
      ),
      'Google OAuth token exchange',
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

  Future<GoogleAccountProfile> _fetchProfile(String accessToken) async {
    final response = await _runWithRequestTimeout(
      () => _http.get(
        Uri.https('www.googleapis.com', '/oauth2/v2/userinfo'),
        headers: {HttpHeaders.authorizationHeader: 'Bearer $accessToken'},
      ),
      'Google profile lookup',
    );
    if (response.statusCode >= 400) {
      throw StateError(
        'Failed to fetch Google account profile: ${response.statusCode} ${response.body}',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final l10n = _localizationsProvider();
    final email = (payload['email'] as String? ?? '').trim();
    final displayName = (payload['name'] as String? ?? '').trim().isNotEmpty
        ? (payload['name'] as String).trim()
        : email.isNotEmpty
        ? email
        : l10n.accountDisplayNameFallbackGoogle;
    return GoogleAccountProfile(
      email: email,
      displayName: displayName,
      googleSubjectId: (payload['id'] as String?)?.trim(),
      avatarUrl: (payload['picture'] as String?)?.trim(),
    );
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

  Future<T> _runWithRequestTimeout<T>(Future<T> Function() operation, String label) {
    return operation().timeout(
      _requestTimeout,
      onTimeout: () => throw TimeoutException('$label timed out.'),
    );
  }

  Future<void> _respondHtml(
    HttpRequest request, {
    required KickLocalizations l10n,
    required String title,
    required String message,
    required bool isSuccess,
  }) async {
    final htmlLang = l10n.localeName.replaceAll('_', '-');
    final escapedTitle = const HtmlEscape().convert(title);
    final escapedMessage = const HtmlEscape().convert(message);
    final stateClass = isSuccess ? 'success' : 'error';
    request.response.headers.contentType = ContentType.html;
    request.response.write('''
<!DOCTYPE html>
<html lang="$htmlLang">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>$escapedTitle</title>
    <style>
      :root {
        color-scheme: dark;
        --surface: #101318;
        --surface-raised: #0b0f14;
        --surface-panel: #171c22;
        --surface-panel-high: #1f252d;
        --outline: rgba(184, 196, 211, 0.17);
        --outline-strong: rgba(184, 196, 211, 0.28);
        --text: #edf1f7;
        --text-muted: #c2c8d2;
        --shadow: rgba(0, 0, 0, 0.34);
      }

      body.success {
        --accent: #9fcaff;
        --accent-soft: rgba(159, 202, 255, 0.16);
        --accent-text: #cbe2ff;
      }

      body.error {
        --accent: #ffb4ab;
        --accent-soft: rgba(255, 180, 171, 0.16);
        --accent-text: #ffd6d1;
      }

      * {
        box-sizing: border-box;
      }

      html {
        min-height: 100%;
        background: var(--surface);
      }

      body {
        min-height: 100vh;
        min-height: 100svh;
        margin: 0;
        padding:
          max(24px, env(safe-area-inset-top))
          max(20px, env(safe-area-inset-right))
          max(24px, env(safe-area-inset-bottom))
          max(20px, env(safe-area-inset-left));
        display: grid;
        place-items: center;
        background:
          linear-gradient(180deg, rgba(159, 202, 255, 0.035), transparent 34%),
          var(--surface);
        color: var(--text);
        font-family:
          "Google Sans",
          "Segoe UI",
          system-ui,
          -apple-system,
          BlinkMacSystemFont,
          sans-serif;
        text-rendering: optimizeLegibility;
      }

      .shell {
        width: min(100%, 520px);
      }

      .page-title {
        margin: 0 0 24px;
        color: var(--text);
        font-size: clamp(2rem, 8vw, 3.25rem);
        line-height: 1.02;
        font-weight: 700;
        letter-spacing: 0;
      }

      .panel {
        padding: 22px;
        border: 1px solid var(--outline);
        border-radius: 36px;
        background: color-mix(in srgb, var(--surface-raised) 94%, var(--accent) 6%);
        box-shadow: 0 24px 60px var(--shadow);
      }

      @supports not (background: color-mix(in srgb, black, white)) {
        .panel {
          background: var(--surface-raised);
        }
      }

      .hero {
        padding: 10px 14px 18px;
      }

      .status-icon {
        width: 56px;
        height: 56px;
        margin-bottom: 18px;
        border-radius: 20px;
        display: grid;
        place-items: center;
        background: var(--accent-soft);
        color: var(--accent-text);
        border: 1px solid rgba(255, 255, 255, 0.06);
      }

      .status-icon::before {
        content: "";
        width: 20px;
        height: 11px;
        border-left: 3px solid currentColor;
        border-bottom: 3px solid currentColor;
        transform: translateY(-2px) rotate(-45deg);
      }

      body.error .status-icon::before {
        width: auto;
        height: auto;
        border: 0;
        transform: none;
        content: "!";
        font-size: 1.6rem;
        font-weight: 800;
        line-height: 1;
      }

      h1 {
        margin: 0;
        max-width: 11ch;
        color: var(--text);
        font-size: clamp(2rem, 8.5vw, 3.1rem);
        line-height: 1.06;
        font-weight: 800;
        letter-spacing: 0;
        overflow-wrap: anywhere;
      }

      .message-tile {
        margin-top: 22px;
        padding: 16px;
        display: flex;
        align-items: flex-start;
        gap: 12px;
        border: 1px solid var(--outline-strong);
        border-radius: 24px;
        background: var(--surface-panel);
      }

      .message-icon {
        flex: 0 0 auto;
        width: 34px;
        height: 34px;
        border-radius: 14px;
        display: grid;
        place-items: center;
        background: var(--surface-panel-high);
      }

      .message-icon::before {
        content: "";
        width: 10px;
        height: 10px;
        border-radius: 50%;
        background: var(--accent);
      }

      p {
        margin: 3px 0 0;
        color: var(--text-muted);
        font-size: 1.03rem;
        line-height: 1.45;
      }

      @media (max-width: 420px) {
        body {
          padding-left: 16px;
          padding-right: 16px;
        }

        .page-title {
          margin-bottom: 20px;
        }

        .panel {
          padding: 20px;
          border-radius: 32px;
        }

        .hero {
          padding-left: 4px;
          padding-right: 4px;
        }
      }
    </style>
  </head>
  <body class="$stateClass">
    <main class="shell" aria-labelledby="oauth-title">
      <p class="page-title">KiCk</p>
      <section class="panel">
        <div class="hero">
          <div class="status-icon" aria-hidden="true"></div>
          <h1 id="oauth-title">$escapedTitle</h1>
          <div class="message-tile">
            <span class="message-icon" aria-hidden="true"></span>
            <p>$escapedMessage</p>
          </div>
        </div>
      </section>
    </main>
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
