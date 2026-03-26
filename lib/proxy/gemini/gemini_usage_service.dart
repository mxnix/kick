import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../data/models/account_profile.dart';
import '../../data/models/oauth_tokens.dart';
import 'gemini_auth_constants.dart';
import 'gemini_client_fingerprint.dart';
import 'gemini_code_assist_client.dart';
import 'gemini_installation_identity.dart';
import 'gemini_usage_models.dart';

class GeminiUsageService {
  GeminiUsageService({
    required Future<OAuthTokens?> Function(String tokenRef) readTokens,
    required Future<OAuthTokens> Function(OAuthTokens tokens) refreshTokens,
    required Future<void> Function(String tokenRef, OAuthTokens tokens) persistTokens,
    GeminiInstallationIdLoader? privilegedUserIdLoader,
    http.Client? httpClient,
  }) : _readTokens = readTokens,
       _refreshTokens = refreshTokens,
       _persistTokens = persistTokens,
       _privilegedUserIdLoader = privilegedUserIdLoader ?? GeminiInstallationIdLoader(),
       _http = httpClient ?? http.Client();

  final Future<OAuthTokens?> Function(String tokenRef) _readTokens;
  final Future<OAuthTokens> Function(OAuthTokens tokens) _refreshTokens;
  final Future<void> Function(String tokenRef, OAuthTokens tokens) _persistTokens;
  final GeminiInstallationIdLoader _privilegedUserIdLoader;
  final http.Client _http;

  Future<GeminiUsageSnapshot> fetchUsage(AccountProfile account) async {
    final storedTokens = await _readTokens(account.tokenRef);
    if (storedTokens == null) {
      throw StateError('OAuth tokens for this account were not found.');
    }

    var activeTokens = storedTokens;
    if (activeTokens.isExpired) {
      activeTokens = await _refreshAndPersist(account.tokenRef, activeTokens);
    }

    try {
      return await _requestUsage(account, activeTokens);
    } on GeminiGatewayException catch (error) {
      if (!_shouldRetryWithTokenRefresh(error)) {
        rethrow;
      }

      activeTokens = await _refreshAndPersist(account.tokenRef, activeTokens);
      return _requestUsage(account, activeTokens);
    }
  }

  void dispose() {
    _http.close();
  }

  Future<GeminiUsageSnapshot> _requestUsage(AccountProfile account, OAuthTokens tokens) async {
    final privilegedUserId = await _resolvePrivilegedUserId();
    final response = await _http.post(
      Uri.parse('$geminiCodeAssistEndpoint/$geminiCodeAssistApiVersion:retrieveUserQuota'),
      headers: buildGeminiCodeAssistHeaders(
        accessToken: tokens.accessToken,
        model: geminiCodeAssistAuxiliaryHeaderModel,
        privilegedUserId: privilegedUserId,
        tokenType: tokens.tokenType,
      ),
      body: jsonEncode({'project': account.projectId}),
    );

    if (response.statusCode >= 400) {
      throw decodeGeminiGatewayError(response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Unexpected Gemini usage response shape.');
    }

    return GeminiUsageSnapshot.fromApi(decoded.cast<String, Object?>(), fetchedAt: DateTime.now());
  }

  Future<OAuthTokens> _refreshAndPersist(String tokenRef, OAuthTokens tokens) async {
    final refreshed = await _refreshTokens(tokens);
    await _persistTokens(tokenRef, refreshed);
    return refreshed;
  }

  bool _shouldRetryWithTokenRefresh(GeminiGatewayException error) {
    if (error.kind != GeminiGatewayFailureKind.auth) {
      return false;
    }

    return error.statusCode == HttpStatus.unauthorized && error.detail == null;
  }

  Future<String> _resolvePrivilegedUserId() async {
    if (!shouldSendGeminiPrivilegedUserId()) {
      return '';
    }
    return _privilegedUserIdLoader.load();
  }
}
