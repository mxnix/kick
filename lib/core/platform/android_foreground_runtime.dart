import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../l10n/kick_localizations.dart';

const _notificationModeStorageKey = 'kick.notification_mode';
const _notificationModePayloadKey = 'notification_mode';
const _notificationTitleStorageKey = 'kick.notification_title';
const _notificationTitlePayloadKey = 'notification_title';
const _notificationModeProxy = 'proxy';
const _notificationModeOAuth = 'oauth';

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

    final permission = await ensureNotificationPermission();
    if (permission != NotificationPermission.granted) {
      return;
    }

    await _ensureBatteryOptimizationExemption();
  }

  static Future<NotificationPermission> ensureNotificationPermission() async {
    if (!Platform.isAndroid) {
      return NotificationPermission.granted;
    }

    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission == NotificationPermission.granted ||
        permission == NotificationPermission.permanently_denied) {
      return permission;
    }

    try {
      return await FlutterForegroundTask.requestNotificationPermission();
    } on PlatformException catch (error) {
      if (isExpectedAndroidNotificationPermissionCancellation(error)) {
        return NotificationPermission.denied;
      }
      rethrow;
    }
  }

  static Future<void> ensureRunning() async {
    if (!Platform.isAndroid) {
      return;
    }

    final l10n = lookupKickLocalizations();
    await ensurePermissions();
    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      return;
    }
    await _setNotificationState(mode: _notificationModeProxy);
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

  static Future<bool> ensureTemporaryRunning({String? notificationTitle}) async {
    if (!Platform.isAndroid) {
      return false;
    }

    if (await isRunning()) {
      return false;
    }

    if (await ensureNotificationPermission() != NotificationPermission.granted) {
      return false;
    }

    // Keep the process prioritized while an external browser completes the
    // loopback OAuth flow on devices that aggressively kill background apps.
    final l10n = lookupKickLocalizations();
    final resolvedNotificationTitle = notificationTitle?.trim();
    final authNotificationTitle = resolvedNotificationTitle?.isNotEmpty == true
        ? resolvedNotificationTitle!
        : l10n.connectGoogleAccountTitle;
    try {
      await _setNotificationState(
        mode: _notificationModeOAuth,
        notificationTitle: resolvedNotificationTitle,
      );
      await FlutterForegroundTask.startService(
        serviceId: 701,
        notificationTitle: authNotificationTitle,
        notificationText: l10n.runtimeNotificationReturn,
        notificationInitialRoute: '/home',
        callback: startForegroundRuntimeCallback,
      );
      return true;
    } on PlatformException {
      return false;
    }
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
    await FlutterForegroundTask.removeData(key: _notificationModeStorageKey);
    await FlutterForegroundTask.removeData(key: _notificationTitleStorageKey);
  }

  static Future<void> _setNotificationState({
    required String mode,
    String? notificationTitle,
  }) async {
    await FlutterForegroundTask.saveData(key: _notificationModeStorageKey, value: mode);
    final resolvedNotificationTitle = notificationTitle?.trim() ?? '';
    if (resolvedNotificationTitle.isEmpty) {
      await FlutterForegroundTask.removeData(key: _notificationTitleStorageKey);
    } else {
      await FlutterForegroundTask.saveData(
        key: _notificationTitleStorageKey,
        value: resolvedNotificationTitle,
      );
    }
    if (await isRunning()) {
      FlutterForegroundTask.sendDataToTask({
        _notificationModePayloadKey: mode,
        _notificationTitlePayloadKey: resolvedNotificationTitle,
      });
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
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(KickForegroundTaskHandler());
}

class KickForegroundTaskHandler extends TaskHandler {
  String _notificationMode = _notificationModeProxy;
  String _notificationTitle = '';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _notificationMode =
        await FlutterForegroundTask.getData<String>(key: _notificationModeStorageKey) ??
        _notificationModeProxy;
    _notificationTitle =
        await FlutterForegroundTask.getData<String>(key: _notificationTitleStorageKey) ?? '';
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    final l10n = lookupKickLocalizations();
    final authNotificationTitle = _notificationTitle.trim().isNotEmpty
        ? _notificationTitle.trim()
        : l10n.connectGoogleAccountTitle;
    final (title, text) = switch (_notificationMode) {
      _notificationModeOAuth => (authNotificationTitle, l10n.runtimeNotificationReturn),
      _ => (l10n.runtimeNotificationTitle, l10n.runtimeNotificationActive),
    };
    unawaited(
      FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text),
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {
    if (data is! Map) {
      return;
    }

    final mode = data[_notificationModePayloadKey];
    if (mode is String && mode.isNotEmpty) {
      _notificationMode = mode;
    }

    final notificationTitle = data[_notificationTitlePayloadKey];
    if (notificationTitle is String) {
      _notificationTitle = notificationTitle.trim();
    }
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/home');
  }

  @override
  void onNotificationDismissed() {}
}

class AndroidForegroundRuntimeScope extends StatefulWidget {
  const AndroidForegroundRuntimeScope({super.key, required this.child});

  final Widget child;

  @override
  State<AndroidForegroundRuntimeScope> createState() => _AndroidForegroundRuntimeScopeState();
}

class _AndroidForegroundRuntimeScopeState extends State<AndroidForegroundRuntimeScope> {
  bool _notificationPromptScheduled = false;

  @override
  void initState() {
    super.initState();
    if (!Platform.isAndroid) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _notificationPromptScheduled) {
        return;
      }
      _notificationPromptScheduled = true;
      unawaited(_requestNotificationPermissionOnStart());
    });
  }

  Future<void> _requestNotificationPermissionOnStart() async {
    try {
      await AndroidForegroundRuntime.ensureNotificationPermission();
    } on PlatformException {
      // Notification permission prompt at startup is best-effort.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return widget.child;
    }

    return WithForegroundTask(child: widget.child);
  }
}

bool isExpectedAndroidNotificationPermissionCancellation(PlatformException error) {
  final code = error.code.trim().toLowerCase();
  if (code.contains('permissionrequestcancelledexception')) {
    return true;
  }

  final message = error.message?.trim().toLowerCase() ?? '';
  return message.contains('permission request dialog was closed') ||
      message.contains('request was cancelled');
}
