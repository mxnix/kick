import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:aptabase_flutter/aptabase_flutter.dart';
import 'package:aptabase_flutter/storage_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/models/account_profile.dart';
import '../data/models/app_settings.dart';
import '../proxy/model_catalog.dart';

const _kickAptabaseBoxName = 'kick_aptabase_events';
const _kickAptabaseStorageDirectoryName = 'analytics';

const kickAnalyticsSessionSummarySchemaVersion = 2;

bool analyticsTrackingAllowed(AppSettings settings) {
  return settings.hasAcknowledgedDisclaimer && settings.analyticsConsentEnabled;
}

abstract final class KickAnalyticsEvents {
  static const appOpen = 'app_open';
  static const appOpenPerf = 'app_open_perf';
  static const disclaimerAccepted = 'disclaimer_accepted';
  static const analyticsConsentRevoked = 'analytics_consent_revoked';
  static const accountConnectStarted = 'account_connect_started';
  static const accountConnectSucceeded = 'account_connect_succeeded';
  static const accountConnectFailed = 'account_connect_failed';
  static const accountStateChanged = 'account_state_changed';
  static const proxyStarted = 'proxy_started';
  static const proxyStartFailed = 'proxy_start_failed';
  static const firstSuccessfulRequest = 'first_successful_request';
  static const proxyRequestFailed = 'proxy_request_failed';
  static const proxyRequestRetried = 'proxy_request_retried';
  static const proxySessionSummary = 'proxy_session_summary';
  static const upstreamCompatibilityIssue = 'upstream_compatibility_issue';
  static const androidBackgroundSession = 'android_background_session';
  static const updateCheckCompleted = 'update_check_completed';
  static const updateDownloadCompleted = 'update_download_completed';
  static const updateInstallLaunched = 'update_install_launched';
  static const updateInstallFailed = 'update_install_failed';
  static const backupExported = 'backup_exported';
  static const backupRestored = 'backup_restored';
  static const sillyTavernPushSucceeded = 'silly_tavern_push_succeeded';
  static const sillyTavernPushFailed = 'silly_tavern_push_failed';
  static const logsExported = 'logs_exported';
}

abstract final class KickAnalyticsKeys {
  static const buildChannel = 'build_channel';
  static const schemaVersion = 'schema_version';
  static const sessionId = 'session_id';
  static const route = 'route';
  static const modelFamily = 'model_family';
  static const provider = 'provider';
  static const stream = 'stream';
  static const errorKind = 'error_kind';
  static const errorSource = 'error_source';
  static const errorDetail = 'error_detail';
  static const upstreamReason = 'upstream_reason';
  static const statusCode = 'status_code';
  static const retryAfterMs = 'retry_after_ms';
  static const hasActionUrl = 'has_action_url';
  static const stopReason = 'stop_reason';
  static const platform = 'platform';
  static const action = 'action';
}

class AnalyticsBuildConfig {
  const AnalyticsBuildConfig({required this.buildChannel, required this.appKey, this.host});

  final String buildChannel;
  final String appKey;
  final String? host;

  bool get isEnabled => appKey.trim().isNotEmpty;

  static AnalyticsBuildConfig fromEnvironment() {
    const releaseAppKey = String.fromEnvironment('KICK_APTABASE_APP_KEY_RELEASE');
    const debugAppKey = String.fromEnvironment('KICK_APTABASE_APP_KEY_DEBUG');
    const releaseHost = String.fromEnvironment('KICK_APTABASE_HOST_RELEASE');
    const debugHost = String.fromEnvironment('KICK_APTABASE_HOST_DEBUG');

    return resolve(
      isReleaseMode: kReleaseMode,
      releaseAppKey: releaseAppKey,
      debugAppKey: debugAppKey,
      releaseHost: releaseHost,
      debugHost: debugHost,
    );
  }

  @visibleForTesting
  static AnalyticsBuildConfig resolve({
    required bool isReleaseMode,
    required String releaseAppKey,
    required String debugAppKey,
    String releaseHost = '',
    String debugHost = '',
  }) {
    final buildChannel = isReleaseMode ? 'release' : 'debug';
    final appKey = isReleaseMode ? releaseAppKey.trim() : debugAppKey.trim();
    final host = (isReleaseMode ? releaseHost : debugHost).trim();

    return AnalyticsBuildConfig(
      buildChannel: buildChannel,
      appKey: appKey,
      host: host.isEmpty ? null : host,
    );
  }
}

