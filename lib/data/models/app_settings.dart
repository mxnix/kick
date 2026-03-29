import 'package:flutter/material.dart';

enum KickLogVerbosity { quiet, normal, verbose }

const _defaultRequestMaxRetries = 10;
const _minRequestMaxRetries = 0;
const _maxRequestMaxRetries = 20;
const _defaultRetry429DelaySeconds = 30;
const _minRetry429DelaySeconds = 1;
const _maxRetry429DelaySeconds = 3600;

class AppSettings {
  static const Set<String> storageKeys = {
    'api_key_required',
    'theme_mode',
    'use_dynamic_color',
    'has_acknowledged_disclaimer',
    'analytics_consent_enabled',
    'host',
    'port',
    'allow_lan',
    'android_background_runtime',
    'windows_launch_at_startup',
    'request_max_retries',
    'retry_429_delay_seconds',
    'mark_429_as_unhealthy',
    'default_google_web_search_enabled',
    'render_google_grounding_in_message',
    'logging_verbosity',
    'unsafe_raw_logging_enabled',
    'custom_models',
  };

  const AppSettings({
    required this.apiKey,
    required this.apiKeyRequired,
    required this.themeMode,
    required this.useDynamicColor,
    required this.hasAcknowledgedDisclaimer,
    required this.analyticsConsentEnabled,
    required this.host,
    required this.port,
    required this.allowLan,
    required this.androidBackgroundRuntime,
    required this.windowsLaunchAtStartup,
    required this.requestMaxRetries,
    required this.retry429DelaySeconds,
    required this.mark429AsUnhealthy,
    this.defaultGoogleWebSearchEnabled = false,
    this.renderGoogleGroundingInMessage = false,
    required this.loggingVerbosity,
    required this.unsafeRawLoggingEnabled,
    required this.customModels,
  });

  final String apiKey;
  final bool apiKeyRequired;
  final ThemeMode themeMode;
  final bool useDynamicColor;
  final bool hasAcknowledgedDisclaimer;
  final bool analyticsConsentEnabled;
  final String host;
  final int port;
  final bool allowLan;
  final bool androidBackgroundRuntime;
  final bool windowsLaunchAtStartup;
  final int requestMaxRetries;
  final int retry429DelaySeconds;
  final bool mark429AsUnhealthy;
  final bool defaultGoogleWebSearchEnabled;
  final bool renderGoogleGroundingInMessage;
  final KickLogVerbosity loggingVerbosity;
  final bool unsafeRawLoggingEnabled;
  final List<String> customModels;

  static AppSettings defaults({required String apiKey}) {
    return AppSettings(
      apiKey: apiKey,
      apiKeyRequired: true,
      themeMode: ThemeMode.system,
      useDynamicColor: true,
      hasAcknowledgedDisclaimer: false,
      analyticsConsentEnabled: false,
      host: '127.0.0.1',
      port: 3000,
      allowLan: false,
      androidBackgroundRuntime: true,
      windowsLaunchAtStartup: false,
      requestMaxRetries: _defaultRequestMaxRetries,
      retry429DelaySeconds: _defaultRetry429DelaySeconds,
      mark429AsUnhealthy: false,
      defaultGoogleWebSearchEnabled: false,
      renderGoogleGroundingInMessage: false,
      loggingVerbosity: KickLogVerbosity.normal,
      unsafeRawLoggingEnabled: false,
      customModels: const [],
    );
  }

  AppSettings copyWith({
    String? apiKey,
    bool? apiKeyRequired,
    ThemeMode? themeMode,
    bool? useDynamicColor,
    bool? hasAcknowledgedDisclaimer,
    bool? analyticsConsentEnabled,
    String? host,
    int? port,
    bool? allowLan,
    bool? androidBackgroundRuntime,
    bool? windowsLaunchAtStartup,
    int? requestMaxRetries,
    int? retry429DelaySeconds,
    bool? mark429AsUnhealthy,
    bool? defaultGoogleWebSearchEnabled,
    bool? renderGoogleGroundingInMessage,
    KickLogVerbosity? loggingVerbosity,
    bool? unsafeRawLoggingEnabled,
    List<String>? customModels,
  }) {
    final resolvedAllowLan = allowLan ?? this.allowLan;
    return AppSettings(
      apiKey: apiKey ?? this.apiKey,
      apiKeyRequired: apiKeyRequired ?? this.apiKeyRequired,
      themeMode: themeMode ?? this.themeMode,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      hasAcknowledgedDisclaimer: hasAcknowledgedDisclaimer ?? this.hasAcknowledgedDisclaimer,
      analyticsConsentEnabled: analyticsConsentEnabled ?? this.analyticsConsentEnabled,
      host: _normalizeHost(host ?? this.host, allowLan: resolvedAllowLan),
      port: port ?? this.port,
      allowLan: resolvedAllowLan,
      androidBackgroundRuntime: androidBackgroundRuntime ?? this.androidBackgroundRuntime,
      windowsLaunchAtStartup: windowsLaunchAtStartup ?? this.windowsLaunchAtStartup,
      requestMaxRetries: _normalizeRequestMaxRetries(requestMaxRetries ?? this.requestMaxRetries),
      retry429DelaySeconds: _normalizeRetry429DelaySeconds(
        retry429DelaySeconds ?? this.retry429DelaySeconds,
      ),
      mark429AsUnhealthy: mark429AsUnhealthy ?? this.mark429AsUnhealthy,
      defaultGoogleWebSearchEnabled:
          defaultGoogleWebSearchEnabled ?? this.defaultGoogleWebSearchEnabled,
      renderGoogleGroundingInMessage:
          renderGoogleGroundingInMessage ?? this.renderGoogleGroundingInMessage,
      loggingVerbosity: loggingVerbosity ?? this.loggingVerbosity,
      unsafeRawLoggingEnabled: unsafeRawLoggingEnabled ?? this.unsafeRawLoggingEnabled,
      customModels: customModels ?? this.customModels,
    );
  }

