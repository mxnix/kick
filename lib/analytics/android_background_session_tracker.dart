import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../app/bootstrap.dart';
import '../data/models/app_log_entry.dart';
import '../data/models/app_settings.dart';
import '../data/repositories/logs_repository.dart';
import '../features/app_state/providers.dart';
import 'kick_analytics.dart';

const androidBackgroundSessionCategory = 'app.lifecycle';
const androidBackgroundSessionStartedMessage = 'Android background session started';
const androidBackgroundSessionEndedMessage = 'Android background session ended';
const androidBackgroundSessionRecoveredMessage =
    'Android background session recovered after process restart';

class AndroidBackgroundSessionTracker {
  AndroidBackgroundSessionTracker({
    required LogsRepository logsRepository,
    required KickAnalytics analytics,
    DateTime Function()? now,
    String Function()? createId,
  }) : _logsRepository = logsRepository,
       _analytics = analytics,
       _now = now ?? DateTime.now,
       _createId = createId ?? const Uuid().v4;

  final LogsRepository _logsRepository;
  final KickAnalytics _analytics;
  final DateTime Function() _now;
  final String Function() _createId;

  _BackgroundSessionState? _openSession;
  bool _recoveryCompleted = false;

  Future<void> recoverIfNeeded() async {
    if (_recoveryCompleted) {
      return;
    }
    _recoveryCompleted = true;

    final recovered = await _findRecoverableSession();
    if (recovered == null) {
      return;
    }

    final durationSec = _durationSec(_now().difference(recovered.startedAt));
    await _writeLifecycleLog(
      level: AppLogLevel.warning,
      message: androidBackgroundSessionRecoveredMessage,
      payload: {
        'session_id': recovered.sessionId,
        'duration_sec': durationSec,
        'killed_in_background': true,
        'android_background_runtime_enabled': recovered.androidBackgroundRuntimeEnabled,
        'proxy_was_running': recovered.proxyWasRunning,
      },
    );
    await _analytics.trackAndroidBackgroundSession(
      durationSec: durationSec,
      killedInBackground: true,
      androidBackgroundRuntimeEnabled: recovered.androidBackgroundRuntimeEnabled,
      proxyWasRunning: recovered.proxyWasRunning,
    );
  }

  Future<void> onBackgrounded({
    required bool androidBackgroundRuntimeEnabled,
    required bool proxyWasRunning,
  }) async {
    if (_openSession != null) {
      return;
    }

    final session = _BackgroundSessionState(
      sessionId: _createId(),
      startedAt: _now(),
      androidBackgroundRuntimeEnabled: androidBackgroundRuntimeEnabled,
      proxyWasRunning: proxyWasRunning,
    );
    _openSession = session;
    await _writeLifecycleLog(
      level: AppLogLevel.info,
      message: androidBackgroundSessionStartedMessage,
      payload: {
        'session_id': session.sessionId,
        'android_background_runtime_enabled': androidBackgroundRuntimeEnabled,
        'proxy_was_running': proxyWasRunning,
      },
    );
  }

  Future<void> onResumed({
    required bool androidBackgroundRuntimeEnabled,
    required bool proxyWasRunning,
  }) async {
    final session = _openSession;
    if (session == null) {
      return;
    }
    _openSession = null;

    final durationSec = _durationSec(_now().difference(session.startedAt));
    await _writeLifecycleLog(
      level: AppLogLevel.info,
      message: androidBackgroundSessionEndedMessage,
      payload: {
        'session_id': session.sessionId,
        'duration_sec': durationSec,
        'killed_in_background': false,
        'android_background_runtime_enabled': androidBackgroundRuntimeEnabled,
        'proxy_was_running': proxyWasRunning,
      },
    );
    await _analytics.trackAndroidBackgroundSession(
      durationSec: durationSec,
      killedInBackground: false,
      androidBackgroundRuntimeEnabled: androidBackgroundRuntimeEnabled,
      proxyWasRunning: proxyWasRunning,
    );
  }

  Future<void> _writeLifecycleLog({
    required AppLogLevel level,
    required String message,
    required Map<String, Object?> payload,
  }) {
    final timestamp = _now();
    return _logsRepository.insert(
      AppLogEntry(
        id: 'app-lifecycle-${timestamp.microsecondsSinceEpoch}-${_createId()}',
        timestamp: timestamp,
        level: level,
        category: androidBackgroundSessionCategory,
        route: '/android/background',
        message: message,
        maskedPayload: jsonEncode(payload),
      ),
    );
  }

