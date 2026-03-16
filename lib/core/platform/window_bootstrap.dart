import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/kick_localizations.dart';

class WindowBootstrap {
  static Future<void>? _configureFuture;
  static Future<void>? _revealFuture;

  static Future<void> configure() async {
    if (!Platform.isWindows) {
      return;
    }

    await (_configureFuture ??= _configureWindow());
  }

  static Future<void> reveal() async {
    if (!Platform.isWindows) {
      return;
    }

    await (_revealFuture ??= _revealWindow());
  }

  static Future<void> _configureWindow() async {
    await windowManager.ensureInitialized();
    final options = WindowOptions(
      size: Size(430, 860),
      minimumSize: Size(400, 720),
      center: true,
      title: lookupKickLocalizations().appTitle,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
    });
  }

  static Future<void> _revealWindow() async {
    await configure();
    await windowManager.show();
    await windowManager.focus();
  }
}
