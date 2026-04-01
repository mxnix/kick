import 'oauth_tokens.dart';

enum AccountProvider {
  gemini,
  kiro;

  static AccountProvider fromValue(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'kiro' => AccountProvider.kiro,
      _ => AccountProvider.gemini,
    };
  }
}

class AccountProfile {
  const AccountProfile({
    required this.id,
    required this.label,
    required this.email,
    required this.projectId,
    this.provider = AccountProvider.gemini,
    this.providerRegion,
    this.credentialSourceType,
    this.credentialSourcePath,
    this.providerProfileArn,
    this.googleSubjectId,
    this.avatarUrl,
    required this.enabled,
    required this.priority,
    required this.notSupportedModels,
    this.runtimeNotSupportedModels = const [],
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
  final AccountProvider provider;
  final String? providerRegion;
  final String? credentialSourceType;
  final String? credentialSourcePath;
  final String? providerProfileArn;
  final String? googleSubjectId;
  final String? avatarUrl;
  final bool enabled;
  final int priority;
  final List<String> notSupportedModels;
  final List<String> runtimeNotSupportedModels;
  final DateTime? lastUsedAt;
  final int usageCount;
  final int errorCount;
  final DateTime? cooldownUntil;
  final String? lastQuotaSnapshot;
  final String tokenRef;

  bool get isCoolingDown => cooldownUntil != null && cooldownUntil!.isAfter(DateTime.now());
  bool get usesSecretStoreTokens => provider == AccountProvider.gemini;
  bool get supportsUsageDiagnostics => provider == AccountProvider.gemini;
  String get displayIdentity {
    if (provider == AccountProvider.kiro) {
      final path = credentialSourcePath?.trim();
      final sourceName = path == null || path.isEmpty
          ? null
          : path.replaceAll('\\', '/').split('/').last.trim();
      return _firstNonEmpty(email, providerProfileArn, sourceName, 'Kiro local session');
    }
    return email;
  }

  List<String> get effectiveNotSupportedModels =>
      _mergeModelLists(notSupportedModels, runtimeNotSupportedModels);

  AccountProfile copyWith({
    String? id,
    String? label,
    String? email,
    String? projectId,
    AccountProvider? provider,
    String? providerRegion,
    bool clearProviderRegion = false,
    String? credentialSourceType,
    bool clearCredentialSourceType = false,
    String? credentialSourcePath,
    bool clearCredentialSourcePath = false,
    String? providerProfileArn,
    bool clearProviderProfileArn = false,
    String? googleSubjectId,
    bool clearGoogleSubjectId = false,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    bool? enabled,
    int? priority,
    List<String>? notSupportedModels,
    List<String>? runtimeNotSupportedModels,
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
      provider: provider ?? this.provider,
      providerRegion: clearProviderRegion ? null : (providerRegion ?? this.providerRegion),
      credentialSourceType: clearCredentialSourceType
          ? null
          : (credentialSourceType ?? this.credentialSourceType),
      credentialSourcePath: clearCredentialSourcePath
          ? null
          : (credentialSourcePath ?? this.credentialSourcePath),
      providerProfileArn: clearProviderProfileArn
          ? null
          : (providerProfileArn ?? this.providerProfileArn),
      googleSubjectId: clearGoogleSubjectId ? null : (googleSubjectId ?? this.googleSubjectId),
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
      notSupportedModels: notSupportedModels ?? this.notSupportedModels,
      runtimeNotSupportedModels: runtimeNotSupportedModels ?? this.runtimeNotSupportedModels,
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
      'provider': provider.name,
      'provider_region': providerRegion,
      'credential_source_type': credentialSourceType,
      'credential_source_path': credentialSourcePath,
      'provider_profile_arn': providerProfileArn,
      'google_subject_id': googleSubjectId,
      'avatar_url': avatarUrl,
      'enabled': enabled ? 1 : 0,
      'priority': priority,
      'not_supported_models': notSupportedModels.join('\n'),
      'runtime_not_supported_models': runtimeNotSupportedModels.join('\n'),
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
      'provider': provider.name,
      'enabled': enabled,
      'google_subject_id': googleSubjectId,
      'avatar_url': avatarUrl,
      'not_supported_models': List<String>.from(effectiveNotSupportedModels),
      'last_used_at': lastUsedAt?.toIso8601String(),
      'cooldown_until': cooldownUntil?.toIso8601String(),
      'tokens': tokens?.toJson(),
    };
  }

  Map<String, Object?> toBackupJson({OAuthTokens? tokens}) {
    return {
      'id': id,
      'label': label,
      'email': email,
      'project_id': projectId,
      'provider': provider.name,
      'provider_region': providerRegion,
      'credential_source_type': credentialSourceType,
      'credential_source_path': credentialSourcePath,
      'provider_profile_arn': providerProfileArn,
      'google_subject_id': googleSubjectId,
      'avatar_url': avatarUrl,
      'enabled': enabled,
      'priority': priority,
      'not_supported_models': List<String>.from(notSupportedModels),
      'runtime_not_supported_models': List<String>.from(runtimeNotSupportedModels),
      'last_used_at': lastUsedAt?.toIso8601String(),
      'usage_count': usageCount,
      'error_count': errorCount,
      'cooldown_until': cooldownUntil?.toIso8601String(),
      'last_quota_snapshot': lastQuotaSnapshot,
      'token_ref': tokenRef,
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
      provider: AccountProvider.fromValue(map['provider'] as String?),
      providerRegion: _readOptionalString(map['provider_region']),
      credentialSourceType: _readOptionalString(map['credential_source_type']),
      credentialSourcePath: _readOptionalString(map['credential_source_path']),
      providerProfileArn: _readOptionalString(map['provider_profile_arn']),
      googleSubjectId: _readOptionalString(map['google_subject_id']),
      avatarUrl: _readOptionalString(map['avatar_url']),
      enabled: (map['enabled'] as int? ?? 1) == 1,
      priority: map['priority'] as int? ?? 0,
      notSupportedModels: _decodeModelList(map['not_supported_models']),
      runtimeNotSupportedModels: _decodeModelList(map['runtime_not_supported_models']),
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

  factory AccountProfile.fromBackupJson(Map<String, Object?> json) {
    final id = _readRequiredString(json['id'], fieldName: 'id');
    return AccountProfile(
      id: id,
      label: _readRequiredString(json['label'], fieldName: 'label'),
      email: _readRequiredString(json['email'], fieldName: 'email'),
      projectId: _readString(json['project_id']) ?? '',
      provider: AccountProvider.fromValue(_readString(json['provider'])),
      providerRegion: _readNullableString(json['provider_region']),
      credentialSourceType: _readNullableString(json['credential_source_type']),
      credentialSourcePath: _readNullableString(json['credential_source_path']),
      providerProfileArn: _readNullableString(json['provider_profile_arn']),
      googleSubjectId: _readNullableString(json['google_subject_id']),
      avatarUrl: _readNullableString(json['avatar_url']),
      enabled: _readBool(json['enabled'], defaultValue: true),
      priority: _readInt(json['priority']) ?? 0,
      notSupportedModels: _readStringList(json['not_supported_models']),
      runtimeNotSupportedModels: _readStringList(json['runtime_not_supported_models']),
      lastUsedAt: DateTime.tryParse(_readString(json['last_used_at']) ?? ''),
      usageCount: _readInt(json['usage_count']) ?? 0,
      errorCount: _readInt(json['error_count']) ?? 0,
      cooldownUntil: DateTime.tryParse(_readString(json['cooldown_until']) ?? ''),
      lastQuotaSnapshot: _readNullableString(json['last_quota_snapshot']),
      tokenRef: _readNullableString(json['token_ref']) ?? 'kick.oauth.$id',
    );
  }

  static String? _readOptionalString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  static List<String> _decodeModelList(Object? value) {
    return (value?.toString() ?? '')
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _mergeModelLists(List<String> primary, List<String> secondary) {
    final merged = <String>{...primary, ...secondary};
    return merged.toList(growable: false);
  }
}

String _firstNonEmpty(String? first, [String? second, String? third, String? fallback]) {
  for (final candidate in [first, second, third, fallback]) {
    final trimmed = candidate?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}

String _readRequiredString(Object? value, {required String fieldName}) {
  final text = _readString(value);
  if (text == null || text.isEmpty) {
    throw FormatException('Backup account is missing "$fieldName".');
  }
  return text;
}

String? _readString(Object? value) {
  return switch (value) {
    String text => text.trim(),
    _ => null,
  };
}

String? _readNullableString(Object? value) {
  final text = _readString(value);
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

bool _readBool(Object? value, {required bool defaultValue}) {
  return switch (value) {
    bool flag => flag,
    String text => text.trim().toLowerCase() == 'true',
    num number => number != 0,
    _ => defaultValue,
  };
}

int? _readInt(Object? value) {
  return switch (value) {
    int number => number,
    num number => number.round(),
    String text => int.tryParse(text.trim()),
    _ => null,
  };
}

List<String> _readStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
