import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../app/app_metadata.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.hasUpdate,
    this.installerUrl,
    this.installerFileName,
    this.checksumUrl,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseUrl;
  final bool hasUpdate;
  final String? installerUrl;
  final String? installerFileName;
  final String? checksumUrl;
}

class AppUpdateChecker {
  AppUpdateChecker({
    http.Client? httpClient,
    String apiUrl = kickLatestReleaseApiUrl,
    Duration requestTimeout = const Duration(seconds: 8),
    TargetPlatform? targetPlatform,
    LinuxPackageFormat? linuxPackageFormat,
  }) : _http = httpClient ?? http.Client(),
       _apiUrl = apiUrl,
       _requestTimeout = requestTimeout > Duration.zero
           ? requestTimeout
           : const Duration(seconds: 8),
       _targetPlatform = targetPlatform ?? defaultTargetPlatform,
       _linuxPackageFormat = linuxPackageFormat;

  final http.Client _http;
  final String _apiUrl;
  final Duration _requestTimeout;
  final TargetPlatform _targetPlatform;
  final LinuxPackageFormat? _linuxPackageFormat;

  Future<AppUpdateInfo> checkForUpdates({required String currentVersion}) async {
    final normalizedCurrentVersion = normalizeVersion(currentVersion);
    final response = await _runWithTimeout(
      () => _http.get(
        Uri.parse(_apiUrl),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'KiCk/$normalizedCurrentVersion',
        },
      ),
      'Checking for updates',
    );

    if (response.statusCode >= 400) {
      throw StateError('Failed to check updates: ${response.statusCode}');
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map) {
      throw const FormatException('Unexpected release payload.');
    }

    final map = payload.cast<String, Object?>();
    final latestVersion = normalizeVersion(map['tag_name']?.toString() ?? '');
    if (latestVersion.isEmpty) {
      throw const FormatException('Release tag is missing.');
    }

    final releaseUrl = (map['html_url']?.toString().trim().isNotEmpty == true)
        ? map['html_url']!.toString().trim()
        : kickLatestReleaseUrl;
    final linuxPackageFormat = _targetPlatform == TargetPlatform.linux
        ? (_linuxPackageFormat ?? await LinuxPackageFormat.detect())
        : null;
    final installerAsset = _resolveInstallerAsset(
      releasePayload: map,
      latestVersion: latestVersion,
      targetPlatform: _targetPlatform,
      linuxPackageFormat: linuxPackageFormat,
    );
    final checksumUrl = _resolveChecksumUrl(releasePayload: map, latestVersion: latestVersion);

    return AppUpdateInfo(
      currentVersion: normalizedCurrentVersion,
      latestVersion: latestVersion,
      releaseUrl: releaseUrl,
      hasUpdate: compareVersions(latestVersion, normalizedCurrentVersion) > 0,
      installerUrl: installerAsset?.downloadUrl,
      installerFileName: installerAsset?.name,
      checksumUrl: checksumUrl,
    );
  }

  void dispose() {
    _http.close();
  }

  Future<T> _runWithTimeout<T>(Future<T> Function() operation, String label) {
    return operation().timeout(
      _requestTimeout,
      onTimeout: () => throw TimeoutException('$label timed out.'),
    );
  }

  @visibleForTesting
  static String normalizeVersion(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final withoutPrefix = trimmed.startsWith('v') ? trimmed.substring(1) : trimmed;
    return withoutPrefix.split('+').first.trim();
  }

  @visibleForTesting
  static int compareVersions(String left, String right) {
    final leftParts = _VersionParts.parse(left);
    final rightParts = _VersionParts.parse(right);

    final maxLength = leftParts.numbers.length > rightParts.numbers.length
        ? leftParts.numbers.length
        : rightParts.numbers.length;
    for (var index = 0; index < maxLength; index++) {
      final leftNumber = index < leftParts.numbers.length ? leftParts.numbers[index] : 0;
      final rightNumber = index < rightParts.numbers.length ? rightParts.numbers[index] : 0;
      if (leftNumber != rightNumber) {
        return leftNumber.compareTo(rightNumber);
      }
    }

    if (leftParts.preRelease == rightParts.preRelease) {
      return 0;
    }
    if (leftParts.preRelease == null) {
      return 1;
    }
    if (rightParts.preRelease == null) {
      return -1;
    }
    return leftParts.preRelease!.compareTo(rightParts.preRelease!);
  }

  static _ReleaseAsset? _resolveInstallerAsset({
    required Map<String, Object?> releasePayload,
    required String latestVersion,
    required TargetPlatform targetPlatform,
    LinuxPackageFormat? linuxPackageFormat,
  }) {
    final assets = releasePayload['assets'];
    if (assets is! List) {
      return null;
    }

    final expectedAssetNames = switch (targetPlatform) {
      TargetPlatform.android => ['kick-android-$latestVersion.apk'],
      TargetPlatform.windows => ['kick-windows-$latestVersion-setup.exe'],
      TargetPlatform.linux => _expectedLinuxAssetNames(
        latestVersion: latestVersion,
        packageFormat: linuxPackageFormat,
      ),
      TargetPlatform.fuchsia || TargetPlatform.iOS || TargetPlatform.macOS => const <String>[],
    };
    if (expectedAssetNames.isEmpty) {
      return null;
    }

    for (final assetName in expectedAssetNames) {
      final asset = _findReleaseAsset(assets: assets, expectedAssetName: assetName);
      if (asset != null) {
        return asset;
      }
    }
    return null;
  }

  static List<String> _expectedLinuxAssetNames({
    required String latestVersion,
    required LinuxPackageFormat? packageFormat,
  }) {
    final packageNames = switch (packageFormat) {
      LinuxPackageFormat.deb => ['kick-linux-x64-$latestVersion.deb'],
      LinuxPackageFormat.rpm => ['kick-linux-x64-$latestVersion.rpm'],
      LinuxPackageFormat.pacman => const <String>[],
      null => const <String>[],
    };
    return [...packageNames, 'kick-linux-x64-$latestVersion.AppImage'];
  }

  static _ReleaseAsset? _findReleaseAsset({
    required List<Object?> assets,
    required String expectedAssetName,
  }) {
    for (final asset in assets) {
      if (asset is! Map) {
        continue;
      }

      final assetMap = asset.cast<Object?, Object?>();
      final name = assetMap['name']?.toString().trim();
      final downloadUrl = assetMap['browser_download_url']?.toString().trim();
      if (name == expectedAssetName && downloadUrl?.isNotEmpty == true) {
        return _ReleaseAsset(name: name!, downloadUrl: downloadUrl!);
      }
    }

    return null;
  }

  static String? _resolveChecksumUrl({
    required Map<String, Object?> releasePayload,
    required String latestVersion,
  }) {
    final assets = releasePayload['assets'];
    if (assets is! List) {
      return null;
    }

    final expectedAssetName = 'kick-$latestVersion-checksums.txt';
    for (final asset in assets) {
      if (asset is! Map) {
        continue;
      }

      final assetMap = asset.cast<Object?, Object?>();
      final name = assetMap['name']?.toString().trim();
      final downloadUrl = assetMap['browser_download_url']?.toString().trim();
      if (name == expectedAssetName && downloadUrl?.isNotEmpty == true) {
        return downloadUrl;
      }
    }

    return null;
  }
}

