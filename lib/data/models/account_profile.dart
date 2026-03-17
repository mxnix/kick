import 'oauth_tokens.dart';

class AccountProfile {
  const AccountProfile({
    required this.id,
    required this.label,
    required this.email,
    required this.projectId,
    this.googleSubjectId,
    this.avatarUrl,
    required this.enabled,
    required this.priority,
    required this.notSupportedModels,
    required this.lastUsedAt,
    required this.usageCount,
    required this.errorCount,
    required this.cooldownUntil,
    required this.lastQuotaSnapshot,
    required this.tokenRef,
  });

  final String id;
  final String label;
  final String email;
  final String projectId;
  final String? googleSubjectId;
  final String? avatarUrl;
  final bool enabled;
  final int priority;
  final List<String> notSupportedModels;
  final DateTime? lastUsedAt;
  final int usageCount;
  final int errorCount;
  final DateTime? cooldownUntil;
  final String? lastQuotaSnapshot;
  final String tokenRef;

  bool get isCoolingDown => cooldownUntil != null && cooldownUntil!.isAfter(DateTime.now());

  AccountProfile copyWith({
    String? id,
    String? label,
    String? email,
    String? projectId,
    String? googleSubjectId,
    bool clearGoogleSubjectId = false,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    bool? enabled,
    int? priority,
    List<String>? notSupportedModels,
    DateTime? lastUsedAt,
    bool clearLastUsedAt = false,
    int? usageCount,
    int? errorCount,
    DateTime? cooldownUntil,
    bool clearCooldown = false,
    String? lastQuotaSnapshot,
    bool clearQuotaSnapshot = false,
    String? tokenRef,
  }) {
    return AccountProfile(
      id: id ?? this.id,
      label: label ?? this.label,
      email: email ?? this.email,
      projectId: projectId ?? this.projectId,
      googleSubjectId: clearGoogleSubjectId ? null : (googleSubjectId ?? this.googleSubjectId),
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
      notSupportedModels: notSupportedModels ?? this.notSupportedModels,
      lastUsedAt: clearLastUsedAt ? null : (lastUsedAt ?? this.lastUsedAt),
      usageCount: usageCount ?? this.usageCount,
      errorCount: errorCount ?? this.errorCount,
      cooldownUntil: clearCooldown ? null : (cooldownUntil ?? this.cooldownUntil),
      lastQuotaSnapshot: clearQuotaSnapshot ? null : (lastQuotaSnapshot ?? this.lastQuotaSnapshot),
      tokenRef: tokenRef ?? this.tokenRef,
    );
  }

  Map<String, Object?> toDatabaseMap() {
    return {
      'id': id,
      'label': label,
      'email': email,
      'project_id': projectId,
      'google_subject_id': googleSubjectId,
      'avatar_url': avatarUrl,
      'enabled': enabled ? 1 : 0,
      'priority': priority,
      'not_supported_models': notSupportedModels.join('\n'),
      'last_used_at': lastUsedAt?.toIso8601String(),
      'usage_count': usageCount,
      'error_count': errorCount,
      'cooldown_until': cooldownUntil?.toIso8601String(),
      'last_quota_snapshot': lastQuotaSnapshot,
      'token_ref': tokenRef,
    };
  }

  Map<String, Object?> toRuntimeJson({OAuthTokens? tokens}) {
    return {
      ...toDatabaseMap(),
      'email': email,
      'enabled': enabled,
      'google_subject_id': googleSubjectId,
      'avatar_url': avatarUrl,
      'not_supported_models': List<String>.from(notSupportedModels),
      'last_used_at': lastUsedAt?.toIso8601String(),
      'cooldown_until': cooldownUntil?.toIso8601String(),
      'tokens': tokens?.toJson(),
    };
  }

  factory AccountProfile.fromDatabaseMap(Map<String, Object?> map) {
    final rawQuotaSnapshot = map['last_quota_snapshot'] as String?;
    return AccountProfile(
      id: map['id'] as String? ?? '',
      label: map['label'] as String? ?? '',
      email: map['email'] as String? ?? '',
      projectId: map['project_id'] as String? ?? '',
      googleSubjectId: _readOptionalString(map['google_subject_id']),
      avatarUrl: _readOptionalString(map['avatar_url']),
      enabled: (map['enabled'] as int? ?? 1) == 1,
      priority: map['priority'] as int? ?? 0,
      notSupportedModels: ((map['not_supported_models'] as String?) ?? '')
          .split('\n')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      lastUsedAt: DateTime.tryParse(map['last_used_at'] as String? ?? ''),
      usageCount: map['usage_count'] as int? ?? 0,
      errorCount: map['error_count'] as int? ?? 0,
      cooldownUntil: DateTime.tryParse(map['cooldown_until'] as String? ?? ''),
      lastQuotaSnapshot: rawQuotaSnapshot == null || rawQuotaSnapshot.isEmpty
          ? null
          : rawQuotaSnapshot,
      tokenRef: map['token_ref'] as String? ?? '',
    );
  }

  static String? _readOptionalString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }
}