abstract class AnalyticsTransport {
  Future<void> ensureInitialized(AnalyticsBuildConfig config);

  Future<void> track(String eventName, Map<String, Object?> properties);

  Future<void> flush() async {}

  Future<void> dispose() async {}

  Future<void> clearQueue() async {}
}

class NoOpAnalyticsTransport implements AnalyticsTransport {
  const NoOpAnalyticsTransport();

  @override
  Future<void> ensureInitialized(AnalyticsBuildConfig config) async {}

  @override
  Future<void> track(String eventName, Map<String, Object?> properties) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> clearQueue() async {}
}

typedef AnalyticsStorageFactory = Future<StorageManager> Function();
typedef AnalyticsTransportInitializer =
    Future<void> Function(AnalyticsBuildConfig config, StorageManager storage);

class AptabaseAnalyticsTransport implements AnalyticsTransport {
  AptabaseAnalyticsTransport({
    AnalyticsStorageFactory? storageFactory,
    AnalyticsTransportInitializer? initializer,
  }) : _storageFactory = storageFactory ?? _defaultAnalyticsStorageFactory,
       _initializer = initializer ?? _defaultInitialize;

  final AnalyticsStorageFactory _storageFactory;
  final AnalyticsTransportInitializer _initializer;

  Future<void>? _initialization;
  bool _initialized = false;
  StorageManager? _storage;

  @override
  Future<void> ensureInitialized(AnalyticsBuildConfig config) async {
    if (_initialized) {
      return;
    }

    final initialization = _initialization ??= _initialize(config);
    try {
      await initialization;
      if (identical(_initialization, initialization)) {
        _initialized = true;
      }
    } catch (_) {
      if (identical(_initialization, initialization)) {
        _initialization = null;
      }
      rethrow;
    }
  }

  Future<void> _initialize(AnalyticsBuildConfig config) async {
    final storage = await _storageFactory();
    _storage = storage;
    await _initializer(config, storage);
  }

  static Future<StorageManager> _defaultAnalyticsStorageFactory() async {
    return createDefaultAnalyticsStorage(isWindows: Platform.isWindows);
  }

  static Future<void> _defaultInitialize(
    AnalyticsBuildConfig config,
    StorageManager storage,
  ) async {
    final host = config.host?.trim();
    final options = host == null || host.isEmpty
        ? const InitOptions(printDebugMessages: !kReleaseMode)
        : InitOptions(host: host, printDebugMessages: !kReleaseMode);
    await Aptabase.init(config.appKey, options, storage);
  }

  @override
  Future<void> track(String eventName, Map<String, Object?> properties) {
    return Aptabase.instance.trackEvent(eventName, properties);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> dispose() async {
    await flush();
  }

  @override
  Future<void> clearQueue() async {
    final storage = _storage;
    if (storage == null) {
      return;
    }
    try {
      while (true) {
        final batch = (await storage.getItems(200)).toList(growable: false);
        if (batch.isEmpty) {
          break;
        }
        await storage.deleteAllKeys(batch.map((entry) => entry.key));
      }
    } catch (_) {}
  }
}

@visibleForTesting
StorageManager createDefaultAnalyticsStorage({
  required bool isWindows,
  Future<Directory> Function()? supportDirectoryProvider,
}) {
  if (isWindows) {
    // Persisted Hive-backed storage is not reliable on Windows desktop when
    // multiple KiCk processes overlap briefly during startup/shutdown.
    return _InMemoryAnalyticsStorage();
  }
  return _KickHiveStorage(supportDirectoryProvider: supportDirectoryProvider);
}

class _SessionEventThrottle {
  _SessionEventThrottle({required this.cap});

  final int cap;
  final Map<String, int> _emitted = <String, int>{};
  final Map<String, int> _dropped = <String, int>{};

  bool allow(String eventName) {
    final emitted = _emitted[eventName] ?? 0;
    if (emitted >= cap) {
      _dropped[eventName] = (_dropped[eventName] ?? 0) + 1;
      return false;
    }
    _emitted[eventName] = emitted + 1;
    return true;
  }

  int droppedFor(String eventName) => _dropped[eventName] ?? 0;

