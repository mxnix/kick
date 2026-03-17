import 'dart:async';
import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/app_metadata.dart';
import '../../data/models/app_settings.dart';
import '../../l10n/kick_localizations.dart';
import 'window_bootstrap.dart';

const windowsLaunchToTrayArgument = '--background';
const _showWindowMenuItemKey = 'show_window';
const _hideWindowMenuItemKey = 'hide_window';
const _exitAppMenuItemKey = 'exit_app';

class WindowsLaunchOptions {
  const WindowsLaunchOptions({required this.startHidden});

  factory WindowsLaunchOptions.fromArguments(List<String> arguments) {
    return WindowsLaunchOptions(startHidden: arguments.contains(windowsLaunchToTrayArgument));
  }

  final bool startHidden;
}

class WindowsDesktopRuntime with TrayListener, WindowListener {
  WindowsDesktopRuntime._();

  static const trayNotificationShownKey = 'windows_tray_notification_shown';
  static final WindowsDesktopRuntime _instance = WindowsDesktopRuntime._();
  static final WindowsLaunchOptions launchOptions = WindowsLaunchOptions.fromArguments(
    Platform.executableArguments,
  );

  static bool get startHiddenOnLaunch => Platform.isWindows && launchOptions.startHidden;

  static Future<void> configure({
    required AppSettings settings,
    required Future<bool> Function() readTrayNotificationShown,
    required Future<void> Function(bool value) writeTrayNotificationShown,
  }) async {
    if (!Platform.isWindows) {
      return;
    }

    await _instance._configure(
      settings,
      readTrayNotificationShown: readTrayNotificationShown,
      writeTrayNotificationShown: writeTrayNotificationShown,
    );
  }

  static Future<void> applySettings(AppSettings settings) async {
    if (!Platform.isWindows) {
      return;
    }

    await _instance._applySettings(settings);
  }

  static Future<void> dispose() async {
    if (!Platform.isWindows) {
      return;
    }

    await _instance._dispose();
  }

  bool _configured = false;
  bool _listenersAttached = false;
  bool _exitRequested = false;
  bool _trayNotificationShown = false;
  Future<void>? _configureFuture;
  Future<bool> Function()? _readTrayNotificationShown;
  Future<void> Function(bool value)? _writeTrayNotificationShown;

  Future<void> _configure(
    AppSettings settings, {
    required Future<bool> Function() readTrayNotificationShown,
    required Future<void> Function(bool value) writeTrayNotificationShown,
  }) async {
    _readTrayNotificationShown = readTrayNotificationShown;
    _writeTrayNotificationShown = writeTrayNotificationShown;
    await (_configureFuture ??= _configureOnce());
    await _applySettings(settings, refreshRegistration: true);
  }

  Future<void> _configureOnce() async {
    if (_configured) {
      return;
    }

    final l10n = lookupKickLocalizations();
    _trayNotificationShown = await (_readTrayNotificationShown?.call() ?? Future.value(false));

    launchAtStartup.setup(
      appName: 'kick',
      appPath: Platform.resolvedExecutable,
      args: const [windowsLaunchToTrayArgument],
    );
    await localNotifier.setup(appName: l10n.appTitle, shortcutPolicy: ShortcutPolicy.requireCreate);

    if (!_listenersAttached) {
      trayManager.addListener(this);
      windowManager.addListener(this);
      _listenersAttached = true;
    }

    await windowManager.setPreventClose(true);
    await trayManager.setIcon(kickWindowsTrayIconAssetPath);
    await trayManager.setToolTip(l10n.appTitle);
    await _setTrayContextMenu(windowVisible: !startHiddenOnLaunch);

    if (startHiddenOnLaunch) {
      await windowManager.setSkipTaskbar(true);
    }

    _configured = true;
  }

  Future<void> _applySettings(AppSettings settings, {bool refreshRegistration = false}) async {
    if (!_configured) {
      return;
    }

    final isEnabled = await launchAtStartup.isEnabled();
    if (settings.windowsLaunchAtStartup) {
      if (refreshRegistration && isEnabled) {
        await launchAtStartup.disable();
      }
      await launchAtStartup.enable();
      return;
    }

    if (isEnabled) {
      await launchAtStartup.disable();
    }
  }

  Future<void> _dispose() async {
    if (_listenersAttached) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
      _listenersAttached = false;
    }
    if (_configured) {
      try {
        await trayManager.destroy();
      } catch (_) {
        // Best-effort cleanup while the engine is shutting down.
      }
    }

    _configured = false;
    _exitRequested = false;
    _trayNotificationShown = false;
    _configureFuture = null;
    _readTrayNotificationShown = null;
    _writeTrayNotificationShown = null;
  }

  Future<void> _showWindow() async {
    await windowManager.setSkipTaskbar(false);
    await WindowBootstrap.reveal();
    await _setTrayContextMenu(windowVisible: true);
  }

  Future<void> _hideWindowToTray({bool showEducationNotification = false}) async {
    if (!await windowManager.isVisible()) {
      return;
    }

    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
    await _setTrayContextMenu(windowVisible: false);
    if (showEducationNotification) {
      await _showFirstHideNotificationIfNeeded();
    }
  }

  Future<void> _toggleWindowVisibility() async {
    final isVisible = await windowManager.isVisible();
    if (isVisible) {
      await _hideWindowToTray();
      return;
    }

    await _showWindow();
  }

  Future<void> _exitApplication() async {
    _exitRequested = true;
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<void> _setTrayContextMenu({required bool windowVisible}) async {
    final l10n = lookupKickLocalizations();
    final items = <MenuItem>[
      MenuItem(
        key: windowVisible ? _hideWindowMenuItemKey : _showWindowMenuItemKey,
        label: windowVisible ? l10n.trayHideToTrayAction : l10n.trayOpenWindowAction,
      ),
      MenuItem.separator(),
      MenuItem(key: _exitAppMenuItemKey, label: l10n.trayExitAction),
    ];
    await trayManager.setContextMenu(Menu(items: items));
  }

  Future<void> _showFirstHideNotificationIfNeeded() async {
    if (_trayNotificationShown) {
      return;
    }

    _trayNotificationShown = true;
    await _writeTrayNotificationShown?.call(true);

    final l10n = lookupKickLocalizations();
    final notification = LocalNotification(
      title: l10n.windowsTrayNotificationTitle,
      body: l10n.windowsTrayNotificationBody,
      silent: false,
    );
    notification.onClick = () {
      unawaited(_showWindow());
      unawaited(notification.close());
    };
    await notification.show();
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_toggleWindowVisibility());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _showWindowMenuItemKey:
        unawaited(_showWindow());
        return;
      case _hideWindowMenuItemKey:
        unawaited(_hideWindowToTray());
        return;
      case _exitAppMenuItemKey:
        unawaited(_exitApplication());
        return;
      case null:
        return;
    }
  }

  @override
  void onWindowClose() {
    if (_exitRequested) {
      return;
    }

    unawaited(_hideWindowToTray(showEducationNotification: true));
  }
}
