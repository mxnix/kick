import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../data/models/account_profile.dart';
import '../../data/models/oauth_tokens.dart';
import 'gemini_auth_constants.dart';
import 'gemini_client_fingerprint.dart';
import 'gemini_code_assist_client.dart';

class GeminiProjectDiagnosticSnapshot {
  const GeminiProjectDiagnosticSnapshot({
    required this.checkedAt,
    required this.modelId,
    this.modelVersion,
    this.responseId,
    this.traceId,
    this.probeText,
  });

  final DateTime checkedAt;
  final String modelId;
  final String? modelVersion;
  final String? responseId;
  final String? traceId;
  final String? probeText;
}

class GeminiProjectDiagnosticsService {
  GeminiProjectDiagnosticsService({
    required Future<OAuthTokens?> Function(String tokenRef) readTokens,
    required Future<OAuthTokens> Function(OAuthTokens tokens) refreshTokens,
    required Future<void> Function(String tokenRef, OAuthTokens tokens) persistTokens,
    http.Client? httpClient,
    String Function()? createDiagnosticId,
  }) : _readTokens = readTokens,
       _refreshTokens = refreshTokens,
       _persistTokens = persistTokens,
       _http = httpClient ?? http.Client(),
       _createDiagnosticId = createDiagnosticId ?? const Uuid().v4;

  static const String probeMethodId = 'retrieveUserQuota';
  static const String probeHeaderModelId = geminiCodeAssistAuxiliaryHeaderModel;

  final Future<OAuthTokens?> Function(String tokenRef) _readTokens;
  final Future<OAuthTokens> Function(OAuthTokens tokens) _refreshTokens;
  final Future<void> Function(String tokenRef, OAuthTokens tokens) _persistTokens;
  final http.Client _http;
  final String Function() _createDiagnosticId;

  Future<GeminiProjectDiagnosticSnapshot> diagnose(AccountProfile account) async {
    final storedTokens = await _readTokens(account.tokenRef);
    if (storedTokens == null) {
      throw StateError('OAuth tokens for this account were not found.');
    }

    var activeTokens = storedTokens;
    if (activeTokens.isExpired) {
      activeTokens = await _refreshAndPersist(account.tokenRef, activeTokens);
    }

    try {
      return await _requestDiagnostic(account, activeTokens);
    } on GeminiGatewayException catch (error) {
      if (!_shouldRetryWithTokenRefresh(error)) {
        rethrow;
      }

      activeTokens = await _refreshAndPersist(account.tokenRef, activeTokens);
      return _requestDiagnostic(account, activeTokens);
    }
  }

  void dispose() {
    _http.close();
  }

  Future<GeminiProjectDiagnosticSnapshot> _requestDiagnostic(
    AccountProfile account,
    OAuthTokens tokens,
  ) async {
    final diagnosticId = _createDiagnosticId();
    final response = await _http.post(
      Uri.parse('$geminiCodeAssistEndpoint/$geminiCodeAssistApiVersion:$probeMethodId'),
      headers: buildGeminiCodeAssistHeaders(
        accessToken: tokens.accessToken,
        model: probeHeaderModelId,
        tokenType: tokens.tokenType,
      ),
      body: jsonEncode({'project': account.projectId}),
    );

    if (response.statusCode >= 400) {
      throw decodeGeminiGatewayError(response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Unexpected Gemini project diagnostics response shape.');
    }

    final payload = decoded.cast<String, Object?>();

    return GeminiProjectDiagnosticSnapshot(
      checkedAt: DateTime.now(),
      modelId: probeHeaderModelId,
      modelVersion: null,
      responseId: diagnosticId,
      traceId: payload['traceId'] as String?,
      probeText: null,
    );
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
}
