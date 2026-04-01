import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/models/account_profile.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/oauth_tokens.dart';
import '../../proxy/kiro/kiro_auth_source.dart';

typedef ConfigurationBackupDirectoryResolver = Future<Directory> Function();
typedef ConfigurationBackupReadTokens = Future<OAuthTokens?> Function(String tokenRef);
typedef ConfigurationBackupWriteTokens = Future<void> Function(String tokenRef, OAuthTokens tokens);
typedef ConfigurationBackupDeleteTokens = Future<void> Function(String tokenRef);
typedef ConfigurationBackupReadAccounts = Future<List<AccountProfile>> Function();
typedef ConfigurationBackupReadSettings = Future<AppSettings?> Function();
typedef ConfigurationBackupReplaceAccounts = Future<void> Function(List<AccountProfile> accounts);
typedef ConfigurationBackupSaveSettings = Future<void> Function(AppSettings settings);
typedef ConfigurationBackupSaveFileCallback =
    Future<String?> Function({
      required String fileName,
      required Uint8List bytes,
      String? dialogTitle,
    });
typedef ConfigurationBackupPickFileCallback =
    Future<ConfigurationBackupPickedFile?> Function({String? dialogTitle});
typedef ConfigurationBackupPasswordPrompt =
    Future<String?> Function(ConfigurationBackupPasswordRequest request);

enum ConfigurationBackupErrorCode {
  invalidFormat,
  unsupportedVersion,
  readFailed,
  passwordRequired,
}

class ConfigurationBackupException implements Exception {
  const ConfigurationBackupException(this.code);

  final ConfigurationBackupErrorCode code;
}

class ConfigurationBackupExportOptions {
  const ConfigurationBackupExportOptions.plainJson() : protectWithPassword = false, password = null;

  const ConfigurationBackupExportOptions.passwordProtected({required this.password})
    : protectWithPassword = true;

  final bool protectWithPassword;
  final String? password;

  String? get normalizedPassword {
    final value = password?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }
}

class ConfigurationBackupPasswordRequest {
  const ConfigurationBackupPasswordRequest({required this.fileName, this.invalidPassword = false});

  final String fileName;
  final bool invalidPassword;
}

class ConfigurationBackupPickedFile {
  const ConfigurationBackupPickedFile({required this.fileName, this.bytes, this.path});

  final String fileName;
  final Uint8List? bytes;
  final String? path;
}

class ConfigurationBackupExportResult {
  const ConfigurationBackupExportResult({
    required this.fileName,
    required this.contents,
    required this.accountCount,
    required this.accountsWithTokens,
    required this.protectedWithPassword,
    this.file,
  });

  final String fileName;
  final String contents;
  final int accountCount;
  final int accountsWithTokens;
  final bool protectedWithPassword;
  final File? file;
}

class ConfigurationBackupRestoreResult {
  const ConfigurationBackupRestoreResult({
    required this.fileName,
    required this.accountCount,
    required this.accountsWithTokens,
    required this.accountsWithoutTokens,
    required this.settings,
    required this.wasPasswordProtected,
  });

  final String fileName;
  final int accountCount;
  final int accountsWithTokens;
  final int accountsWithoutTokens;
  final AppSettings settings;
  final bool wasPasswordProtected;
}

class ConfigurationBackupService {
  ConfigurationBackupService({
    required ConfigurationBackupReadTokens readTokens,
    required ConfigurationBackupReadAccounts readCurrentAccounts,
    required ConfigurationBackupReadSettings readCurrentSettings,
    required ConfigurationBackupSaveSettings saveSettings,
    required ConfigurationBackupReplaceAccounts replaceAccounts,
    required ConfigurationBackupWriteTokens writeTokens,
    required ConfigurationBackupDeleteTokens deleteTokens,
    ConfigurationBackupDirectoryResolver? exportDirectoryResolver,
    ConfigurationBackupSaveFileCallback? saveFileCallback,
    ConfigurationBackupPickFileCallback? pickFileCallback,
    bool? useNativeSaveDialog,
    Future<Directory> Function()? supportDirectoryProvider,
  }) : _readTokens = readTokens,
       _readCurrentAccounts = readCurrentAccounts,
       _readCurrentSettings = readCurrentSettings,
       _saveSettings = saveSettings,
       _replaceAccounts = replaceAccounts,
       _writeTokens = writeTokens,
       _deleteTokens = deleteTokens,
       _exportDirectoryResolver = exportDirectoryResolver ?? _defaultExportDirectory,
       _saveFileCallback = saveFileCallback ?? _defaultSaveFile,
       _pickFileCallback = pickFileCallback ?? _defaultPickFile,
       _useNativeSaveDialog = useNativeSaveDialog ?? (Platform.isAndroid || Platform.isWindows),
       _supportDirectoryProvider = supportDirectoryProvider ?? getApplicationSupportDirectory;

