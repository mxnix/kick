import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../data/models/account_profile.dart';
import '../gemini/gemini_code_assist_client.dart'
    show GeminiGatewayException, GeminiGatewayFailureKind, GeminiGatewayFailureSource;
import 'luma_realm_models.dart';

/// One observation about a Luma generation pulled out of the canvas-sync
/// WebSocket stream. The proxy treats these as the authoritative completion
/// signal because there is no REST polling endpoint exposed by the browser
/// app.
class LumaArtifactUpdate {
  const LumaArtifactUpdate({
    required this.artifactId,
    required this.kind,
    required this.shapeId,
    this.subtitle,
    this.heading,
    this.estimatedCredits,
  });

  /// Final artifact id assigned by the server (e.g. `nlJWU0Uz`).
  final String artifactId;

  /// `image`, `video`, `audio`, or another type emitted by the server.
  final String kind;

  /// Tldraw shape id that hosted the placeholder. Useful for correlation when
  /// multiple actions are in-flight in parallel.
  final String shapeId;

  /// Display-friendly secondary line (e.g. `Nano Banana Pro · 2K`). Optional.
  final String? subtitle;

  /// Display-friendly primary heading. Optional.
  final String? heading;

  /// Credits advertised by the server before the action ran. Optional.
  final int? estimatedCredits;
}

/// Minimal parser/connector for `wss://canvas-sync.cdn-luma.com/ws/canvas/...`.
///
/// We do not implement the full tldraw multiplayer protocol - only enough to
/// extract `LumaArtifactUpdate` events out of `push`/`data` frames.
class LumaCanvasSyncClient {
  LumaCanvasSyncClient({
    Future<WebSocket> Function(Uri uri, {Map<String, dynamic>? headers})? socketFactory,
    Duration connectTimeout = const Duration(seconds: 15),
    Duration pingInterval = const Duration(seconds: 20),
  }) : _socketFactory = socketFactory ?? _defaultSocketFactory,
       _connectTimeout = connectTimeout,
       _pingInterval = pingInterval;

  static const String _defaultOrigin = 'https://app.lumalabs.ai';
  static const String _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';

  final Future<WebSocket> Function(Uri uri, {Map<String, dynamic>? headers}) _socketFactory;
  final Duration _connectTimeout;
  final Duration _pingInterval;

  /// Opens the WebSocket and yields artifact updates as they arrive. The
  /// stream completes when the socket closes; consumers should listen with a
  /// timeout matching the action's expected duration.
  ///
  /// [signature] must be fresh (use `LumaRealmClient.readRealmSignature` and
  /// re-fetch when [LumaRealmSignature.isStale] is `true`).
  Stream<LumaArtifactUpdate> watch({
    required String realmId,
    required LumaRealmSignature signature,
    String? sessionId,
    String? storeId,
  }) {
    final controller = StreamController<LumaArtifactUpdate>();
    unawaited(_run(controller, realmId, signature, sessionId, storeId));
    return controller.stream;
  }

