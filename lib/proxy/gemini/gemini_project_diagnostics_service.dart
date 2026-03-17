import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../data/models/account_profile.dart';
import '../../data/models/oauth_tokens.dart';
import 'gemini_auth_constants.dart';
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
  }) : _readTokens = readTokens,
       _refreshTokens = refreshTokens,
       _persistTokens = persistTokens,
       _http = httpClient ?? http.Client();

  static const String probeModelId = 'gemini-2.5-flash';
  static const String _probeRequestId = 'project-diagnostic';
  static const String _probeSessionId = 'session-project-diagnostic';
  static const String _probeText = 'ok';
  static const List<Map<String, String>> _safetySettings = <Map<String, String>>[
    {'category': 'HARM_CATEGORY_HARASSMENT', 'threshold': 'OFF'},
    {'category': 'HARM_CATEGORY_HATE_SPEECH', 'threshold': 'OFF'},
    {'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT', 'threshold': 'OFF'},
    {'category': 'HARM_CATEGORY_DANGEROUS_CONTENT', 'threshold': 'OFF'},
    {'category': 'HARM_CATEGORY_CIVIC_INTEGRITY', 'threshold': 'OFF'},
  ];

  final Future<OAuthTokens?> Function(String tokenRef) _readTokens;
  final Future<OAuthTokens> Function(OAuthTokens tokens) _refreshTokens;
  final Future<void> Function(String tokenRef, OAuthTokens tokens) _persistTokens;
  final http.Client _http;

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
    final response = await _http.post(
      Uri.parse('$geminiCodeAssistEndpoint/$geminiCodeAssistApiVersion:generateContent'),
      headers: {
        HttpHeaders.authorizationHeader: '${tokens.tokenType} ${tokens.accessToken}',
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.userAgentHeader:
            '$geminiCodeAssistUserAgentPrefix/$probeModelId (${Platform.operatingSystem})',
      },
      body: jsonEncode({
        'model': probeModelId,
        'project': account.projectId,
        'user_prompt_id': '$_probeSessionId########$_probeRequestId',
        'request': {
          'contents': [
            {
              'role': 'user',
              'parts': [
                {
                  'text':
                      'Reply with exactly `$_probeText`. Do not add any extra words or punctuation.',
                },
              ],
            },
          ],
          'generationConfig': {
            'maxOutputTokens': 16,
            'thinkingConfig': {'thinkingBudget': 0, 'includeThoughts': false},
            'responseModalities': ['TEXT'],
          },
          'safetySettings': _safetySettings,
          'session_id': _probeSessionId,
        },
      }),
    );

    if (response.statusCode >= 400) {
      throw decodeGeminiGatewayError(response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Unexpected Gemini project diagnostics response shape.');
    }

    final payload = decoded.cast<String, Object?>();
    final responsePayload = ((payload['response'] as Map?) ?? const <String, Object?>{})
        .cast<String, Object?>();
    final candidates = (responsePayload['candidates'] as List?) ?? const [];
    final firstCandidate = candidates.isNotEmpty && candidates.first is Map
        ? (candidates.first as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final content = ((firstCandidate['content'] as Map?) ?? const <String, Object?>{})
        .cast<String, Object?>();
    final parts = (content['parts'] as List?) ?? const [];
    final buffer = StringBuffer();
    for (final rawPart in parts) {
      if (rawPart is! Map) {
        continue;
      }
      final part = rawPart.cast<String, Object?>();
      if (part['text'] is String) {
        buffer.write(part['text'] as String);
      }
    }

    return GeminiProjectDiagnosticSnapshot(
      checkedAt: DateTime.now(),
      modelId: probeModelId,
      modelVersion: responsePayload['modelVersion'] as String?,
      responseId: responsePayload['responseId'] as String?,
      traceId: payload['traceId'] as String?,
      probeText: buffer.toString().trim().isEmpty ? null : buffer.toString().trim(),
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
