import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/account_profile.dart';
import '../../data/models/oauth_tokens.dart';
import '../../proxy/kiro/kiro_auth_source.dart';

typedef AccountShareDirectoryResolver = Future<Directory> Function();
typedef AccountShareReadTokens = Future<OAuthTokens?> Function(String tokenRef);
typedef AccountShareWriteTokens = Future<void> Function(String tokenRef, OAuthTokens tokens);
typedef AccountShareSaveFileCallback =
    Future<String?> Function({
      required String fileName,
      required Uint8List bytes,
      String? dialogTitle,
    });
typedef AccountSharePickFileCallback =
    Future<AccountSharePickedFile?> Function({String? dialogTitle});
typedef AccountShareCallback = Future<ShareResult> Function(ShareParams params);

/// Marker error code surfaced to the UI when an import file is malformed.
enum AccountShareErrorCode { invalidFormat, unsupportedVersion, readFailed }

class AccountShareException implements Exception {
  const AccountShareException(this.code);

  final AccountShareErrorCode code;
}

class AccountSharePickedFile {
  const AccountSharePickedFile({required this.fileName, this.bytes, this.path});

  final String fileName;
  final Uint8List? bytes;
  final String? path;
}

class AccountShareExportResult {
  const AccountShareExportResult({
    required this.fileName,
    required this.contents,
    required this.tokensIncluded,
    this.file,
  });

  final String fileName;
  final String contents;
  final bool tokensIncluded;
  final File? file;
}

class AccountShareImportResult {
  const AccountShareImportResult({
    required this.fileName,
    required this.account,
    required this.tokens,
    required this.kiroManagedCredentialState,
  });

  final String fileName;
  final AccountProfile account;
  final OAuthTokens? tokens;
  final SharedKiroManagedCredentialState? kiroManagedCredentialState;
}

const _accountShareSchema = 'kick.account_share';
const _accountShareVersion = 1;
const _accountShareFileExtension = 'kickacc';

class AccountShareService {
  AccountShareService({
    required AccountShareReadTokens readTokens,
    AccountShareDirectoryResolver? exportDirectoryResolver,
    AccountShareSaveFileCallback? saveFileCallback,
    AccountSharePickFileCallback? pickFileCallback,
    AccountShareCallback? shareCallback,
    bool? useNativeSaveDialog,
    Future<Directory> Function()? supportDirectoryProvider,
  }) : _readTokens = readTokens,
       _exportDirectoryResolver = exportDirectoryResolver ?? _defaultExportDirectory,
       _saveFileCallback = saveFileCallback ?? _defaultSaveFile,
       _pickFileCallback = pickFileCallback ?? _defaultPickFile,
       _shareCallback = shareCallback ?? _defaultShare,
       _useNativeSaveDialog = useNativeSaveDialog ?? (Platform.isWindows || Platform.isLinux),
       _supportDirectoryProvider = supportDirectoryProvider ?? getApplicationSupportDirectory;

  final AccountShareReadTokens _readTokens;
  final AccountShareDirectoryResolver _exportDirectoryResolver;
  final AccountShareSaveFileCallback _saveFileCallback;
  final AccountSharePickFileCallback _pickFileCallback;
  final AccountShareCallback _shareCallback;
  final bool _useNativeSaveDialog;
  final Future<Directory> Function() _supportDirectoryProvider;

  Future<AccountShareExportResult?> share({
    required AccountProfile account,
    String? dialogTitle,
    String? shareSubject,
    String? shareText,
  }) async {
    final tokens = account.usesSecretStoreTokens ? await _readTokens(account.tokenRef) : null;
    final managedKiroState = await _readKiroManagedCredentialState(account);
    final document = _AccountShareDocument(
      exportedAt: DateTime.now(),
      account: account,
      tokens: tokens,
      kiroManagedCredentialState: managedKiroState,
    );
    final contents = _encodeDocument(document);
    final fileName = _buildFileName(account);

    if (_useNativeSaveDialog) {
      final savedLocation = await _saveFileCallback(
        dialogTitle: dialogTitle,
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(contents)),
      );
      if (savedLocation == null) {
        return null;
      }
      return AccountShareExportResult(
        fileName: _extractFileName(savedLocation, fallback: fileName),
        contents: contents,
        tokensIncluded: tokens != null || managedKiroState != null,
      );
    }

