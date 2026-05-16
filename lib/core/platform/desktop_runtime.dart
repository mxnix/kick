import 'dart:async';
import 'dart:io';

import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/app_metadata.dart';
import '../../data/models/app_settings.dart';
import '../../l10n/kick_localizations.dart';
import 'launch_at_login_service.dart';
import 'tray_notification_service.dart';
import 'window_bootstrap.dart';

const desktopLaunchToTrayArgument = '--background';

// Stable identifiers required by Windows toast notifications. Generated once
// for KiCk; do not change between releases or queued notifications may go to
// the wrong action centre slot.
const _kickWindowsAppUserModelId = 'KiCk.Desktop';
const _kickWindowsToastGuid = '4f5c2e4a-7c8b-4f9b-9e6e-2c3a4d8a3a11';

class DesktopLaunchOptions {
  const DesktopLaunchOptions({required this.startHidden});

  factory DesktopLaunchOptions.fromArguments(List<String> arguments) {
    return DesktopLaunchOptions(startHidden: arguments.contains(desktopLaunchToTrayArgument));
  }

  final bool startHidden;
}

class DesktopRuntime with WindowListener {
  DesktopRuntime._();

  static const trayNotificationShownKey = 'desktop_tray_notification_shown';
  static final DesktopRuntime _instance = DesktopRuntime._();
  static DesktopLaunchOptions _launchOptions = const DesktopLaunchOptions(startHidden: false);

  static bool get isSupported => Platform.isWindows || Platform.isLinux;
  static DesktopLaunchOptions get launchOptions => _launchOptions;
  static bool get startHiddenOnLaunch => isSupported && launchOptions.startHidden;

  static void configureLaunchOptions(DesktopLaunchOptions launchOptions) {
    _launchOptions = launchOptions;
  }

  static Future<void> configure({
    required AppSettings settings,
    required Future<bool> Function() readTrayNotificationShown,
    required Future<void> Function(bool value) writeTrayNotificationShown,
  }) async {
    if (!isSupported) {
      return;
    }

    await _instance._configure(
      settings,
      readTrayNotificationShown: readTrayNotificationShown,
      writeTrayNotificationShown: writeTrayNotificationShown,
    );
  }

  static Future<void> applySettings(AppSettings settings) async {
    if (!isSupported) {
      return;
    }

    await _instance._applySettings(settings);
  }

  static Future<void> dispose() async {
    if (!isSupported) {
      return;
    }

    await _instance._dispose();
  }

  static Future<void> exitApplication() async {
    if (!isSupported) {
      return;
    }

    await _instance._exitApplication();
  }

  final SystemTray _tray = SystemTray();
  final Menu _trayMenu = Menu();
  final LaunchAtLoginService _launchAtLogin = const LaunchAtLoginService(
    appName: 'kick',
    startupArgument: desktopLaunchToTrayArgument,
  );

  TrayNotificationService? _notifications;
  bool _configured = false;
  bool _windowListenerAttached = false;
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

    _notifications = TrayNotificationService(
      appName: l10n.appTitle,
      windowsAppUserModelId: _kickWindowsAppUserModelId,
      windowsGuid: _kickWindowsToastGuid,
    );
    await _notifications!.initialize(onTap: () => unawaited(_showWindow()));

    if (!_windowListenerAttached) {
      windowManager.addListener(this);
      _windowListenerAttached = true;
    }

    await windowManager.setPreventClose(true);
    await _tray.initSystemTray(
      title: Platform.isLinux ? l10n.appTitle : '',
      iconPath: _trayIconAssetPath,
      toolTip: l10n.appTitle,
    );
    _tray.registerSystemTrayEventHandler(_handleTrayEvent);
    await _refreshTrayContextMenu(windowVisible: !startHiddenOnLaunch);

    if (startHiddenOnLaunch) {
      await _hideWindowFromTaskbarIfSupported();
    }

