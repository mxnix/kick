import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../data/models/account_profile.dart';
import '../gemini/gemini_code_assist_client.dart'
    show GeminiGatewayException, GeminiGatewayFailureKind, GeminiGatewayFailureSource;
import 'luma_realm_models.dart';
import 'luma_session.dart';

/// Stateless HTTP client around the Lumalabs Vespa REST surface.
///
/// The client owns no session of its own - callers pass an immutable
/// `LumaSession` to every call. This makes it safe to use from background
/// isolates and from unit tests with a fake `http.Client`.
class LumaRealmClient {
  LumaRealmClient({
    http.Client? httpClient,
    Duration requestTimeout = const Duration(seconds: 30),
    String userAgent = _defaultUserAgent,
    String clientContext = _defaultClientContext,
  }) : _http = httpClient ?? http.Client(),
       _requestTimeout = requestTimeout,
       _userAgent = userAgent,
       _clientContext = clientContext;

  static const _host = lumaPrimaryHost;
  static const _basePath = '/api/vespa';
  static const _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
  static const _defaultClientContext = 'name=kick,locale=en-US';

  final http.Client _http;
  final Duration _requestTimeout;
  final String _userAgent;
  final String _clientContext;

  /// Lists teams visible to the current session. Returns the first valid
  /// `accepted` team membership or `null` if there is none.
  Future<LumaTeamMembership?> readPrimaryTeam(LumaSession session) async {
    final json = await _getJson(session, '$_basePath/teams');
    if (json is! Map) {
      return null;
    }
    final accepted = (json['accepted'] as List?) ?? const [];
    for (final entry in accepted) {
      if (entry is Map) {
        final membership = LumaTeamMembership.fromJson(entry.cast<String, Object?>());
        if (membership.isValid) {
          return membership;
        }
      }
    }
    return null;
  }

  /// Reads the team's billing/usage snapshot.
  /// See `.tmp/luma/full/GET___api__vespa__teams___uuid___usage.json` for a
  /// sample payload. Returns the JSON map as-is.
  Future<Map<String, Object?>> readTeamUsage(LumaSession session, String teamId) async {
    final json = await _getJson(session, '$_basePath/teams/$teamId/usage');
    if (json is! Map) {
      throw _gatewayError(
        kind: GeminiGatewayFailureKind.unknown,
        message: 'Unexpected usage payload from team $teamId.',
      );
    }
    return json.cast<String, Object?>();
  }

  /// Lists realms inside [teamId]. Empty list when the team has none yet.
  Future<List<LumaRealmRef>> listRealms(LumaSession session, String teamId) async {
    final json = await _getJson(session, '$_basePath/teams/$teamId/realms');
    final realms = <LumaRealmRef>[];
    if (json is List) {
      for (final entry in json) {
        if (entry is Map) {
          final realm = LumaRealmRef.fromJson(entry.cast<String, Object?>());
          if (realm.isValid) {
            realms.add(realm);
          }
        }
      }
    }
    return realms;
  }

  /// Creates a new realm in [teamId] with the given [name].
  Future<LumaRealmRef> createRealm(
    LumaSession session, {
    required String teamId,
    required String name,
  }) async {
    final json = await _postJson(
      session,
      '$_basePath/teams/$teamId/realms',
      body: jsonEncode({'name': name}),
    );
    if (json is! Map) {
      throw _gatewayError(
        kind: GeminiGatewayFailureKind.unknown,
        message: 'Unexpected response shape from POST /teams/$teamId/realms.',
      );
    }
    final realm = LumaRealmRef.fromJson(json.cast<String, Object?>());
    if (!realm.isValid) {
      throw _gatewayError(
        kind: GeminiGatewayFailureKind.unknown,
        message: 'Luma did not return a realm id when creating a realm.',
      );
    }
    return realm;
  }

  /// Returns the CDN/WebSocket signing material for [realmId].
  Future<LumaRealmSignature> readRealmSignature(LumaSession session, String realmId) async {
    final json = await _getJson(session, '$_basePath/realms/$realmId/signature');
    if (json is! Map) {
      throw _gatewayError(
        kind: GeminiGatewayFailureKind.unknown,
        message: 'Unexpected signature payload from realm $realmId.',
      );
    }
    return LumaRealmSignature.fromJson(json.cast<String, Object?>());
  }

