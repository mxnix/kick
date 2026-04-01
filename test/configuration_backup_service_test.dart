import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/data/models/app_settings.dart';
import 'package:kick/data/models/oauth_tokens.dart';
import 'package:kick/features/settings/configuration_backup_service.dart';
import 'package:kick/proxy/kiro/kiro_auth_source.dart';

void main() {
  AccountProfile buildAccount({
    required String id,
    required String label,
    required String email,
    required String projectId,
    required String tokenRef,
    AccountProvider provider = AccountProvider.gemini,
    String? credentialSourcePath,
    String? credentialSourceType,
    String? providerProfileArn,
    bool enabled = true,
    int priority = 0,
    List<String> notSupportedModels = const [],
    List<String> runtimeNotSupportedModels = const [],
  }) {
    return AccountProfile(
      id: id,
      label: label,
      email: email,
      projectId: projectId,
      provider: provider,
      credentialSourcePath: credentialSourcePath,
      credentialSourceType: credentialSourceType,
      providerProfileArn: providerProfileArn,
      enabled: enabled,
      priority: priority,
      notSupportedModels: notSupportedModels,
      runtimeNotSupportedModels: runtimeNotSupportedModels,
      lastUsedAt: DateTime.parse('2026-03-20T12:00:00Z'),
      usageCount: 3,
      errorCount: 1,
      cooldownUntil: DateTime.parse('2026-03-20T13:00:00Z'),
      lastQuotaSnapshot: 'quota-warning',
      tokenRef: tokenRef,
    );
  }

  OAuthTokens buildTokens(String accessToken) {
    return OAuthTokens(
      accessToken: accessToken,
      refreshToken: 'refresh-$accessToken',
      expiry: DateTime.parse('2026-03-21T12:00:00Z'),
      tokenType: 'Bearer',
      scope: 'openid email profile',
    );
  }

  test('exports settings, accounts and oauth tokens into backup json', () async {
    Uint8List? exportedBytes;
    final service = ConfigurationBackupService(
      readTokens: (tokenRef) async => tokenRef == 'primary-ref' ? buildTokens('access-1') : null,
      readCurrentAccounts: () async => const [],
      readCurrentSettings: () async => AppSettings.defaults(apiKey: 'kick-secret'),
      saveSettings: (_) async {},
      replaceAccounts: (_) async {},
      writeTokens: (_, _) async {},
      deleteTokens: (_) async {},
      useNativeSaveDialog: true,
      saveFileCallback:
          ({required String fileName, required Uint8List bytes, String? dialogTitle}) async {
            exportedBytes = bytes;
            return 'content://downloads/document/primary%3ADownload%2Fkick-transfer.json';
          },
    );

    final result = await service.export(
      settings: AppSettings.defaults(
        apiKey: 'kick-secret',
      ).copyWith(host: '192.168.0.10', port: 4010, customModels: const ['gemini-2.5-flash']),
      accounts: [
        buildAccount(
          id: 'primary',
          label: 'Primary',
          email: 'primary@example.com',
          projectId: 'proj-primary',
          tokenRef: 'primary-ref',
          priority: 2,
          notSupportedModels: const ['gemini-2.5-pro'],
          runtimeNotSupportedModels: const ['gemini-2.5-flash-preview'],
        ),
      ],
      options: const ConfigurationBackupExportOptions.plainJson(),
      dialogTitle: 'Save backup',
    );

    expect(result, isNotNull);
    expect(result!.fileName, 'kick-transfer.json');
    expect(result.accountCount, 1);
    expect(result.accountsWithTokens, 1);
    expect(result.protectedWithPassword, isFalse);

    final decoded = jsonDecode(utf8.decode(exportedBytes!)) as Map<String, Object?>;
    expect(decoded['schema'], 'kick.configuration_backup');
    expect(decoded['version'], 1);

    final settings = decoded['settings'] as Map<String, Object?>;
    expect(settings['api_key'], 'kick-secret');
    expect(settings['host'], '192.168.0.10');
    expect(settings['port'], 4010);
    expect(settings['custom_models'], ['gemini-2.5-flash']);

    final accounts = decoded['accounts'] as List<Object?>;
    final account = accounts.single as Map<String, Object?>;
    expect(account['id'], 'primary');
    expect(account['token_ref'], 'primary-ref');
    expect(account['not_supported_models'], ['gemini-2.5-pro']);
    expect(account['runtime_not_supported_models'], ['gemini-2.5-flash-preview']);

    final tokens = account['tokens'] as Map<String, Object?>;
    expect(tokens['access_token'], 'access-1');
    expect(tokens['refresh_token'], 'refresh-access-1');
  });

  test('exports password-protected backup without leaking plaintext secrets', () async {
    Uint8List? exportedBytes;
    final service = ConfigurationBackupService(
      readTokens: (tokenRef) async => tokenRef == 'primary-ref' ? buildTokens('access-1') : null,
      readCurrentAccounts: () async => const [],
      readCurrentSettings: () async => AppSettings.defaults(apiKey: 'kick-secret'),
      saveSettings: (_) async {},
      replaceAccounts: (_) async {},
      writeTokens: (_, _) async {},
      deleteTokens: (_) async {},
      useNativeSaveDialog: true,
      saveFileCallback:
          ({required String fileName, required Uint8List bytes, String? dialogTitle}) async {
            exportedBytes = bytes;
            return 'content://downloads/document/primary%3ADownload%2Fkick-secure.json';
          },
    );

    final result = await service.export(
      settings: AppSettings.defaults(apiKey: 'kick-secret'),
      accounts: [
        buildAccount(
          id: 'primary',
          label: 'Primary',
          email: 'primary@example.com',
          projectId: 'proj-primary',
          tokenRef: 'primary-ref',
        ),
      ],
      options: const ConfigurationBackupExportOptions.passwordProtected(password: 'Pa55w0rd!'),
      dialogTitle: 'Save backup',
    );

    final contents = utf8.decode(exportedBytes!);
    expect(result, isNotNull);
    expect(result!.protectedWithPassword, isTrue);
    expect(contents, contains('"schema": "kick.encrypted_configuration_backup"'));
    expect(contents, isNot(contains('kick-secret')));
    expect(contents, isNot(contains('access-1')));
    expect(contents, isNot(contains('primary@example.com')));
  });

  test('exports Kiro accounts with source metadata but without external tokens', () async {
    Uint8List? exportedBytes;
    final tokenReads = <String>[];
    final service = ConfigurationBackupService(
      readTokens: (tokenRef) async {
        tokenReads.add(tokenRef);
        return tokenRef == 'primary-ref' ? buildTokens('access-1') : null;
      },
      readCurrentAccounts: () async => const [],
      readCurrentSettings: () async => AppSettings.defaults(apiKey: 'kick-secret'),
      saveSettings: (_) async {},
      replaceAccounts: (_) async {},
      writeTokens: (_, _) async {},
      deleteTokens: (_) async {},
      useNativeSaveDialog: true,
      saveFileCallback:
          ({required String fileName, required Uint8List bytes, String? dialogTitle}) async {
            exportedBytes = bytes;
            return 'content://downloads/document/primary%3ADownload%2Fkick-transfer.json';
          },
    );

    final result = await service.export(
      settings: AppSettings.defaults(apiKey: 'kick-secret'),
      accounts: [
        buildAccount(
          id: 'primary',
          label: 'Primary',
          email: 'primary@example.com',
          projectId: 'proj-primary',
          tokenRef: 'primary-ref',
        ),
        buildAccount(
          id: 'kiro',
          label: 'Kiro',
          email: 'Kiro local session',
          projectId: '',
          provider: AccountProvider.kiro,
          credentialSourcePath: r'C:\Users\demo\.aws\sso\cache\kiro-auth-token.json',
          credentialSourceType: 'local_json',
          providerProfileArn: 'arn:aws:iam::123456789012:user/demo',
          tokenRef: 'kiro-ref',
        ),
      ],
      options: const ConfigurationBackupExportOptions.plainJson(),
      dialogTitle: 'Save backup',
    );

    expect(result, isNotNull);
    expect(result!.accountsWithTokens, 1);
    expect(tokenReads, ['primary-ref']);

    final decoded = jsonDecode(utf8.decode(exportedBytes!)) as Map<String, Object?>;
    final accounts = (decoded['accounts'] as List).cast<Map<String, Object?>>();
    final kiroAccount = accounts.singleWhere((account) => account['id'] == 'kiro');

    expect(kiroAccount['provider'], 'kiro');
    expect(kiroAccount['credential_source_type'], 'local_json');
    expect(
      kiroAccount['credential_source_path'],
      r'C:\Users\demo\.aws\sso\cache\kiro-auth-token.json',
    );
    expect(kiroAccount['provider_profile_arn'], 'arn:aws:iam::123456789012:user/demo');
    expect(kiroAccount['tokens'], isNull);
  });

  test('restores managed Builder ID Kiro sessions into a new local managed path', () async {
    final exportSupportDirectory = await Directory.systemTemp.createTemp('kick_kiro_backup_export');
    final restoreSupportDirectory = await Directory.systemTemp.createTemp(
      'kick_kiro_backup_restore',
    );
    addTearDown(() => exportSupportDirectory.delete(recursive: true));
    addTearDown(() => restoreSupportDirectory.delete(recursive: true));

    final savedSource = await persistKiroAuthSourceSnapshot(
      KiroAuthSourceSnapshot(
        sourcePath: '',
        sourceType: builderIdKiroCredentialSourceType,
        accessToken: 'kiro-access',
        refreshToken: 'kiro-refresh',
        expiry: DateTime.parse('2026-04-01T12:00:00Z'),
        region: 'us-east-1',
        profileArn: 'arn:aws:iam::123456789012:user/demo',
        authMethod: builderIdKiroAuthMethod,
        provider: 'kiro',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        startUrl: defaultKiroBuilderIdStartUrl,
      ),
      supportDirectoryProvider: () async => exportSupportDirectory,
    );

    Uint8List? exportedBytes;
    final exportService = ConfigurationBackupService(
      readTokens: (_) async => null,
      readCurrentAccounts: () async => const [],
      readCurrentSettings: () async => AppSettings.defaults(apiKey: 'kick-secret'),
      saveSettings: (_) async {},
      replaceAccounts: (_) async {},
      writeTokens: (_, _) async {},
      deleteTokens: (_) async {},
      useNativeSaveDialog: true,
      supportDirectoryProvider: () async => exportSupportDirectory,
      saveFileCallback:
          ({required String fileName, required Uint8List bytes, String? dialogTitle}) async {
            exportedBytes = bytes;
            return 'content://downloads/document/primary%3ADownload%2Fkick-transfer.json';
          },
    );

    await exportService.export(
      settings: AppSettings.defaults(apiKey: 'kick-secret'),
      accounts: [
        buildAccount(
          id: 'kiro',
          label: 'Kiro',
          email: 'AWS Builder ID',
          projectId: '',
          provider: AccountProvider.kiro,
          credentialSourcePath: savedSource.sourcePath,
          credentialSourceType: builderIdKiroCredentialSourceType,
          providerProfileArn: 'arn:aws:iam::123456789012:user/demo',
          tokenRef: 'kiro-ref',
        ),
      ],
      options: const ConfigurationBackupExportOptions.plainJson(),
    );

    final restoredAccounts = <List<AccountProfile>>[];
    final restoreService = ConfigurationBackupService(
      readTokens: (_) async => null,
      readCurrentAccounts: () async => const [],
      readCurrentSettings: () async => AppSettings.defaults(apiKey: 'old-api-key'),
      saveSettings: (_) async {},
      replaceAccounts: (accounts) async {
        restoredAccounts.add(accounts);
      },
      writeTokens: (_, _) async {},
      deleteTokens: (_) async {},
      supportDirectoryProvider: () async => restoreSupportDirectory,
      pickFileCallback: ({String? dialogTitle}) async {
        return ConfigurationBackupPickedFile(
          fileName: 'kick-restore.json',
          bytes: exportedBytes,
        );
      },
    );

    final result = await restoreService.restore();

    expect(result, isNotNull);
    expect(result!.accountsWithTokens, 0);
    expect(restoredAccounts, hasLength(1));
    expect(restoredAccounts.single, hasLength(1));

    final restoredAccount = restoredAccounts.single.single;
    expect(restoredAccount.provider, AccountProvider.kiro);
    expect(restoredAccount.credentialSourceType, builderIdKiroCredentialSourceType);
    expect(restoredAccount.credentialSourcePath, isNot(savedSource.sourcePath));
    expect(
      await isManagedKiroCredentialSourcePath(
        restoredAccount.credentialSourcePath,
        supportDirectoryProvider: () async => restoreSupportDirectory,
      ),
      isTrue,
    );

    final restoredSnapshot = await loadKiroAuthSource(
      sourcePath: restoredAccount.credentialSourcePath,
    );
    expect(restoredSnapshot, isNotNull);
    expect(restoredSnapshot!.accessToken, 'kiro-access');
    expect(restoredSnapshot.refreshToken, 'kiro-refresh');
    expect(restoredSnapshot.clientId, 'client-id');
    expect(restoredSnapshot.clientSecret, 'client-secret');
    expect(restoredSnapshot.profileArn, 'arn:aws:iam::123456789012:user/demo');
  });

  test('restores settings, replaces accounts and cleans up stale tokens', () async {
    final savedSettings = <AppSettings>[];
    final replacedAccounts = <List<AccountProfile>>[];
    final writtenTokens = <String, OAuthTokens>{};
    final deletedTokens = <String>[];
    final backupContents = jsonEncode({
      'schema': 'kick.configuration_backup',
      'version': 1,
      'exported_at': '2026-03-29T10:00:00Z',
      'settings': AppSettings.defaults(apiKey: 'restored-api-key')
          .copyWith(host: '10.0.0.5', port: 5000, allowLan: true, themeMode: ThemeMode.dark)
          .toBackupJson(),
      'accounts': [
        buildAccount(
          id: 'primary',
          label: 'Primary',
          email: 'primary@example.com',
          projectId: 'proj-primary',
          tokenRef: 'primary-ref',
          priority: 2,
        ).toBackupJson(tokens: buildTokens('access-primary')),
        buildAccount(
          id: 'secondary',
          label: 'Secondary',
          email: 'secondary@example.com',
          projectId: 'proj-secondary',
          tokenRef: 'secondary-ref',
        ).toBackupJson(),
      ],
    });

    final service = ConfigurationBackupService(
      readTokens: (_) async => null,
      readCurrentAccounts: () async => [
        buildAccount(
          id: 'obsolete',
          label: 'Obsolete',
          email: 'obsolete@example.com',
          projectId: 'proj-obsolete',
          tokenRef: 'obsolete-ref',
        ),
      ],
      readCurrentSettings: () async => AppSettings.defaults(apiKey: 'old-api-key'),
      saveSettings: (settings) async {
        savedSettings.add(settings);
      },
      replaceAccounts: (accounts) async {
        replacedAccounts.add(accounts);
      },
      writeTokens: (tokenRef, tokens) async {
        writtenTokens[tokenRef] = tokens;
      },
      deleteTokens: (tokenRef) async {
        deletedTokens.add(tokenRef);
      },
      pickFileCallback: ({String? dialogTitle}) async {
        return ConfigurationBackupPickedFile(
          fileName: 'kick-restore.json',
          bytes: Uint8List.fromList(utf8.encode(backupContents)),
        );
      },
    );

    final result = await service.restore(dialogTitle: 'Pick backup');

    expect(result, isNotNull);
    expect(result!.fileName, 'kick-restore.json');
    expect(result.accountCount, 2);
    expect(result.accountsWithTokens, 1);
    expect(result.accountsWithoutTokens, 1);

    expect(savedSettings, hasLength(1));
    expect(savedSettings.single.apiKey, 'restored-api-key');
    expect(savedSettings.single.host, '10.0.0.5');
    expect(savedSettings.single.port, 5000);
    expect(savedSettings.single.allowLan, isTrue);
    expect(result.wasPasswordProtected, isFalse);

    expect(replacedAccounts, hasLength(1));
    expect(replacedAccounts.single.map((account) => account.id), ['primary', 'secondary']);
    expect(replacedAccounts.single.first.tokenRef, 'primary-ref');
    expect(replacedAccounts.single.last.tokenRef, 'secondary-ref');

    expect(writtenTokens.keys, ['primary-ref']);
    expect(writtenTokens['primary-ref']?.accessToken, 'access-primary');
    expect(deletedTokens, containsAll(['obsolete-ref', 'secondary-ref']));
  });

  test('restores password-protected backup after retrying invalid password', () async {
    Uint8List? exportedBytes;
    final exportService = ConfigurationBackupService(
      readTokens: (tokenRef) async => tokenRef == 'primary-ref' ? buildTokens('access-1') : null,
      readCurrentAccounts: () async => const [],
      readCurrentSettings: () async => AppSettings.defaults(apiKey: 'kick-secret'),
      saveSettings: (_) async {},
      replaceAccounts: (_) async {},
      writeTokens: (_, _) async {},
      deleteTokens: (_) async {},
      useNativeSaveDialog: true,
      saveFileCallback:
          ({required String fileName, required Uint8List bytes, String? dialogTitle}) async {
            exportedBytes = bytes;
            return 'content://downloads/document/primary%3ADownload%2Fkick-secure.json';
          },
    );

    await exportService.export(
      settings: AppSettings.defaults(apiKey: 'kick-secret'),
      accounts: [
        buildAccount(
          id: 'primary',
          label: 'Primary',
          email: 'primary@example.com',
          projectId: 'proj-primary',
          tokenRef: 'primary-ref',
        ),
      ],
      options: const ConfigurationBackupExportOptions.passwordProtected(password: 'Pa55w0rd!'),
      dialogTitle: 'Save backup',
    );

    final passwordRequests = <ConfigurationBackupPasswordRequest>[];
    final savedSettings = <AppSettings>[];
    final replacedAccounts = <List<AccountProfile>>[];
    final writtenTokens = <String, OAuthTokens>{};

    final restoreService = ConfigurationBackupService(
      readTokens: (_) async => null,
      readCurrentAccounts: () async => const [],
      readCurrentSettings: () async => AppSettings.defaults(apiKey: 'old-api-key'),
      saveSettings: (settings) async {
        savedSettings.add(settings);
      },
      replaceAccounts: (accounts) async {
        replacedAccounts.add(accounts);
      },
      writeTokens: (tokenRef, tokens) async {
        writtenTokens[tokenRef] = tokens;
      },
      deleteTokens: (_) async {},
      pickFileCallback: ({String? dialogTitle}) async {
        return ConfigurationBackupPickedFile(fileName: 'kick-secure.json', bytes: exportedBytes);
      },
    );

    final result = await restoreService.restore(
      passwordPrompt: (request) async {
        passwordRequests.add(request);
        return request.invalidPassword ? 'Pa55w0rd!' : 'wrong-password';
      },
    );

    expect(result, isNotNull);
    expect(result!.wasPasswordProtected, isTrue);
    expect(passwordRequests, hasLength(2));
    expect(passwordRequests.first.invalidPassword, isFalse);
    expect(passwordRequests.last.invalidPassword, isTrue);
    expect(savedSettings.single.apiKey, 'kick-secret');
    expect(replacedAccounts.single.map((account) => account.id), ['primary']);
    expect(writtenTokens['primary-ref']?.accessToken, 'access-1');
  });

  test('throws a typed error for unsupported backup schema versions', () async {
    final service = ConfigurationBackupService(
      readTokens: (_) async => null,
      readCurrentAccounts: () async => const [],
      readCurrentSettings: () async => AppSettings.defaults(apiKey: 'kick-secret'),
      saveSettings: (_) async {},
      replaceAccounts: (_) async {},
      writeTokens: (_, _) async {},
      deleteTokens: (_) async {},
      pickFileCallback: ({String? dialogTitle}) async {
        return ConfigurationBackupPickedFile(
          fileName: 'kick-restore.json',
          bytes: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'schema': 'kick.configuration_backup',
                'version': 99,
                'settings': AppSettings.defaults(apiKey: 'restored-api-key').toBackupJson(),
                'accounts': const [],
              }),
            ),
          ),
        );
      },
    );

    await expectLater(
      service.restore(),
      throwsA(
        isA<ConfigurationBackupException>().having(
          (error) => error.code,
          'code',
          ConfigurationBackupErrorCode.unsupportedVersion,
        ),
      ),
    );
  });

  test('throws when protected export is requested without password', () async {
    final service = ConfigurationBackupService(
      readTokens: (_) async => null,
      readCurrentAccounts: () async => const [],
      readCurrentSettings: () async => AppSettings.defaults(apiKey: 'kick-secret'),
      saveSettings: (_) async {},
      replaceAccounts: (_) async {},
      writeTokens: (_, _) async {},
      deleteTokens: (_) async {},
      useNativeSaveDialog: false,
    );

    await expectLater(
      service.export(
        settings: AppSettings.defaults(apiKey: 'kick-secret'),
        accounts: const [],
        options: const ConfigurationBackupExportOptions.passwordProtected(password: '   '),
      ),
      throwsA(
        isA<ConfigurationBackupException>().having(
          (error) => error.code,
          'code',
          ConfigurationBackupErrorCode.passwordRequired,
        ),
      ),
    );
  });

  test('rolls back accounts, tokens, and settings when restore fails mid-flight', () async {
    final previousSettings = AppSettings.defaults(
      apiKey: 'previous-key',
    ).copyWith(host: '127.0.0.1', port: 3000);
    final restoredSettings = AppSettings.defaults(
      apiKey: 'restored-key',
    ).copyWith(host: '10.0.0.5', port: 4010);
    final existingAccount = buildAccount(
      id: 'existing',
      label: 'Existing',
      email: 'existing@example.com',
      projectId: 'proj-existing',
      tokenRef: 'existing-ref',
    );
    final restoredAccount = buildAccount(
      id: 'restored',
      label: 'Restored',
      email: 'restored@example.com',
      projectId: 'proj-restored',
      tokenRef: 'restored-ref',
    );

    AppSettings persistedSettings = previousSettings;
    List<AccountProfile> persistedAccounts = [existingAccount];
    final persistedTokens = <String, OAuthTokens?>{'existing-ref': buildTokens('existing-access')};
    var replaceAttempts = 0;

    final service = ConfigurationBackupService(
      readTokens: (tokenRef) async => persistedTokens[tokenRef],
      readCurrentAccounts: () async => List<AccountProfile>.from(persistedAccounts),
      readCurrentSettings: () async => persistedSettings,
      saveSettings: (settings) async {
        persistedSettings = settings;
      },
      replaceAccounts: (accounts) async {
        replaceAttempts += 1;
        persistedAccounts = List<AccountProfile>.from(accounts);
      },
      writeTokens: (tokenRef, tokens) async {
        if (tokenRef == 'restored-ref' && replaceAttempts == 1) {
          throw StateError('secure storage write failed');
        }
        persistedTokens[tokenRef] = tokens;
      },
      deleteTokens: (tokenRef) async {
        persistedTokens.remove(tokenRef);
      },
      pickFileCallback: ({String? dialogTitle}) async {
        return ConfigurationBackupPickedFile(
          fileName: 'kick-restore.json',
          bytes: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'schema': 'kick.configuration_backup',
                'version': 1,
                'exported_at': '2026-03-29T10:00:00Z',
                'settings': restoredSettings.toBackupJson(),
                'accounts': [restoredAccount.toBackupJson(tokens: buildTokens('restored-access'))],
              }),
            ),
          ),
        );
      },
    );

    await expectLater(service.restore(), throwsA(isA<StateError>()));

    expect(persistedSettings.apiKey, previousSettings.apiKey);
    expect(persistedSettings.host, previousSettings.host);
    expect(persistedSettings.port, previousSettings.port);
    expect(persistedAccounts.map((account) => account.id), [existingAccount.id]);
    expect(persistedTokens.keys, ['existing-ref']);
    expect(persistedTokens['existing-ref']?.accessToken, 'existing-access');
    expect(persistedTokens.containsKey('restored-ref'), isFalse);
  });
}
