import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'kiro_auth_source.dart';

const _defaultKiroLinkAuthRequestTimeout = Duration(seconds: 20);
const List<String> _defaultKiroBuilderIdScopes = <String>[
  'codewhisperer:completions',
  'codewhisperer:analysis',
  'codewhisperer:conversations',
];

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
  });

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
        'Не удалось зарегистрировать Kiro Builder ID клиент '
        '(${registrationResponse.statusCode}).',
      );
    }

    final registration = _decodeJsonMap(registrationResponse.body);
    final clientId = (registration['clientId'] as String? ?? '').trim();
    final clientSecret = (registration['clientSecret'] as String? ?? '').trim();
    if (clientId.isEmpty || clientSecret.isEmpty) {
      throw StateError('Kiro Builder ID не вернул clientId/clientSecret.');
    }

    final deviceAuthorizationResponse = await _postJson(
      _oidcUri(resolvedRegion, '/device_authorization'),
      body: {'clientId': clientId, 'clientSecret': clientSecret, 'startUrl': resolvedStartUrl},
    );
    if (deviceAuthorizationResponse.statusCode >= 400) {
      throw StateError(
        'Не удалось запустить Kiro авторизацию по ссылке '
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
      throw StateError('Kiro Builder ID вернул неполные данные авторизации.');
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
    var nextDelay = request.interval;
    while (DateTime.now().isBefore(request.expiresAt)) {
      if (isCancelled?.call() == true) {
        throw StateError('Авторизация Kiro была отменена.');
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
        throw TimeoutException('Авторизация Kiro по ссылке истекла.');
      }

      final description = (payload['error_description'] as String? ?? '').trim();
      throw StateError(
        description.isNotEmpty ? description : 'Kiro отклонил авторизацию по ссылке.',
      );
    }

    throw TimeoutException('Авторизация Kiro по ссылке истекла.');
  }

  void dispose() {
    _http.close();
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