  final ConfigurationBackupReadTokens _readTokens;
  final ConfigurationBackupReadAccounts _readCurrentAccounts;
  final ConfigurationBackupReadSettings _readCurrentSettings;
  final ConfigurationBackupSaveSettings _saveSettings;
  final ConfigurationBackupReplaceAccounts _replaceAccounts;
  final ConfigurationBackupWriteTokens _writeTokens;
  final ConfigurationBackupDeleteTokens _deleteTokens;
  final ConfigurationBackupDirectoryResolver _exportDirectoryResolver;
  final ConfigurationBackupSaveFileCallback _saveFileCallback;
  final ConfigurationBackupPickFileCallback _pickFileCallback;
  final bool _useNativeSaveDialog;
  final Future<Directory> Function() _supportDirectoryProvider;

  Future<ConfigurationBackupExportResult?> export({
    required AppSettings settings,
    required List<AccountProfile> accounts,
    required ConfigurationBackupExportOptions options,
    String? dialogTitle,
  }) async {
    final document = await _ConfigurationBackupDocument.fromState(
      settings: settings,
      accounts: accounts,
      readTokens: _readTokens,
      readKiroManagedCredentialState: _readKiroManagedCredentialState,
    );
    final plainContents = _encodeDocument(document);
    final contents = options.protectWithPassword
        ? await _encryptDocumentContents(plainContents, password: options.normalizedPassword)
        : plainContents;
    final fileName = _buildFileName();

    if (_useNativeSaveDialog) {
      final savedLocation = await _saveFileCallback(
        dialogTitle: dialogTitle,
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(contents)),
      );
      if (savedLocation == null) {
        return null;
      }

      return ConfigurationBackupExportResult(
        fileName: _extractFileName(savedLocation, fallback: fileName),
        contents: contents,
        accountCount: document.accounts.length,
        accountsWithTokens: document.accounts
            .where((account) => account.profile.usesSecretStoreTokens && account.tokens != null)
            .length,
        protectedWithPassword: options.protectWithPassword,
      );
    }

