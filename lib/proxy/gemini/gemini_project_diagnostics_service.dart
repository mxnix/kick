import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../data/models/account_profile.dart';
import '../../data/models/oauth_tokens.dart';
import 'gemini_auth_constants.dart';
import 'gemini_client_fingerprint.dart';
import 'gemini_code_assist_client.dart';
import 'gemini_installation_identity.dart';

class GeminiProjectDiagnosticSnapshot {
  const GeminiProjectDiagnosticSnapshot({
    required this.checkedAt,
    required this.projectId,
    required this.modelId,
    this.modelVersion,
    this.responseId,
    this.traceId,
    this.probeText,
  });

  final DateTime checkedAt;
  final String projectId;
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
    Future<void> Function(AccountProfile account, String projectId)? onProjectIdResolved,
    GeminiInstallationIdLoader? privilegedUserIdLoader,
    http.Client? httpClient,
    String Function()? createDiagnosticId,
  }) : _readTokens = readTokens,
       _refreshTokens = refreshTokens,
       _persistTokens = persistTokens,
       _onProjectIdResolved = onProjectIdResolved ?? _noopProjectIdResolved,
       _privilegedUserIdLoader = privilegedUserIdLoader ?? GeminiInstallationIdLoader(),
       _http = httpClient ?? http.Client(),
       _createDiagnosticId = createDiagnosticId ?? const Uuid().v4;

  static const String probeMethodId = 'retrieveUserQuota';
  static const String probeHeaderModelId = geminiCodeAssistAuxiliaryHeaderModel;
  static const String _fallbackOnboardTierId = 'legacy-tier';
  static const int _projectDiscoveryMaxPollAttempts = 15;
  static const Duration _projectDiscoveryPollDelay = Duration(seconds: 2);

  final Future<OAuthTokens?> Function(String tokenRef) _readTokens;
  final Future<OAuthTokens> Function(OAuthTokens tokens) _refreshTokens;
  final Future<void> Function(String tokenRef, OAuthTokens tokens) _persistTokens;
  final Future<void> Function(AccountProfile account, String projectId) _onProjectIdResolved;
  final GeminiInstallationIdLoader _privilegedUserIdLoader;
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
    final privilegedUserId = await _privilegedUserIdLoader.load();
    final resolvedProjectId = await _ensureResolvedProjectId(account, tokens, privilegedUserId);
    final response = await _http.post(
      Uri.parse('$geminiCodeAssistEndpoint/$geminiCodeAssistApiVersion:$probeMethodId'),
      headers: buildGeminiCodeAssistHeaders(
        accessToken: tokens.accessToken,
        model: probeHeaderModelId,
        privilegedUserId: privilegedUserId,
        tokenType: tokens.tokenType,
      ),
      body: jsonEncode({'project': resolvedProjectId}),
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
      projectId: resolvedProjectId,
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

  Future<String> _ensureResolvedProjectId(
    AccountProfile account,
    OAuthTokens tokens,
    String privilegedUserId,
  ) async {
    final currentProjectId = account.projectId.trim();
    if (currentProjectId.isNotEmpty) {
      return currentProjectId;
    }

    final setup = await _loadCodeAssistSetup(tokens, privilegedUserId);
    var resolvedProjectId = setup.projectId;
    if (resolvedProjectId.isEmpty) {
      resolvedProjectId = await _discoverProjectId(tokens, privilegedUserId, setup.tierId);
    }
    if (resolvedProjectId.isEmpty) {
      throw GeminiGatewayException(
        kind: GeminiGatewayFailureKind.invalidRequest,
        message: 'Could not discover a valid Google Cloud project ID for this account.',
        statusCode: 400,
        detail: GeminiGatewayFailureDetail.projectIdMissing,
      );
    }

    await _onProjectIdResolved(account, resolvedProjectId);
    return resolvedProjectId;
  }

  Future<_ProjectSetup> _loadCodeAssistSetup(OAuthTokens tokens, String privilegedUserId) async {
    final response = await _postJson(
      methodId: 'loadCodeAssist',
      tokens: tokens,
      privilegedUserId: privilegedUserId,
      body: {'metadata': _setupMetadata},
    );
    return _ProjectSetup(
      projectId: _extractProjectId(response['cloudaicompanionProject']),
      tierId: _extractDefaultTierId(response['allowedTiers']),
    );
  }

  Future<String> _discoverProjectId(
    OAuthTokens tokens,
    String privilegedUserId,
    String tierId,
  ) async {
    for (var attempt = 0; attempt < _projectDiscoveryMaxPollAttempts; attempt++) {
      final response = await _postJson(
        methodId: 'onboardUser',
        tokens: tokens,
        privilegedUserId: privilegedUserId,
        body: {'tierId': tierId, 'metadata': _setupMetadata},
      );
      if (response['done'] == true) {
        final payload =
            (response['response'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
        return _extractProjectId(payload['cloudaicompanionProject']);
      }
      if (attempt + 1 < _projectDiscoveryMaxPollAttempts) {
        await Future<void>.delayed(_projectDiscoveryPollDelay);
      }
    }
    return '';
  }

  Future<Map<String, Object?>> _postJson({
    required String methodId,
    required OAuthTokens tokens,
    required String privilegedUserId,
    required Map<String, Object?> body,
  }) async {
    final response = await _http.post(
      Uri.parse('$geminiCodeAssistEndpoint/$geminiCodeAssistApiVersion:$methodId'),
      headers: buildGeminiCodeAssistHeaders(
        accessToken: tokens.accessToken,
        model: probeHeaderModelId,
        privilegedUserId: privilegedUserId,
        tokenType: tokens.tokenType,
      ),
      body: jsonEncode(body),
    );

    if (response.statusCode >= 400) {
      throw decodeGeminiGatewayError(response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Unexpected Gemini project diagnostics response shape.');
    }
    return decoded.cast<String, Object?>();
  }
}

const Map<String, String> _setupMetadata = <String, String>{
  'ideType': geminiCodeAssistIdeType,
  'platform': geminiCodeAssistPlatformUnspecified,
  'pluginType': geminiCodeAssistPluginType,
};

Future<void> _noopProjectIdResolved(AccountProfile account, String projectId) async {}

final class _ProjectSetup {
  const _ProjectSetup({required this.projectId, required this.tierId});

  final String projectId;
  final String tierId;
}

String _extractProjectId(Object? value) {
  if (value is String) {
    return value.trim();
  }
  if (value is Map) {
    return (value['id'] as String? ?? '').trim();
  }
  return '';
}

String _extractDefaultTierId(Object? value) {
  if (value is! List) {
    return GeminiProjectDiagnosticsService._fallbackOnboardTierId;
  }

  for (final rawTier in value) {
    if (rawTier is! Map) {
      continue;
    }
    if (rawTier['isDefault'] != true) {
      continue;
    }
    final tierId = (rawTier['id'] as String? ?? '').trim();
    if (tierId.isNotEmpty) {
      return tierId;
    }
  }
  return GeminiProjectDiagnosticsService._fallbackOnboardTierId;
}
