import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/models/oauth_tokens.dart';

const defaultKiroRegion = 'us-east-1';
const defaultKiroBuilderIdStartUrl = 'https://view.awsapps.com/start';
const defaultKiroBuilderIdProfileArn =
    'arn:aws:codewhisperer:us-east-1:638616132270:profile/AAAACCCCXXXX';
const defaultKiroSocialProfileArn =
    'arn:aws:codewhisperer:us-east-1:699475941385:profile/EHGA3GRVQMUK';
const defaultKiroCredentialSourceType = 'local_json';
const manualKiroCredentialSourceType = 'manual_json';
const builderIdKiroCredentialSourceType = 'builder_id_link';
const builderIdKiroAuthMethod = 'builder-id';

class KiroAuthSourceSnapshot {
  const KiroAuthSourceSnapshot({
    required this.sourcePath,
    required this.sourceType,
    required this.accessToken,
    required this.refreshToken,
    required this.expiry,
    required this.region,
    required this.profileArn,
    this.authMethod,
    this.provider,
    this.clientId,
    this.clientSecret,
    this.startUrl,
  });

  final String sourcePath;
  final String sourceType;
  final String accessToken;
  final String refreshToken;
  final DateTime expiry;
  final String? region;
  final String? profileArn;
  final String? authMethod;
  final String? provider;
  final String? clientId;
  final String? clientSecret;
  final String? startUrl;

  String get effectiveRegion {
    final trimmed = region?.trim();
    return trimmed == null || trimmed.isEmpty ? defaultKiroRegion : trimmed;
  }

  bool get usesBuilderIdRefresh =>
      authMethod?.trim().toLowerCase() == builderIdKiroAuthMethod &&
      clientId?.trim().isNotEmpty == true &&
      clientSecret?.trim().isNotEmpty == true;

  String get displayIdentity {
    final sourceName = p.basename(sourcePath).trim();
    final normalizedSource = switch (authMethod?.trim().toLowerCase()) {
      builderIdKiroAuthMethod => 'AWS Builder ID',
      _ when sourceName == 'kiro-auth-token.json' => 'Kiro local session',
      _ => sourceName,
    };
    if (authMethod?.trim().toLowerCase() == builderIdKiroAuthMethod) {
      return _firstNonEmpty(normalizedSource, profileArn, 'Kiro local session');
    }
    return _firstNonEmpty(profileArn, normalizedSource, 'Kiro local session');
  }

  OAuthTokens toOAuthTokens() {
    return OAuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiry: expiry,
      tokenType: 'Bearer',
      scope: null,
    );
  }

  KiroAuthSourceSnapshot copyWith({
    String? sourcePath,
    String? sourceType,
    String? accessToken,
    String? refreshToken,
    DateTime? expiry,
    String? region,
    bool clearRegion = false,
    String? profileArn,
    bool clearProfileArn = false,
    String? authMethod,
    bool clearAuthMethod = false,
    String? provider,
    bool clearProvider = false,
    String? clientId,
    bool clearClientId = false,
    String? clientSecret,
    bool clearClientSecret = false,
    String? startUrl,
    bool clearStartUrl = false,
  }) {
    return KiroAuthSourceSnapshot(
      sourcePath: sourcePath ?? this.sourcePath,
      sourceType: sourceType ?? this.sourceType,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiry: expiry ?? this.expiry,
      region: clearRegion ? null : (region ?? this.region),
      profileArn: clearProfileArn ? null : (profileArn ?? this.profileArn),
      authMethod: clearAuthMethod ? null : (authMethod ?? this.authMethod),
      provider: clearProvider ? null : (provider ?? this.provider),
      clientId: clearClientId ? null : (clientId ?? this.clientId),
      clientSecret: clearClientSecret ? null : (clientSecret ?? this.clientSecret),
      startUrl: clearStartUrl ? null : (startUrl ?? this.startUrl),
    );
  }
}

