import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../data/models/account_profile.dart';
import 'gemini_auth_constants.dart';
import 'gemini_client_fingerprint.dart';

typedef GeminiPlayTelemetryClock = DateTime Function();

class GeminiPlayTelemetryService {
  GeminiPlayTelemetryService({
    http.Client? httpClient,
    String Function()? createUuid,
    GeminiPlayTelemetryClock? clock,
    String? installationIdPath,
    Duration requestTimeout = const Duration(seconds: 10),
  }) : _http = httpClient ?? http.Client(),
       _createUuid = createUuid ?? const Uuid().v4,
       _clock = clock ?? DateTime.now,
       _installationIdPath = installationIdPath,
       _requestTimeout = requestTimeout > Duration.zero
           ? requestTimeout
           : const Duration(seconds: 10);

  final http.Client _http;
  final String Function() _createUuid;
  final GeminiPlayTelemetryClock _clock;
  final String? _installationIdPath;
  final Duration _requestTimeout;

  Future<void>? _pendingSend;
  bool _sent = false;
  String? _sessionId;

  String get _activeSessionId => _sessionId ??= _createUuid();

  Future<void> sendSessionTelemetryOnce({
    required Iterable<AccountProfile> accounts,
    String startSessionModel = geminiPlayTelemetryStartSessionModel,
    String apiRequestModel = geminiCodeAssistWarmupModel,
  }) {
    if (_sent) {
      return Future<void>.value();
    }

    return _pendingSend ??= _send(
      accounts: accounts,
      startSessionModel: startSessionModel,
      apiRequestModel: apiRequestModel,
    ).then((_) {
      _sent = true;
    }).whenComplete(() {
      _pendingSend = null;
    });
  }

  void dispose() {
    _http.close();
  }

  Future<void> _send({
    required Iterable<AccountProfile> accounts,
    required String startSessionModel,
    required String apiRequestModel,
  }) async {
    final normalizedAccounts = accounts.where((account) => account.enabled).toList(growable: false);
    final sessionId = _activeSessionId;
    final promptId = '$sessionId########0';
    final accountCount = normalizedAccounts.length;
    final authType = accountCount > 0 ? 'oauth-personal' : 'unknown';
    final clientEmail = _firstClientEmail(normalizedAccounts);
    final clientInstallId = clientEmail == null ? await _loadOrCreateInstallationId() : null;
    final now = _clock().toUtc();
    final requestTimeMs = now.millisecondsSinceEpoch;
    final defaultMetadata = _defaultMetadata(
      sessionId: sessionId,
      promptId: sessionId,
      accountCount: accountCount,
      authType: authType,
    );
    final sessionData = _startSessionMetadata(startSessionModel);

    final requestBody = <Map<String, Object?>>[
      {
        'log_source_name': geminiPlayTelemetrySourceName,
        'request_time_ms': requestTimeMs,
        'log_event': [
          [
            _logEventEntry(
              eventTimeMs: requestTimeMs - 1,
              event: _logEvent(
                eventName: 'start_session',
                clientEmail: clientEmail,
                clientInstallId: clientInstallId,
                metadata: [...sessionData, ...defaultMetadata, ..._baseMetadata()],
              ),
            ),
          ],
          [
            _logEventEntry(
              eventTimeMs: requestTimeMs,
              event: _logEvent(
                eventName: 'api_request',
                clientEmail: clientEmail,
                clientInstallId: clientInstallId,
                metadata: [
                  _eventValue(_TelemetryMetadataKey.apiRequestModel, jsonEncode(apiRequestModel)),
                  ...sessionData,
                  ..._defaultMetadata(
                    sessionId: sessionId,
                    promptId: promptId,
                    accountCount: accountCount,
                    authType: authType,
                  ),
                  ..._baseMetadata(),
                ],
              ),
            ),
          ],
        ],
      },
    ];

    final response = await _http
        .post(
          Uri.parse(geminiPlayTelemetryEndpoint),
          headers: {
            HttpHeaders.contentTypeHeader: 'application/json',
            HttpHeaders.acceptHeader: '*/*',
            HttpHeaders.userAgentHeader: 'node',
          },
          body: jsonEncode(requestBody),
        )
        .timeout(_requestTimeout);

    if (response.statusCode >= 400) {
      throw HttpException(
        'Gemini play telemetry request failed with status ${response.statusCode}.',
        uri: Uri.parse(geminiPlayTelemetryEndpoint),
      );
    }
  }

  Map<String, Object?> _logEvent({
    required String eventName,
    required String? clientEmail,
    required String? clientInstallId,
    required List<Map<String, Object?>> metadata,
  }) {
    return {
      'console_type': geminiPlayTelemetryConsoleType,
      'application': geminiPlayTelemetryApplicationId,
      'event_name': eventName,
      'event_metadata': [metadata],
      ...?switch (clientEmail) {
        final email? => {'client_email': email},
        _ => null,
      },
      ...?switch ((clientEmail, clientInstallId)) {
        (null, final installId?) => {'client_install_id': installId},
        _ => null,
      },
    };
  }

  Map<String, Object?> _logEventEntry({
    required int eventTimeMs,
    required Map<String, Object?> event,
  }) {
    return {'event_time_ms': eventTimeMs, 'source_extension_json': jsonEncode(event)};
  }