  /// Runs a preflight check against [realmId] for the given action [type].
  /// Returns the credit estimate and output specs without consuming credits.
  Future<LumaActionPreflight> preflightAction(
    LumaSession session, {
    required String realmId,
    required String type,
    required Map<String, Object?> fields,
  }) async {
    final json = await _postJson(
      session,
      '$_basePath/realms/$realmId/actions/preflight',
      body: jsonEncode({'type': type, 'fields': fields}),
    );
    if (json is! Map) {
      throw _gatewayError(
        kind: GeminiGatewayFailureKind.unknown,
        message: 'Unexpected preflight response for action `$type`.',
      );
    }
    return LumaActionPreflight.fromJson(json.cast<String, Object?>());
  }

  /// Submits a generation action against [realmId]. The server returns the
  /// pending action plus optimistic output artifact ids.
  Future<LumaActionSubmission> submitAction(
    LumaSession session, {
    required String realmId,
    required String type,
    required Map<String, Object?> fields,
    List<String>? optimisticOutputIds,
  }) async {
    final json = await _postJson(
      session,
      '$_basePath/realms/$realmId/actions',
      body: encodeLumaActionBody(
        type: type,
        fields: fields,
        optimisticOutputIds: optimisticOutputIds,
      ),
    );
    if (json is! Map) {
      throw _gatewayError(
        kind: GeminiGatewayFailureKind.unknown,
        message: 'Unexpected action submission response for `$type`.',
      );
    }
    return LumaActionSubmission.fromJson(json.cast<String, Object?>());
  }

  /// Reserves a new artifact slot and obtains a presigned S3 URL the caller
  /// must `PUT` the binary payload to. Once uploaded, call [completeArtifact].
  Future<LumaArtifact> reserveArtifact(
    LumaSession session, {
    required String realmId,
    required String contentType,
    required String name,
    int? width,
    int? height,
    String source = 'upload',
    String? id,
  }) async {
    final artifactId = id ?? generateLumaArtifactId();
    final body = <String, Object?>{
      'type': contentType,
      'id': artifactId,
      'source': source,
      'name': name,
      if (width != null || height != null)
        'meta': <String, Object?>{
          if (width != null) 'width': width,
          if (height != null) 'height': height,
        },
    };
    final json = await _postJson(
      session,
      '$_basePath/realms/$realmId/artifacts',
      body: jsonEncode(body),
    );
    if (json is! Map) {
      throw _gatewayError(
        kind: GeminiGatewayFailureKind.unknown,
        message: 'Unexpected artifact reservation payload.',
      );
    }
    final artifact = LumaArtifact.fromJson(json.cast<String, Object?>());
    if (artifact.id.isEmpty || artifact.presignedUrl == null) {
      throw _gatewayError(
        kind: GeminiGatewayFailureKind.unknown,
        message: 'Luma did not return a presigned upload URL.',
      );
    }
    return artifact;
  }

  /// Marks an uploaded artifact as complete so the server starts thumbnailing
  /// and probing. Idempotent; safe to retry.
  Future<LumaArtifact> completeArtifact(
    LumaSession session, {
    required String realmId,
    required String artifactId,
  }) async {
    final json = await _postJson(
      session,
      '$_basePath/realms/$realmId/artifacts/$artifactId/complete',
      body: '{}',
    );
    if (json is! Map) {
      throw _gatewayError(
        kind: GeminiGatewayFailureKind.unknown,
        message: 'Unexpected artifact completion payload.',
      );
    }
    return LumaArtifact.fromJson(json.cast<String, Object?>());
  }

  /// Resolves signed CDN URLs for the given [artifactIds].
  Future<List<LumaDownloadFile>> requestDownloads(
    LumaSession session, {
    required String realmId,
    required List<String> artifactIds,
    bool organizeByCanvas = false,
  }) async {
    if (artifactIds.isEmpty) {
      return const <LumaDownloadFile>[];
    }
    final json = await _postJson(
      session,
      '$_basePath/realms/$realmId/downloads',
      body: jsonEncode({'artifact_ids': artifactIds, 'organize_by_canvas': organizeByCanvas}),
    );
    if (json is! Map) {
      throw _gatewayError(
        kind: GeminiGatewayFailureKind.unknown,
        message: 'Unexpected download payload from realm $realmId.',
      );
    }
    final files = (json['files'] as List?) ?? const [];
    return files
        .whereType<Map>()
        .map((entry) => LumaDownloadFile.fromJson(entry.cast<String, Object?>()))
        .where((file) => file.url.isNotEmpty)
        .toList(growable: false);
  }