    final result = await _writeToTempFile(fileName: fileName, contents: contents);
    final shareResult = await _shareCallback(
      ShareParams(
        files: [XFile(result.file!.path, name: result.fileName, mimeType: 'application/json')],
        subject: shareSubject,
        text: shareText,
      ),
    );
    if (shareResult.status == ShareResultStatus.dismissed) {
      return null;
    }
    return AccountShareExportResult(
      fileName: result.fileName,
      contents: contents,
      tokensIncluded: tokens != null || managedKiroState != null,
      file: result.file,
    );
  }

  Future<AccountShareImportResult?> pickAndDecode({String? dialogTitle}) async {
    final pickedFile = await _pickFileCallback(dialogTitle: dialogTitle);
    if (pickedFile == null) {
      return null;
    }
    final rawContents = await _readPickedFileContents(pickedFile);
    final document = _decodeDocument(rawContents);
    return AccountShareImportResult(
      fileName: pickedFile.fileName,
      account: document.account,
      tokens: document.tokens,
      kiroManagedCredentialState: document.kiroManagedCredentialState,
    );
  }

  Future<KiroAuthSourceSnapshot?> materializeKiroManagedCredential(
    SharedKiroManagedCredentialState state,
  ) {
    return persistKiroAuthSourceSnapshot(
      state.toSnapshot(),
      supportDirectoryProvider: _supportDirectoryProvider,
    );
  }

  Future<SharedKiroManagedCredentialState?> _readKiroManagedCredentialState(
    AccountProfile account,
  ) async {
    if (account.provider != AccountProvider.kiro) {
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
    return SharedKiroManagedCredentialState.fromSnapshot(snapshot);
  }

  String _encodeDocument(_AccountShareDocument document) {
    return '${const JsonEncoder.withIndent('  ').convert(document.toJson())}\n';
  }

  _AccountShareDocument _decodeDocument(String rawContents) {
    try {
      final decoded = jsonDecode(rawContents);
      if (decoded is! Map) {
        throw const AccountShareException(AccountShareErrorCode.invalidFormat);
      }
      return _AccountShareDocument.fromJson(decoded.cast<String, Object?>());
    } on AccountShareException {
      rethrow;
    } on FormatException {
      throw const AccountShareException(AccountShareErrorCode.invalidFormat);
    } on TypeError {
      throw const AccountShareException(AccountShareErrorCode.invalidFormat);
    }
  }

  Future<String> _readPickedFileContents(AccountSharePickedFile file) async {
    try {
      if (file.bytes case final bytes? when bytes.isNotEmpty) {
        return _stripBom(utf8.decode(bytes));
      }
      final path = file.path?.trim();
      if (path != null && path.isNotEmpty) {
        return _stripBom(await File(path).readAsString());
      }
    } on FileSystemException {
      throw const AccountShareException(AccountShareErrorCode.readFailed);
    } on FormatException {
      throw const AccountShareException(AccountShareErrorCode.invalidFormat);
    }
    throw const AccountShareException(AccountShareErrorCode.readFailed);
  }

  String _stripBom(String raw) {
    if (raw.startsWith('\uFEFF')) {
      return raw.substring(1);
    }
    return raw;
  }

  Future<AccountShareExportResult> _writeToTempFile({
    required String fileName,
    required String contents,
  }) async {
    final directory = await _exportDirectoryResolver();
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, fileName));
    await file.writeAsString(contents, flush: true);
    return AccountShareExportResult(
      fileName: fileName,
      contents: contents,
      tokensIncluded: false, // recomputed by caller before returning to UI
      file: file,
    );
  }

  static String _buildFileName(AccountProfile account) {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final slug = _slugify(account.label.isNotEmpty ? account.label : account.email);
    final prefix = slug.isEmpty ? 'account' : slug;
    return 'kick-$prefix-$timestamp.$_accountShareFileExtension';
  }

  static String _slugify(String value) {
    final lowered = value.toLowerCase();
    final buffer = StringBuffer();
    var lastWasDash = false;
    for (final rune in lowered.runes) {
      final isAlphaNumeric = (rune >= 0x30 && rune <= 0x39) || (rune >= 0x61 && rune <= 0x7a);
      if (isAlphaNumeric) {
        buffer.writeCharCode(rune);
        lastWasDash = false;
      } else if (!lastWasDash && buffer.isNotEmpty) {
        buffer.write('-');
        lastWasDash = true;
      }
    }
    final slug = buffer.toString();
    final trimmed = slug.endsWith('-') ? slug.substring(0, slug.length - 1) : slug;
    if (trimmed.length <= 32) {
      return trimmed;
    }
    return trimmed.substring(0, 32);
  }

  static Future<Directory> _defaultExportDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final supportDirectory = await getApplicationSupportDirectory();
      return Directory(p.join(supportDirectory.path, 'shared_accounts'));
    }
    final downloadsDirectory = await getDownloadsDirectory();
    if (downloadsDirectory != null) {
      return Directory(p.join(downloadsDirectory.path, 'kick'));
    }
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(p.join(supportDirectory.path, 'shared_accounts'));
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
      allowedExtensions: const [_accountShareFileExtension],
      bytes: bytes,
      lockParentWindow: Platform.isWindows,
    );
  }

  static Future<AccountSharePickedFile?> _defaultPickFile({String? dialogTitle}) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const [_accountShareFileExtension, 'json'],
      lockParentWindow: Platform.isWindows,
    );
    final file = result?.files.singleOrNull;
    if (file == null) {
      return null;
    }
    return AccountSharePickedFile(fileName: file.name, bytes: file.bytes, path: file.path);
  }

  static Future<ShareResult> _defaultShare(ShareParams params) {
    return SharePlus.instance.share(params);
  }

  static String _extractFileName(String savedLocation, {required String fallback}) {
    final decodedLocation = Uri.decodeFull(savedLocation);
    final decodedBaseName = p.basename(decodedLocation);
    if (decodedBaseName.isNotEmpty && decodedBaseName != '.' && decodedBaseName != '/') {
      return decodedBaseName;
    }
    final uri = Uri.tryParse(savedLocation);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final lastSegment = Uri.decodeComponent(uri.pathSegments.last);
      final uriBaseName = p.basename(lastSegment);
      if (uriBaseName.isNotEmpty && uriBaseName != '.' && uriBaseName != '/') {
        return uriBaseName;
      }
    }
    return fallback;
  }
}

