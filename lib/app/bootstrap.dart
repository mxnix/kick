import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../analytics/kick_analytics.dart';
import '../core/logging/log_sanitizer.dart';
import '../core/platform/android_foreground_runtime.dart';
import '../core/platform/desktop_runtime.dart';
import '../core/platform/window_bootstrap.dart';
import '../core/platform/window_state_store.dart';
import '../core/security/proxy_api_key.dart';
import '../data/app_database.dart';
import '../data/models/account_profile.dart';
import '../data/models/app_settings.dart';
import '../data/repositories/accounts_repository.dart';
import '../data/repositories/logs_repository.dart';
import '../data/repositories/secret_store.dart';
import '../data/repositories/settings_repository.dart';
import '../l10n/kick_localizations.dart';
import '../observability/glitchtip.dart';
import '../proxy/engine/proxy_controller.dart';
import '../proxy/gemini/gemini_oauth_service.dart';
import '../proxy/gemini/gemini_play_telemetry_service.dart';
import '../proxy/kiro/kiro_ide_runtime_version.dart';

final appBootstrapProvider = Provider<AppBootstrap>(
  (ref) => throw UnimplementedError('Bootstrap must be provided before runApp.'),
);

const _kDesktopWindowStateKey = 'desktop_window_state';
const _kKiroIdeVersionStateKey = 'kiro_ide_version_state';
const _kLogScrubVersionKey = 'logs_scrub_version';
const _kLogScrubClearedRawKey = 'logs_scrub_cleared_raw';

class AppBootstrap {
  AppBootstrap({
    required this.database,
    required this.secretStore,
    required this.settingsRepository,
    required this.accountsRepository,
    required this.logsRepository,
    required this.oauthService,
    required this.analytics,
    required this.proxyController,
    this.geminiInstallationIdPath = '',
    required this.initialSettings,
    required this.initialAccounts,
    this.windowStatePersister,
  });

  final AppDatabase database;
  final SecretStore secretStore;
  final SettingsRepository settingsRepository;
  final AccountsRepository accountsRepository;
  final LogsRepository logsRepository;
  final GeminiOAuthService oauthService;
  final KickAnalytics analytics;
  final KickProxyController proxyController;
  final String geminiInstallationIdPath;
  final AppSettings initialSettings;
  final List<AccountProfile> initialAccounts;
  final WindowStatePersister? windowStatePersister;

  Future<void> dispose() async {
    if (windowStatePersister != null) {
      await windowStatePersister!.flush();
      await windowStatePersister!.dispose();
    }
    await DesktopRuntime.dispose();
    await proxyController.dispose();
    await analytics.dispose();
    await database.close();
  }
}

