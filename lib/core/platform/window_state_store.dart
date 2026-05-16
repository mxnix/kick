import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Persisted window geometry: outer bounds plus maximized state.
@immutable
class DesktopWindowState {
  const DesktopWindowState({required this.bounds, required this.isMaximized});

  final Rect bounds;
  final bool isMaximized;

  Map<String, Object?> toJson() => {
    'x': bounds.left,
    'y': bounds.top,
    'w': bounds.width,
    'h': bounds.height,
    'maximized': isMaximized,
  };

  static DesktopWindowState? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final x = _readDouble(decoded['x']);
      final y = _readDouble(decoded['y']);
      final w = _readDouble(decoded['w']);
      final h = _readDouble(decoded['h']);
      if (x == null || y == null || w == null || h == null) {
        return null;
      }
      if (w <= 0 || h <= 0) {
        return null;
      }
      final maximized = decoded['maximized'];
      return DesktopWindowState(
        bounds: Rect.fromLTWH(x, y, w, h),
        isMaximized: maximized is bool ? maximized : maximized == 'true',
      );
    } catch (_) {
      return null;
    }
  }

  static double? _readDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}

typedef WindowStateReader = Future<String?> Function();
typedef WindowStateWriter = Future<void> Function(String value);

/// Listens to window resize/move events and persists the current geometry,
/// debounced to avoid hammering storage during interactive drags.
class WindowStatePersister with WindowListener {
  WindowStatePersister({
    required WindowStateWriter writer,
    Duration debounce = const Duration(milliseconds: 400),
  }) : _writer = writer,
       _debounce = debounce;

  final WindowStateWriter _writer;
  final Duration _debounce;

  Timer? _saveTimer;
  bool _attached = false;
  bool _disposed = false;
  bool _isMaximized = false;
  bool _isFullScreen = false;
  Rect? _lastNormalBounds;

  Future<void> attach() async {
    if (_attached || _disposed) {
      return;
    }
    _attached = true;
    windowManager.addListener(this);

    try {
      _isMaximized = await windowManager.isMaximized();
      _isFullScreen = await windowManager.isFullScreen();
      if (!_isMaximized && !_isFullScreen) {
        _lastNormalBounds = await windowManager.getBounds();
      }
    } catch (_) {
      // Best-effort: window may not be ready yet.
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _saveTimer?.cancel();
    if (_attached) {
      windowManager.removeListener(this);
      _attached = false;
    }
  }

  /// Forces an immediate write of the current state. Useful at shutdown.
  Future<void> flush() async {
    _saveTimer?.cancel();
    await _persistNow();
  }

  void _scheduleSave() {
    if (_disposed) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(_debounce, () {
      unawaited(_persistNow());
    });
  }

  Future<void> _persistNow() async {
    if (_disposed) {
      return;
    }
    try {
      if (!_isMaximized && !_isFullScreen) {
        _lastNormalBounds = await windowManager.getBounds();
      }
      final bounds = _lastNormalBounds;
      if (bounds == null) {
        return;
      }
      final state = DesktopWindowState(bounds: bounds, isMaximized: _isMaximized);
      await _writer(jsonEncode(state.toJson()));
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[window_state] failed to persist: $error\n$stackTrace');
      }
    }
  }

  @override
  void onWindowResized() {
    _scheduleSave();
  }

  @override
  void onWindowMoved() {
    _scheduleSave();
  }

  @override
  void onWindowResize() {
    // Linux does not emit `resized`; treat live resize as the save trigger
    // there. Debounce keeps writes cheap on Windows too.
    _scheduleSave();
  }

  @override
  void onWindowMove() {
    _scheduleSave();
  }

  @override
  void onWindowMaximize() {
    _isMaximized = true;
    _scheduleSave();
  }

  @override
  void onWindowUnmaximize() {
    _isMaximized = false;
    _scheduleSave();
  }

  @override
  void onWindowEnterFullScreen() {
    _isFullScreen = true;
    _scheduleSave();
  }

  @override
  void onWindowLeaveFullScreen() {
    _isFullScreen = false;
    _scheduleSave();
  }
}
