import 'dart:convert';

/// Lightweight value types around the Luma Vespa REST surface.
///
/// We deliberately keep these models thin - they exist to give the rest of
/// the codebase a typed view over the JSON payloads documented in
/// `.tmp/luma/REVERSE_NOTES.md` without locking us into a particular schema.

class LumaTeamMembership {
  const LumaTeamMembership({
    required this.teamId,
    required this.teamName,
    required this.role,
    required this.tier,
    this.tierDisplayName,
    this.userEmail,
    this.userId,
  });

  factory LumaTeamMembership.fromJson(Map<String, Object?> json) {
    final team = (json['team'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    final membership =
        (json['membership'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    final user = (membership['user'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    final subscription =
        (json['subscription'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    return LumaTeamMembership(
      teamId: (team['id'] as String?)?.trim() ?? '',
      teamName: (team['name'] as String?)?.trim() ?? '',
      role: (membership['role'] as String?)?.trim() ?? '',
      tier: (subscription['tier'] as String?)?.trim() ?? '',
      tierDisplayName: (json['tier_display_name'] as String?)?.trim().isNotEmpty == true
          ? (json['tier_display_name'] as String).trim()
          : null,
      userEmail: (user['email'] as String?)?.trim().isNotEmpty == true
          ? (user['email'] as String).trim()
          : null,
      userId: (user['uuid'] as String?)?.trim().isNotEmpty == true
          ? (user['uuid'] as String).trim()
          : null,
    );
  }

  final String teamId;
  final String teamName;
  final String role;
  final String tier;
  final String? tierDisplayName;
  final String? userEmail;
  final String? userId;

  bool get isValid => teamId.isNotEmpty;
}

class LumaRealmRef {
  const LumaRealmRef({required this.id, required this.name, this.role, this.teamRole});

  factory LumaRealmRef.fromJson(Map<String, Object?> json) {
    final access =
        (json['user_access'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    final teamAccess =
        (json['team_access'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    return LumaRealmRef(
      id: (json['id'] as String?)?.trim() ?? '',
      name: (json['name'] as String?)?.trim() ?? '',
      role: (access['role'] as String?)?.trim().isNotEmpty == true
          ? (access['role'] as String).trim()
          : null,
      teamRole: (teamAccess['team_role'] as String?)?.trim().isNotEmpty == true
          ? (teamAccess['team_role'] as String).trim()
          : null,
    );
  }

  final String id;
  final String name;
  final String? role;
  final String? teamRole;

  bool get isValid => id.isNotEmpty;
}

class LumaRealmSignature {
  const LumaRealmSignature({
    required this.queryParams,
    required this.cdnUrl,
    required this.wsUrl,
    required this.wsToken,
    required this.expiresAt,
  });

  factory LumaRealmSignature.fromJson(Map<String, Object?> json) {
    final expires = (json['expires_at'] as String?)?.trim();
    return LumaRealmSignature(
      queryParams: (json['query_params'] as String?) ?? '',
      cdnUrl: (json['cdn_url'] as String?) ?? '',
      wsUrl: (json['ws_url'] as String?) ?? '',
      wsToken: (json['ws_token'] as String?) ?? '',
      expiresAt: expires == null || expires.isEmpty ? null : DateTime.tryParse(expires)?.toLocal(),
    );
  }

  final String queryParams;
  final String cdnUrl;
  final String wsUrl;
  final String wsToken;
  final DateTime? expiresAt;

  bool get isStale {
    final at = expiresAt;
    if (at == null) {
      return false;
    }
    // Treat as stale 60 seconds before the server-stated expiry to give us
    // time to renew in the background.
    return at.subtract(const Duration(seconds: 60)).isBefore(DateTime.now());
  }
}

class LumaArtifact {
  const LumaArtifact({
    required this.id,
    required this.realmId,
    required this.type,
    required this.state,
    this.objectRef,
    this.thumbnailRef,
    this.name,
    this.width,
    this.height,
    this.sizeBytes,
    this.presignedUrl,
  });

  factory LumaArtifact.fromJson(Map<String, Object?> json) {
    final meta = (json['meta'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    return LumaArtifact(
      id: (json['id'] as String?)?.trim() ?? '',
      realmId: (json['realm_id'] as String?)?.trim() ?? '',
      type: (json['type'] as String?)?.trim() ?? '',
      state: (json['state'] as String?)?.trim() ?? '',
      objectRef: (json['object_ref'] as String?)?.trim().isNotEmpty == true
          ? (json['object_ref'] as String).trim()
          : null,
      thumbnailRef: (json['thumbnail_ref'] as String?)?.trim().isNotEmpty == true
          ? (json['thumbnail_ref'] as String).trim()
          : null,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : null,
      width: _readInt(meta['width']),
      height: _readInt(meta['height']),
      sizeBytes: _readInt(json['size_bytes']),
      presignedUrl: (json['presigned_url'] as String?)?.trim().isNotEmpty == true
          ? (json['presigned_url'] as String).trim()
          : null,
    );
  }

  final String id;
  final String realmId;
  final String type;
  final String state;
  final String? objectRef;
  final String? thumbnailRef;
  final String? name;
  final int? width;
  final int? height;
  final int? sizeBytes;
  final String? presignedUrl;

  bool get isReady => state == 'ready';
}

class LumaActionPreflight {
  const LumaActionPreflight({
    required this.outputSpecs,
    required this.estimatedCredits,
    required this.estimatedSeconds,
    this.estimatedQueueSeconds,
    this.availability,
  });

  factory LumaActionPreflight.fromJson(Map<String, Object?> json) {
    final rawSpecs = (json['output_specs'] as List?) ?? const [];
    return LumaActionPreflight(
      outputSpecs: rawSpecs
          .whereType<Map>()
          .map((item) => LumaActionOutputSpec.fromJson(item.cast<String, Object?>()))
          .toList(growable: false),
      estimatedCredits: _readDouble(json['estimated_credits']) ?? 0,
      estimatedSeconds: _readDouble(json['estimated_seconds']) ?? 0,
      estimatedQueueSeconds: _readDouble(json['estimated_queue_seconds']),
      availability: json['availability'] is String
          ? (json['availability'] as String).trim().isEmpty
                ? null
                : (json['availability'] as String).trim()
          : null,
    );
  }

  final List<LumaActionOutputSpec> outputSpecs;
  final double estimatedCredits;
  final double estimatedSeconds;
  final double? estimatedQueueSeconds;
  final String? availability;

  bool get isAvailable => availability == null || availability == 'available';
}

class LumaActionOutputSpec {
  const LumaActionOutputSpec({
    required this.key,
    required this.artifactType,
    required this.count,
    this.width,
    this.height,
    this.displayTags = const <String, String>{},
  });

  factory LumaActionOutputSpec.fromJson(Map<String, Object?> json) {
    final tags =
        (json['display_tags'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    return LumaActionOutputSpec(
      key: (json['key'] as String?)?.trim() ?? '',
      artifactType: (json['artifact_type'] as String?)?.trim() ?? '',
      count: _readInt(json['count']) ?? 1,
      width: _readInt(json['width']),
      height: _readInt(json['height']),
      displayTags: <String, String>{
        for (final entry in tags.entries)
          if (entry.value is String) entry.key: entry.value as String,
      },
    );
  }

  final String key;
  final String artifactType;
  final int count;
  final int? width;
  final int? height;
  final Map<String, String> displayTags;
}

class LumaActionSubmission {
  const LumaActionSubmission({
    required this.actionId,
    required this.type,
    required this.state,
    required this.params,
    required this.outputArtifactIds,
    required this.estimatedCredits,
    this.estimatedSeconds,
    this.estimatedQueueSeconds,
  });

  factory LumaActionSubmission.fromJson(Map<String, Object?> json) {
    final action = (json['action'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    final outputs =
        (json['output_artifacts'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    final ids = <String, List<String>>{};
    outputs.forEach((key, value) {
      if (value is List) {
        ids[key] = value.whereType<String>().toList(growable: false);
      }
    });
    return LumaActionSubmission(
      actionId: (action['id'] as String?)?.trim() ?? '',
      type: (action['type'] as String?)?.trim() ?? '',
      state: (action['state'] as String?)?.trim() ?? 'pending',
      params: (action['params'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{},
      outputArtifactIds: ids,
      estimatedCredits: _readDouble(action['estimated_credits']) ?? 0,
      estimatedSeconds: _readDouble(json['estimated_seconds']),
      estimatedQueueSeconds: _readDouble(json['estimated_queue_seconds']),
    );
  }

  final String actionId;
  final String type;
  final String state;
  final Map<String, Object?> params;

  /// Output artifact ids grouped by their semantic key (`image`, `video`, ...).
  final Map<String, List<String>> outputArtifactIds;

  final double estimatedCredits;
  final double? estimatedSeconds;
  final double? estimatedQueueSeconds;

  Iterable<String> get allArtifactIds =>
      outputArtifactIds.values.expand((ids) => ids).where((id) => id.isNotEmpty);
}

class LumaDownloadFile {
  const LumaDownloadFile({
    required this.url,
    required this.filename,
    required this.artifactId,
    required this.sizeBytes,
    this.variantKind,
  });

  factory LumaDownloadFile.fromJson(Map<String, Object?> json) {
    return LumaDownloadFile(
      url: (json['url'] as String?)?.trim() ?? '',
      filename: (json['filename'] as String?)?.trim() ?? '',
      artifactId: (json['artifact_id'] as String?)?.trim() ?? '',
      sizeBytes: _readInt(json['size_bytes']) ?? 0,
      variantKind: (json['variant_kind'] as String?)?.trim().isNotEmpty == true
          ? (json['variant_kind'] as String).trim()
          : null,
    );
  }

  final String url;
  final String filename;
  final String artifactId;
  final int sizeBytes;
  final String? variantKind;
}

/// A short-lived 8-character base64-url id matching the layout Luma uses for
/// artifacts and optimistic outputs (e.g. `nlJWU0Uz`, `8bYJsN4q`).
String generateLumaArtifactId() {
  // We avoid pulling in `package:uuid` here to keep this module standalone.
  // The id space (~62^8 ≈ 2.18e14) is more than enough for short-lived ids.
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  final random = _LumaIdRandom.instance;
  final buffer = StringBuffer();
  for (var i = 0; i < 8; i++) {
    buffer.writeCharCode(alphabet.codeUnitAt(random.nextInt(alphabet.length)));
  }
  return buffer.toString();
}

/// JSON-encodes the typical action submission body so callers can keep their
/// surface narrow.
String encodeLumaActionBody({
  required String type,
  required Map<String, Object?> fields,
  List<String>? optimisticOutputIds,
}) {
  final body = <String, Object?>{
    'type': type,
    'fields': fields,
    if (optimisticOutputIds != null && optimisticOutputIds.isNotEmpty)
      'optimistic_output_ids': optimisticOutputIds,
  };
  return jsonEncode(body);
}

double? _readDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

class _LumaIdRandom {
  _LumaIdRandom._();

  static final _LumaIdRandom instance = _LumaIdRandom._();

  // Use a cheap, fast PRNG seeded from the system clock. We do NOT need
  // crypto-grade randomness for these short-lived ids - the server is the
  // authoritative allocator anyway. Avoid `dart:math.Random.secure()` so this
  // module remains usable inside the proxy isolate without extra plugins.
  final _random = _SimpleRandom(DateTime.now().microsecondsSinceEpoch);

  int nextInt(int max) => _random.nextInt(max);
}

class _SimpleRandom {
  _SimpleRandom(int seed) : _state = (seed == 0 ? 0xdeadbeef : seed) & 0xffffffff;

  int _state;

  int nextInt(int max) {
    if (max <= 0) {
      return 0;
    }
    // xorshift32
    var x = _state;
    x ^= (x << 13) & 0xffffffff;
    x ^= (x >> 17) & 0xffffffff;
    x ^= (x << 5) & 0xffffffff;
    _state = x & 0xffffffff;
    return _state % max;
  }
}