  void reset() {
    _emitted.clear();
    _dropped.clear();
  }
}

class KickAnalytics {
  KickAnalytics({
    AnalyticsBuildConfig? config,
    AnalyticsTransport? transport,
    bool trackingAllowed = false,
    int requestEventCapPerSession = 200,
  }) : _config = config ?? AnalyticsBuildConfig.fromEnvironment(),
       _transport =
           transport ??
           ((config ?? AnalyticsBuildConfig.fromEnvironment()).isEnabled
               ? AptabaseAnalyticsTransport()
               : const NoOpAnalyticsTransport()),
       _trackingAllowed = trackingAllowed,
       _throttle = _SessionEventThrottle(cap: requestEventCapPerSession);

  final AnalyticsBuildConfig _config;
  final AnalyticsTransport _transport;
  final _SessionEventThrottle _throttle;

  bool _trackingAllowed;
  bool _firstSuccessfulRequestTracked = false;

  bool get isEnabled => _config.isEnabled;

  void resetSessionThrottle() {
    _throttle.reset();
  }

  int droppedEventsFor(String eventName) => _throttle.droppedFor(eventName);

  Future<void> setTrackingAllowed(bool value) async {
    final previous = _trackingAllowed;
    _trackingAllowed = value;
    if (previous && !value) {
      try {
        await _transport.ensureInitialized(_config);
        await _transport.track(KickAnalyticsEvents.analyticsConsentRevoked, {
          KickAnalyticsKeys.buildChannel: _config.buildChannel,
        });
        await _transport.flush();
      } catch (_) {}
      try {
        await _transport.clearQueue();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    try {
      await _transport.dispose();
    } catch (_) {}
  }

  Future<void> trackAppOpen() {
    return _track(KickAnalyticsEvents.appOpen);
  }

  Future<void> trackAppOpenPerf({
    required int totalBootstrapMs,
    int? databaseReadyMs,
    int? settingsReadyMs,
    int? proxyReadyMs,
    int? logsScrubMs,
  }) {
    final properties = <String, Object?>{'total_ms': _bucketMs(totalBootstrapMs)};
    _putIfPositive(properties, 'database_ms', databaseReadyMs);
    _putIfPositive(properties, 'settings_ms', settingsReadyMs);
    _putIfPositive(properties, 'proxy_ms', proxyReadyMs);
    _putIfPositive(properties, 'logs_scrub_ms', logsScrubMs);
    properties['platform'] = _platformName();
    return _track(KickAnalyticsEvents.appOpenPerf, properties);
  }

  Future<void> trackDisclaimerAccepted({required bool analyticsEnabled}) {
    return _track(KickAnalyticsEvents.disclaimerAccepted, {'analytics_enabled': analyticsEnabled});
  }

  Future<void> trackAccountConnectStarted({required bool reauthorization}) {
    return _track(KickAnalyticsEvents.accountConnectStarted, {'reauthorization': reauthorization});
  }

  Future<void> trackAccountConnectSucceeded({
    required bool reauthorization,
    required int enabledAccounts,
    String? provider,
  }) {
    return _track(KickAnalyticsEvents.accountConnectSucceeded, {
      'reauthorization': reauthorization,
      'enabled_accounts': enabledAccounts,
      KickAnalyticsKeys.provider: provider,
    });
  }

  Future<void> trackAccountConnectFailed({
    required bool reauthorization,
    required String errorKind,
    String? provider,
  }) {
    return _track(KickAnalyticsEvents.accountConnectFailed, {
      'reauthorization': reauthorization,
      KickAnalyticsKeys.errorKind: errorKind,
      KickAnalyticsKeys.provider: provider,
    });
  }

  Future<void> trackAccountStateChanged({
    required String action,
    required String provider,
    required int enabledAccounts,
    required int totalAccounts,
  }) {
    return _track(KickAnalyticsEvents.accountStateChanged, {
      KickAnalyticsKeys.action: action,
      KickAnalyticsKeys.provider: provider,
      'enabled_accounts': enabledAccounts,
      'total_accounts': totalAccounts,
    });
  }

  Future<void> trackProxyStarted({
    required bool allowLan,
    required int activeAccounts,
    String? sessionId,
    int? startLatencyMs,
  }) {
    final properties = <String, Object?>{
      'allow_lan': allowLan,
      'active_accounts': activeAccounts,
      KickAnalyticsKeys.sessionId: sessionId,
    };
    _putIfPositive(properties, 'start_latency_ms', startLatencyMs);
    return _track(KickAnalyticsEvents.proxyStarted, properties);
  }

  Future<void> trackProxyStartFailed({required String errorKind, String? sessionId}) {
    return _track(KickAnalyticsEvents.proxyStartFailed, {
      KickAnalyticsKeys.errorKind: errorKind,
      KickAnalyticsKeys.sessionId: sessionId,
    });
  }

  Future<void> trackFirstSuccessfulRequest({
    required String route,
    required String model,
    required bool stream,
    String? sessionId,
    int? latencyMs,
  }) async {
    if (_firstSuccessfulRequestTracked) {
      return;
    }

    final properties = <String, Object?>{
      KickAnalyticsKeys.route: route,
      KickAnalyticsKeys.modelFamily: modelFamily(model),
      KickAnalyticsKeys.stream: stream,
      KickAnalyticsKeys.sessionId: sessionId,
    };
    _putIfPositive(properties, 'latency_ms', latencyMs);

    final tracked = await _trackEvent(KickAnalyticsEvents.firstSuccessfulRequest, properties);
    if (tracked) {
      _firstSuccessfulRequestTracked = true;
    }
  }

  Future<void> trackProxyRequestFailed({
    required String route,
    required String model,
    required bool stream,
    required String errorKind,
    String? errorSource,
    int? statusCode,
    String? errorDetail,
    String? upstreamReason,
    int? retryAfterMs,
    bool? hasActionUrl,
    String? sessionId,
    int? latencyMs,
  }) {
    if (!_throttle.allow(KickAnalyticsEvents.proxyRequestFailed)) {
      return Future<void>.value();
    }
    final properties = <String, Object?>{
      KickAnalyticsKeys.route: route,
      KickAnalyticsKeys.modelFamily: modelFamily(model),
      KickAnalyticsKeys.stream: stream,
      KickAnalyticsKeys.errorKind: errorKind,
      KickAnalyticsKeys.sessionId: sessionId,
    };
    _putIfNotBlank(properties, KickAnalyticsKeys.errorSource, errorSource);
    if (statusCode != null) {
      properties[KickAnalyticsKeys.statusCode] = statusCode;
    }
    _putIfNotBlank(properties, KickAnalyticsKeys.errorDetail, errorDetail);
    _putIfNotBlank(properties, KickAnalyticsKeys.upstreamReason, upstreamReason);
    _putIfPositive(properties, KickAnalyticsKeys.retryAfterMs, retryAfterMs);
    _putIfBool(properties, KickAnalyticsKeys.hasActionUrl, hasActionUrl);
    _putIfPositive(properties, 'latency_ms', latencyMs);
    return _track(KickAnalyticsEvents.proxyRequestFailed, properties);
  }

  Future<void> trackProxyRequestRetried({
    required String route,
    required String model,
    required bool stream,
    required String outcome,
    required int retryCount,
    required int upstreamRetryCount,
    required int accountFailoverCount,
    String? retryKinds,
    int? retryDelayMs,
    int? statusCode,
    String? errorSource,
    String? errorDetail,
    String? upstreamReason,
    int? retryAfterMs,
    bool? hasActionUrl,
    String? sessionId,
    int? latencyMs,
  }) {
    if (!_throttle.allow(KickAnalyticsEvents.proxyRequestRetried)) {
      return Future<void>.value();
    }
    final properties = <String, Object?>{
      KickAnalyticsKeys.route: route,
      KickAnalyticsKeys.modelFamily: modelFamily(model),
      KickAnalyticsKeys.stream: stream,
      'outcome': outcome,
      'retry_count': retryCount,
      'upstream_retry_count': upstreamRetryCount,
      'account_failover_count': accountFailoverCount,
      KickAnalyticsKeys.sessionId: sessionId,
    };
    if (retryKinds != null && retryKinds.trim().isNotEmpty) {
      properties['retry_kinds'] = retryKinds;
    }
    if (retryDelayMs != null && retryDelayMs > 0) {
      properties['retry_delay_ms'] = retryDelayMs;
    }
    if (statusCode != null) {
      properties[KickAnalyticsKeys.statusCode] = statusCode;
    }
    _putIfNotBlank(properties, KickAnalyticsKeys.errorSource, errorSource);
    _putIfNotBlank(properties, KickAnalyticsKeys.errorDetail, errorDetail);
    _putIfNotBlank(properties, KickAnalyticsKeys.upstreamReason, upstreamReason);
    _putIfPositive(properties, KickAnalyticsKeys.retryAfterMs, retryAfterMs);
    _putIfBool(properties, KickAnalyticsKeys.hasActionUrl, hasActionUrl);
    _putIfPositive(properties, 'latency_ms', latencyMs);
    return _track(KickAnalyticsEvents.proxyRequestRetried, properties);
  }

  Future<void> trackProxySessionSummary({
    required int uptimeSec,
    required int requestCount,
    required int successCount,
    required int failedCount,
    required int retriedCount,
    required int activeAccounts,
    required int healthyAccounts,
    required int requestMaxRetries,
    required bool mark429AsUnhealthy,
    required bool androidBackgroundRuntime,
    String? stopReason,
    String? sessionId,
    int? failedDropped,
    int? retriedDropped,
    int? latencyP50Ms,
    int? latencyP95Ms,
    int? latencyMaxMs,
    int? bytesIn,
    int? bytesOut,
    List<String>? routesSeen,
    List<String>? modelFamiliesSeen,
  }) {
    final properties = <String, Object?>{
      KickAnalyticsKeys.schemaVersion: kickAnalyticsSessionSummarySchemaVersion,
      KickAnalyticsKeys.sessionId: sessionId,
      'uptime_sec': uptimeSec,
      'request_count': requestCount,
      'success_count': successCount,
      'failed_count': failedCount,
      'retried_count': retriedCount,
      'active_accounts': activeAccounts,
      'healthy_accounts': healthyAccounts,
      'request_max_retries': requestMaxRetries,
      'mark_429_as_unhealthy': mark429AsUnhealthy,
      'android_background_runtime': androidBackgroundRuntime,
      KickAnalyticsKeys.stopReason: stopReason,
    };
    _putIfPositive(properties, 'failed_dropped', failedDropped);
    _putIfPositive(properties, 'retried_dropped', retriedDropped);
    _putIfPositive(properties, 'latency_p50_ms', latencyP50Ms);
    _putIfPositive(properties, 'latency_p95_ms', latencyP95Ms);
    _putIfPositive(properties, 'latency_max_ms', latencyMaxMs);
    _putIfPositive(properties, 'bytes_in', bytesIn);
    _putIfPositive(properties, 'bytes_out', bytesOut);
    _putIfNonEmptyStringList(properties, 'routes_seen', routesSeen);
    _putIfNonEmptyStringList(properties, 'model_families_seen', modelFamiliesSeen);
    return _track(KickAnalyticsEvents.proxySessionSummary, properties);
  }

  Future<void> trackUpstreamCompatibilityIssue({
    required String issueKind,
    required String route,
    required String model,
    required bool stream,
    String? errorKind,
    String? errorSource,
    int? statusCode,
    String? errorDetail,
    String? upstreamReason,
    int? retryAfterMs,
    bool? hasActionUrl,
    String? sessionId,
  }) {
    final properties = <String, Object?>{
      'issue_kind': issueKind,
      KickAnalyticsKeys.route: route,
      KickAnalyticsKeys.modelFamily: modelFamily(model),
      KickAnalyticsKeys.stream: stream,
      KickAnalyticsKeys.sessionId: sessionId,
    };
    if (errorKind != null && errorKind.trim().isNotEmpty) {
      properties[KickAnalyticsKeys.errorKind] = errorKind;
    }
    _putIfNotBlank(properties, KickAnalyticsKeys.errorSource, errorSource);
    if (statusCode != null) {
      properties[KickAnalyticsKeys.statusCode] = statusCode;
    }
    _putIfNotBlank(properties, KickAnalyticsKeys.errorDetail, errorDetail);
    _putIfNotBlank(properties, KickAnalyticsKeys.upstreamReason, upstreamReason);
    _putIfPositive(properties, KickAnalyticsKeys.retryAfterMs, retryAfterMs);
    _putIfBool(properties, KickAnalyticsKeys.hasActionUrl, hasActionUrl);
    return _track(KickAnalyticsEvents.upstreamCompatibilityIssue, properties);
  }

  Future<void> trackAndroidBackgroundSession({
    required int durationSec,
    required bool killedInBackground,
    required bool androidBackgroundRuntimeEnabled,
    required bool proxyWasRunning,
  }) {
    return _track(KickAnalyticsEvents.androidBackgroundSession, {
      'duration_sec': durationSec,
      'killed_in_background': killedInBackground,
      'android_background_runtime_enabled': androidBackgroundRuntimeEnabled,
      'proxy_was_running': proxyWasRunning,
    });
  }

  Future<void> trackUpdateCheckCompleted({
    required bool hasUpdate,
    required bool installerAvailable,
    String? errorKind,
  }) {
    final properties = <String, Object?>{
      'has_update': hasUpdate,
      'installer_available': installerAvailable,
      KickAnalyticsKeys.platform: _platformName(),
    };
    _putIfNotBlank(properties, KickAnalyticsKeys.errorKind, errorKind);
    return _track(KickAnalyticsEvents.updateCheckCompleted, properties);
  }

  Future<void> trackUpdateDownloadCompleted({
    required bool checksumVerified,
    required bool succeeded,
    int? sizeBytes,
    int? durationMs,
    String? errorKind,
  }) {
    final properties = <String, Object?>{
      'succeeded': succeeded,
      'checksum_verified': checksumVerified,
      KickAnalyticsKeys.platform: _platformName(),
    };
    if (sizeBytes != null && sizeBytes > 0) {
      properties['size_mb'] = (sizeBytes / (1024 * 1024)).round();
    }
    _putIfPositive(properties, 'duration_ms', durationMs);
    _putIfNotBlank(properties, KickAnalyticsKeys.errorKind, errorKind);
    return _track(KickAnalyticsEvents.updateDownloadCompleted, properties);
  }

  Future<void> trackUpdateInstallLaunched({required bool permissionRequired}) {
    return _track(KickAnalyticsEvents.updateInstallLaunched, {
      'permission_required': permissionRequired,
      KickAnalyticsKeys.platform: _platformName(),
    });
  }

  Future<void> trackUpdateInstallFailed({required String errorKind}) {
    return _track(KickAnalyticsEvents.updateInstallFailed, {
      KickAnalyticsKeys.errorKind: errorKind,
      KickAnalyticsKeys.platform: _platformName(),
    });
  }

  Future<void> trackBackupExported({
    required bool encrypted,
    required int accountCount,
    required int accountsWithTokens,
  }) {
    return _track(KickAnalyticsEvents.backupExported, {
      'encrypted': encrypted,
      'account_count': accountCount,
      'accounts_with_tokens': accountsWithTokens,
    });
  }

  Future<void> trackBackupRestored({
    required bool wasPasswordProtected,
    required int accountCount,
    required int accountsWithoutTokens,
    String? errorKind,
  }) {
    final properties = <String, Object?>{
      'encrypted': wasPasswordProtected,
      'account_count': accountCount,
      'accounts_without_tokens': accountsWithoutTokens,
    };
    _putIfNotBlank(properties, KickAnalyticsKeys.errorKind, errorKind);
    return _track(KickAnalyticsEvents.backupRestored, properties);
  }

  Future<void> trackSillyTavernPushSucceeded() {
    return _track(KickAnalyticsEvents.sillyTavernPushSucceeded);
  }

  Future<void> trackSillyTavernPushFailed({required String failureKind, int? statusCode}) {
    final properties = <String, Object?>{'failure_kind': failureKind};
    if (statusCode != null) {
      properties[KickAnalyticsKeys.statusCode] = statusCode;
    }
    return _track(KickAnalyticsEvents.sillyTavernPushFailed, properties);
  }

  Future<void> trackLogsExported({required String target, required int entryCount}) {
    return _track(KickAnalyticsEvents.logsExported, {'target': target, 'entry_count': entryCount});
  }

  Future<void> _track(String eventName, [Map<String, Object?> properties = const {}]) async {
    await _trackEvent(eventName, properties);
  }

  Future<bool> _trackEvent(String eventName, [Map<String, Object?> properties = const {}]) async {
    if (!_trackingAllowed || !_config.isEnabled) {
      return false;
    }

    try {
      await _transport.ensureInitialized(_config);
      await _transport.track(eventName, {
        KickAnalyticsKeys.buildChannel: _config.buildChannel,
        ..._sanitizeProperties(properties),
      });
      return true;
    } catch (error, stackTrace) {
      _debugAnalyticsFailure(eventName, error, stackTrace);
      return false;
    }
  }

  static Map<String, Object?> _sanitizeProperties(Map<String, Object?> properties) {
    final sanitized = <String, Object?>{};
    for (final entry in properties.entries) {
      final value = _sanitizeValue(entry.value);
      if (value == null) {
        continue;
      }
      sanitized[entry.key] = value;
    }
    return sanitized;
  }

  static Object? _sanitizeValue(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is num) {
      return value;
    }
    if (value is bool) {
      return value;
    }
    if (value is Enum) {
      return value.name;
    }
    if (value is List) {
      final entries = <String>[];
      for (final item in value) {
        if (item is String) {
          final trimmed = item.trim();
          if (trimmed.isNotEmpty) {
            entries.add(trimmed);
          }
        }
      }
      if (entries.isEmpty) {
        return null;
      }
      return entries.join(',');
    }
    return null;
  }

  static int _bucketMs(int valueMs) {
    if (valueMs <= 0) {
      return 0;
    }
    if (valueMs < 1000) {
      return ((valueMs + 25) ~/ 50) * 50;
    }
    if (valueMs < 10000) {
      return ((valueMs + 50) ~/ 100) * 100;
    }
    return ((valueMs + 250) ~/ 500) * 500;
  }

  static void _putIfNotBlank(Map<String, Object?> properties, String key, String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return;
    }
    properties[key] = normalized;
  }