Future<KiroAuthSourceSnapshot?> loadKiroAuthSource({String? sourcePath}) async {
  final resolvedPath = resolveKiroCredentialSourcePath(sourcePath);
  if (resolvedPath == null || resolvedPath.isEmpty) {
    return null;
  }

  final file = File(resolvedPath);
  Map<String, Object?> json;
  try {
    if (!await file.exists()) {
      return null;
    }

    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    json = decoded.cast<String, Object?>();
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }

  final accessToken = _readString(json, const [
    'accessToken',
    'access_token',
    'token',
    'idToken',
    'id_token',
  ]);
  final refreshToken = _readString(json, const ['refreshToken', 'refresh_token']);
  if ((accessToken?.isEmpty ?? true) && (refreshToken?.isEmpty ?? true)) {
    return null;
  }

  final expiry =
      _readDateTime(json, const ['expiresAt', 'expires_at', 'expiry', 'expires']) ??
      DateTime.now().subtract(const Duration(minutes: 5));
  final authMethod = _readString(json, const ['authMethod', 'auth_method']);
  final provider = _readString(json, const ['provider']);
  final profileArn =
      _readString(json, const ['profileArn', 'profile_arn']) ??
      _fallbackKiroProfileArn(authMethod: authMethod, provider: provider);

  return KiroAuthSourceSnapshot(
    sourcePath: file.path,
    sourceType: authMethod?.trim().toLowerCase() == builderIdKiroAuthMethod
        ? builderIdKiroCredentialSourceType
        : _credentialSourceTypeForPath(sourcePath, file.path),
    accessToken: accessToken ?? '',
    refreshToken: refreshToken ?? '',
    expiry: expiry,
    region: _readString(json, const ['idcRegion', 'region']),
    profileArn: profileArn,
    authMethod: authMethod,
    provider: provider,
    clientId: _readString(json, const ['clientId', 'client_id']),
    clientSecret: _readString(json, const ['clientSecret', 'client_secret']),
    startUrl: _readString(json, const ['startUrl', 'start_url']),
  );
}

Future<KiroAuthSourceSnapshot> persistKiroAuthSourceSnapshot(
  KiroAuthSourceSnapshot snapshot, {
  String? outputPath,
  Future<Directory> Function()? supportDirectoryProvider,
}) async {
  final resolvedOutputPath = outputPath?.trim().isNotEmpty == true
      ? outputPath!.trim()
      : await _defaultManagedKiroSourcePath(
          supportDirectoryProvider ?? getApplicationSupportDirectory,
        );
  final file = File(resolvedOutputPath);
  await file.parent.create(recursive: true);

  final payload = <String, Object?>{
    'accessToken': snapshot.accessToken,
    'refreshToken': snapshot.refreshToken,
    'expiresAt': snapshot.expiry.toUtc().toIso8601String(),
    ...?_optionalEntry('region', snapshot.region),
    ...?_optionalEntry('idcRegion', snapshot.region),
    ...?_optionalEntry('profileArn', snapshot.profileArn),
    ...?_optionalEntry('authMethod', snapshot.authMethod),
    ...?_optionalEntry('provider', snapshot.provider),
    ...?_optionalEntry('clientId', snapshot.clientId),
    ...?_optionalEntry('clientSecret', snapshot.clientSecret),
    ...?_optionalEntry('startUrl', snapshot.startUrl),
  };
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  return snapshot.copyWith(sourcePath: file.path);
}

