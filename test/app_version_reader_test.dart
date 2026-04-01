import 'package:flutter_test/flutter_test.dart';
import 'package:kick/app/app_version_reader.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test('reads version from package metadata when available', () async {
    const reader = AppVersionReader(
      packageInfoLoader: _packageInfo_1_0_1,
      buildVersionFallback: '1.0.0',
      defaultVersion: '0.1.0',
    );

    expect(await reader.readVersion(), '1.0.1');
  });

  test('falls back to build version when package metadata is empty', () async {
    const reader = AppVersionReader(
      packageInfoLoader: _packageInfoEmpty,
      buildVersionFallback: '1.0.1',
      defaultVersion: '0.1.0',
    );

    expect(await reader.readVersion(), '1.0.1');
  });

  test('falls back to default version when runtime lookups fail', () async {
    const reader = AppVersionReader(
      packageInfoLoader: _throwingPackageInfo,
      buildVersionFallback: '   ',
      defaultVersion: '0.1.0',
    );

    expect(await reader.readVersion(), '0.1.0');
  });
}

Future<PackageInfo> _packageInfo_1_0_1() async => PackageInfo(
  appName: 'KiCk',
  packageName: 'com.example.kick',
  version: '1.0.1',
  buildNumber: '1',
);

Future<PackageInfo> _packageInfoEmpty() async =>
    PackageInfo(appName: 'KiCk', packageName: 'com.example.kick', version: '', buildNumber: '1');

Future<PackageInfo> _throwingPackageInfo() async {
  throw StateError('Package metadata is unavailable.');
}