  Map<String, String> toStorageMap() {
    return {
      'api_key_required': apiKeyRequired.toString(),
      'theme_mode': themeMode.name,
      'use_dynamic_color': useDynamicColor.toString(),
      'has_acknowledged_disclaimer': hasAcknowledgedDisclaimer.toString(),
      'analytics_consent_enabled': analyticsConsentEnabled.toString(),
      'host': host,
      'port': port.toString(),
      'allow_lan': allowLan.toString(),
      'android_background_runtime': androidBackgroundRuntime.toString(),
      'windows_launch_at_startup': windowsLaunchAtStartup.toString(),
      'request_max_retries': requestMaxRetries.toString(),
      'retry_429_delay_seconds': retry429DelaySeconds.toString(),
      'mark_429_as_unhealthy': mark429AsUnhealthy.toString(),
      'default_google_web_search_enabled': defaultGoogleWebSearchEnabled.toString(),
      'render_google_grounding_in_message': renderGoogleGroundingInMessage.toString(),
      'logging_verbosity': loggingVerbosity.name,
      'unsafe_raw_logging_enabled': unsafeRawLoggingEnabled.toString(),
      'custom_models': customModels.join('\n'),
    };
  }

  factory AppSettings.fromStorageMap(Map<String, String> values, {required String apiKey}) {
    final allowLan = values['allow_lan'] == 'true';
    return AppSettings(
      apiKey: apiKey,
      apiKeyRequired: values['api_key_required'] != 'false',
      themeMode: ThemeMode.values.firstWhere(
        (value) => value.name == values['theme_mode'],
        orElse: () => ThemeMode.system,
      ),
      useDynamicColor: values['use_dynamic_color'] != 'false',
      hasAcknowledgedDisclaimer: values['has_acknowledged_disclaimer'] == 'true',
      analyticsConsentEnabled: values['analytics_consent_enabled'] == 'true',
      host: _normalizeHost(values['host'], allowLan: allowLan),
      port: int.tryParse(values['port'] ?? '') ?? 3000,
      allowLan: allowLan,
      androidBackgroundRuntime: values['android_background_runtime'] != 'false',
      windowsLaunchAtStartup: values['windows_launch_at_startup'] == 'true',
      requestMaxRetries: _normalizeRequestMaxRetries(
        int.tryParse(values['request_max_retries'] ?? ''),
      ),
      retry429DelaySeconds: _normalizeRetry429DelaySeconds(
        int.tryParse(values['retry_429_delay_seconds'] ?? ''),
      ),
      mark429AsUnhealthy: values['mark_429_as_unhealthy'] == 'true',
      defaultGoogleWebSearchEnabled: values['default_google_web_search_enabled'] == 'true',
      renderGoogleGroundingInMessage: values['render_google_grounding_in_message'] == 'true',
      loggingVerbosity: KickLogVerbosity.values.firstWhere(
        (value) => value.name == values['logging_verbosity'],
        orElse: () => KickLogVerbosity.normal,
      ),
      unsafeRawLoggingEnabled: values['unsafe_raw_logging_enabled'] == 'true',
      customModels: (values['custom_models'] ?? '')
          .split('\n')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
  }
}

String _normalizeHost(String? value, {required bool allowLan}) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return '127.0.0.1';
  }
  if (!allowLan && trimmed == '0.0.0.0') {
    return '127.0.0.1';
  }
  return trimmed;
}

int _normalizeRequestMaxRetries(int? value) {
  if (value == null) {
    return _defaultRequestMaxRetries;
  }
  if (value < _minRequestMaxRetries) {
    return _minRequestMaxRetries;
  }
  if (value > _maxRequestMaxRetries) {
    return _maxRequestMaxRetries;
  }
  return value;
}

int _normalizeRetry429DelaySeconds(int? value) {
  if (value == null) {
    return _defaultRetry429DelaySeconds;
  }
  if (value < _minRetry429DelaySeconds) {
    return _minRetry429DelaySeconds;
  }
  if (value > _maxRetry429DelaySeconds) {
    return _maxRetry429DelaySeconds;
  }
  return value;
}
