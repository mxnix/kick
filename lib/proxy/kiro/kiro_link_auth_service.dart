import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'kiro_auth_source.dart';

const _defaultKiroLinkAuthRequestTimeout = Duration(seconds: 20);
const _defaultKiroAuthorizationTimeout = Duration(minutes: 5);
const _kiroPortalUrl = 'https://app.kiro.dev';
const _kiroIdeVersion = '0.12.155';
// The Kiro IDE Cognito client accepts only this exact loopback redirect URI.
// Changing host/port causes Cognito to respond with redirect_mismatch.
const _kiroPortalCallbackHost = 'localhost';
const _kiroPortalCallbackPort = 3128;
const List<String> _defaultKiroBuilderIdScopes = <String>[
  'codewhisperer:completions',
  'codewhisperer:analysis',
  'codewhisperer:conversations',
];

enum KiroLinkAuthFlow { builderId, portalSocial }

class KiroLinkAuthRequest {
  const KiroLinkAuthRequest({
    required this.clientId,
    required this.clientSecret,
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.interval,
    required this.expiresAt,
    required this.region,
    required this.startUrl,
    this.flow = KiroLinkAuthFlow.builderId,
    this.state,
    this.redirectUri,
    String? codeVerifier,
    Future<Object?>? callbackFuture,
    HttpServer? callbackServer,
  }) : _codeVerifier = codeVerifier,
       _callbackFuture = callbackFuture,
       _callbackServer = callbackServer;

  final String clientId;
  final String clientSecret;
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final String verificationUriComplete;
  final Duration interval;
  final DateTime expiresAt;
  final String region;
  final String startUrl;
  final KiroLinkAuthFlow flow;
  final String? state;
  final String? redirectUri;
  final String? _codeVerifier;
  final Future<Object?>? _callbackFuture;
  final HttpServer? _callbackServer;
}

class KiroLinkAuthService {
  KiroLinkAuthService({
    http.Client? httpClient,
    Future<Directory> Function()? supportDirectoryProvider,
    Future<void> Function(Duration delay)? wait,
    Duration requestTimeout = _defaultKiroLinkAuthRequestTimeout,
  }) : _http = httpClient ?? http.Client(),
       _supportDirectoryProvider = supportDirectoryProvider ?? getApplicationSupportDirectory,
       _wait = wait ?? _defaultWait,
       _requestTimeout = requestTimeout > Duration.zero
           ? requestTimeout
           : _defaultKiroLinkAuthRequestTimeout;

  final http.Client _http;
  final Future<Directory> Function() _supportDirectoryProvider;
  final Future<void> Function(Duration delay) _wait;
  final Duration _requestTimeout;

  Future<KiroLinkAuthRequest> startSocialAuthorization({String region = defaultKiroRegion}) async {
    final resolvedRegion = region.trim().isEmpty ? defaultKiroRegion : region.trim();
    final state = _randomToken(16);
    final codeVerifier = _randomToken(32);
    final codeChallenge = _codeChallenge(codeVerifier);
    final HttpServer callbackServer;
    try {
      callbackServer = await HttpServer.bind(_kiroPortalCallbackHost, _kiroPortalCallbackPort);
    } on SocketException catch (error) {
      throw StateError(
        'Kiro sign-in callback port $_kiroPortalCallbackPort is already in use. '
        'Close other Kiro instances or applications using this port and try again. '
        'Details: ${error.message}',
      );
    }
    final redirectUri = 'http://$_kiroPortalCallbackHost:${callbackServer.port}';
    final callbackCompleter = Completer<Object?>();

    callbackServer.listen(
      (request) async {
        try {
          await _handlePortalCallback(
            request,
            expectedState: state,
            callbackCompleter: callbackCompleter,
          );
        } catch (error) {
          if (!callbackCompleter.isCompleted) {
            callbackCompleter.completeError(error);
          }
        }
      },
      onError: (Object error) {
        if (!callbackCompleter.isCompleted) {
          callbackCompleter.completeError(error);
        }
      },
    );

    final portalUrl = Uri.parse('$_kiroPortalUrl/signin').replace(
      queryParameters: {
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'redirect_uri': redirectUri,
        'redirect_from': 'KiroIDE',
      },
    );

    return KiroLinkAuthRequest(
      clientId: '',
      clientSecret: '',
      deviceCode: '',
      userCode: '',
      verificationUri: portalUrl.toString(),
      verificationUriComplete: portalUrl.toString(),
      interval: const Duration(milliseconds: 250),
      expiresAt: DateTime.now().add(_defaultKiroAuthorizationTimeout),
      region: resolvedRegion,
      startUrl: _kiroPortalUrl,
      flow: KiroLinkAuthFlow.portalSocial,
      state: state,
      redirectUri: redirectUri,
      codeVerifier: codeVerifier,
      callbackFuture: callbackCompleter.future,
      callbackServer: callbackServer,
    );
  }

