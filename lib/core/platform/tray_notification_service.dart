import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around [FlutterLocalNotificationsPlugin] that the desktop
/// runtime uses to show the educational "minimized to tray" banner.
///
/// Notifications are an optional enhancement and the rest of the runtime
/// should keep working if initialization or display fails (for example on a
/// Linux system without a notification daemon). Failures are swallowed
/// silently here for that reason.
class TrayNotificationService {
  TrayNotificationService({
    required this.appName,
    required this.windowsAppUserModelId,
    required this.windowsGuid,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final String appName;
  final String windowsAppUserModelId;
  final String windowsGuid;
  final FlutterLocalNotificationsPlugin _plugin;

  static const _trayHintNotificationId = 1001;

  bool _initialized = false;
  Future<void>? _initialization;
  VoidCallback? _onTap;

  Future<void> initialize({VoidCallback? onTap}) async {
    _onTap = onTap;
    if (_initialized) {
      return;
    }
    final initialization = _initialization ??= _initializeOnce();
    try {
      await initialization;
      _initialized = true;
    } catch (_) {
      _initialization = null;
    }
  }

  Future<void> _initializeOnce() async {
    final settings = InitializationSettings(
      linux: const LinuxInitializationSettings(defaultActionName: 'Open'),
      windows: WindowsInitializationSettings(
        appName: appName,
        appUserModelId: windowsAppUserModelId,
        guid: windowsGuid,
      ),
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (_) {
        _onTap?.call();
      },
    );
  }

  Future<void> showTrayHint({required String title, required String body}) async {
    if (!_initialized) {
      return;
    }
    if (!Platform.isWindows && !Platform.isLinux) {
      return;
    }

    final details = const NotificationDetails(
      windows: WindowsNotificationDetails(),
      linux: LinuxNotificationDetails(category: LinuxNotificationCategory.im),
    );

    try {
      await _plugin.show(
        id: _trayHintNotificationId,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (_) {
      // The desktop tray hint is purely informational; ignore display errors.
    }
  }

  Future<void> dispose() async {
    if (!_initialized) {
      return;
    }
    try {
      await _plugin.cancel(id: _trayHintNotificationId);
    } catch (_) {
      // Best-effort cleanup.
    }
    _initialized = false;
    _initialization = null;
    _onTap = null;
  }
}
