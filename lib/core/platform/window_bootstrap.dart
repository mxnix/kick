import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/kick_localizations.dart';
import 'window_state_store.dart';

class WindowBootstrap {
  static Future<void>? _configureFuture;
  static DesktopWindowState? _restoreState;

  static const Size _defaultSize = Size(430, 860);
  static const Size _minimumSize = Size(400, 720);

  static set restoreState(DesktopWindowState? value) {
    _restoreState = value;
  }

  static Future<void> configure() async {
    if (!_isDesktopWindowPlatform) {
      return;
    }

    await (_configureFuture ??= _configureWindow());
  }

  static Future<void> reveal() async {
    if (!_isDesktopWindowPlatform) {
      return;
    }

    await _revealWindow();
  }

  static Future<void> refreshTitle() async {
    if (!_isDesktopWindowPlatform) {
      return;
    }

    await configure();
    await windowManager.setTitle(lookupKickLocalizations().appTitle);
  }

  static Future<void> _configureWindow() async {
    await windowManager.ensureInitialized();
    final saved = _restoreState;
    final initialSize = saved != null ? saved.bounds.size : _defaultSize;
    final initialPosition = saved?.bounds.topLeft;
    final shouldCenter = saved == null;

    final options = WindowOptions(
      size: initialSize,
      minimumSize: _minimumSize,
      center: shouldCenter,
      title: lookupKickLocalizations().appTitle,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (Platform.isWindows || Platform.isLinux) {
        await windowManager.setAsFrameless();
        await windowManager.setHasShadow(false);
      }
      if (Platform.isWindows) {
        await windowManager.setSkipTaskbar(false);
      }

      if (saved != null) {
        final clamped = _clampBoundsToVisibleArea(saved.bounds);
        await windowManager.setBounds(clamped);
        if (initialPosition != null) {
          // setBounds sets both, but Linux occasionally ignores position
          // unless reapplied after the size has settled.
          await windowManager.setPosition(clamped.topLeft);
        }
        if (saved.isMaximized) {
          await windowManager.maximize();
        }
      }
    });
  }

  static Future<void> _revealWindow() async {
    await configure();
    await windowManager.show();
    await windowManager.focus();
  }

  /// Keeps a saved window inside reasonable bounds so we never restore it
  /// fully off-screen (e.g. after a monitor disconnect).
  static Rect _clampBoundsToVisibleArea(Rect bounds) {
    final width = bounds.width < _minimumSize.width ? _minimumSize.width : bounds.width;
    final height = bounds.height < _minimumSize.height ? _minimumSize.height : bounds.height;
    // Ensure at least a small portion of the title bar stays accessible.
    final left = bounds.left.isFinite ? bounds.left : 0.0;
    final top = bounds.top.isFinite && bounds.top > -100 ? bounds.top : 0.0;
    return Rect.fromLTWH(left, top, width, height);
  }
}

bool get _isDesktopWindowPlatform => Platform.isWindows || Platform.isLinux;