  List<Map<String, Object?>> _startSessionMetadata(String startSessionModel) {
    return <Map<String, Object?>>[
      _eventValue(_TelemetryMetadataKey.startSessionModel, startSessionModel),
      _eventValue(_TelemetryMetadataKey.startSessionEmbeddingModel, geminiPlayTelemetryEmbeddingModel),
      _eventValue(_TelemetryMetadataKey.startSessionSandboxEnabled, 'false'),
      _eventValue(_TelemetryMetadataKey.startSessionCoreTools, ''),
      _eventValue(_TelemetryMetadataKey.startSessionApprovalMode, geminiPlayTelemetryApprovalMode),
      _eventValue(_TelemetryMetadataKey.startSessionApiKeyEnabled, 'false'),
      _eventValue(_TelemetryMetadataKey.startSessionVertexApiEnabled, 'false'),
      _eventValue(_TelemetryMetadataKey.startSessionDebugModeEnabled, 'false'),
      _eventValue(_TelemetryMetadataKey.startSessionMcpServers, ''),
      _eventValue(_TelemetryMetadataKey.startSessionTelemetryEnabled, 'false'),
      _eventValue(_TelemetryMetadataKey.startSessionTelemetryLogPromptsEnabled, 'true'),
      _eventValue(_TelemetryMetadataKey.startSessionMcpServersCount, ''),
      _eventValue(_TelemetryMetadataKey.startSessionMcpToolsCount, ''),
      _eventValue(_TelemetryMetadataKey.startSessionMcpTools, ''),
      _eventValue(_TelemetryMetadataKey.startSessionExtensionsCount, '0'),
      _eventValue(_TelemetryMetadataKey.startSessionExtensionIds, ''),
    ];
  }

  List<Map<String, Object?>> _defaultMetadata({
    required String sessionId,
    required String promptId,
    required int accountCount,
    required String authType,
  }) {
    return <Map<String, Object?>>[
      _eventValue(_TelemetryMetadataKey.sessionId, sessionId),
      _eventValue(_TelemetryMetadataKey.authType, jsonEncode(authType)),
      _eventValue(_TelemetryMetadataKey.googleAccountsCount, '$accountCount'),
      _eventValue(_TelemetryMetadataKey.promptId, promptId),
      _eventValue(_TelemetryMetadataKey.nodeVersion, geminiCodeAssistNodeRuntimeVersion),
      _eventValue(_TelemetryMetadataKey.userSettings, _defaultUserSettingsJson),
      _eventValue(_TelemetryMetadataKey.interactive, 'true'),
      _eventValue(_TelemetryMetadataKey.activeApprovalMode, geminiPlayTelemetryApprovalMode),
    ];
  }

  List<Map<String, Object?>> _baseMetadata() {
    return <Map<String, Object?>>[
      _eventValue(_TelemetryMetadataKey.surface, geminiPlayTelemetrySurface),
      _eventValue(_TelemetryMetadataKey.version, geminiCodeAssistCliVersion),
      _eventValue(_TelemetryMetadataKey.gitCommitHash, geminiCodeAssistCliGitCommitHash),
      _eventValue(_TelemetryMetadataKey.os, nodeStylePlatform()),
    ];
  }

  Map<String, Object?> _eventValue(int key, String value) {
    return {'gemini_cli_key': key, 'value': value};
  }

  String? _firstClientEmail(List<AccountProfile> accounts) {
    for (final account in accounts) {
      final email = account.email.trim();
      if (email.isNotEmpty) {
        return email;
      }
    }
    return null;
  }

  Future<String> _loadOrCreateInstallationId() async {
    final installationIdPath = _installationIdPath;
    if (installationIdPath == null || installationIdPath.trim().isEmpty) {
      return _createUuid();
    }

    final file = File(installationIdPath);
    try {
      final existing = (await file.readAsString()).trim();
      if (existing.isNotEmpty) {
        return existing;
      }
    } on FileSystemException {
      // Fall through and create a new identifier.
    }

    final created = _createUuid();
    await file.parent.create(recursive: true);
    await file.writeAsString(created, flush: true);
    return created;
  }

  static const String _defaultUserSettingsJson =
      '{"debugMode":false,"usageStatisticsEnabled":true,"interactive":true,'
      '"initialized":true,"mcpEnabled":false,"extensionsEnabled":false,'
      '"planEnabled":false,"trackerEnabled":false}';
}

abstract final class _TelemetryMetadataKey {
  static const int startSessionModel = 1;
  static const int startSessionEmbeddingModel = 2;
  static const int startSessionSandboxEnabled = 3;
  static const int startSessionCoreTools = 4;
  static const int startSessionApprovalMode = 5;
  static const int startSessionApiKeyEnabled = 6;
  static const int startSessionVertexApiEnabled = 7;
  static const int startSessionDebugModeEnabled = 8;
  static const int startSessionMcpServers = 9;
  static const int startSessionTelemetryEnabled = 10;
  static const int startSessionTelemetryLogPromptsEnabled = 11;
  static const int apiRequestModel = 20;
  static const int promptId = 35;
  static const int authType = 36;
  static const int googleAccountsCount = 37;
  static const int surface = 39;
  static const int sessionId = 40;
  static const int version = 54;
  static const int gitCommitHash = 55;
  static const int startSessionMcpServersCount = 63;
  static const int startSessionMcpToolsCount = 64;
  static const int startSessionMcpTools = 65;
  static const int os = 82;
  static const int nodeVersion = 83;
  static const int userSettings = 84;
  static const int startSessionExtensionsCount = 119;
  static const int startSessionExtensionIds = 120;
  static const int interactive = 125;
  static const int activeApprovalMode = 141;
}
