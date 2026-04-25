import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kick/features/settings/app_update_checker.dart';
import 'package:kick/features/settings/app_update_installer.dart';

void main() {
  test('downloads the installer and verifies the SHA-256 checksum', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick_app_update_test_');
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    final installerBytes = utf8.encode('kick installer payload');
    final installerHash = sha256.convert(installerBytes).toString();
    final installer = AppUpdateInstaller(
      httpClient: QueueHttpClient([
        (_) async => http.Response('$installerHash *kick-windows-1.1.0-setup.exe\n', 200),
        (_) async => http.StreamedResponse(Stream.value(installerBytes), 200),
      ]),
      directoryProvider: () async => tempDirectory,
    );
    addTearDown(installer.dispose);

    final downloadedUpdate = await installer.downloadUpdate(
      updateInfo: const AppUpdateInfo(
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        releaseUrl: 'https://example.com/releases/tag/v1.1.0',
        hasUpdate: true,
        installerUrl: 'https://example.com/releases/download/v1.1.0/kick-windows-1.1.0-setup.exe',
        installerFileName: 'kick-windows-1.1.0-setup.exe',
        checksumUrl: 'https://example.com/releases/download/v1.1.0/kick-1.1.0-checksums.txt',
      ),
      onProgress: (_, _) {},
    );

    expect(downloadedUpdate.fileName, 'kick-windows-1.1.0-setup.exe');
    expect(downloadedUpdate.isChecksumVerified, isTrue);
    expect(downloadedUpdate.sha256, installerHash);
    expect(await File(downloadedUpdate.filePath).readAsBytes(), installerBytes);
  });

  test('fails when the published checksum does not match the downloaded installer', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick_app_update_test_');
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    final installer = AppUpdateInstaller(
      httpClient: QueueHttpClient([
        (_) async => http.Response('${'0' * 64} *kick-windows-1.1.0-setup.exe\n', 200),
        (_) async =>
            http.StreamedResponse(Stream.value(utf8.encode('kick installer payload')), 200),
      ]),
      directoryProvider: () async => tempDirectory,
    );
    addTearDown(installer.dispose);

    await expectLater(
      installer.downloadUpdate(
        updateInfo: const AppUpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '1.1.0',
          releaseUrl: 'https://example.com/releases/tag/v1.1.0',
          hasUpdate: true,
          installerUrl: 'https://example.com/releases/download/v1.1.0/kick-windows-1.1.0-setup.exe',
          installerFileName: 'kick-windows-1.1.0-setup.exe',
          checksumUrl: 'https://example.com/releases/download/v1.1.0/kick-1.1.0-checksums.txt',
        ),
        onProgress: (_, _) {},
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('opens a verified Linux package without invoking a package manager', () async {
    final openedPaths = <String>[];
    final installer = AppUpdateInstaller(
      installPlatform: AppUpdateInstallPlatform.linux,
      linuxPackageOpener: (filePath) async {
        openedPaths.add(filePath);
      },
    );
    addTearDown(installer.dispose);

    final result = await installer.launchInstall(
      const DownloadedAppUpdate(
        version: '1.1.0',
        filePath: '/tmp/kick-linux-x64-1.1.0.deb',
        fileName: 'kick-linux-x64-1.1.0.deb',
        sha256: 'abc',
        isChecksumVerified: true,
      ),
    );

    expect(result, AppUpdateInstallLaunchResult.launched);
    expect(openedPaths, ['/tmp/kick-linux-x64-1.1.0.deb']);
  });
}

class QueueHttpClient extends http.BaseClient {
  QueueHttpClient(this._handlers);

  final List<Future<http.BaseResponse> Function(http.BaseRequest request)> _handlers;
  var _index = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_index >= _handlers.length) {
      throw StateError('No queued HTTP response for ${request.method} ${request.url}.');
    }

    final response = await _handlers[_index++](request);
    if (response is http.StreamedResponse) {
      return response;
    }
    if (response is http.Response) {
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
        reasonPhrase: response.reasonPhrase,
      );
    }
    throw StateError('Unsupported HTTP response type: ${response.runtimeType}.');
  }
}