Future<bool> isManagedKiroCredentialSourcePath(
  String? sourcePath, {
  Future<Directory> Function()? supportDirectoryProvider,
}) async {
  final resolvedPath = sourcePath?.trim();
  if (resolvedPath == null || resolvedPath.isEmpty) {
    return false;
  }

  final managedDirectoryPath = await managedKiroSessionsDirectoryPath(
    supportDirectoryProvider: supportDirectoryProvider,
  );
  final normalizedManagedDirectory = p.normalize(managedDirectoryPath);
  final normalizedSourcePath = p.normalize(resolvedPath);
  final fileName = p.basename(normalizedSourcePath).toLowerCase();
  if (!fileName.startsWith('kiro-auth-')) {
    return false;
  }

  return p.equals(p.dirname(normalizedSourcePath), normalizedManagedDirectory) ||
      p.isWithin(normalizedManagedDirectory, normalizedSourcePath);
}

Future<bool> deleteManagedKiroCredentialSource(
  String? sourcePath, {
  Future<Directory> Function()? supportDirectoryProvider,
}) async {
  if (!await isManagedKiroCredentialSourcePath(
    sourcePath,
    supportDirectoryProvider: supportDirectoryProvider,
  )) {
    return false;
  }

  final resolvedPath = sourcePath!.trim();
  final file = File(resolvedPath);
  if (!await file.exists()) {
    return false;
  }
  await file.delete();
  return true;
}

Future<String> managedKiroSessionsDirectoryPath({
  Future<Directory> Function()? supportDirectoryProvider,
}) async {
  final supportDirectory = await (supportDirectoryProvider ?? getApplicationSupportDirectory)();
  return p.join(supportDirectory.path, 'kiro', 'sessions');
}

String? resolveKiroCredentialSourcePath(String? sourcePath) {
  final explicit = sourcePath?.trim();
  if (explicit != null && explicit.isNotEmpty) {
    return explicit;
  }

  final environment = Platform.environment;
  final home =
      environment['USERPROFILE']?.trim() ??
      environment['HOME']?.trim() ??
      environment['HOMEPATH']?.trim();
  if (home == null || home.isEmpty) {
    return null;
  }

  return p.join(home, '.aws', 'sso', 'cache', 'kiro-auth-token.json');
}

String _credentialSourceTypeForPath(String? requestedPath, String resolvedPath) {
  final explicit = requestedPath?.trim();
  if (explicit == null || explicit.isEmpty) {
    return defaultKiroCredentialSourceType;
  }

  final defaultPath = resolveKiroCredentialSourcePath(null);
  if (defaultPath != null && p.equals(p.normalize(defaultPath), p.normalize(resolvedPath))) {
    return defaultKiroCredentialSourceType;
  }

  final fileName = p.basename(resolvedPath).toLowerCase();
  if (fileName.startsWith('kiro-auth-')) {
    return builderIdKiroCredentialSourceType;
  }
  return manualKiroCredentialSourceType;
}

Future<String> _defaultManagedKiroSourcePath(
  Future<Directory> Function() supportDirectoryProvider,
) async {
  final managedDirectory = Directory(
    await managedKiroSessionsDirectoryPath(supportDirectoryProvider: supportDirectoryProvider),
  );
  await managedDirectory.create(recursive: true);
  final fileName = 'kiro-auth-${DateTime.now().millisecondsSinceEpoch}.json';
  return p.join(managedDirectory.path, fileName);
}

String? _readString(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    final trimmed = switch (value) {
      String text => text.trim(),
      _ => null,
    };
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

DateTime? _readDateTime(Map<String, Object?> json, List<String> keys) {
  final raw = _readString(json, keys);
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}

Map<String, Object?>? _optionalEntry(String key, String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return {key: trimmed};
}

String _firstNonEmpty(String? first, [String? second, String? fallback]) {
  for (final candidate in [first, second, fallback]) {
    final trimmed = candidate?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}

String? _fallbackKiroProfileArn({required String? authMethod, required String? provider}) {
  if (authMethod?.trim().toLowerCase() == builderIdKiroAuthMethod) {
    return defaultKiroBuilderIdProfileArn;
  }

  return switch (provider?.trim().toLowerCase()) {
    'github' || 'google' => defaultKiroSocialProfileArn,
    _ => null,
  };
}
