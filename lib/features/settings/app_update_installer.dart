import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/platform/desktop_runtime.dart';
import 'app_update_checker.dart';

const _appUpdateChannelName = 'kick/app_update';
const defaultAppUpdateDownloadTimeout = Duration(minutes: 10);
const defaultAppUpdateDownloadIdleTimeout = Duration(seconds: 30);
const defaultAppUpdateMaxDownloadBytes = 512 * 1024 * 1024;

enum AppUpdatePhase { idle, downloading, verifying, readyToInstall, awaitingPermission, error }

class AppUpdateFlowState {
  const AppUpdateFlowState({
    this.version,
    this.phase = AppUpdatePhase.idle,
    this.progress,
    this.downloadedUpdate,
    this.errorMessage,
  });

  final String? version;
  final AppUpdatePhase phase;
  final double? progress;
  final DownloadedAppUpdate? downloadedUpdate;
  final String? errorMessage;

  bool matches(AppUpdateInfo updateInfo) => version == updateInfo.latestVersion;

  AppUpdateFlowState copyWith({
    String? version,
    AppUpdatePhase? phase,
    Object? progress = _flowFieldUnset,
    Object? downloadedUpdate = _flowFieldUnset,
    Object? errorMessage = _flowFieldUnset,
  }) {
    return AppUpdateFlowState(
      version: version ?? this.version,
      phase: phase ?? this.phase,
      progress: identical(progress, _flowFieldUnset) ? this.progress : progress as double?,
      downloadedUpdate: identical(downloadedUpdate, _flowFieldUnset)
          ? this.downloadedUpdate
          : downloadedUpdate as DownloadedAppUpdate?,
      errorMessage: identical(errorMessage, _flowFieldUnset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  static const idle = AppUpdateFlowState();
}

const _flowFieldUnset = Object();

class DownloadedAppUpdate {
  const DownloadedAppUpdate({
    required this.version,
    required this.filePath,
    required this.fileName,
    required this.sha256,
    required this.isChecksumVerified,
  });

  final String version;
  final String filePath;
  final String fileName;
  final String sha256;
  final bool isChecksumVerified;
}

enum AppUpdateInstallLaunchResult { launched, permissionRequired }

enum AppUpdateInstallPlatform {
  android,
  windows,
  linux,
  unsupported;

  static AppUpdateInstallPlatform current() {
    if (Platform.isAndroid) {
      return AppUpdateInstallPlatform.android;
    }
    if (Platform.isWindows) {
      return AppUpdateInstallPlatform.windows;
    }
    if (Platform.isLinux) {
      return AppUpdateInstallPlatform.linux;
    }
    return AppUpdateInstallPlatform.unsupported;
  }
}

typedef AppUpdateDirectoryProvider = Future<Directory> Function();
typedef AppUpdateWindowsInstallerLauncher = Future<void> Function();
typedef AppUpdateLinuxPackageOpener = Future<void> Function(String filePath);

final appUpdateInstallerProvider = Provider<AppUpdateInstaller>((ref) {
  final installer = AppUpdateInstaller();
  ref.onDispose(installer.dispose);
  return installer;
});

final appUpdateControllerProvider = NotifierProvider<AppUpdateController, AppUpdateFlowState>(
  AppUpdateController.new,
);

class AppUpdateInstaller {
  AppUpdateInstaller({
    http.Client? httpClient,
    MethodChannel? platformChannel,
    AppUpdateDirectoryProvider? directoryProvider,
    AppUpdateWindowsInstallerLauncher? windowsInstallerLauncher,
    AppUpdateLinuxPackageOpener? linuxPackageOpener,
    AppUpdateInstallPlatform? installPlatform,
    Duration downloadTimeout = defaultAppUpdateDownloadTimeout,
    Duration downloadIdleTimeout = defaultAppUpdateDownloadIdleTimeout,
    int maxDownloadBytes = defaultAppUpdateMaxDownloadBytes,
  }) : _http = httpClient ?? http.Client(),
       _platformChannel = platformChannel ?? const MethodChannel(_appUpdateChannelName),
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _windowsInstallerLauncher = windowsInstallerLauncher ?? DesktopRuntime.exitApplication,
       _linuxPackageOpener = linuxPackageOpener ?? _openLinuxPackage,
       _installPlatform = installPlatform ?? AppUpdateInstallPlatform.current(),
       _downloadTimeout = downloadTimeout > Duration.zero
           ? downloadTimeout
           : defaultAppUpdateDownloadTimeout,
       _downloadIdleTimeout = downloadIdleTimeout > Duration.zero
           ? downloadIdleTimeout
           : defaultAppUpdateDownloadIdleTimeout,
       _maxDownloadBytes = maxDownloadBytes > 0
           ? maxDownloadBytes
           : defaultAppUpdateMaxDownloadBytes;

  final http.Client _http;
  final MethodChannel _platformChannel;
  final AppUpdateDirectoryProvider _directoryProvider;
  final AppUpdateWindowsInstallerLauncher _windowsInstallerLauncher;
  final AppUpdateLinuxPackageOpener _linuxPackageOpener;
  final AppUpdateInstallPlatform _installPlatform;
  final Duration _downloadTimeout;
  final Duration _downloadIdleTimeout;
  final int _maxDownloadBytes;

  Future<DownloadedAppUpdate> downloadUpdate({
    required AppUpdateInfo updateInfo,
    required void Function(int receivedBytes, int? totalBytes) onProgress,
    VoidCallback? onVerifying,
  }) async {
    final installerUrl = updateInfo.installerUrl?.trim();
    final installerFileName = updateInfo.installerFileName?.trim();
    if (installerUrl == null ||
        installerUrl.isEmpty ||
        installerFileName == null ||
        installerFileName.isEmpty) {
      throw StateError('This release does not provide a native installer package.');
    }

    final safeVersion = _safePathSegment(updateInfo.latestVersion, 'latestVersion');
    final safeInstallerFileName = _safeInstallerFileName(installerFileName);
    final updatesDirectory = await _resolveUpdatesDirectory(safeVersion);
    final targetFile = _safeFileInDirectory(updatesDirectory, safeInstallerFileName);
    final tempFile = File('${targetFile.path}.part');
    final expectedSha256 = await _loadExpectedSha256(
      updateInfo,
      installerFileName: safeInstallerFileName,
    );

    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    if (await targetFile.exists()) {
      final existingSha256 = await _digestFile(targetFile);
      if (expectedSha256 == null || _hashesEqual(existingSha256, expectedSha256)) {
        return DownloadedAppUpdate(
          version: safeVersion,
          filePath: targetFile.path,
          fileName: safeInstallerFileName,
          sha256: existingSha256,
          isChecksumVerified: expectedSha256 != null,
        );
      }
      await targetFile.delete();
    }

    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(installerUrl));
      final response = await _http
          .send(request)
          .timeout(
            _downloadTimeout,
            onTimeout: () => throw TimeoutException('Update download timed out.'),
          );
      if (response.statusCode >= 400) {
        throw StateError('Failed to download the update package: ${response.statusCode}.');
      }
      final contentLength = response.contentLength;
      if (contentLength != null && contentLength > _maxDownloadBytes) {
        throw StateError('Update package is larger than the allowed download limit.');
      }

      sink = tempFile.openWrite();
      var receivedBytes = 0;
      final downloadTimer = Stopwatch()..start();
      final guardedStream = response.stream.timeout(
        _downloadIdleTimeout,
        onTimeout: (controller) {
          controller.addError(TimeoutException('Update download stalled.'));
          controller.close();
        },
      );
      await for (final chunk in guardedStream) {
        receivedBytes += chunk.length;
        if (receivedBytes > _maxDownloadBytes) {
          throw StateError('Update package is larger than the allowed download limit.');
        }
        if (downloadTimer.elapsed > _downloadTimeout) {
          throw TimeoutException('Update download timed out.');
        }
        sink.add(chunk);
        onProgress(receivedBytes, response.contentLength);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      onVerifying?.call();
      final sha256Hash = await _digestFile(tempFile);
      if (expectedSha256 != null && !_hashesEqual(sha256Hash, expectedSha256)) {
        throw StateError('SHA-256 mismatch for $safeInstallerFileName.');
      }

      await tempFile.rename(targetFile.path);
      return DownloadedAppUpdate(
        version: safeVersion,
        filePath: targetFile.path,
        fileName: safeInstallerFileName,
        sha256: sha256Hash,
        isChecksumVerified: expectedSha256 != null,
      );
    } catch (_) {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {
          // The original download error is more useful than a cleanup failure.
        }
      }
      await _deleteIfExists(tempFile);
      rethrow;
    }
  }

  Future<AppUpdateInstallLaunchResult> launchInstall(DownloadedAppUpdate downloadedUpdate) async {
    if (!downloadedUpdate.isChecksumVerified) {
      throw StateError(
        'Cannot install update ${downloadedUpdate.version}: checksum verification failed or was unavailable.',
      );
    }
    return switch (_installPlatform) {
      AppUpdateInstallPlatform.windows => _launchWindowsInstaller(downloadedUpdate),
      AppUpdateInstallPlatform.android => _launchAndroidInstaller(downloadedUpdate),
      AppUpdateInstallPlatform.linux => _launchLinuxPackage(downloadedUpdate),
      AppUpdateInstallPlatform.unsupported => throw UnsupportedError(
        'Native update install is not supported on this platform.',
      ),
    };
  }

  Future<void> dispose() async {
    _http.close();
  }

  Future<String?> _loadExpectedSha256(
    AppUpdateInfo updateInfo, {
    required String installerFileName,
  }) async {
    final checksumUrl = updateInfo.checksumUrl?.trim();
    if (checksumUrl == null || checksumUrl.isEmpty || installerFileName.trim().isEmpty) {
      return null;
    }

    final response = await _http
        .get(Uri.parse(checksumUrl))
        .timeout(
          _downloadTimeout,
          onTimeout: () => throw TimeoutException('Update checksum download timed out.'),
        );
    if (response.statusCode >= 400) {
      return null;
    }

    final normalizedFileName = installerFileName.toLowerCase();
    for (final rawLine in response.body.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      final match = RegExp(r'^([A-Fa-f0-9]{64})\s+\*?(.+)$').firstMatch(line);
      if (match == null) {
        continue;
      }

      final assetName = match.group(2)?.trim().toLowerCase();
      if (assetName == normalizedFileName) {
        return match.group(1)!.toLowerCase();
      }
    }

    return null;
  }

  Future<Directory> _resolveUpdatesDirectory(String version) async {
    final rootDirectory = await _directoryProvider();
    final updatesRoot = Directory(p.join(rootDirectory.path, 'updates'));
    final updatesDirectory = Directory(p.join(updatesRoot.path, version));
    final normalizedRoot = p.normalize(updatesRoot.path);
    final normalizedTarget = p.normalize(updatesDirectory.path);
    if (!p.isWithin(normalizedRoot, normalizedTarget)) {
      throw StateError('Invalid update version metadata.');
    }
    await updatesDirectory.create(recursive: true);
    return updatesDirectory;
  }

  Future<String> _digestFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }

  bool _hashesEqual(String left, String right) =>
      left.trim().toLowerCase() == right.trim().toLowerCase();

  String _safePathSegment(String value, String fieldName) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        trimmed == '.' ||
        trimmed == '..' ||
        trimmed.contains('..') ||
        trimmed.contains('/') ||
        trimmed.contains('\\') ||
        p.basename(trimmed) != trimmed) {
      throw StateError('Invalid update $fieldName metadata.');
    }
    return trimmed;
  }

  String _safeInstallerFileName(String value) {
    final trimmed = value.trim();
    final basename = p.basename(trimmed);
    if (trimmed.isEmpty ||
        basename != trimmed ||
        trimmed == '.' ||
        trimmed == '..' ||
        trimmed.contains('..') ||
        trimmed.contains('/') ||
        trimmed.contains('\\')) {
      throw StateError('Invalid update installer file name metadata.');
    }
    return basename;
  }

  File _safeFileInDirectory(Directory directory, String fileName) {
    final normalizedDirectory = p.normalize(directory.path);
    final targetPath = p.normalize(p.join(directory.path, fileName));
    if (!p.isWithin(normalizedDirectory, targetPath)) {
      throw StateError('Invalid update installer file name metadata.');
    }
    return File(targetPath);
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Cleanup is best-effort; callers should see the original download failure.
    }
  }

  Future<AppUpdateInstallLaunchResult> _launchWindowsInstaller(
    DownloadedAppUpdate downloadedUpdate,
  ) async {
    final scheduled =
        await _platformChannel.invokeMethod<bool>('scheduleInstallerOnExit', {
          'filePath': downloadedUpdate.filePath,
        }) ??
        false;
    if (!scheduled) {
      throw StateError('Failed to stage the Windows installer.');
    }
    await _windowsInstallerLauncher();
    return AppUpdateInstallLaunchResult.launched;
  }

  Future<AppUpdateInstallLaunchResult> _launchAndroidInstaller(
    DownloadedAppUpdate downloadedUpdate,
  ) async {
    final canInstall =
        await _platformChannel.invokeMethod<bool>('canRequestPackageInstalls') ?? true;
    if (!canInstall) {
      await _platformChannel.invokeMethod<void>('openUnknownSourcesSettings');
      return AppUpdateInstallLaunchResult.permissionRequired;
    }

    final installerOpened =
        await _platformChannel.invokeMethod<bool>('installApk', {
          'filePath': downloadedUpdate.filePath,
        }) ??
        false;
    if (!installerOpened) {
      throw StateError('Android installer could not be opened.');
    }
    return AppUpdateInstallLaunchResult.launched;
  }

  Future<AppUpdateInstallLaunchResult> _launchLinuxPackage(
    DownloadedAppUpdate downloadedUpdate,
  ) async {
    await _linuxPackageOpener(downloadedUpdate.filePath);
    return AppUpdateInstallLaunchResult.launched;
  }
}

