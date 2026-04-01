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
    expect(reloaded.clientId, 'client-id');
    expect(reloaded.clientSecret, 'client-secret');
    expect(reloaded.startUrl, defaultKiroBuilderIdStartUrl);
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
}
