import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kick/features/settings/app_update_checker.dart';

void main() {
  test('normalizes GitHub tags into app version format', () {
    expect(AppUpdateChecker.normalizeVersion('v0.2.1'), '0.2.1');
    expect(AppUpdateChecker.normalizeVersion('0.2.1+9'), '0.2.1');
  });

  test('compares semantic versions numerically', () {
    expect(AppUpdateChecker.compareVersions('0.2.0', '0.1.9'), greaterThan(0));
    expect(AppUpdateChecker.compareVersions('1.0.0', '1.0.0'), 0);
    expect(AppUpdateChecker.compareVersions('1.0.0-beta.1', '1.0.0'), lessThan(0));
  });

  test('detects available update from GitHub release payload', () async {
    final checker = AppUpdateChecker(
      apiUrl: 'https://example.com/releases/latest',
      targetPlatform: TargetPlatform.windows,
      httpClient: QueueHttpClient([
        (request) async {
          expect(request.url.toString(), 'https://example.com/releases/latest');
          return http.Response(
            jsonEncode({
              'tag_name': 'v0.2.0',
              'html_url': 'https://github.com/mxnix/kick/releases/tag/v0.2.0',
              'assets': [
                {
                  'name': 'kick-windows-0.2.0-setup.exe',
                  'browser_download_url':
                      'https://github.com/mxnix/kick/releases/download/v0.2.0/kick-windows-0.2.0-setup.exe',
                },
                {
                  'name': 'kick-0.2.0-checksums.txt',
                  'browser_download_url':
                      'https://github.com/mxnix/kick/releases/download/v0.2.0/kick-0.2.0-checksums.txt',
                },
                {
                  'name': 'kick-windows-0.2.0-portable.zip',
                  'browser_download_url':
                      'https://github.com/mxnix/kick/releases/download/v0.2.0/kick-windows-0.2.0-portable.zip',
                },
              ],
            }),
            200,
          );
        },
      ]),
    );

    final result = await checker.checkForUpdates(currentVersion: '0.1.0');

    expect(result.currentVersion, '0.1.0');
    expect(result.latestVersion, '0.2.0');
    expect(result.hasUpdate, isTrue);
    expect(result.releaseUrl, 'https://github.com/mxnix/kick/releases/tag/v0.2.0');
    expect(
      result.installerUrl,
      'https://github.com/mxnix/kick/releases/download/v0.2.0/kick-windows-0.2.0-setup.exe',
    );
    expect(result.installerFileName, 'kick-windows-0.2.0-setup.exe');
    expect(
      result.checksumUrl,
      'https://github.com/mxnix/kick/releases/download/v0.2.0/kick-0.2.0-checksums.txt',
    );
  });

  test('selects distro-native Linux package with AppImage fallback assets', () async {
    final checker = AppUpdateChecker(
      apiUrl: 'https://example.com/releases/latest',
      targetPlatform: TargetPlatform.linux,
      linuxPackageFormat: LinuxPackageFormat.rpm,
      httpClient: QueueHttpClient([
        (_) async => http.Response(
          jsonEncode({
            'tag_name': 'v1.4.0',
            'html_url': 'https://github.com/mxnix/kick/releases/tag/v1.4.0',
            'assets': [
              {
                'name': 'kick-linux-x64-1.4.0.deb',
                'browser_download_url':
                    'https://github.com/mxnix/kick/releases/download/v1.4.0/kick-linux-x64-1.4.0.deb',
              },
              {
                'name': 'kick-linux-x64-1.4.0.rpm',
                'browser_download_url':
                    'https://github.com/mxnix/kick/releases/download/v1.4.0/kick-linux-x64-1.4.0.rpm',
              },
              {
                'name': 'kick-linux-x64-1.4.0.AppImage',
                'browser_download_url':
                    'https://github.com/mxnix/kick/releases/download/v1.4.0/kick-linux-x64-1.4.0.AppImage',
              },
              {
                'name': 'kick-1.4.0-checksums.txt',
                'browser_download_url':
                    'https://github.com/mxnix/kick/releases/download/v1.4.0/kick-1.4.0-checksums.txt',
              },
            ],
          }),
          200,
        ),
      ]),
    );

    final result = await checker.checkForUpdates(currentVersion: '1.3.5');

    expect(result.hasUpdate, isTrue);
    expect(result.installerFileName, 'kick-linux-x64-1.4.0.rpm');
    expect(
      result.installerUrl,
      'https://github.com/mxnix/kick/releases/download/v1.4.0/kick-linux-x64-1.4.0.rpm',
    );
  });

  test('falls back to Linux AppImage when distro package is unavailable', () async {
    final checker = AppUpdateChecker(
      apiUrl: 'https://example.com/releases/latest',
      targetPlatform: TargetPlatform.linux,
      linuxPackageFormat: LinuxPackageFormat.pacman,
      httpClient: QueueHttpClient([
        (_) async => http.Response(
          jsonEncode({
            'tag_name': 'v1.4.0',
            'assets': [
              {
                'name': 'kick-linux-x64-1.4.0.AppImage',
                'browser_download_url':
                    'https://github.com/mxnix/kick/releases/download/v1.4.0/kick-linux-x64-1.4.0.AppImage',
              },
            ],
          }),
          200,
        ),
      ]),
    );

    final result = await checker.checkForUpdates(currentVersion: '1.3.5');

    expect(result.installerFileName, 'kick-linux-x64-1.4.0.AppImage');
  });

  test('uses AppImage for pacman systems instead of opening a package archive', () async {
    final checker = AppUpdateChecker(
      apiUrl: 'https://example.com/releases/latest',
      targetPlatform: TargetPlatform.linux,
      linuxPackageFormat: LinuxPackageFormat.pacman,
      httpClient: QueueHttpClient([
        (_) async => http.Response(
          jsonEncode({
            'tag_name': 'v1.4.0',
            'assets': [
              {
                'name': 'kick-linux-x64-1.4.0.pkg.tar.zst',
                'browser_download_url':
                    'https://github.com/mxnix/kick/releases/download/v1.4.0/kick-linux-x64-1.4.0.pkg.tar.zst',
              },
              {
                'name': 'kick-linux-x64-1.4.0.AppImage',
                'browser_download_url':
                    'https://github.com/mxnix/kick/releases/download/v1.4.0/kick-linux-x64-1.4.0.AppImage',
              },
            ],
          }),
          200,
        ),
      ]),
    );

    final result = await checker.checkForUpdates(currentVersion: '1.3.5');

    expect(result.installerFileName, 'kick-linux-x64-1.4.0.AppImage');
  });

  test('does not treat Linux tarball as a native installer', () async {
    final checker = AppUpdateChecker(
      apiUrl: 'https://example.com/releases/latest',
      targetPlatform: TargetPlatform.linux,
      httpClient: QueueHttpClient([
        (_) async => http.Response(
          jsonEncode({
            'tag_name': 'v1.4.0',
            'assets': [
              {
                'name': 'kick-linux-x64-1.4.0.tar.gz',
                'browser_download_url':
                    'https://github.com/mxnix/kick/releases/download/v1.4.0/kick-linux-x64-1.4.0.tar.gz',
              },
            ],
          }),
          200,
        ),
      ]),
    );

    final result = await checker.checkForUpdates(currentVersion: '1.3.5');

    expect(result.installerUrl, isNull);
    expect(result.installerFileName, isNull);
  });

  test('detects Linux package family from os-release contents', () {
    expect(LinuxPackageFormat.fromOsRelease('ID=ubuntu\nID_LIKE=debian\n'), LinuxPackageFormat.deb);
    expect(
      LinuxPackageFormat.fromOsRelease('ID=fedora\nID_LIKE="rhel fedora"\n'),
      LinuxPackageFormat.rpm,
    );
    expect(
      LinuxPackageFormat.fromOsRelease('ID=manjaro\nID_LIKE=arch\n'),
      LinuxPackageFormat.pacman,
    );
  });

  test('reports no update when installed version is current', () async {
    final checker = AppUpdateChecker(
      apiUrl: 'https://example.com/releases/latest',
      httpClient: QueueHttpClient([
        (_) async => http.Response(
          jsonEncode({
            'tag_name': 'v0.2.0',
            'html_url': 'https://github.com/mxnix/kick/releases/tag/v0.2.0',
          }),
          200,
        ),
      ]),
    );

    final result = await checker.checkForUpdates(currentVersion: '0.2.0');

    expect(result.hasUpdate, isFalse);
  });

  test('times out when the update endpoint stalls', () async {
    final checker = AppUpdateChecker(
      apiUrl: 'https://example.com/releases/latest',
      requestTimeout: const Duration(milliseconds: 10),
      httpClient: QueueHttpClient([
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return http.Response('{}', 200);
        },
      ]),
    );

    await expectLater(
      checker.checkForUpdates(currentVersion: '0.2.0'),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'message',
          'Checking for updates timed out.',
        ),
      ),
    );
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