  static void _putIfPositive(Map<String, Object?> properties, String key, int? value) {
    if (value == null || value <= 0) {
      return;
    }
    properties[key] = value;
  }

  static void _putIfBool(Map<String, Object?> properties, String key, bool? value) {
    if (value == null) {
      return;
    }
    properties[key] = value;
  }

  static void _putIfNonEmptyStringList(
    Map<String, Object?> properties,
    String key,
    List<String>? values,
  ) {
    if (values == null) {
      return;
    }
    final cleaned = <String>{};
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        cleaned.add(trimmed);
      }
    }
    if (cleaned.isEmpty) {
      return;
    }
    final sorted = cleaned.toList()..sort();
    properties[key] = sorted;
  }

  static String _platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    if (Platform.isFuchsia) return 'fuchsia';
    return 'unknown';
  }

  /// Buckets a model identifier into a non-identifying family for analytics.
  ///
  /// Resolves the model through [ModelCatalog] when possible, then collapses
  /// the result into one of a few fixed family buckets. Anything that doesn't
  /// match a known family ends up under `custom` so we never leak raw model
  /// IDs from custom-model lists.
  static String modelFamily(String model) {
    final raw = model.trim().toLowerCase();
    if (raw.isEmpty) {
      return 'unknown';
    }

    final resolved = ModelCatalog.normalizePublicModel(model);
    final normalized = resolved.isEmpty ? raw : resolved.toLowerCase();

    final providerSeparator = normalized.indexOf('/');
    final provider = providerSeparator > 0 ? normalized.substring(0, providerSeparator) : null;
    final modelId = providerSeparator > 0
        ? normalized.substring(providerSeparator + 1)
        : normalized;

    if (provider == ModelCatalog.kiroProviderId) {
      return _kiroModelFamily(modelId);
    }
    if (provider == ModelCatalog.googleProviderId) {
      return _geminiModelFamily(modelId);
    }

    if (modelId.startsWith('claude-') ||
        modelId.startsWith('anthropic.') ||
        modelId.startsWith('opus-') ||
        modelId.startsWith('sonnet-') ||
        modelId.startsWith('haiku-')) {
      return _kiroModelFamily(modelId);
    }
    if (modelId.startsWith('gemini-')) {
      return _geminiModelFamily(modelId);
    }
    if (modelId == 'auto' || modelId == 'simple-task') {
      return 'kiro';
    }
    if (modelId.startsWith('deepseek-')) {
      return 'kiro-deepseek';
    }
    if (modelId.startsWith('qwen')) {
      return 'kiro-qwen';
    }
    if (modelId.startsWith('minimax-')) {
      return 'kiro-minimax';
    }
    if (modelId.startsWith('gpt-') || modelId.startsWith('openai-')) {
      return 'openai';
    }

    return 'custom';
  }

  static String _geminiModelFamily(String modelId) {
    final id = modelId.toLowerCase();
    if (id.contains('gemini-3')) {
      return 'gemini-3';
    }
    if (id.contains('2.5-flash-lite')) {
      return 'gemini-2.5-flash-lite';
    }
    if (id.contains('2.5-flash')) {
      return 'gemini-2.5-flash';
    }
    if (id.contains('2.5-pro')) {
      return 'gemini-2.5-pro';
    }
    if (id.contains('2.0-flash')) {
      return 'gemini-2.0-flash';
    }
    if (id.contains('2.0-pro')) {
      return 'gemini-2.0-pro';
    }
    if (id.startsWith('gemini-')) {
      return 'gemini-other';
    }
    return 'gemini-other';
  }

  static String _kiroModelFamily(String modelId) {
    final id = modelId.toLowerCase();
    if (id == 'auto' || id == 'simple-task') {
      return 'kiro';
    }
    if (id.contains('opus-4.7') || id.contains('opus4.7')) {
      return 'kiro-claude-opus-4.7';
    }
    if (id.contains('opus-4.5') || id.contains('opus4.5')) {
      return 'kiro-claude-opus-4.5';
    }
    if (id.contains('opus-4') || id.contains('opus4')) {
      return 'kiro-claude-opus-4';
    }
    if (id.contains('sonnet-4.5') || id.contains('sonnet4.5')) {
      return 'kiro-claude-sonnet-4.5';
    }
    if (id.contains('sonnet-4') || id.contains('sonnet4')) {
      return 'kiro-claude-sonnet-4';
    }
    if (id.contains('haiku')) {
      return 'kiro-claude-haiku';
    }
    if (id.contains('claude-')) {
      return 'kiro-claude-other';
    }
    if (id.startsWith('deepseek-')) {
      return 'kiro-deepseek';
    }
    if (id.startsWith('qwen')) {
      return 'kiro-qwen';
    }
    if (id.startsWith('minimax-')) {
      return 'kiro-minimax';
    }
    return 'kiro';
  }

  /// Returns the analytics provider tag for an [AccountProvider].
  static String providerName(AccountProvider provider) {
    return switch (provider) {
      AccountProvider.gemini => 'google',
      AccountProvider.kiro => 'kiro',
    };
  }
}

