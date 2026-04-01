import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:aptabase_flutter/aptabase_flutter.dart';
import 'package:aptabase_flutter/storage_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/models/app_settings.dart';
import '../proxy/model_catalog.dart';

const _kickAptabaseBoxName = 'kick_aptabase_events';
const _kickAptabaseStorageDirectoryName = 'analytics';

bool analyticsTrackingAllowed(AppSettings settings) {
  return settings.hasAcknowledgedDisclaimer && settings.analyticsConsentEnabled;
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

abstract interface class AnalyticsTransport {
  Future<void> ensureInitialized(AnalyticsBuildConfig config);

  Future<void> track(String eventName, Map<String, Object?> properties);
}

class NoOpAnalyticsTransport implements AnalyticsTransport {
  const NoOpAnalyticsTransport();

  @override
  Future<void> ensureInitialized(AnalyticsBuildConfig config) async {}

  @override
  Future<void> track(String eventName, Map<String, Object?> properties) async {}
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
        ? InitOptions(printDebugMessages: !kReleaseMode)
        : InitOptions(host: host, printDebugMessages: !kReleaseMode);
    await Aptabase.init(config.appKey, options, storage);
  }

  @override
  Future<void> track(String eventName, Map<String, Object?> properties) {
    return Aptabase.instance.trackEvent(eventName, properties);
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

class KickAnalytics {
  KickAnalytics({
    AnalyticsBuildConfig? config,
    AnalyticsTransport? transport,
    bool trackingAllowed = false,
  }) : _config = config ?? AnalyticsBuildConfig.fromEnvironment(),
       _transport =
           transport ??
           ((config ?? AnalyticsBuildConfig.fromEnvironment()).isEnabled
               ? AptabaseAnalyticsTransport()
               : const NoOpAnalyticsTransport()),
       _trackingAllowed = trackingAllowed;

  final AnalyticsBuildConfig _config;
  final AnalyticsTransport _transport;

  bool _trackingAllowed;
  bool _firstSuccessfulRequestTracked = false;

  bool get isEnabled => _config.isEnabled;

  Future<void> setTrackingAllowed(bool value) async {
    _trackingAllowed = value;
  }

  Future<void> trackAppOpen() {
    return _track('app_open');
  }

  Future<void> trackDisclaimerAccepted({required bool analyticsEnabled}) {
    return _track('disclaimer_accepted', {'analytics_enabled': _flag(analyticsEnabled)});
  }

  Future<void> trackAccountConnectStarted({required bool reauthorization}) {
    return _track('account_connect_started', {'reauthorization': _flag(reauthorization)});
  }

  Future<void> trackAccountConnectSucceeded({
    required bool reauthorization,
    required int enabledAccounts,
  }) {
    return _track('account_connect_succeeded', {
      'reauthorization': _flag(reauthorization),
      'enabled_accounts': enabledAccounts,
    });
  }

  Future<void> trackAccountConnectFailed({
    required bool reauthorization,
    required String errorKind,
  }) {
    return _track('account_connect_failed', {
      'reauthorization': _flag(reauthorization),
      'error_kind': errorKind,
    });
  }

  Future<void> trackProxyStarted({required bool allowLan, required int activeAccounts}) {
    return _track('proxy_started', {
      'allow_lan': _flag(allowLan),
      'active_accounts': activeAccounts,
    });
  }

  Future<void> trackProxyStartFailed({required String errorKind}) {
    return _track('proxy_start_failed', {'error_kind': errorKind});
  }

  Future<void> trackFirstSuccessfulRequest({
    required String route,
    required String model,
    required bool stream,
  }) async {
    if (_firstSuccessfulRequestTracked) {
      return;
    }

    final tracked = await _trackEvent('first_successful_request', {
      'route': route,
      'model_family': modelFamily(model),
      'stream': _flag(stream),
    });
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
  }) {
    final properties = <String, Object?>{
      'route': route,
      'model_family': modelFamily(model),
      'stream': _flag(stream),
      'error_kind': errorKind,
    };
    _putIfNotBlank(properties, 'error_source', errorSource);
    if (statusCode != null) {
      properties['status_code'] = statusCode;
    }
    _putIfNotBlank(properties, 'error_detail', errorDetail);
    _putIfNotBlank(properties, 'upstream_reason', upstreamReason);
    _putIfPositive(properties, 'retry_after_ms', retryAfterMs);
    _putIfBool(properties, 'has_action_url', hasActionUrl);
    return _track('proxy_request_failed', properties);
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
  }) {
    final properties = <String, Object?>{
      'route': route,
      'model_family': modelFamily(model),
      'stream': _flag(stream),
      'outcome': outcome,
      'retry_count': retryCount,
      'upstream_retry_count': upstreamRetryCount,
      'account_failover_count': accountFailoverCount,
    };
    if (retryKinds != null && retryKinds.trim().isNotEmpty) {
      properties['retry_kinds'] = retryKinds;
    }
    if (retryDelayMs != null && retryDelayMs > 0) {
      properties['retry_delay_ms'] = retryDelayMs;
    }
    if (statusCode != null) {
      properties['status_code'] = statusCode;
    }
    _putIfNotBlank(properties, 'error_source', errorSource);
    _putIfNotBlank(properties, 'error_detail', errorDetail);
    _putIfNotBlank(properties, 'upstream_reason', upstreamReason);
    _putIfPositive(properties, 'retry_after_ms', retryAfterMs);
    _putIfBool(properties, 'has_action_url', hasActionUrl);
    return _track('proxy_request_retried', properties);
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
  }) {
    return _track('proxy_session_summary', {
      'uptime_sec': uptimeSec,
      'request_count': requestCount,
      'success_count': successCount,
      'failed_count': failedCount,
      'retried_count': retriedCount,
      'active_accounts': activeAccounts,
      'healthy_accounts': healthyAccounts,
      'request_max_retries': requestMaxRetries,
      'mark_429_as_unhealthy': _flag(mark429AsUnhealthy),
      'android_background_runtime': _flag(androidBackgroundRuntime),
      'stop_reason': stopReason,
    });
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
  }) {
    final properties = <String, Object?>{
      'issue_kind': issueKind,
      'route': route,
      'model_family': modelFamily(model),
      'stream': _flag(stream),
    };
    if (errorKind != null && errorKind.trim().isNotEmpty) {
      properties['error_kind'] = errorKind;
    }
    _putIfNotBlank(properties, 'error_source', errorSource);
    if (statusCode != null) {
      properties['status_code'] = statusCode;
    }
    _putIfNotBlank(properties, 'error_detail', errorDetail);
    _putIfNotBlank(properties, 'upstream_reason', upstreamReason);
    _putIfPositive(properties, 'retry_after_ms', retryAfterMs);
    _putIfBool(properties, 'has_action_url', hasActionUrl);
    return _track('upstream_compatibility_issue', properties);
  }

  Future<void> trackAndroidBackgroundSession({
    required int durationSec,
    required bool killedInBackground,
    required bool androidBackgroundRuntimeEnabled,
    required bool proxyWasRunning,
  }) {
    return _track('android_background_session', {
      'duration_sec': durationSec,
      'killed_in_background': _flag(killedInBackground),
      'android_background_runtime_enabled': _flag(androidBackgroundRuntimeEnabled),
      'proxy_was_running': _flag(proxyWasRunning),
    });
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
        'build_channel': _config.buildChannel,
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
      return _flag(value);
    }
    if (value is Enum) {
      return value.name;
    }
    return null;
  }

  static int _flag(bool value) => value ? 1 : 0;

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
    properties[key] = _flag(value);
  }

  @visibleForTesting
  static String modelFamily(String model) {
    final trimmed = model.trim().toLowerCase();
    if (trimmed.startsWith('kiro/') || trimmed.startsWith('kiro:')) {
      return 'kiro';
    }
    final normalized = ModelCatalog.normalizeModel(model).toLowerCase();
    if (normalized.startsWith('claude-') || normalized == 'auto') {
      return 'kiro';
    }
    if (normalized.contains('gemini-3')) {
      return 'gemini-3';
    }
    if (normalized.contains('2.5-flash')) {
      return 'gemini-2.5-flash';
    }
    if (normalized.contains('2.5-pro')) {
      return 'gemini-2.5-pro';
    }
    if (normalized.startsWith('gemini-')) {
      return 'gemini-other';
    }
    return 'custom';
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