    return _writeExportFile(
      fileName: fileName,
      contents: contents,
      document: document,
      protectedWithPassword: options.protectWithPassword,
    );
  }

  Future<ConfigurationBackupRestoreResult?> restore({
    String? dialogTitle,
    ConfigurationBackupPasswordPrompt? passwordPrompt,
  }) async {
    final pickedFile = await _pickFileCallback(dialogTitle: dialogTitle);
    if (pickedFile == null) {
      return null;
    }

    final decodedPayload = await _decodeFilePayload(
      fileName: pickedFile.fileName,
      rawContents: await _readPickedFileContents(pickedFile),
      passwordPrompt: passwordPrompt,
    );
    if (decodedPayload == null) {
      return null;
    }

    final document = _decodeDocument(decodedPayload.contents);
    final currentSettings = await _readCurrentSettings();
    final existingAccounts = await _readCurrentAccounts();
    final previousTokensByRef = await _snapshotTokens(existingAccounts);
    final preparedRestore = await _prepareAccountsForRestore(document.accounts);
    final restoredEntries = preparedRestore.accounts;
    final restoredAccounts = restoredEntries
        .map((entry) => entry.profile)
        .toList(growable: false);
    final restoredCredentialSourcePaths = {
      for (final account in restoredAccounts)
        if (account.provider == AccountProvider.kiro &&
            account.credentialSourcePath?.trim().isNotEmpty == true)
          account.credentialSourcePath!.trim(),
    };

    final importedTokenRefs = <String>{};
    for (final entry in restoredEntries) {
      if (!entry.profile.usesSecretStoreTokens) {
        continue;
      }
      final tokenRef = entry.profile.tokenRef.trim();
      if (tokenRef.isNotEmpty) {
        importedTokenRefs.add(tokenRef);
      }
    }

    try {
      await _replaceAccounts(restoredAccounts);

      var accountsWithTokens = 0;
      for (final entry in restoredEntries) {
        if (!entry.profile.usesSecretStoreTokens) {
          continue;
        }
        final tokenRef = entry.profile.tokenRef.trim();
        if (tokenRef.isEmpty) {
          continue;
        }
        if (entry.tokens == null) {
          await _deleteTokens(tokenRef);
          continue;
        }
        accountsWithTokens += 1;
        await _writeTokens(tokenRef, entry.tokens!);
      }

      for (final account in existingAccounts) {
        if (!account.usesSecretStoreTokens) {
          final sourcePath = account.credentialSourcePath?.trim();
          if (sourcePath == null ||
              sourcePath.isEmpty ||
              restoredCredentialSourcePaths.contains(sourcePath)) {
            continue;
          }
          await deleteManagedKiroCredentialSource(
            sourcePath,
            supportDirectoryProvider: _supportDirectoryProvider,
          );
          continue;
        }
        final tokenRef = account.tokenRef.trim();
        if (tokenRef.isEmpty || importedTokenRefs.contains(tokenRef)) {
          continue;
        }
        await _deleteTokens(tokenRef);
      }

      await _saveSettings(document.settings);

      return ConfigurationBackupRestoreResult(
        fileName: pickedFile.fileName,
        accountCount: document.accounts.length,
        accountsWithTokens: accountsWithTokens,
        accountsWithoutTokens: document.accounts
            .where((entry) => entry.profile.usesSecretStoreTokens && entry.tokens == null)
            .length,
        settings: document.settings,
        wasPasswordProtected: decodedPayload.wasPasswordProtected,
      );
    } catch (error, stackTrace) {
      await _rollbackRestore(
        settings: currentSettings,
        accounts: existingAccounts,
        tokensByRef: previousTokensByRef,
        importedTokenRefs: importedTokenRefs,
        createdManagedKiroSourcePaths: preparedRestore.createdManagedKiroSourcePaths,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  String _encodeDocument(_ConfigurationBackupDocument document) {
    return '${const JsonEncoder.withIndent('  ').convert(document.toJson())}\n';
  }

  _ConfigurationBackupDocument _decodeDocument(String rawContents) {
    try {
      final decoded = jsonDecode(rawContents);
      if (decoded is! Map) {
        throw const ConfigurationBackupException(ConfigurationBackupErrorCode.invalidFormat);
      }
      return _ConfigurationBackupDocument.fromJson(decoded.cast<String, Object?>());
    } on ConfigurationBackupException {
      rethrow;
    } on FormatException {
      throw const ConfigurationBackupException(ConfigurationBackupErrorCode.invalidFormat);
    } on TypeError {
      throw const ConfigurationBackupException(ConfigurationBackupErrorCode.invalidFormat);
    }
  }

  Future<_DecodedBackupPayload?> _decodeFilePayload({
    required String fileName,
    required String rawContents,
    required ConfigurationBackupPasswordPrompt? passwordPrompt,
  }) async {
    final decoded = _decodeJsonMap(rawContents);
    final schema = decoded['schema'];
    if (schema == _ConfigurationBackupDocument.schema) {
      return _DecodedBackupPayload(contents: rawContents, wasPasswordProtected: false);
    }

    if (schema != _EncryptedConfigurationBackupEnvelope.schema) {
      throw const ConfigurationBackupException(ConfigurationBackupErrorCode.invalidFormat);
    }

    if (passwordPrompt == null) {
      throw const ConfigurationBackupException(ConfigurationBackupErrorCode.passwordRequired);
    }

    final envelope = _EncryptedConfigurationBackupEnvelope.fromJson(decoded);
    var invalidPassword = false;
    while (true) {
      final password = await passwordPrompt(
        ConfigurationBackupPasswordRequest(fileName: fileName, invalidPassword: invalidPassword),
      );
      if (password == null) {
        return null;
      }

      try {
        final contents = await _decryptDocumentContents(envelope, password: password.trim());
        return _DecodedBackupPayload(contents: contents, wasPasswordProtected: true);
      } on _InvalidBackupPasswordException {
        invalidPassword = true;
      }
    }
  }

  Map<String, Object?> _decodeJsonMap(String rawContents) {
    try {
      final decoded = jsonDecode(rawContents);
      if (decoded is! Map) {
        throw const ConfigurationBackupException(ConfigurationBackupErrorCode.invalidFormat);
      }
      return decoded.cast<String, Object?>();
    } on ConfigurationBackupException {
      rethrow;
    } on FormatException {
      throw const ConfigurationBackupException(ConfigurationBackupErrorCode.invalidFormat);
    } on TypeError {
      throw const ConfigurationBackupException(ConfigurationBackupErrorCode.invalidFormat);
    }
  }

  Future<String> _readPickedFileContents(ConfigurationBackupPickedFile file) async {
    try {
      if (file.bytes case final bytes? when bytes.isNotEmpty) {
        return _normalizeDecodedContents(utf8.decode(bytes));
      }

      final path = file.path?.trim();
      if (path != null && path.isNotEmpty) {
        return _normalizeDecodedContents(await File(path).readAsString());
      }
    } on FileSystemException {
      throw const ConfigurationBackupException(ConfigurationBackupErrorCode.readFailed);
    } on FormatException {
      throw const ConfigurationBackupException(ConfigurationBackupErrorCode.invalidFormat);
    }

    throw const ConfigurationBackupException(ConfigurationBackupErrorCode.readFailed);
  }

  String _normalizeDecodedContents(String raw) {
    if (raw.startsWith('\uFEFF')) {
      return raw.substring(1);
    }
    return raw;
  }

  Future<String> _encryptDocumentContents(String plainContents, {required String? password}) async {
    final normalizedPassword = password?.trim();
    if (normalizedPassword == null || normalizedPassword.isEmpty) {
      throw const ConfigurationBackupException(ConfigurationBackupErrorCode.passwordRequired);
    }

    final envelope = await _EncryptedConfigurationBackupEnvelope.encrypt(
      plainContents,
      password: normalizedPassword,
    );
    return '${const JsonEncoder.withIndent('  ').convert(envelope.toJson())}\n';
  }

  Future<String> _decryptDocumentContents(
    _EncryptedConfigurationBackupEnvelope envelope, {
    required String password,
  }) async {
    if (password.isEmpty) {
      throw const _InvalidBackupPasswordException();
    }

    try {
      return await envelope.decrypt(password);
    } on SecretBoxAuthenticationError {
      throw const _InvalidBackupPasswordException();
    }
  }

  Future<ConfigurationBackupExportResult> _writeExportFile({
    required String fileName,
    required String contents,
    required _ConfigurationBackupDocument document,
    required bool protectedWithPassword,
  }) async {
    final directory = await _exportDirectoryResolver();
    await directory.create(recursive: true);

    final file = File(p.join(directory.path, fileName));
    await file.writeAsString(contents, flush: true);
    return ConfigurationBackupExportResult(
      fileName: fileName,
      contents: contents,
      accountCount: document.accounts.length,
      accountsWithTokens: document.accounts
          .where((account) => account.profile.usesSecretStoreTokens && account.tokens != null)
          .length,
      protectedWithPassword: protectedWithPassword,
      file: file,
    );
  }

  Future<Map<String, OAuthTokens?>> _snapshotTokens(List<AccountProfile> accounts) async {
    final tokensByRef = <String, OAuthTokens?>{};
    for (final account in accounts) {
      if (!account.usesSecretStoreTokens) {
        continue;
      }
      final tokenRef = account.tokenRef.trim();
      if (tokenRef.isEmpty || tokensByRef.containsKey(tokenRef)) {
        continue;
      }
      tokensByRef[tokenRef] = await _readTokens(tokenRef);
    }
    return tokensByRef;
  }

  Future<_KiroManagedCredentialBackupState?> _readKiroManagedCredentialState(
    AccountProfile account,
  ) async {
    if (account.provider != AccountProvider.kiro ||
        account.credentialSourceType != builderIdKiroCredentialSourceType) {
      return null;
    }

    if (!await isManagedKiroCredentialSourcePath(
      account.credentialSourcePath,
      supportDirectoryProvider: _supportDirectoryProvider,
    )) {
      return null;
    }

    final snapshot = await loadKiroAuthSource(sourcePath: account.credentialSourcePath);
    if (snapshot == null) {
      return null;
    }
    return _KiroManagedCredentialBackupState.fromSnapshot(snapshot);
  }

  Future<_PreparedRestoreAccounts> _prepareAccountsForRestore(
    List<_ConfigurationBackupAccount> accounts,
  ) async {
    final restoredAccounts = <_ConfigurationBackupAccount>[];
    final createdManagedKiroSourcePaths = <String>[];

    for (final entry in accounts) {
      final providerState = entry.kiroManagedCredentialState;
      if (entry.profile.provider != AccountProvider.kiro || providerState == null) {
        restoredAccounts.add(entry);
        continue;
      }

      final restoredSnapshot = await persistKiroAuthSourceSnapshot(
        providerState.toSnapshot(),
        supportDirectoryProvider: _supportDirectoryProvider,
      );
      createdManagedKiroSourcePaths.add(restoredSnapshot.sourcePath);
      restoredAccounts.add(
        _ConfigurationBackupAccount(
          profile: entry.profile.copyWith(
            credentialSourcePath: restoredSnapshot.sourcePath,
            credentialSourceType: restoredSnapshot.sourceType,
            providerRegion: restoredSnapshot.effectiveRegion,
            providerProfileArn: restoredSnapshot.profileArn ?? entry.profile.providerProfileArn,
          ),
          tokens: entry.tokens,
          kiroManagedCredentialState: providerState,
        ),
      );
    }

    return _PreparedRestoreAccounts(
      accounts: restoredAccounts,
      createdManagedKiroSourcePaths: createdManagedKiroSourcePaths,
    );
  }

  Future<void> _rollbackRestore({
    required AppSettings? settings,
    required List<AccountProfile> accounts,
    required Map<String, OAuthTokens?> tokensByRef,
    required Set<String> importedTokenRefs,
    required List<String> createdManagedKiroSourcePaths,
  }) async {
    try {
      await _replaceAccounts(accounts);
    } catch (_) {
      // Best-effort rollback; preserve the original restore error.
    }

    final affectedTokenRefs = <String>{...tokensByRef.keys, ...importedTokenRefs};
    for (final tokenRef in affectedTokenRefs) {
      try {
        final tokens = tokensByRef[tokenRef];
        if (tokens == null) {
          await _deleteTokens(tokenRef);
        } else {
          await _writeTokens(tokenRef, tokens);
        }
      } catch (_) {
        // Best-effort rollback; preserve the original restore error.
      }
    }

    for (final sourcePath in createdManagedKiroSourcePaths) {
      try {
        await deleteManagedKiroCredentialSource(
          sourcePath,
          supportDirectoryProvider: _supportDirectoryProvider,
        );
      } catch (_) {
        // Best-effort rollback; preserve the original restore error.
      }
    }

    if (settings == null) {
      return;
    }

    try {
      await _saveSettings(settings);
    } catch (_) {
      // Best-effort rollback; preserve the original restore error.
    }
  }

  static String _buildFileName() {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return 'kick-backup-$timestamp.json';
  }

  static Future<Directory> _defaultExportDirectory() async {
    if (Platform.isAndroid) {
      final externalDirectory = await getExternalStorageDirectory();
      if (externalDirectory != null) {
        return Directory(p.join(externalDirectory.path, 'backups'));
      }
    }

    final downloadsDirectory = await getDownloadsDirectory();
    if (downloadsDirectory != null) {
      return Directory(p.join(downloadsDirectory.path, 'kick'));
    }

    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(p.join(supportDirectory.path, 'backups'));
  }

  static Future<String?> _defaultSaveFile({
    required String fileName,
    required Uint8List bytes,
    String? dialogTitle,
  }) {
    return FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: bytes,
      lockParentWindow: Platform.isWindows,
    );
  }

  static Future<ConfigurationBackupPickedFile?> _defaultPickFile({String? dialogTitle}) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      lockParentWindow: Platform.isWindows,
    );
    final file = result?.files.singleOrNull;
    if (file == null) {
      return null;
    }
    return ConfigurationBackupPickedFile(fileName: file.name, bytes: file.bytes, path: file.path);
  }

  static String _extractFileName(String savedLocation, {required String fallback}) {
    final decodedLocation = Uri.decodeFull(savedLocation);
    final decodedBaseName = p.basename(decodedLocation);
    if (_isUsefulFileName(decodedBaseName)) {
      return decodedBaseName;
    }

    final uri = Uri.tryParse(savedLocation);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final lastSegment = Uri.decodeComponent(uri.pathSegments.last);
      final uriBaseName = p.basename(lastSegment);
      if (_isUsefulFileName(uriBaseName)) {
        return uriBaseName;
      }
    }

    return fallback;
  }

  static bool _isUsefulFileName(String candidate) {
    return candidate.isNotEmpty && candidate != '.' && candidate != '/' && candidate != '\\';
  }
}