  Future<void> _run(
    StreamController<LumaArtifactUpdate> controller,
    String realmId,
    LumaRealmSignature signature,
    String? sessionId,
    String? storeId,
  ) async {
    if (signature.wsUrl.isEmpty || signature.wsToken.isEmpty) {
      controller.addError(
        GeminiGatewayException(
          provider: AccountProvider.luma,
          kind: GeminiGatewayFailureKind.auth,
          message: 'Luma realm signature is missing the WebSocket token.',
          statusCode: 401,
        ),
      );
      await controller.close();
      return;
    }

    // `WebSocket.connect` re-builds the underlying upgrade request from the
    // ws/wss URI. When the signature payload uses `https://canvas-sync.cdn-luma.com`
    // (no explicit port), `Uri.parse` leaves `port=0` internally, and
    // `WebSocket.connect` then issues an upgrade against `https://host:0/...`
    // which Cloudflare rejects with a 400. Forcing the canonical default
    // port keeps `Uri.port` returning the right value through the round-trip.
    final originalUri = Uri.parse(signature.wsUrl);
    final wsScheme = signature.wsUrl.startsWith('https://') ? 'wss' : 'ws';
    final defaultPort = wsScheme == 'wss' ? 443 : 80;
    // Synthesize browser-style query params when the caller hasn't supplied
    // their own. `canvas-sync.cdn-luma.com` accepts the upgrade without them
    // in tests, but Cloudflare/tldraw expect both keys to be present. Mirror
    // the shape captured in our HAR (`TLDRAW_INSTANCE_STATE_V1_<rand>` and
    // an 8-char base64 store id).
    final resolvedSessionId =
        sessionId ??
        'TLDRAW_INSTANCE_STATE_V1_${generateLumaArtifactId()}${generateLumaArtifactId()}';
    final resolvedStoreId = storeId ?? generateLumaArtifactId();
    final wsUri = Uri(
      scheme: wsScheme,
      userInfo: originalUri.userInfo.isEmpty ? null : originalUri.userInfo,
      host: originalUri.host,
      port: originalUri.hasPort ? originalUri.port : defaultPort,
      pathSegments: <String>['ws', 'canvas', realmId, signature.wsToken],
      queryParameters: <String, String>{'sessionId': resolvedSessionId, 'storeId': resolvedStoreId},
    );

    WebSocket? socket;
    Timer? pingTimer;
    try {
      socket = await _socketFactory(
        wsUri,
        headers: <String, dynamic>{
          'Origin': _defaultOrigin,
          'User-Agent': _defaultUserAgent,
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      ).timeout(_connectTimeout);

      socket.add(
        jsonEncode({
          'type': 'connect',
          'connectRequestId': generateLumaArtifactId(),
          'protocolVersion': 8,
          'lastServerClock': -1,
          'schema': _connectSchema,
        }),
      );

      pingTimer = Timer.periodic(_pingInterval, (_) {
        if (socket?.readyState == WebSocket.open) {
          socket!.add(jsonEncode({'type': 'ping'}));
        }
      });

      await socket
          .listen(
            (event) {
              if (event is! String) return;
              for (final update in _parseFrame(event)) {
                controller.add(update);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              controller.addError(
                GeminiGatewayException(
                  provider: AccountProvider.luma,
                  kind: GeminiGatewayFailureKind.serviceUnavailable,
                  message: 'Luma WebSocket failure: $error',
                  statusCode: 503,
                  source: GeminiGatewayFailureSource.transport,
                ),
                stackTrace,
              );
            },
            cancelOnError: true,
          )
          .asFuture<void>();
    } catch (error, stackTrace) {
      controller.addError(
        GeminiGatewayException(
          provider: AccountProvider.luma,
          kind: GeminiGatewayFailureKind.serviceUnavailable,
          message: 'Failed to connect to Luma canvas sync: $error',
          statusCode: 503,
          source: GeminiGatewayFailureSource.transport,
        ),
        stackTrace,
      );
    } finally {
      pingTimer?.cancel();
      try {
        await socket?.close();
      } catch (_) {
        // Ignore close failures - the stream is already done.
      }
      await controller.close();
    }
  }

  /// Parses a single text frame and emits artifact updates discovered inside.
  /// Public for unit tests.
  static List<LumaArtifactUpdate> _parseFrame(String raw) {
    final updates = <LumaArtifactUpdate>[];
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return updates;
    }
    _walk(decoded, updates);
    return updates;
  }

  static void _walk(Object? node, List<LumaArtifactUpdate> updates) {
    if (node is List) {
      for (final entry in node) {
        _walk(entry, updates);
      }
      return;
    }
    if (node is! Map) {
      return;
    }
    final type = node['type'];
    if (type == 'push' || type == 'data') {
      _maybeExtractFromPush(node.cast<String, Object?>(), updates);
    }
    // Walk further: server frames sometimes wrap pushes inside `data` arrays.
    for (final value in node.values) {
      if (value is Map || value is List) {
        _walk(value, updates);
      }
    }
  }

  static void _maybeExtractFromPush(Map<String, Object?> frame, List<LumaArtifactUpdate> updates) {
    final diff = frame['diff'];
    if (diff is! Map) {
      return;
    }
    diff.forEach((key, raw) {
      if (key is! String || !key.startsWith('shape:') || raw is! List) return;
      // Tldraw stores `["put"|"patch", payload]`.
      if (raw.length < 2) return;
      final action = raw.first;
      if (action != 'patch' && action != 'put') return;
      final payload = raw[1];
      if (payload is! Map) return;
      final patch = payload.cast<String, Object?>();
      final props = patch['props'];
      String? artifactId;
      String? kind;
      if (props is List && props.length >= 2 && props.first == 'patch') {
        final propPatch = (props[1] as Map?)?.cast<String, Object?>();
        if (propPatch != null) {
          artifactId = _readAppendedString(propPatch['artifact_id']);
          kind = _readPutString(propPatch['type']);
        }
      } else if (props is Map) {
        final propMap = props.cast<String, Object?>();
        final maybeId = propMap['artifact_id'];
        if (maybeId is String && maybeId.isNotEmpty) {
          artifactId = maybeId;
        }
        final maybeKind = propMap['type'];
        if (maybeKind is String && maybeKind != 'placeholder') {
          kind = maybeKind;
        }
      }
      if (artifactId == null || kind == null) {
        return;
      }
      final meta = patch['meta'];
      String? subtitle;
      String? heading;
      int? credits;
      if (meta is List && meta.length >= 2 && meta.first == 'patch') {
        final metaPatch = (meta[1] as Map?)?.cast<String, Object?>();
        if (metaPatch != null) {
          subtitle = _readPutString(metaPatch['subtitle']);
          heading = _readPutString(metaPatch['leadingHeading']);
          credits = _readPutInt(metaPatch['estimatedCredits']);
        }
      }
      updates.add(
        LumaArtifactUpdate(
          artifactId: artifactId,
          kind: kind,
          shapeId: key.substring('shape:'.length),
          subtitle: subtitle,
          heading: heading,
          estimatedCredits: credits,
        ),
      );
    });
  }

  static String? _readAppendedString(Object? value) {
    if (value is! List || value.isEmpty) return null;
    final action = value.first;
    if (action == 'append' && value.length >= 2 && value[1] is String) {
      return value[1] as String;
    }
    if (action == 'put' && value.length >= 2 && value[1] is String) {
      return value[1] as String;
    }
    return null;
  }

  static String? _readPutString(Object? value) {
    if (value is! List || value.isEmpty) return null;
    if (value.first == 'put' && value.length >= 2 && value[1] is String) {
      return (value[1] as String).trim().isEmpty ? null : (value[1] as String).trim();
    }
    return null;
  }

  static int? _readPutInt(Object? value) {
    if (value is! List || value.isEmpty) return null;
    if (value.first == 'put' && value.length >= 2) {
      final v = value[1];
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim());
    }
    return null;
  }
}