  void close() {
    _http.close();
  }

  Future<Object?> _getJson(LumaSession session, String path) async {
    final response = await _send(session, 'GET', path);
    return _decodeBodyOrNull(response.body);
  }

  Future<Object?> _postJson(LumaSession session, String path, {required String body}) async {
    final response = await _send(session, 'POST', path, body: body);
    return _decodeBodyOrNull(response.body);
  }

  Future<http.Response> _send(
    LumaSession session,
    String method,
    String path, {
    String? body,
  }) async {
    if (!session.hasSession) {
      throw _gatewayError(
        kind: GeminiGatewayFailureKind.auth,
        message: 'Luma session is missing the required cookies.',
        statusCode: 401,
      );
    }
    final uri = Uri.https(_host, path);
    final headers = <String, String>{
      HttpHeaders.acceptHeader: 'application/json, text/plain, */*',
      HttpHeaders.userAgentHeader: _userAgent,
      'origin': 'https://$_host',
      'referer': 'https://$_host/',
      'x-client-context': _clientContext,
      'x-client-capabilities': 'retry,upgrade_plan',
      HttpHeaders.cookieHeader: session.buildCookieHeader(),
      if (body != null) HttpHeaders.contentTypeHeader: 'application/json',
    };

    final response = await _runWithRequestTimeout(() {
      switch (method) {
        case 'GET':
          return _http.get(uri, headers: headers);
        case 'POST':
          return _http.post(uri, headers: headers, body: body);
        default:
          throw StateError('Unsupported HTTP method: $method');
      }
    });

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw _gatewayErrorFromResponse(response);
  }

  Future<T> _runWithRequestTimeout<T>(Future<T> Function() body) {
    return body().timeout(
      _requestTimeout,
      onTimeout: () {
        throw _gatewayError(
          kind: GeminiGatewayFailureKind.serviceUnavailable,
          message: 'Luma request timed out after ${_requestTimeout.inSeconds}s.',
          source: GeminiGatewayFailureSource.transport,
          statusCode: 504,
        );
      },
    );
  }

  Object? _decodeBodyOrNull(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(trimmed);
    } on FormatException {
      return null;
    }
  }

  GeminiGatewayException _gatewayError({
    required GeminiGatewayFailureKind kind,
    required String message,
    int statusCode = 500,
    GeminiGatewayFailureSource source = GeminiGatewayFailureSource.upstream,
  }) {
    return GeminiGatewayException(
      provider: AccountProvider.luma,
      kind: kind,
      message: message,
      statusCode: statusCode,
      source: source,
    );
  }

  GeminiGatewayException _gatewayErrorFromResponse(http.Response response) {
    final status = response.statusCode;
    final kind = switch (status) {
      401 || 403 => GeminiGatewayFailureKind.auth,
      402 || 429 => GeminiGatewayFailureKind.quota,
      503 || 504 => GeminiGatewayFailureKind.serviceUnavailable,
      400 => GeminiGatewayFailureKind.invalidRequest,
      _ when status >= 500 => GeminiGatewayFailureKind.serviceUnavailable,
      _ => GeminiGatewayFailureKind.unknown,
    };
    final excerpt = _extractMessage(response.body);
    return GeminiGatewayException(
      provider: AccountProvider.luma,
      kind: kind,
      message: 'Luma responded with HTTP $status${excerpt == null ? '' : ': $excerpt'}',
      statusCode: status,
      rawResponseBody: response.body.isEmpty ? null : response.body,
    );
  }

  String? _extractMessage(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        for (final key in const ['detail', 'message', 'error']) {
          final value = decoded[key];
          if (value is String && value.trim().isNotEmpty) {
            return value.trim();
          }
        }
      }
    } catch (_) {
      // fall through to plain text
    }
    if (trimmed.length > 240) {
      return '${trimmed.substring(0, 240)}…';
    }
    return trimmed;
  }
}