class _ConfigurationBackupDocument {
  const _ConfigurationBackupDocument({
    required this.settings,
    required this.exportedAt,
    required this.accounts,
  });

  static const schema = 'kick.configuration_backup';
  static const version = 1;

  final AppSettings settings;
  final DateTime exportedAt;
  final List<_ConfigurationBackupAccount> accounts;

  static Future<_ConfigurationBackupDocument> fromState({
    required AppSettings settings,
    required List<AccountProfile> accounts,
    required ConfigurationBackupReadTokens readTokens,
    required Future<_KiroManagedCredentialBackupState?> Function(AccountProfile account)
    readKiroManagedCredentialState,
  }) async {
    final exportedAccounts = <_ConfigurationBackupAccount>[];
    for (final account in accounts) {
      exportedAccounts.add(
        _ConfigurationBackupAccount(
          profile: account,
          tokens: account.usesSecretStoreTokens ? await readTokens(account.tokenRef) : null,
          kiroManagedCredentialState: await readKiroManagedCredentialState(account),
        ),
      );
    }

    return _ConfigurationBackupDocument(
      settings: settings,
      exportedAt: DateTime.now(),
      accounts: exportedAccounts,
    );
  }

  factory _ConfigurationBackupDocument.fromJson(Map<String, Object?> json) {
    if (json['schema'] != schema) {
      throw const ConfigurationBackupException(ConfigurationBackupErrorCode.invalidFormat);
    }

    final parsedVersion = _readInt(json['version']);
    if (parsedVersion != version) {
      throw const ConfigurationBackupException(ConfigurationBackupErrorCode.unsupportedVersion);
    }

    final settingsJson = json['settings'];
    final accountsJson = json['accounts'];
    if (settingsJson is! Map || accountsJson is! List) {
      throw const ConfigurationBackupException(ConfigurationBackupErrorCode.invalidFormat);
    }

    final exportedAccounts = <_ConfigurationBackupAccount>[];
    for (final entry in accountsJson) {
      if (entry is! Map) {
        throw const ConfigurationBackupException(ConfigurationBackupErrorCode.invalidFormat);
      }
      exportedAccounts.add(_ConfigurationBackupAccount.fromJson(entry.cast<String, Object?>()));
    }

    return _ConfigurationBackupDocument(
      settings: AppSettings.fromBackupJson(settingsJson.cast<String, Object?>()),
      exportedAt: DateTime.tryParse(_readString(json['exported_at']) ?? '') ?? DateTime.now(),
      accounts: exportedAccounts,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schema': schema,
      'version': version,
      'exported_at': exportedAt.toIso8601String(),
      'settings': settings.toBackupJson(),
      'accounts': accounts.map((entry) => entry.toJson()).toList(growable: false),
    };
  }
}