Future<void> _openLinuxPackage(String filePath) async {
  if (filePath.toLowerCase().endsWith('.appimage')) {
    final chmodResult = await Process.run('chmod', ['u+x', filePath]);
    if (chmodResult.exitCode != 0) {
      throw StateError('Linux AppImage could not be marked executable.');
    }

    await Process.start(filePath, const [], mode: ProcessStartMode.detached);
    return;
  }

  await Process.start('xdg-open', [filePath], mode: ProcessStartMode.detached);
}

class AppUpdateController extends Notifier<AppUpdateFlowState> {
  @override
  AppUpdateFlowState build() => AppUpdateFlowState.idle;

  Future<void> download(AppUpdateInfo updateInfo) async {
    if (state.matches(updateInfo) && state.phase == AppUpdatePhase.downloading) {
      return;
    }

    state = AppUpdateFlowState(
      version: updateInfo.latestVersion,
      phase: AppUpdatePhase.downloading,
      progress: 0,
    );

    try {
      final downloadedUpdate = await ref
          .read(appUpdateInstallerProvider)
          .downloadUpdate(
            updateInfo: updateInfo,
            onProgress: (receivedBytes, totalBytes) {
              final nextProgress = totalBytes == null || totalBytes <= 0
                  ? null
                  : receivedBytes / totalBytes;
              state = state.copyWith(
                version: updateInfo.latestVersion,
                phase: AppUpdatePhase.downloading,
                progress: nextProgress,
                downloadedUpdate: null,
                errorMessage: null,
              );
            },
            onVerifying: () {
              state = state.copyWith(
                version: updateInfo.latestVersion,
                phase: AppUpdatePhase.verifying,
                progress: null,
                errorMessage: null,
              );
            },
          );

      state = AppUpdateFlowState(
        version: updateInfo.latestVersion,
        phase: AppUpdatePhase.readyToInstall,
        progress: 1,
        downloadedUpdate: downloadedUpdate,
      );
    } catch (error) {
      state = AppUpdateFlowState(
        version: updateInfo.latestVersion,
        phase: AppUpdatePhase.error,
        errorMessage: _normalizeInstallerError(error),
      );
    }
  }

