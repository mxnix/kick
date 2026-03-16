import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../l10n/kick_localizations.dart';

class AndroidForegroundRuntime {
  static bool _configured = false;
  static bool _batteryOptimizationPrompted = false;
  static const _channel = MethodChannel('kick/android_runtime');

  static Future<void> configure() async {
    if (!Platform.isAndroid || _configured) {
      return;
    }

    final l10n = lookupKickLocalizations();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'kick_proxy_runtime',
        channelName: l10n.runtimeChannelName,
        channelDescription: l10n.runtimeChannelDescription,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _configured = true;
  }

  static Future<void> ensurePermissions() async {
    if (!Platform.isAndroid) {
      return;
    }

    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    await _ensureBatteryOptimizationExemption();
  }

  static Future<void> ensureRunning() async {
    if (!Platform.isAndroid) {
      return;
    }

    final l10n = lookupKickLocalizations();
    await ensurePermissions();
    if (await isRunning()) {
      await FlutterForegroundTask.updateService(
        notificationTitle: l10n.runtimeNotificationTitle,
        notificationText: l10n.runtimeNotificationReturn,
      );
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId: 701,
      notificationTitle: l10n.runtimeNotificationTitle,
      notificationText: l10n.runtimeNotificationManage,
      notificationInitialRoute: '/home',
      callback: startForegroundRuntimeCallback,
    );
  }

  static Future<bool> isRunning() async {
    if (!Platform.isAndroid) {
      return false;
    }

    return FlutterForegroundTask.isRunningService;
  }

  static Future<void> stopIfRunning() async {
    if (!Platform.isAndroid) {
      return;
    }

    if (await isRunning()) {
      await FlutterForegroundTask.stopService();
    }
  }

  static Future<void> _ensureBatteryOptimizationExemption() async {
    if (_batteryOptimizationPrompted) {
      return;
    }

    try {
      final ignored = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? true;
      if (ignored) {
        return;
      }
      _batteryOptimizationPrompted = true;
      await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
    } on PlatformException {
      // Battery optimization exemption is best-effort.
    }
  }
}

@pragma('vm:entry-point')
void startForegroundRuntimeCallback() {
  FlutterForegroundTask.setTaskHandler(KickForegroundTaskHandler());
}

class KickForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    final l10n = lookupKickLocalizations();
    FlutterForegroundTask.updateService(
      notificationTitle: l10n.runtimeNotificationTitle,
      notificationText: l10n.runtimeNotificationActive,
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/home');
  }

  @override
  void onNotificationDismissed() {}
}

class AndroidForegroundRuntimeScope extends StatelessWidget {
  const AndroidForegroundRuntimeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return child;
    }

    return WithForegroundTask(child: child);
  }
}