class _PreparedRestoreAccounts {
  const _PreparedRestoreAccounts({
    required this.accounts,
    required this.createdManagedKiroSourcePaths,
  });

  final List<_ConfigurationBackupAccount> accounts;
  final List<String> createdManagedKiroSourcePaths;
}

class _ConfigurationBackupAccount {
  const _ConfigurationBackupAccount({
    required this.profile,
    required this.tokens,
    this.kiroManagedCredentialState,
  });

  final AccountProfile profile;
  final OAuthTokens? tokens;
  final _KiroManagedCredentialBackupState? kiroManagedCredentialState;

  factory _ConfigurationBackupAccount.fromJson(Map<String, Object?> json) {
    final tokensJson = json['tokens'];
    final providerStateJson = json['provider_state'];
    return _ConfigurationBackupAccount(
      profile: AccountProfile.fromBackupJson(json),
      tokens: tokensJson is Map<String, Object?>
          ? OAuthTokens.fromJson(tokensJson)
          : tokensJson is Map
          ? OAuthTokens.fromJson(tokensJson.cast<String, Object?>())
          : null,
      kiroManagedCredentialState: providerStateJson is Map<String, Object?>
          ? _KiroManagedCredentialBackupState.fromJson(providerStateJson)
          : providerStateJson is Map
          ? _KiroManagedCredentialBackupState.fromJson(providerStateJson.cast<String, Object?>())
          : null,
    );
  }