enum LinuxPackageFormat {
  deb,
  rpm,
  pacman;

  static Future<LinuxPackageFormat?> detect({String osReleasePath = '/etc/os-release'}) async {
    if (!Platform.isLinux) {
      return null;
    }

    try {
      final file = File(osReleasePath);
      if (!await file.exists()) {
        return null;
      }
      return fromOsRelease(await file.readAsString());
    } on FileSystemException {
      return null;
    }
  }

  static LinuxPackageFormat? fromOsRelease(String contents) {
    final fields = <String, String>{};
    for (final rawLine in contents.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      final separatorIndex = line.indexOf('=');
      if (separatorIndex <= 0) {
        continue;
      }
      final key = line.substring(0, separatorIndex).trim().toUpperCase();
      var value = line.substring(separatorIndex + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      fields[key] = value.toLowerCase();
    }

    final ids = <String>{
      for (final key in const ['ID', 'ID_LIKE'])
        ...?fields[key]?.split(RegExp(r'\s+')).where((item) => item.trim().isNotEmpty),
    };
    if (ids.any(_isDebianLike)) {
      return LinuxPackageFormat.deb;
    }
    if (ids.any(_isRpmLike)) {
      return LinuxPackageFormat.rpm;
    }
    if (ids.any(_isPacmanLike)) {
      return LinuxPackageFormat.pacman;
    }
    return null;
  }

  static bool _isDebianLike(String id) =>
      id == 'debian' || id == 'ubuntu' || id == 'linuxmint' || id == 'pop';

  static bool _isRpmLike(String id) =>
      id == 'fedora' ||
      id == 'rhel' ||
      id == 'centos' ||
      id == 'rocky' ||
      id == 'almalinux' ||
      id == 'suse' ||
      id == 'opensuse';

  static bool _isPacmanLike(String id) =>
      id == 'arch' || id == 'manjaro' || id == 'endeavouros' || id == 'cachyos';
}

class _ReleaseAsset {
  const _ReleaseAsset({required this.name, required this.downloadUrl});

  final String name;
  final String downloadUrl;
}

class _VersionParts {
  const _VersionParts({required this.numbers, required this.preRelease});

  final List<int> numbers;
  final String? preRelease;

  static _VersionParts parse(String raw) {
    final normalized = AppUpdateChecker.normalizeVersion(raw);
    final separatorIndex = normalized.indexOf('-');
    final numberPart = separatorIndex == -1 ? normalized : normalized.substring(0, separatorIndex);
    final preRelease = separatorIndex == -1
        ? null
        : normalized.substring(separatorIndex + 1).trim();

    final numbers = numberPart
        .split('.')
        .map((item) => int.tryParse(item.trim()) ?? 0)
        .toList(growable: false);

    return _VersionParts(
      numbers: numbers,
      preRelease: preRelease == null || preRelease.isEmpty ? null : preRelease,
    );
  }
}