Future<AppBootstrap> initializeAppBootstrap() async {
  final timings = _BootstrapTimings()..mark('initialize:start');
  try {
    // Kick off independent I/O concurrently. path_provider, secure_storage,
    // and the database open all touch separate subsystems.
    final supportDirectoryFuture = getApplicationSupportDirectory();
    const secretStore = SecretStore();
    final secretApiKeyFuture = secretStore.readProxyApiKey();

    final supportDirectory = await supportDirectoryFuture;
    timings.mark('support_directory_ready');
    final databasePath = p.join(supportDirectory.path, 'kick.sqlite');
    final database = await AppDatabase.open(databasePath);
    timings.mark('database_ready');

    final settingsRepository = SettingsRepository(database);
    final accountsRepository = AccountsRepository(database);
    final logsRepository = LogsRepository(database);
    final oauthService = GeminiOAuthService(secretStore: secretStore);

    // Fan out every read against the freshly-opened database in parallel.
    // Each one is its own customSelect via drift; running them on the same
    // background isolate lets drift batch round-trips.
    final rawSettingsFuture = settingsRepository.readAllRaw();
    final accountsFuture = accountsRepository.readAll();

    final secretApiKey = await secretApiKeyFuture;
    final rawSettings = await rawSettingsFuture;

    final legacyApiKey = secretApiKey == null
        ? SettingsRepository.readLegacyApiKeyFromRaw(rawSettings)
        : null;
    final apiKey = secretApiKey ?? legacyApiKey ?? generateProxyApiKey();

    // Only touch DPAPI / settings table when the source of truth needs to
    // change. Steady-state launches skip both writes entirely.
    if (secretApiKey != apiKey) {
      unawaited(
        secretStore.writeProxyApiKey(apiKey).catchError((Object error, StackTrace stackTrace) {
          _debugBootstrapFailure('secret_store_write', error, stackTrace);
        }),
      );
    }
    if (rawSettings.containsKey('api_key')) {
      unawaited(
        settingsRepository.deleteLegacyApiKey().catchError((Object error, StackTrace stackTrace) {
          _debugBootstrapFailure('legacy_api_key_delete', error, stackTrace);
        }),
      );
    }
    timings.mark('api_key_ready');

    final parsedSettings = SettingsRepository.parseSettingsFromRaw(rawSettings, apiKey: apiKey);
    if (parsedSettings == null) {
      await settingsRepository.writeSettings(AppSettings.defaults(apiKey: apiKey));
    }
    final effectiveSettings =
        parsedSettings?.copyWith(apiKey: apiKey) ?? AppSettings.defaults(apiKey: apiKey);
    setKickLocaleOverride(effectiveSettings.appLocale);
    timings.mark('settings_ready');

    // Window state + tray flag live in the same `settings` table we already
    // read above, so reuse the in-memory map instead of issuing fresh
    // selects. On Windows/SQLite each customSelect is ~tens of ms.
    final savedWindowStateRaw = SettingsRepository.readNonEmptyString(
      rawSettings,
      _kDesktopWindowStateKey,
    );
    final savedWindowState = DesktopWindowState.tryParse(savedWindowStateRaw);
    final initialTrayNotificationShown = SettingsRepository.readBoolFlag(
      rawSettings,
      DesktopRuntime.trayNotificationShownKey,
    );
    WindowBootstrap.restoreState = savedWindowState;

    // Hydrate the Kiro IDE version probe from persistent storage so the
    // 12h throttle survives process restarts. After this the next probe
    // call returns 0ms unless the cached entry has actually expired.
    hydrateKiroIdeRuntimeVersionFromCache(
      KiroIdeVersionPersistedState.tryDecode(
        SettingsRepository.readNonEmptyString(rawSettings, _kKiroIdeVersionStateKey),
      ),
    );
    registerKiroIdeRuntimeVersionPersistence(
      writer: (state) =>
          settingsRepository.writeStringValue(_kKiroIdeVersionStateKey, state.encode()),
    );

    // Window/tray/runtime configuration is independent: WindowBootstrap
    // touches window_manager, AndroidForegroundRuntime is a no-op on
    // desktop, DesktopRuntime stages system_tray. Run them concurrently.
    final windowConfigureFuture = WindowBootstrap.configure();
    final androidConfigureFuture = AndroidForegroundRuntime.configure();
    final desktopConfigureFuture = DesktopRuntime.configure(
      settings: effectiveSettings,
      readTrayNotificationShown: () async => initialTrayNotificationShown,
      writeTrayNotificationShown: (value) =>
          settingsRepository.writeBooleanFlag(DesktopRuntime.trayNotificationShownKey, value),
    );

    await windowConfigureFuture;
    timings.mark('window_bootstrap_ready');

    WindowStatePersister? windowStatePersister;
    if (Platform.isWindows || Platform.isLinux) {
      windowStatePersister = WindowStatePersister(
        writer: (value) => settingsRepository.writeStringValue(_kDesktopWindowStateKey, value),
      );
      await windowStatePersister.attach();
      final persister = windowStatePersister;
      DesktopRuntime.registerPreExitHook(() => persister.flush());
    }
    await androidConfigureFuture;
    timings.mark('android_runtime_ready');

    // Set the in-memory limit immediately, but defer the DELETE until idle.
    // The big retention prune is what blocks desktop_runtime_ready today.
    logsRepository.setRetentionLimitWithoutPruning(effectiveSettings.logRetentionCount);

    await desktopConfigureFuture;
    timings.mark('desktop_runtime_ready');

    final initialAccounts = await accountsFuture;
    timings.mark('accounts_ready');

    final analytics = KickAnalytics(trackingAllowed: analyticsTrackingAllowed(effectiveSettings));
    final geminiInstallationIdPath = p.join(supportDirectory.path, '.gemini', 'installation_id');

    final proxyController = KickProxyController(
      accountsRepository: accountsRepository,
      analytics: analytics,
      geminiInstallationIdPath: geminiInstallationIdPath,
      logsRepository: logsRepository,
      secretStore: secretStore,
    );
    timings.mark('bootstrap_ready');

    unawaited(
      _warmBootstrapServices(
        analytics: analytics,
        initialAccounts: initialAccounts,
        logsRepository: logsRepository,
        settingsRepository: settingsRepository,
        playTelemetryInstallationIdPath: geminiInstallationIdPath,
        proxyController: proxyController,
        clearRawPayload: !effectiveSettings.unsafeRawLoggingEnabled,
        rawSettings: rawSettings,
        timings: timings,
      ),
    );

    return AppBootstrap(
      database: database,
      secretStore: secretStore,
      settingsRepository: settingsRepository,
      accountsRepository: accountsRepository,
      logsRepository: logsRepository,
      oauthService: oauthService,
      analytics: analytics,
      proxyController: proxyController,
      geminiInstallationIdPath: geminiInstallationIdPath,
      initialSettings: effectiveSettings,
      initialAccounts: initialAccounts,
      windowStatePersister: windowStatePersister,
    );
  } catch (error, stackTrace) {
    unawaited(
      captureGlitchTipException(
        error: error,
        stackTrace: stackTrace,
        source: 'app_bootstrap',
        message: 'Application bootstrap failed',
      ),
    );
    rethrow;
  }
}

