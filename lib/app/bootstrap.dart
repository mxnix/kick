import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../analytics/kick_analytics.dart';
import '../core/platform/android_foreground_runtime.dart';
import '../core/platform/window_bootstrap.dart';
import '../core/platform/windows_desktop_runtime.dart';
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

final appBootstrapProvider = Provider<AppBootstrap>(
  (ref) => throw UnimplementedError('Bootstrap must be provided before runApp.'),
);

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

  Future<void> dispose() async {
    await WindowsDesktopRuntime.dispose();
    await proxyController.dispose();
    await database.close();
  }
}

Future<AppBootstrap> initializeAppBootstrap() async {
  final timings = _BootstrapTimings()..mark('initialize:start');
  try {
    final supportDirectory = await getApplicationSupportDirectory();
    timings.mark('support_directory_ready');
    final databasePath = p.join(supportDirectory.path, 'kick.sqlite');
    final database = await AppDatabase.open(databasePath);
    timings.mark('database_ready');
    final secretStore = const SecretStore();
    final settingsRepository = SettingsRepository(database);
    final accountsRepository = AccountsRepository(database);
    final logsRepository = LogsRepository(database);
    final oauthService = GeminiOAuthService(secretStore: secretStore);

    var apiKey = await secretStore.readProxyApiKey();
    apiKey ??= await settingsRepository.readLegacyApiKey();
    apiKey ??= generateProxyApiKey();
    await secretStore.writeProxyApiKey(apiKey);
    await settingsRepository.deleteLegacyApiKey();
    timings.mark('api_key_ready');

    final currentSettings = await settingsRepository.readSettings(apiKey: apiKey);
    if (currentSettings == null) {
      await settingsRepository.writeSettings(AppSettings.defaults(apiKey: apiKey));
    }
    final effectiveSettings =
        currentSettings?.copyWith(apiKey: apiKey) ?? AppSettings.defaults(apiKey: apiKey);
    setKickLocaleOverride(effectiveSettings.appLocale);
    timings.mark('settings_ready');
    await WindowBootstrap.configure();
    timings.mark('window_bootstrap_ready');
    await AndroidForegroundRuntime.configure();
    timings.mark('android_runtime_ready');
    await logsRepository.setRetentionLimit(effectiveSettings.logRetentionCount);
    await WindowsDesktopRuntime.configure(
      settings: effectiveSettings,
      readTrayNotificationShown: () =>
          settingsRepository.readBooleanFlag(WindowsDesktopRuntime.trayNotificationShownKey),
      writeTrayNotificationShown: (value) => settingsRepository.writeBooleanFlag(
        WindowsDesktopRuntime.trayNotificationShownKey,
        value,
      ),
    );
    timings.mark('windows_runtime_ready');
    final initialAccounts = await accountsRepository.readAll();
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
        playTelemetryInstallationIdPath: geminiInstallationIdPath,
        proxyController: proxyController,
        clearRawPayload: !effectiveSettings.unsafeRawLoggingEnabled,
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
  required String playTelemetryInstallationIdPath,
  required KickProxyController proxyController,
  required bool clearRawPayload,
  required _BootstrapTimings timings,
}) async {
  await Future<void>.delayed(Duration.zero);
  try {
    await logsRepository.scrubSensitiveEntries(clearRawPayload: clearRawPayload);
    timings.mark('logs_scrubbed');
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

  try {
    await proxyController.initialize();
    timings.mark('proxy_controller_initialized');
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

  try {
    await analytics.trackAppOpen();
    timings.mark('analytics_tracked');
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

  final playTelemetry = GeminiPlayTelemetryService(
    installationIdPath: playTelemetryInstallationIdPath,
  );
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
