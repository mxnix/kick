import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kick/proxy/kiro/kiro_auth_source.dart';

void main() {
  test('loads builder id metadata from persisted source file', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick_kiro_auth_source');
    addTearDown(() => tempDirectory.delete(recursive: true));
    final sourceFile = File('${tempDirectory.path}${Platform.pathSeparator}builder-id.json');
    await sourceFile.writeAsString(
      jsonEncode({
        'accessToken': 'access-token',
        'refreshToken': 'refresh-token',
        'expiresAt': '2026-04-01T12:00:00Z',
        'authMethod': 'builder-id',
        'clientId': 'client-id',
        'clientSecret': 'client-secret',
        'idcRegion': 'us-east-1',
        'startUrl': 'https://view.awsapps.com/start',
      }),
    );

    final snapshot = await loadKiroAuthSource(sourcePath: sourceFile.path);

    expect(snapshot, isNotNull);
    expect(snapshot!.sourceType, builderIdKiroCredentialSourceType);
    expect(snapshot.authMethod, builderIdKiroAuthMethod);
    expect(snapshot.clientId, 'client-id');
    expect(snapshot.clientSecret, 'client-secret');
    expect(snapshot.profileArn, defaultKiroBuilderIdProfileArn);
    expect(snapshot.startUrl, 'https://view.awsapps.com/start');
    expect(snapshot.effectiveRegion, 'us-east-1');
    expect(snapshot.displayIdentity, 'AWS Builder ID');
  });

  test('persists managed builder id snapshot and reloads it', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick_kiro_auth_store');
    addTearDown(() => tempDirectory.delete(recursive: true));

    final saved = await persistKiroAuthSourceSnapshot(
      KiroAuthSourceSnapshot(
        sourcePath: '',
        sourceType: builderIdKiroCredentialSourceType,
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiry: DateTime.parse('2026-04-01T12:00:00Z'),
        region: 'us-east-1',
        profileArn: null,
        authMethod: builderIdKiroAuthMethod,
        provider: 'kiro',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        startUrl: defaultKiroBuilderIdStartUrl,
      ),
      supportDirectoryProvider: () async => tempDirectory,
    );

    expect(File(saved.sourcePath).existsSync(), isTrue);

    final reloaded = await loadKiroAuthSource(sourcePath: saved.sourcePath);
    expect(reloaded, isNotNull);
    expect(reloaded!.sourceType, builderIdKiroCredentialSourceType);
    expect(reloaded.accessToken, 'access-token');
    expect(reloaded.refreshToken, 'refresh-token');
    expect(reloaded.profileArn, defaultKiroBuilderIdProfileArn);
    expect(reloaded.clientId, 'client-id');
    expect(reloaded.clientSecret, 'client-secret');
    expect(reloaded.startUrl, defaultKiroBuilderIdStartUrl);
  });

  test('persists social Kiro snapshot as an independent managed source', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick_kiro_auth_social_store');
    addTearDown(() => tempDirectory.delete(recursive: true));

    final saved = await persistKiroAuthSourceSnapshot(
      KiroAuthSourceSnapshot(
        sourcePath: r'C:\Users\demo\.aws\sso\cache\kiro-auth-token.json',
        sourceType: defaultKiroCredentialSourceType,
        accessToken: 'social-access-token',
        refreshToken: 'social-refresh-token',
        expiry: DateTime.parse('2026-04-01T12:00:00Z'),
        region: 'us-east-1',
        profileArn: defaultKiroSocialProfileArn,
        authMethod: socialKiroAuthMethod,
        provider: 'Github',
      ),
      supportDirectoryProvider: () async => tempDirectory,
    );

    expect(File(saved.sourcePath).existsSync(), isTrue);
    expect(saved.sourcePath, isNot(r'C:\Users\demo\.aws\sso\cache\kiro-auth-token.json'));
    expect(saved.sourceType, manualKiroCredentialSourceType);
    expect(
      await isManagedKiroCredentialSourcePath(
        saved.sourcePath,
        supportDirectoryProvider: () async => tempDirectory,
      ),
      isTrue,
    );

    final reloaded = await loadKiroAuthSource(sourcePath: saved.sourcePath);
    expect(reloaded, isNotNull);
    expect(reloaded!.sourceType, manualKiroCredentialSourceType);
    expect(reloaded.authMethod, socialKiroAuthMethod);
    expect(reloaded.provider, 'Github');
    expect(reloaded.accessToken, 'social-access-token');
    expect(reloaded.refreshToken, 'social-refresh-token');
  });

  test('returns null for malformed Kiro source JSON', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick_kiro_auth_malformed');
    addTearDown(() => tempDirectory.delete(recursive: true));
    final sourceFile = File('${tempDirectory.path}${Platform.pathSeparator}broken.json');
    await sourceFile.writeAsString('{');

    final snapshot = await loadKiroAuthSource(sourcePath: sourceFile.path);

    expect(snapshot, isNull);
  });

  test('detects and deletes app-managed Kiro sources', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick_kiro_auth_managed');
    addTearDown(() => tempDirectory.delete(recursive: true));

    final saved = await persistKiroAuthSourceSnapshot(
      KiroAuthSourceSnapshot(
        sourcePath: '',
        sourceType: builderIdKiroCredentialSourceType,
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiry: DateTime.parse('2026-04-01T12:00:00Z'),
        region: 'us-east-1',
        profileArn: null,
        authMethod: builderIdKiroAuthMethod,
        provider: 'kiro',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        startUrl: defaultKiroBuilderIdStartUrl,
      ),
      supportDirectoryProvider: () async => tempDirectory,
    );

    expect(
      await isManagedKiroCredentialSourcePath(
        saved.sourcePath,
        supportDirectoryProvider: () async => tempDirectory,
      ),
      isTrue,
    );
    expect(
      await deleteManagedKiroCredentialSource(
        saved.sourcePath,
        supportDirectoryProvider: () async => tempDirectory,
      ),
      isTrue,
    );
    expect(File(saved.sourcePath).existsSync(), isFalse);
  });

  test('does not treat external Kiro sources as app-managed', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick_kiro_auth_external');
    addTearDown(() => tempDirectory.delete(recursive: true));
    final externalFile = File('${tempDirectory.path}${Platform.pathSeparator}builder-id.json');
    await externalFile.writeAsString('{}');

    expect(
      await isManagedKiroCredentialSourcePath(
        externalFile.path,
        supportDirectoryProvider: () async => tempDirectory,
      ),
      isFalse,
    );
    expect(
      await deleteManagedKiroCredentialSource(
        externalFile.path,
        supportDirectoryProvider: () async => tempDirectory,
      ),
      isFalse,
    );
    expect(externalFile.existsSync(), isTrue);
  });

  test('migrates away from the legacy Builder ID placeholder profile ARN', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick_kiro_auth_legacy');
    addTearDown(() => tempDirectory.delete(recursive: true));
    final sourceFile = File('${tempDirectory.path}${Platform.pathSeparator}legacy.json');
    await sourceFile.writeAsString(
      jsonEncode({
        'accessToken': 'access-token',
        'refreshToken': 'refresh-token',
        'expiresAt': '2026-04-01T12:00:00Z',
        'authMethod': 'builder-id',
        'clientId': 'client-id',
        'clientSecret': 'client-secret',
        'idcRegion': 'us-east-1',
        'profileArn': 'arn:aws:codewhisperer:us-east-1:638616132270:profile/AAAACCCCXXXX',
      }),
    );

    final snapshot = await loadKiroAuthSource(sourcePath: sourceFile.path);

    expect(snapshot, isNotNull);
    expect(snapshot!.profileArn, defaultKiroBuilderIdProfileArn);
    expect(isLegacyPlaceholderKiroProfileArn(snapshot.profileArn), isFalse);
  });

  test('resolveKiroProfileArn replaces placeholder and preserves real ARNs', () {
    expect(
      resolveKiroProfileArn('arn:aws:codewhisperer:us-east-1:638616132270:profile/AAAACCCCXXXX'),
      defaultKiroBuilderIdProfileArn,
    );
    expect(
      resolveKiroProfileArn(
        'arn:aws:codewhisperer:us-east-1:638616132270:profile/AAAACCCCXXXX',
        fallback: 'arn:aws:codewhisperer:us-east-1:123456789012:profile/ABC',
      ),
      'arn:aws:codewhisperer:us-east-1:123456789012:profile/ABC',
    );
    expect(
      resolveKiroProfileArn('arn:aws:codewhisperer:us-east-1:123456789012:profile/ABC'),
      'arn:aws:codewhisperer:us-east-1:123456789012:profile/ABC',
    );
    expect(
      resolveKiroProfileArn(null, fallback: defaultKiroBuilderIdProfileArn),
      defaultKiroBuilderIdProfileArn,
    );
    expect(resolveKiroProfileArn(null), isNull);
  });

  test('recognizes the default Kiro credential source path', () {
    final defaultPath = resolveKiroCredentialSourcePath(null);

    expect(defaultPath, isNotNull);
    expect(isDefaultKiroCredentialSourcePath(defaultPath), isTrue);
    expect(isDefaultKiroCredentialSourcePath('${defaultPath!}.backup'), isFalse);
  });

  test('uses configured builder id source when no default social source exists', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick_kiro_effective_builder');
    addTearDown(() => tempDirectory.delete(recursive: true));
    final sourceFile = File('${tempDirectory.path}${Platform.pathSeparator}builder.json');
    await sourceFile.writeAsString(
      jsonEncode({
        'accessToken': 'access-token',
        'refreshToken': 'refresh-token',
        'expiresAt': '2026-04-01T12:00:00Z',
        'authMethod': 'builder-id',
        'clientId': 'client-id',
        'clientSecret': 'client-secret',
        'idcRegion': 'us-east-1',
      }),
    );

    final snapshot = await loadEffectiveKiroAuthSource(
      sourcePath: sourceFile.path,
      defaultSourcePath: '${tempDirectory.path}${Platform.pathSeparator}missing.json',
    );

    expect(snapshot, isNotNull);
    expect(snapshot!.sourcePath, sourceFile.path);
    expect(snapshot.authMethod, builderIdKiroAuthMethod);
  });

  test('keeps configured builder id source instead of borrowing default social source', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick_kiro_effective_isolated');
    addTearDown(() => tempDirectory.delete(recursive: true));
    final builderFile = File('${tempDirectory.path}${Platform.pathSeparator}builder.json');
    final socialFile = File('${tempDirectory.path}${Platform.pathSeparator}kiro-auth-token.json');
    await builderFile.writeAsString(
      jsonEncode({
        'accessToken': 'builder-access',
        'refreshToken': 'builder-refresh',
        'expiresAt': '2026-04-01T12:00:00Z',
        'authMethod': 'builder-id',
        'clientId': 'client-id',
        'clientSecret': 'client-secret',
        'idcRegion': 'us-east-1',
      }),
    );
    await socialFile.writeAsString(
      jsonEncode({
        'accessToken': 'social-access',
        'refreshToken': 'social-refresh',
        'expiresAt': '2026-04-01T12:00:00Z',
        'authMethod': 'social',
        'provider': 'Github',
        'profileArn': defaultKiroSocialProfileArn,
      }),
    );

    final snapshot = await loadEffectiveKiroAuthSource(
      sourcePath: builderFile.path,
      defaultSourcePath: socialFile.path,
    );

    expect(snapshot, isNotNull);
    expect(snapshot!.sourcePath, builderFile.path);
    expect(snapshot.authMethod, builderIdKiroAuthMethod);
    expect(snapshot.accessToken, 'builder-access');
  });
}