Future<void> _warmBootstrapServices({
  required KickAnalytics analytics,
  required List<AccountProfile> initialAccounts,
  required LogsRepository logsRepository,
  required SettingsRepository settingsRepository,
  required String playTelemetryInstallationIdPath,
  required KickProxyController proxyController,
  required bool clearRawPayload,
  required Map<String, String> rawSettings,
  required _BootstrapTimings timings,
}) async {
  final perfStopwatch = Stopwatch()..start();
  int? logsScrubMs;
  int? proxyReadyMs;
  int? analyticsTrackedMs;
  await Future<void>.delayed(Duration.zero);

  // Wait for the first frame before doing background SQLite churn so we
  // never compete with proxy startup or window restoration. The wait can
  // dominate the warm-up clock on slow devices, so each downstream stage
  // measures its own elapsed time with a private stopwatch instead of
  // reading [perfStopwatch] (which still includes the frame wait).
  await _waitForFirstFrame();

  // Run the retention prune that we deferred during bootstrap_ready. The
  // limit was already updated in memory; this is just the DELETE.
  unawaited(
    logsRepository.pruneToRetentionLimit().catchError((Object error, StackTrace stackTrace) {
      _debugBootstrapFailure('logs_prune', error, stackTrace);
    }),
  );

  // Scrub, proxy.initialize and analytics.trackAppOpen are independent.
  // On Android the scrub on a fresh install dominates warm-up (~800ms);
  // running it next to proxy.initialize and analytics gets the proxy ready
  // sooner without changing observable ordering.
  final scrubFuture = () async {
    final stopwatch = Stopwatch()..start();
    try {
      final didScrub = await _maybeScrubLogs(
        logsRepository: logsRepository,
        settingsRepository: settingsRepository,
        clearRawPayload: clearRawPayload,
        rawSettings: rawSettings,
      );
      timings.mark('logs_scrubbed');
      logsScrubMs = didScrub ? stopwatch.elapsedMilliseconds : 0;
    } catch (error, stackTrace) {
      _debugBootstrapFailure('logs_scrubbed', error, stackTrace);
      unawaited(
        captureGlitchTipException(
          error: error,
          stackTrace: stackTrace,
          source: 'bootstrap_warmup',
          message: 'Bootstrap warmup stage failed',
          tags: const <String, String>{'stage': 'logs_scrubbed'},
        ),
      );
    }
  }();

  final proxyFuture = () async {
    final stopwatch = Stopwatch()..start();
    try {
      await proxyController.initialize();
      timings.mark('proxy_controller_initialized');
      proxyReadyMs = stopwatch.elapsedMilliseconds;
    } catch (error, stackTrace) {
      _debugBootstrapFailure('proxy_controller_initialized', error, stackTrace);
      unawaited(
        captureGlitchTipException(
          error: error,
          stackTrace: stackTrace,
          source: 'bootstrap_warmup',
          message: 'Bootstrap warmup stage failed',
          tags: const <String, String>{'stage': 'proxy_controller_initialized'},
        ),
      );
    }
  }();

  final analyticsFuture = () async {
    final stopwatch = Stopwatch()..start();
    try {
      await analytics.trackAppOpen();
      timings.mark('analytics_tracked');
      analyticsTrackedMs = stopwatch.elapsedMilliseconds;
    } catch (error, stackTrace) {
      _debugBootstrapFailure('analytics_tracked', error, stackTrace);
      unawaited(
        captureGlitchTipException(
          error: error,
          stackTrace: stackTrace,
          source: 'bootstrap_warmup',
          message: 'Bootstrap warmup stage failed',
          tags: const <String, String>{'stage': 'analytics_tracked'},
        ),
      );
    }
  }();

  await Future.wait<void>(<Future<void>>[scrubFuture, proxyFuture, analyticsFuture]);

  unawaited(
    analytics.trackAppOpenPerf(
      totalBootstrapMs: analyticsTrackedMs ?? perfStopwatch.elapsedMilliseconds,
      proxyReadyMs: proxyReadyMs,
      logsScrubMs: logsScrubMs,
    ),
  );

  // Telemetry POST and the IDE version probe are independent network calls.
  // Run them concurrently so the slower one doesn't gate the faster one.
  final playTelemetry = GeminiPlayTelemetryService(
    installationIdPath: playTelemetryInstallationIdPath,
  );
  final telemetryFuture = () async {
    try {
      await playTelemetry.sendSessionTelemetryOnce(accounts: initialAccounts);
      timings.mark('play_telemetry_sent');
    } catch (error, stackTrace) {
      _debugBootstrapFailure('play_telemetry_sent', error, stackTrace);
      if (!isExpectedGeminiPlayTelemetryFailure(error)) {
        unawaited(
          captureGlitchTipException(
            error: error,
            stackTrace: stackTrace,
            source: 'bootstrap_warmup',
            message: 'Bootstrap warmup stage failed',
            tags: const <String, String>{'stage': 'play_telemetry_sent'},
          ),
        );
      }
    } finally {
      playTelemetry.dispose();
    }
  }();

  final versionFuture = () async {
    if (shouldSkipKiroIdeRuntimeVersionProbe()) {
      timings.mark('kiro_ide_version_refreshed');
      return;
    }
    try {
      await refreshKiroIdeRuntimeVersion();
      timings.mark('kiro_ide_version_refreshed');
    } catch (error, stackTrace) {
      _debugBootstrapFailure('kiro_ide_version_refreshed', error, stackTrace);
    }
  }();

  await Future.wait<void>(<Future<void>>[telemetryFuture, versionFuture]);
}