  Future<void> install(AppUpdateInfo updateInfo) async {
    final currentState = state.matches(updateInfo) ? state : AppUpdateFlowState.idle;
    final currentDownload = currentState.downloadedUpdate;
    if (currentDownload == null) {
      await download(updateInfo);
      if (!state.matches(updateInfo) || state.phase != AppUpdatePhase.readyToInstall) {
        return;
      }
    }

    final downloadedUpdate = state.downloadedUpdate;
    if (downloadedUpdate == null) {
      return;
    }

    try {
      final result = await ref.read(appUpdateInstallerProvider).launchInstall(downloadedUpdate);
      if (result == AppUpdateInstallLaunchResult.permissionRequired) {
        state = state.copyWith(
          version: updateInfo.latestVersion,
          phase: AppUpdatePhase.awaitingPermission,
          errorMessage: null,
        );
        return;
      }

      state = state.copyWith(
        version: updateInfo.latestVersion,
        phase: AppUpdatePhase.readyToInstall,
        errorMessage: null,
      );
    } catch (error) {
      state = state.copyWith(
        version: updateInfo.latestVersion,
        phase: AppUpdatePhase.error,
        errorMessage: _normalizeInstallerError(error),
      );
    }
  }

  void resetFor(AppUpdateInfo updateInfo) {
    if (!state.matches(updateInfo) && state.phase != AppUpdatePhase.downloading) {
      state = AppUpdateFlowState.idle;
    }
  }
}

String _normalizeInstallerError(Object error) {
  if (error is PlatformException) {
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }
  }

  final message = error.toString().replaceFirst(RegExp(r'^[A-Za-z]+Exception:\s*'), '').trim();
  return message.isEmpty ? 'The update operation failed.' : message;
}