class _AccountShareDocument {
  const _AccountShareDocument({
    required this.exportedAt,
    required this.account,
    required this.tokens,
    required this.kiroManagedCredentialState,
  });

  final DateTime exportedAt;
  final AccountProfile account;
  final OAuthTokens? tokens;
  final SharedKiroManagedCredentialState? kiroManagedCredentialState;

  factory _AccountShareDocument.fromJson(Map<String, Object?> json) {
    if (json['schema'] != _accountShareSchema) {
      throw const AccountShareException(AccountShareErrorCode.invalidFormat);
    }
    final rawVersion = json['version'];
    final version = rawVersion is num ? rawVersion.toInt() : int.tryParse('$rawVersion');
    if (version != _accountShareVersion) {
      throw const AccountShareException(AccountShareErrorCode.unsupportedVersion);
    }
    final accountJson = json['account'];
    if (accountJson is! Map) {
      throw const AccountShareException(AccountShareErrorCode.invalidFormat);
    }
    final accountMap = accountJson.cast<String, Object?>();
    final tokensJson = accountMap['tokens'];
    final providerStateJson = accountMap['provider_state'];
    AccountProfile profile;
    try {
      profile = AccountProfile.fromBackupJson(accountMap);
    } on FormatException {
      throw const AccountShareException(AccountShareErrorCode.invalidFormat);
    } on TypeError {
      throw const AccountShareException(AccountShareErrorCode.invalidFormat);
    }

    OAuthTokens? tokens;
    if (tokensJson is Map) {
      try {
        tokens = OAuthTokens.fromJson(tokensJson.cast<String, Object?>());
      } on FormatException {
        throw const AccountShareException(AccountShareErrorCode.invalidFormat);
      }
    }

    SharedKiroManagedCredentialState? providerState;
    if (providerStateJson is Map) {
      providerState = SharedKiroManagedCredentialState.fromJson(
        providerStateJson.cast<String, Object?>(),
      );
    }

    return _AccountShareDocument(
      exportedAt: DateTime.tryParse(json['exported_at']?.toString() ?? '') ?? DateTime.now(),
      account: profile,
      tokens: tokens,
      kiroManagedCredentialState: providerState,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schema': _accountShareSchema,
      'version': _accountShareVersion,
      'exported_at': exportedAt.toIso8601String(),
      'account': {
        ...account.toBackupJson(tokens: tokens),
        if (kiroManagedCredentialState != null)
          'provider_state': kiroManagedCredentialState!.toJson(),
      },
    };
  }
}

class SharedKiroManagedCredentialState {
  const SharedKiroManagedCredentialState({
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

  factory SharedKiroManagedCredentialState.fromSnapshot(KiroAuthSourceSnapshot snapshot) {
    return SharedKiroManagedCredentialState(
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

  factory SharedKiroManagedCredentialState.fromJson(Map<String, Object?> json) {
    final accessToken = _readString(json['access_token']);
    final refreshToken = _readString(json['refresh_token']);
    final expiryText = _readString(json['expires_at']);
    final expiry = expiryText == null ? null : DateTime.tryParse(expiryText);
    final sourceType = _readString(json['source_type']);
    if ((json['kind']?.toString() ?? '') != 'kiro_auth_source' ||
        accessToken == null ||
        refreshToken == null ||
        expiry == null ||
        sourceType == null) {
      throw const AccountShareException(AccountShareErrorCode.invalidFormat);
    }
    return SharedKiroManagedCredentialState(
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

String? _readString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