Future<WebSocket> _defaultSocketFactory(Uri uri, {Map<String, dynamic>? headers}) {
  return WebSocket.connect(uri.toString(), headers: headers);
}

/// Visible for testing.
List<LumaArtifactUpdate> debugParseLumaFrame(String raw) => LumaCanvasSyncClient._parseFrame(raw);

/// Tldraw multiplayer schema enrolled by the Luma canvas. Captured verbatim
/// from a HAR `connect` send frame so the server hydrates correctly.
const Map<String, Object?> _connectSchema = <String, Object?>{
  'schemaVersion': 2,
  'sequences': <String, int>{
    'com.tldraw.store': 5,
    'com.tldraw.asset': 1,
    'com.tldraw.camera': 1,
    'com.tldraw.document': 2,
    'com.tldraw.instance': 26,
    'com.tldraw.instance_page_state': 5,
    'com.tldraw.page': 1,
    'com.tldraw.instance_presence': 6,
    'com.tldraw.pointer': 1,
    'com.tldraw.shape': 4,
    'com.tldraw.user': 1,
    'com.tldraw.asset.image': 6,
    'com.tldraw.asset.video': 5,
    'com.tldraw.asset.bookmark': 2,
    'com.tldraw.shape.group': 0,
    'com.tldraw.shape.artifact': 0,
    'com.tldraw.shape.grid': 4,
    'com.tldraw.shape.timeline': 2,
    'com.tldraw.shape.composition': 0,
    'com.tldraw.shape.composition-item': 0,
    'com.tldraw.shape.text': 4,
    'com.tldraw.shape.bookmark': 2,
    'com.tldraw.shape.draw': 4,
    'com.tldraw.shape.geo': 11,
    'com.tldraw.shape.note': 12,
    'com.tldraw.shape.line': 5,
    'com.tldraw.shape.frame': 1,
    'com.tldraw.shape.arrow': 8,
    'com.tldraw.shape.highlight': 3,
    'com.tldraw.shape.embed': 4,
    'com.tldraw.shape.image': 5,
    'com.tldraw.shape.video': 4,
    'com.tldraw.binding.layout': 0,
    'com.tldraw.binding.arrow': 1,
  },
};