    _configured = true;
  }

  Future<void> _applySettings(AppSettings settings, {bool refreshRegistration = false}) async {
    if (!_configured) {
      return;
    }

    await _refreshLocalizedUi();

    final isEnabled = await _launchAtLogin.isEnabled();
    if (settings.windowsLaunchAtStartup) {
      if (refreshRegistration && isEnabled) {
        await _launchAtLogin.disable();
      }
      await _launchAtLogin.enable();
      return;
    }

    if (isEnabled) {
      await _launchAtLogin.disable();
    }
  }

  Future<void> _refreshLocalizedUi() async {
    final windowVisible = await windowManager.isVisible();
    final l10n = lookupKickLocalizations();
    if (Platform.isLinux) {
      await _tray.setTitle(l10n.appTitle);
    } else {
      await _tray.setToolTip(l10n.appTitle);
    }
    await _refreshTrayContextMenu(windowVisible: windowVisible);
  }

  Future<void> _dispose() async {
    if (_windowListenerAttached) {
      windowManager.removeListener(this);
      _windowListenerAttached = false;
    }
    if (_configured) {
      try {
        await _tray.destroy();
      } catch (_) {
        // Best-effort cleanup while the engine is shutting down.
      }
    }
    await _notifications?.dispose();
    _notifications = null;

    _configured = false;
    _exitRequested = false;
    _trayNotificationShown = false;
    _configureFuture = null;
    _readTrayNotificationShown = null;
    _writeTrayNotificationShown = null;
  }

  Future<void> _showWindow() async {
    await _showWindowInTaskbarIfSupported();
    await WindowBootstrap.reveal();
    await _refreshTrayContextMenu(windowVisible: true);
  }

  Future<void> _hideWindowToTray({bool showEducationNotification = false}) async {
    if (!await windowManager.isVisible()) {
      return;
    }

    await _hideWindowFromTaskbarIfSupported();
    await windowManager.hide();
    await _refreshTrayContextMenu(windowVisible: false);
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
    try {
      await _tray.destroy();
    } catch (_) {
      // Best-effort cleanup; continue shutting down even if tray destruction
      // fails (for instance because the icon was never installed).
    }
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<void> _refreshTrayContextMenu({required bool windowVisible}) async {
    final l10n = lookupKickLocalizations();
    await _trayMenu.buildFrom(<MenuItemBase>[
      MenuItemLabel(
        label: windowVisible ? l10n.trayHideToTrayAction : l10n.trayOpenWindowAction,
        onClicked: (_) {
          if (windowVisible) {
            unawaited(_hideWindowToTray());
          } else {
            unawaited(_showWindow());
          }
        },
      ),
      MenuSeparator(),
      MenuItemLabel(label: l10n.trayExitAction, onClicked: (_) => unawaited(_exitApplication())),
    ]);
    await _tray.setContextMenu(_trayMenu);
  }

  Future<void> _showFirstHideNotificationIfNeeded() async {
    if (_trayNotificationShown) {
      return;
    }

    _trayNotificationShown = true;
    await _writeTrayNotificationShown?.call(true);

    final l10n = lookupKickLocalizations();
    await _notifications?.showTrayHint(
      title: l10n.windowsTrayNotificationTitle,
      body: l10n.windowsTrayNotificationBody,
    );
  }

  Future<void> _hideWindowFromTaskbarIfSupported() async {
    if (Platform.isWindows) {
      await windowManager.setSkipTaskbar(true);
    }
  }

  Future<void> _showWindowInTaskbarIfSupported() async {
    if (Platform.isWindows) {
      await windowManager.setSkipTaskbar(false);
    }
  }

  void _handleTrayEvent(String eventName) {
    if (!_configured || _exitRequested) {
      return;
    }

    switch (eventName) {
      case kSystemTrayEventClick:
        if (Platform.isWindows) {
          unawaited(_toggleWindowVisibility());
        } else {
          unawaited(_tray.popUpContextMenu());
        }
        return;
      case kSystemTrayEventRightClick:
        if (Platform.isWindows) {
          unawaited(_tray.popUpContextMenu());
        } else {
          unawaited(_toggleWindowVisibility());
        }
        return;
      case kSystemTrayEventDoubleClick:
        unawaited(_toggleWindowVisibility());
        return;
      default:
        return;
    }
  }

  @override
  void onWindowEvent(String eventName) {
    if (!_configured || _exitRequested) {
      return;
    }

    switch (eventName) {
      case 'show':
        unawaited(_syncVisibleWindowState());
        return;
      case 'hide':
        unawaited(_refreshTrayContextMenu(windowVisible: false));
        return;
      default:
        return;
    }
  }

  Future<void> _syncVisibleWindowState() async {
    if (Platform.isWindows && await windowManager.isSkipTaskbar()) {
      await windowManager.setSkipTaskbar(false);
    }

    await _refreshTrayContextMenu(windowVisible: true);
  }

  @override
  void onWindowClose() {
    if (_exitRequested) {
      return;
    }

    unawaited(_hideWindowToTray(showEducationNotification: true));
  }

  String get _trayIconAssetPath =>
      Platform.isLinux ? kickLinuxTrayIconAssetPath : kickWindowsTrayIconAssetPath;
}
