import 'dart:async';

import 'package:aptabase_flutter/aptabase_flutter.dart';
import 'package:flutter/foundation.dart';

import '../data/models/app_settings.dart';
import '../proxy/model_catalog.dart';

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

class AptabaseAnalyticsTransport implements AnalyticsTransport {
  Future<void>? _initialization;

  @override
  Future<void> ensureInitialized(AnalyticsBuildConfig config) {
    return _initialization ??= _initialize(config);
  }

  Future<void> _initialize(AnalyticsBuildConfig config) async {
    final host = config.host?.trim();
    final options = host == null || host.isEmpty
        ? InitOptions(printDebugMessages: !kReleaseMode)
        : InitOptions(host: host, printDebugMessages: !kReleaseMode);
    await Aptabase.init(config.appKey, options);
  }

  @override
  Future<void> track(String eventName, Map<String, Object?> properties) {
    return Aptabase.instance.trackEvent(eventName, properties);
  }
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
  }) {
    if (_firstSuccessfulRequestTracked) {
      return Future<void>.value();
    }
    _firstSuccessfulRequestTracked = true;
    return _track('first_successful_request', {
      'route': route,
      'model_family': modelFamily(model),
      'stream': _flag(stream),
    });
  }

  Future<void> trackProxyRequestFailed({
    required String route,
    required String model,
    required bool stream,
    required String errorKind,
    int? statusCode,
  }) {
    final properties = <String, Object?>{
      'route': route,
      'model_family': modelFamily(model),
      'stream': _flag(stream),
      'error_kind': errorKind,
    };
    if (statusCode != null) {
      properties['status_code'] = statusCode;
    }
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
    int? statusCode,
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
    if (statusCode != null) {
      properties['status_code'] = statusCode;
    }
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
    if (!_trackingAllowed || !_config.isEnabled) {
      return;
    }

    await _transport.ensureInitialized(_config);
    await _transport.track(eventName, {
      'build_channel': _config.buildChannel,
      ..._sanitizeProperties(properties),
    });
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

  @visibleForTesting
  static String modelFamily(String model) {
    final normalized = ModelCatalog.normalizeModel(model).toLowerCase();
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