/// Returns true when a scrub pass actually ran. Most warm starts skip the
/// 500ms scan because the sanitizer schema hasn't changed, the raw-payload
/// preference matches what was used last time, and (for clear-raw mode) no
/// rows still carry a non-empty `raw_payload`.
Future<bool> _maybeScrubLogs({
  required LogsRepository logsRepository,
  required SettingsRepository settingsRepository,
  required bool clearRawPayload,
  required Map<String, String> rawSettings,
}) async {
  final lastVersion = SettingsRepository.readNonEmptyString(rawSettings, _kLogScrubVersionKey);
  final lastClearRaw = SettingsRepository.readBoolFlag(
    rawSettings,
    _kLogScrubClearedRawKey,
    defaultValue: clearRawPayload,
  );

  final sanitizerUnchanged = lastVersion == LogSanitizer.schemaVersion;
  final clearRawPreferenceUnchanged = lastClearRaw == clearRawPayload;

  if (sanitizerUnchanged && clearRawPreferenceUnchanged) {
    if (!clearRawPayload) {
      return false;
    }
    if (!await logsRepository.hasNonEmptyRawPayload()) {
      return false;
    }
  }

  await logsRepository.scrubSensitiveEntries(clearRawPayload: clearRawPayload);

  // Persist the version + flag we just satisfied, so future warm starts can
  // short-circuit. Two sequential writes are fine — they go through drift's
  // background isolate and aren't on any hot path.
  await settingsRepository.writeStringValue(_kLogScrubVersionKey, LogSanitizer.schemaVersion);
  await settingsRepository.writeBooleanFlag(_kLogScrubClearedRawKey, clearRawPayload);
  return true;
}

/// Awaits the first rendered frame so the warm-up isolate doesn't compete
/// with the proxy isolate spawn or window reveal. Falls back to a microtask
/// when SchedulerBinding is unavailable (e.g. before `runApp`).
Future<void> _waitForFirstFrame() async {
  final binding = SchedulerBinding.instance;
  final completer = Completer<void>();
  binding.addPostFrameCallback((_) {
    if (!completer.isCompleted) {
      completer.complete();
    }
  });
  // Make sure scheduling happens even when `WidgetsBinding` is mid-init.
  binding.scheduleFrame();
  await completer.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () {
      // If the first frame never arrives (e.g. headless test harness)
      // fall through anyway so the warm-up is not wedged.
    },
  );
}

void _debugBootstrapFailure(String stage, Object error, StackTrace stackTrace) {
  if (!kDebugMode) {
    return;
  }
  debugPrint('[bootstrap] $stage failed: $error');
  debugPrint('$stackTrace');
}

class _BootstrapTimings {
  final Stopwatch _stopwatch = Stopwatch()..start();
  Duration _lastElapsed = Duration.zero;

  void mark(String label) {
    if (!kDebugMode) {
      return;
    }

    final elapsed = _stopwatch.elapsed;
    final delta = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    debugPrint('[bootstrap] $label +${delta.inMilliseconds}ms (${elapsed.inMilliseconds}ms total)');
  }
}