  Future<KiroLinkAuthRequest> startBuilderIdAuthorization({
    String startUrl = defaultKiroBuilderIdStartUrl,
    String region = defaultKiroRegion,
  }) async {
    final resolvedRegion = region.trim().isEmpty ? defaultKiroRegion : region.trim();
    final resolvedStartUrl = startUrl.trim().isEmpty
        ? defaultKiroBuilderIdStartUrl
        : startUrl.trim();

    final registrationResponse = await _postJson(
      _oidcUri(resolvedRegion, '/client/register'),
      body: const <String, Object?>{
        'clientName': 'Kiro IDE',
        'clientType': 'public',
        'scopes': _defaultKiroBuilderIdScopes,
      },
      userAgent: 'KiroIDE',
    );
    if (registrationResponse.statusCode >= 400) {
      throw StateError(
        'Kiro Builder ID client registration failed (${registrationResponse.statusCode}).',
      );
    }

    final registration = _decodeJsonMap(registrationResponse.body);
    final clientId = (registration['clientId'] as String? ?? '').trim();
    final clientSecret = (registration['clientSecret'] as String? ?? '').trim();
    if (clientId.isEmpty || clientSecret.isEmpty) {
      throw StateError('Kiro Builder ID returned incomplete client credentials.');
    }

    final deviceAuthorizationResponse = await _postJson(
      _oidcUri(resolvedRegion, '/device_authorization'),
      body: {'clientId': clientId, 'clientSecret': clientSecret, 'startUrl': resolvedStartUrl},
    );
    if (deviceAuthorizationResponse.statusCode >= 400) {
      throw StateError(
        'Kiro link authorization could not be started '
        '(${deviceAuthorizationResponse.statusCode}).',
      );
    }

    final payload = _decodeJsonMap(deviceAuthorizationResponse.body);
    final deviceCode = (payload['deviceCode'] as String? ?? '').trim();
    final userCode = (payload['userCode'] as String? ?? '').trim();
    final verificationUri = (payload['verificationUri'] as String? ?? '').trim();
    final verificationUriComplete = (payload['verificationUriComplete'] as String? ?? '').trim();
    final intervalSeconds = (payload['interval'] as num?)?.toInt() ?? 5;
    final expiresInSeconds = (payload['expiresIn'] as num?)?.toInt() ?? 300;
    if (deviceCode.isEmpty ||
        userCode.isEmpty ||
        verificationUri.isEmpty ||
        verificationUriComplete.isEmpty) {
      throw StateError('Kiro link authorization returned incomplete device authorization data.');
    }

    return KiroLinkAuthRequest(
      clientId: clientId,
      clientSecret: clientSecret,
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: verificationUri,
      verificationUriComplete: verificationUriComplete,
      interval: Duration(seconds: intervalSeconds <= 0 ? 5 : intervalSeconds),
      expiresAt: DateTime.now().add(
        Duration(seconds: expiresInSeconds <= 0 ? 300 : expiresInSeconds),
      ),
      region: resolvedRegion,
      startUrl: resolvedStartUrl,
    );
  }