  Map<String, Object?> toJson() {
    return {
      ...profile.toBackupJson(tokens: tokens),
      if (kiroManagedCredentialState != null) 'provider_state': kiroManagedCredentialState!.toJson(),
    };
  }
}

class _KiroManagedCredentialBackupState {
  const _KiroManagedCredentialBackupState({
    required this.sourceType,
    required this.accessToken,
    required this.refreshToken,
    required this.expiry,
    this.region,
    this.profileArn,
    this.authMethod,
    this.provider,
    this.clientId,
    this.clientSecret,
    this.startUrl,
  });

  factory _KiroManagedCredentialBackupState.fromSnapshot(KiroAuthSourceSnapshot snapshot) {
    return _KiroManagedCredentialBackupState(
      sourceType: snapshot.sourceType,
      accessToken: snapshot.accessToken,
      refreshToken: snapshot.refreshToken,
      expiry: snapshot.expiry,
      region: snapshot.region,
      profileArn: snapshot.profileArn,
      authMethod: snapshot.authMethod,
      provider: snapshot.provider,
      clientId: snapshot.clientId,
      clientSecret: snapshot.clientSecret,
      startUrl: snapshot.startUrl,
    );
  }

  factory _KiroManagedCredentialBackupState.fromJson(Map<String, Object?> json) {
    final accessToken = _readString(json['access_token']);
    final refreshToken = _readString(json['refresh_token']);
    final expiryText = _readString(json['expires_at']);
    final expiry = expiryText == null ? null : DateTime.tryParse(expiryText);
    final sourceType = _readString(json['source_type']);
    if ((json['kind'] as String? ?? '') != 'kiro_auth_source' ||
        accessToken == null ||
        refreshToken == null ||
        expiry == null ||
        sourceType == null) {
      throw const ConfigurationBackupException(ConfigurationBackupErrorCode.invalidFormat);
    }

    return _KiroManagedCredentialBackupState(
      sourceType: sourceType,
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiry: expiry,
      region: _readString(json['region']),
      profileArn: _readString(json['profile_arn']),
      authMethod: _readString(json['auth_method']),
      provider: _readString(json['provider']),
      clientId: _readString(json['client_id']),
      clientSecret: _readString(json['client_secret']),
      startUrl: _readString(json['start_url']),
    );
  }

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

