import 'package:flutter/material.dart';

enum KickLogVerbosity { quiet, normal, verbose }

const _defaultRequestMaxRetries = 10;
const _minRequestMaxRetries = 0;
const _maxRequestMaxRetries = 20;

class AppSettings {
  const AppSettings({
    required this.apiKey,
    required this.apiKeyRequired,
    required this.themeMode,
    required this.useDynamicColor,
    required this.hasAcknowledgedDisclaimer,
    required this.analyticsConsentEnabled,
    required this.autoCheckUpdatesEnabled,
    required this.host,
    required this.port,
    required this.allowLan,
    required this.androidBackgroundRuntime,
    required this.requestMaxRetries,
    required this.mark429AsUnhealthy,
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
  final bool autoCheckUpdatesEnabled;
  final String host;
  final int port;
  final bool allowLan;
  final bool androidBackgroundRuntime;
  final int requestMaxRetries;
  final bool mark429AsUnhealthy;
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
      autoCheckUpdatesEnabled: true,
      host: '127.0.0.1',
      port: 3000,
      allowLan: false,
      androidBackgroundRuntime: true,
      requestMaxRetries: _defaultRequestMaxRetries,
      mark429AsUnhealthy: false,
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
    bool? autoCheckUpdatesEnabled,
    String? host,
    int? port,
    bool? allowLan,
    bool? androidBackgroundRuntime,
    int? requestMaxRetries,
    bool? mark429AsUnhealthy,
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
      autoCheckUpdatesEnabled: autoCheckUpdatesEnabled ?? this.autoCheckUpdatesEnabled,
      host: _normalizeHost(host ?? this.host, allowLan: resolvedAllowLan),
      port: port ?? this.port,
      allowLan: resolvedAllowLan,
      androidBackgroundRuntime: androidBackgroundRuntime ?? this.androidBackgroundRuntime,
      requestMaxRetries: _normalizeRequestMaxRetries(requestMaxRetries ?? this.requestMaxRetries),
      mark429AsUnhealthy: mark429AsUnhealthy ?? this.mark429AsUnhealthy,
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
      'auto_check_updates_enabled': autoCheckUpdatesEnabled.toString(),
      'host': host,
      'port': port.toString(),
      'allow_lan': allowLan.toString(),
      'android_background_runtime': androidBackgroundRuntime.toString(),
      'request_max_retries': requestMaxRetries.toString(),
      'mark_429_as_unhealthy': mark429AsUnhealthy.toString(),
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
      analyticsConsentEnabled: values['analytics_consent_enabled'] != 'false',
      autoCheckUpdatesEnabled: values['auto_check_updates_enabled'] != 'false',
      host: _normalizeHost(values['host'], allowLan: allowLan),
      port: int.tryParse(values['port'] ?? '') ?? 3000,
      allowLan: allowLan,
      androidBackgroundRuntime: values['android_background_runtime'] != 'false',
      requestMaxRetries: _normalizeRequestMaxRetries(
        int.tryParse(values['request_max_retries'] ?? ''),
      ),
      mark429AsUnhealthy: values['mark_429_as_unhealthy'] == 'true',
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