  Future<KiroAuthSourceSnapshot> completeBuilderIdAuthorization(
    KiroLinkAuthRequest request, {
    bool Function()? isCancelled,
  }) async {
    if (request.flow == KiroLinkAuthFlow.portalSocial) {
      return _completeSocialAuthorization(request, isCancelled: isCancelled);
    }

    var nextDelay = request.interval;
    while (DateTime.now().isBefore(request.expiresAt)) {
      if (isCancelled?.call() == true) {
        throw StateError('Kiro link authorization was canceled.');
      }

      final response = await _postJson(
        _oidcUri(request.region, '/token'),
        body: {
          'clientId': request.clientId,
          'clientSecret': request.clientSecret,
          'deviceCode': request.deviceCode,
          'grantType': 'urn:ietf:params:oauth:grant-type:device_code',
        },
        userAgent: 'KiroIDE',
      );
      final payload = _decodeJsonMap(response.body);

      if (response.statusCode < 400 &&
          (payload['accessToken'] as String?)?.trim().isNotEmpty == true) {
        final accessToken = (payload['accessToken'] as String?)!.trim();
        final refreshToken = (payload['refreshToken'] as String? ?? '').trim();
        final profileArn = (payload['profileArn'] as String?)?.trim();
        final expiresInSeconds = (payload['expiresIn'] as num?)?.toInt() ?? 3600;
        final snapshot = KiroAuthSourceSnapshot(
          sourcePath: '',
          sourceType: builderIdKiroCredentialSourceType,
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiry: DateTime.now().add(Duration(seconds: expiresInSeconds)),
          region: request.region,
          profileArn: profileArn,
          authMethod: builderIdKiroAuthMethod,
          provider: 'kiro',
          clientId: request.clientId,
          clientSecret: request.clientSecret,
          startUrl: request.startUrl,
        );
        return persistKiroAuthSourceSnapshot(
          snapshot,
          supportDirectoryProvider: _supportDirectoryProvider,
        );
      }

      final error = (payload['error'] as String? ?? '').trim().toLowerCase();
      if (error == 'authorization_pending') {
        await _wait(nextDelay);
        continue;
      }
      if (error == 'slow_down') {
        nextDelay += const Duration(seconds: 5);
        await _wait(nextDelay);
        continue;
      }
      if (error == 'expired_token') {
        throw TimeoutException('Kiro link authorization timed out.');
      }

      final description = (payload['error_description'] as String? ?? '').trim();
      throw StateError(
        description.isNotEmpty
            ? 'Kiro link authorization was rejected. $description'
            : 'Kiro link authorization was rejected.',
      );
    }

    throw TimeoutException('Kiro link authorization timed out.');
  }

  void dispose() {
    _http.close();
  }

  Future<KiroAuthSourceSnapshot> _completeSocialAuthorization(
    KiroLinkAuthRequest request, {
    bool Function()? isCancelled,
  }) async {
    final callbackFuture = request._callbackFuture;
    final callbackServer = request._callbackServer;
    final codeVerifier = request._codeVerifier;
    if (callbackFuture == null || callbackServer == null || codeVerifier == null) {
      throw StateError('Kiro portal authorization was not started.');
    }

    try {
      final callback = await Future.any([
        callbackFuture,
        _waitForCancellationOrTimeout<Object?>(request, isCancelled),
      ]);
      if (callback is! _KiroPortalCallback) {
        throw StateError('Kiro portal authorization returned an invalid callback.');
      }
      final provider = switch (callback.loginOption.toLowerCase()) {
        'google' => 'Google',
        'github' => 'Github',
        _ => throw StateError('Unsupported Kiro sign-in provider: ${callback.loginOption}.'),
      };
      final response = await _postJson(
        _kiroAuthUri(request.region, '/oauth/token'),
        body: {
          'code': callback.code,
          'code_verifier': codeVerifier,
          'redirect_uri': callback.redirectUri,
        },
        userAgent: _kiroUserAgent(),
      );
      if (response.statusCode >= 400) {
        throw StateError('Kiro token exchange failed (${response.statusCode}).');
      }

      final payload = _decodeJsonMap(response.body);
      final accessToken = (payload['accessToken'] as String? ?? '').trim();
      final refreshToken = (payload['refreshToken'] as String? ?? '').trim();
      final profileArn = (payload['profileArn'] as String?)?.trim();
      final expiresInSeconds = (payload['expiresIn'] as num?)?.toInt() ?? 3600;
      if (accessToken.isEmpty || refreshToken.isEmpty) {
        throw StateError('Kiro token exchange returned incomplete tokens.');
      }

      return persistKiroAuthSourceSnapshot(
        KiroAuthSourceSnapshot(
          sourcePath: '',
          sourceType: manualKiroCredentialSourceType,
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiry: DateTime.now().add(Duration(seconds: expiresInSeconds)),
          region: request.region,
          profileArn: profileArn,
          authMethod: socialKiroAuthMethod,
          provider: provider,
        ),
        supportDirectoryProvider: _supportDirectoryProvider,
      );
    } finally {
      await callbackServer.close(force: true);
    }
  }

  Future<T> _waitForCancellationOrTimeout<T>(
    KiroLinkAuthRequest request,
    bool Function()? isCancelled,
  ) async {
    while (DateTime.now().isBefore(request.expiresAt)) {
      if (isCancelled?.call() == true) {
        throw StateError('Kiro link authorization was canceled.');
      }
      await _wait(request.interval);
    }
    throw TimeoutException('Kiro link authorization timed out.');
  }