  Future<_BackgroundSessionState?> _findRecoverableSession() async {
    final entries = await _logsRepository.readAll(limit: 500);
    if (entries.isEmpty) {
      return null;
    }

    final openSessions = <String, _BackgroundSessionState>{};
    final sorted = entries.toList(growable: false)
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    for (final entry in sorted) {
      if (entry.category != androidBackgroundSessionCategory) {
        continue;
      }
      final payload = _decodePayload(entry.maskedPayload);
      final sessionId = payload['session_id'] as String?;
      if (sessionId == null || sessionId.trim().isEmpty) {
        continue;
      }

      switch (entry.message) {
        case androidBackgroundSessionStartedMessage:
          openSessions[sessionId] = _BackgroundSessionState(
            sessionId: sessionId,
            startedAt: entry.timestamp,
            androidBackgroundRuntimeEnabled: payload['android_background_runtime_enabled'] == true,
            proxyWasRunning: payload['proxy_was_running'] == true,
          );
          break;
        case androidBackgroundSessionEndedMessage:
        case androidBackgroundSessionRecoveredMessage:
          openSessions.remove(sessionId);
          break;
      }
    }

    if (openSessions.isEmpty) {
      return null;
    }

    final sessions = openSessions.values.toList(growable: false)
      ..sort((left, right) => left.startedAt.compareTo(right.startedAt));
    return sessions.last;
  }

  Map<String, Object?> _decodePayload(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const <String, Object?>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.cast<String, Object?>();
      }
    } catch (_) {}
    return const <String, Object?>{};
  }

  int _durationSec(Duration duration) {
    if (duration.isNegative) {
      return 0;
    }
    return duration.inSeconds;
  }
}

class AndroidBackgroundSessionScope extends ConsumerStatefulWidget {
  const AndroidBackgroundSessionScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AndroidBackgroundSessionScope> createState() =>
      _AndroidBackgroundSessionScopeState();
}

class _AndroidBackgroundSessionScopeState extends ConsumerState<AndroidBackgroundSessionScope>
    with WidgetsBindingObserver {
  AndroidBackgroundSessionTracker? _tracker;
  bool _backgrounded = false;

  @override
  void initState() {
    super.initState();
    if (!Platform.isAndroid) {
      return;
    }

    WidgetsBinding.instance.addObserver(this);
    final bootstrap = ref.read(appBootstrapProvider);
    _tracker = AndroidBackgroundSessionTracker(
      logsRepository: bootstrap.logsRepository,
      analytics: bootstrap.analytics,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tracker = _tracker;
      if (!mounted || tracker == null) {
        return;
      }
      unawaited(tracker.recoverIfNeeded());
    });
  }

  @override
  void dispose() {
    if (Platform.isAndroid) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isAndroid) {
      return;
    }

    switch (state) {
      case AppLifecycleState.paused:
        if (_backgrounded) {
          return;
        }
        _backgrounded = true;
        unawaited(
          _tracker?.onBackgrounded(
                androidBackgroundRuntimeEnabled: _currentSettings().androidBackgroundRuntime,
                proxyWasRunning: ref.read(proxyControllerProvider).currentState.running,
              ) ??
              Future<void>.value(),
        );
        break;
      case AppLifecycleState.resumed:
        final wasBackgrounded = _backgrounded;
        _backgrounded = false;
        if (!wasBackgrounded) {
          return;
        }
        unawaited(
          _tracker?.onResumed(
                androidBackgroundRuntimeEnabled: _currentSettings().androidBackgroundRuntime,
                proxyWasRunning: ref.read(proxyControllerProvider).currentState.running,
              ) ??
              Future<void>.value(),
        );
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        break;
    }
  }

  AppSettings _currentSettings() {
    final settings = ref.read(settingsControllerProvider).asData?.value;
    return settings ?? ref.read(appBootstrapProvider).initialSettings;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _BackgroundSessionState {
  const _BackgroundSessionState({
    required this.sessionId,
    required this.startedAt,
    required this.androidBackgroundRuntimeEnabled,
    required this.proxyWasRunning,
  });

  final String sessionId;
  final DateTime startedAt;
  final bool androidBackgroundRuntimeEnabled;
  final bool proxyWasRunning;
}