  Map<String, Object?> toJson() {
    return {
      'kind': 'kiro_auth_source',
      'source_type': sourceType,
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'expires_at': expiry.toUtc().toIso8601String(),
      'region': region,
      'profile_arn': profileArn,
      'auth_method': authMethod,
      'provider': provider,
      'client_id': clientId,
      'client_secret': clientSecret,
      'start_url': startUrl,
    };
  }

  KiroAuthSourceSnapshot toSnapshot() {
    return KiroAuthSourceSnapshot(
      sourcePath: '',
      sourceType: sourceType,
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiry: expiry,
      region: region,
      profileArn: profileArn,
      authMethod: authMethod,
      provider: provider,
      clientId: clientId,
      clientSecret: clientSecret,
      startUrl: startUrl,
    );
  }
}

class _EncryptedConfigurationBackupEnvelope {
  const _EncryptedConfigurationBackupEnvelope({
    required this.iterations,
    required this.salt,
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  static const schema = 'kick.encrypted_configuration_backup';
  static const version = 1;
  static const cipher = 'AES-256-GCM';
  static const kdf = 'PBKDF2-HMAC-SHA256';
  static const keyBits = 256;
  static const _pbkdf2Iterations = 300000;
  static const _saltLength = 16;
  static const _nonceLength = 12;

  final int iterations;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List cipherText;
  final Uint8List mac;

  static Future<_EncryptedConfigurationBackupEnvelope> encrypt(
    String plainContents, {
    required String password,
  }) async {
    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final secretKey = await _deriveKey(
      password: password,
      salt: salt,
      iterations: _pbkdf2Iterations,
    );
    final secretBox = await AesGcm.with256bits().encrypt(
      utf8.encode(plainContents),
      secretKey: secretKey,
      nonce: nonce,
    );

    return _EncryptedConfigurationBackupEnvelope(
      iterations: _pbkdf2Iterations,
      salt: Uint8List.fromList(salt),
      nonce: Uint8List.fromList(secretBox.nonce),
      cipherText: Uint8List.fromList(secretBox.cipherText),
      mac: Uint8List.fromList(secretBox.mac.bytes),
    );
  }

  factory _EncryptedConfigurationBackupEnvelope.fromJson(Map<String, Object?> json) {
    if (json['schema'] != schema) {
      throw const ConfigurationBackupException(ConfigurationBackupErrorCode.invalidFormat);
    }

    final parsedVersion = _readInt(json['version']);
    if (parsedVersion != version) {
      throw const ConfigurationBackupException(ConfigurationBackupErrorCode.unsupportedVersion);
    }

    final kdfJson = json['kdf'];
    if (json['cipher'] != cipher || kdfJson is! Map) {
      throw const ConfigurationBackupException(ConfigurationBackupErrorCode.invalidFormat);
    }

    final kdfName = kdfJson['name'];
    final iterations = _readInt(kdfJson['iterations']);
    final bits = _readInt(kdfJson['bits']);
    final salt = _decodeBase64(kdfJson['salt']);
    final nonce = _decodeBase64(json['nonce']);
    final cipherText = _decodeBase64(json['ciphertext']);
    final mac = _decodeBase64(json['mac']);
    if (kdfName != kdf ||
        iterations == null ||
        iterations < 1 ||
        bits != keyBits ||
        salt == null ||
        nonce == null ||
        cipherText == null ||
        mac == null) {
      throw const ConfigurationBackupException(ConfigurationBackupErrorCode.invalidFormat);
    }

    return _EncryptedConfigurationBackupEnvelope(
      iterations: iterations,
      salt: salt,
      nonce: nonce,
      cipherText: cipherText,
      mac: mac,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schema': schema,
      'version': version,
      'cipher': cipher,
      'kdf': {'name': kdf, 'iterations': iterations, 'bits': keyBits, 'salt': base64Encode(salt)},
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(cipherText),
      'mac': base64Encode(mac),
    };
  }

  Future<String> decrypt(String password) async {
    final secretKey = await _deriveKey(password: password, salt: salt, iterations: iterations);
    final bytes = await AesGcm.with256bits().decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: secretKey,
    );
    return utf8.decode(bytes);
  }

  static Future<SecretKey> _deriveKey({
    required String password,
    required List<int> salt,
    required int iterations,
  }) {
    return Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: keyBits,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => random.nextInt(256)));
  }
}

class _DecodedBackupPayload {
  const _DecodedBackupPayload({required this.contents, required this.wasPasswordProtected});

  final String contents;
  final bool wasPasswordProtected;
}

class _InvalidBackupPasswordException implements Exception {
  const _InvalidBackupPasswordException();
}

String? _readString(Object? value) {
  return switch (value) {
    String text => text.trim(),
    _ => null,
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

Uint8List? _decodeBase64(Object? value) {
  final text = _readString(value);
  if (text == null || text.isEmpty) {
    return null;
  }
  try {
    return Uint8List.fromList(base64Decode(text));
  } on FormatException {
    return null;
  }
}