  Future<void> _handlePortalCallback(
    HttpRequest request, {
    required String expectedState,
    required Completer<Object?> callbackCompleter,
  }) async {
    if (request.uri.path != '/oauth/callback') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final params = request.uri.queryParameters;
    final error = params['error'];
    if (error != null && error.isNotEmpty) {
      await _redirectPortalCallback(request, success: false, message: params['error_description']);
      if (!callbackCompleter.isCompleted) {
        callbackCompleter.completeError(StateError('Kiro authorization failed: $error.'));
      }
      return;
    }

    final state = params['state'];
    if (state != expectedState) {
      await _redirectPortalCallback(request, success: false, message: 'State mismatch.');
      if (!callbackCompleter.isCompleted) {
        callbackCompleter.completeError(StateError('Kiro authorization state mismatch.'));
      }
      return;
    }

    final code = (params['code'] ?? '').trim();
    final loginOption = (params['login_option'] ?? '').trim();
    if (code.isEmpty || loginOption.isEmpty) {
      await _redirectPortalCallback(
        request,
        success: false,
        message: 'Authorization code missing.',
      );
      if (!callbackCompleter.isCompleted) {
        callbackCompleter.completeError(
          StateError('Kiro authorization did not return a social sign-in code.'),
        );
      }
      return;
    }

    final port = request.connectionInfo?.localPort;
    if (port == null) {
      await _redirectPortalCallback(request, success: false, message: 'Callback port missing.');
      if (!callbackCompleter.isCompleted) {
        callbackCompleter.completeError(StateError('Kiro authorization callback port missing.'));
      }
      return;
    }

    final tokenRedirectUri = Uri(
      scheme: 'http',
      host: _kiroPortalCallbackHost,
      port: port,
      path: request.uri.path,
      queryParameters: {'login_option': loginOption},
    ).toString();
    await _redirectPortalCallback(request, success: true);
    if (!callbackCompleter.isCompleted) {
      callbackCompleter.complete(
        _KiroPortalCallback(code: code, loginOption: loginOption, redirectUri: tokenRedirectUri),
      );
    }
  }

  Future<void> _redirectPortalCallback(
    HttpRequest request, {
    required bool success,
    String? message,
  }) async {
    final uri = Uri.parse('$_kiroPortalUrl/signin').replace(
      queryParameters: {
        'auth_status': success ? 'success' : 'error',
        'redirect_from': 'KiroIDE',
        if (!success && message?.trim().isNotEmpty == true) 'error_message': message!.trim(),
      },
    );
    request.response
      ..statusCode = HttpStatus.found
      ..headers.set(HttpHeaders.locationHeader, uri.toString());
    await request.response.close();
  }

  Future<http.Response> _postJson(
    Uri uri, {
    required Map<String, Object?> body,
    String? userAgent,
  }) {
    return _http
        .post(
          uri,
          headers: <String, String>{
            HttpHeaders.contentTypeHeader: 'application/json',
            if (userAgent?.trim().isNotEmpty == true)
              HttpHeaders.userAgentHeader: userAgent!.trim(),
          },
          body: jsonEncode(body),
        )
        .timeout(
          _requestTimeout,
          onTimeout: () => throw TimeoutException('Kiro link authorization timed out.'),
        );
  }

  Uri _oidcUri(String region, String path) {
    return Uri.parse('https://oidc.${region.trim()}.amazonaws.com$path');
  }

  Uri _kiroAuthUri(String region, String path) {
    return Uri.parse('https://prod.${region.trim()}.auth.desktop.kiro.dev$path');
  }
}

class _KiroPortalCallback {
  const _KiroPortalCallback({
    required this.code,
    required this.loginOption,
    required this.redirectUri,
  });

  final String code;
  final String loginOption;
  final String redirectUri;
}

Map<String, Object?> _decodeJsonMap(String body) {
  if (body.trim().isEmpty) {
    return const <String, Object?>{};
  }

  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      return decoded.cast<String, Object?>();
    }
  } on FormatException {
    return const <String, Object?>{};
  }

  return const <String, Object?>{};
}

Future<void> _defaultWait(Duration delay) {
  if (delay <= Duration.zero) {
    return Future<void>.value();
  }
  return Future<void>.delayed(delay);
}

final Random _secureRandom = Random.secure();

String _randomToken(int byteCount) {
  final bytes = List<int>.generate(byteCount, (_) => _secureRandom.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String _codeChallenge(String verifier) {
  return base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
}

String _kiroUserAgent() {
  final host = Platform.localHostname.trim();
  final user =
      Platform.environment['USERNAME']?.trim() ?? Platform.environment['USER']?.trim() ?? 'kick';
  final fingerprint = sha256
      .convert(utf8.encode('${host.isEmpty ? 'host' : host}-$user'))
      .toString();
  return 'KiroIDE-$_kiroIdeVersion-$fingerprint';
}
