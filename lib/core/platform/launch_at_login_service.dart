import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

/// Cross-platform launch-at-login service.
///
/// On Windows the registration is performed by writing the executable path
/// (with the `--background` argument) into
/// `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`. This avoids pulling
/// in the `launch_at_startup` package, which is no longer maintained and
/// has stale behaviour around quoting/argument escaping.
///
/// Linux is currently a no-op (kept for parity with the previous behaviour
/// where `launch_at_startup` only had usable Linux support behind a
/// .desktop autostart file). Tray-only mode on Linux can be added later
/// if there is demand.
class LaunchAtLoginService {
  const LaunchAtLoginService({required this.appName, required this.startupArgument});

  /// Identifier used as the registry value name on Windows. Should be stable
  /// across releases so that toggling does not leave dangling entries.
  final String appName;

  /// Argument appended after the executable path so the binary can recognize
  /// that it was started by the OS at login and decide to start hidden.
  final String startupArgument;

  static const _runKeyPath = r'Software\Microsoft\Windows\CurrentVersion\Run';

  Future<bool> isEnabled() async {
    if (!Platform.isWindows) {
      return false;
    }

    final key = Registry.openPath(RegistryHive.currentUser, path: _runKeyPath);
    try {
      final value = key.getStringValue(appName);
      return value != null && value.trim().isNotEmpty;
    } finally {
      key.close();
    }
  }

  Future<void> enable() async {
    if (!Platform.isWindows) {
      return;
    }

    final command = _buildCommandLine();
    final key = Registry.openPath(
      RegistryHive.currentUser,
      path: _runKeyPath,
      desiredAccessRights: AccessRights.allAccess,
    );
    try {
      key.createValue(RegistryValue.string(appName, command));
    } finally {
      key.close();
    }
  }

  Future<void> disable() async {
    if (!Platform.isWindows) {
      return;
    }

    final key = Registry.openPath(
      RegistryHive.currentUser,
      path: _runKeyPath,
      desiredAccessRights: AccessRights.allAccess,
    );
    try {
      if (key.getStringValue(appName) != null) {
        key.deleteValue(appName);
      }
    } finally {
      key.close();
    }
  }

  String _buildCommandLine() {
    final executable = Platform.resolvedExecutable;
    final quotedExecutable = '"$executable"';
    final argument = startupArgument.trim();
    if (argument.isEmpty) {
      return quotedExecutable;
    }
    return '$quotedExecutable $argument';
  }
}