class _KickHiveStorage implements StorageManager {
  _KickHiveStorage({Future<Directory> Function()? supportDirectoryProvider})
    : _supportDirectoryProvider = supportDirectoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectoryProvider;

  Box<String>? _box;

  @override
  Future<void> init() async {
    final existingBox = _box;
    if (existingBox != null && existingBox.isOpen) {
      return;
    }

    final supportDirectory = await _supportDirectoryProvider();
    final analyticsDirectory = Directory(
      p.join(supportDirectory.path, _kickAptabaseStorageDirectoryName),
    );
    await analyticsDirectory.create(recursive: true);
    _box = await Hive.openBox<String>(_kickAptabaseBoxName, path: analyticsDirectory.path);
  }

  @override
  Future<void> deleteAllKeys(Iterable<dynamic> keys) {
    return _requireBox().deleteAll(keys);
  }

  @override
  Future<Iterable<MapEntry<dynamic, String>>> getItems(int length) async {
    return _requireBox().toMap().entries.take(length);
  }

  @override
  Future<void> add(String item) {
    return _requireBox().add(item);
  }

  Box<String> _requireBox() {
    final box = _box;
    if (box == null) {
      throw StateError('Analytics storage accessed before initialization.');
    }
    return box;
  }
}

class _InMemoryAnalyticsStorage implements StorageManager {
  final LinkedHashMap<int, String> _items = LinkedHashMap<int, String>();
  int _nextKey = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> add(String item) async {
    _items[_nextKey] = item;
    _nextKey += 1;
  }

  @override
  Future<void> deleteAllKeys(Iterable<dynamic> keys) async {
    for (final key in keys) {
      if (key is int) {
        _items.remove(key);
      }
    }
  }

  @override
  Future<Iterable<MapEntry<dynamic, String>>> getItems(int length) async {
    return _items.entries.take(length).toList(growable: false);
  }
}

void _debugAnalyticsFailure(String eventName, Object error, StackTrace stackTrace) {
  if (!kDebugMode) {
    return;
  }

  debugPrint('[analytics] $eventName failed: $error');
  debugPrint('$stackTrace');
}
