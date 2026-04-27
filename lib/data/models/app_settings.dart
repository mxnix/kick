import 'package:flutter/material.dart';

enum KickLogVerbosity { quiet, normal, verbose }

const defaultLogRetentionCount = 500;
const minLogRetentionCount = 1;
const maxLogRetentionCount = 50000;
const _systemAppLocaleStorageValue = 'system';
const Object _appLocaleUnset = Object();
const _defaultRequestMaxRetries = 10;
const _minRequestMaxRetries = 0;
const _maxRequestMaxRetries = 20;
const _defaultRetry429DelaySeconds = 30;
const _minRetry429DelaySeconds = 1;
const _maxRetry429DelaySeconds = 3600;
const _defaultProxyHost = '127.0.0.1';
const _defaultProxyPort = 3000;
const _minProxyPort = 1;
const _maxProxyPort = 65535;

class AppSettings {
  static const Set<String> storageKeys = {
    'api_key_required',
    'app_locale',
    'theme_mode',
    'use_system_font',
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
    'log_retention_count',
    'unsafe_raw_logging_enabled',
    'custom_models',
  };

  const AppSettings({
    required this.apiKey,
    required this.apiKeyRequired,
    this.appLocale,
    required this.themeMode,
    required this.useSystemFont,
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
    required this.logRetentionCount,
    required this.unsafeRawLoggingEnabled,
    required this.customModels,
  });

  final String apiKey;
  final bool apiKeyRequired;
  final Locale? appLocale;
  final ThemeMode themeMode;
  final bool useSystemFont;
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
  final int logRetentionCount;
  final bool unsafeRawLoggingEnabled;
  final List<String> customModels;

  static AppSettings defaults({required String apiKey}) {
    return AppSettings(
      apiKey: apiKey,
      apiKeyRequired: true,
      appLocale: null,
      themeMode: ThemeMode.system,
      useSystemFont: false,
      useDynamicColor: true,
      hasAcknowledgedDisclaimer: false,
      analyticsConsentEnabled: false,
      host: _defaultProxyHost,
      port: _defaultProxyPort,
      allowLan: false,
      androidBackgroundRuntime: true,
      windowsLaunchAtStartup: false,
      requestMaxRetries: _defaultRequestMaxRetries,
      retry429DelaySeconds: _defaultRetry429DelaySeconds,
      mark429AsUnhealthy: false,
      defaultGoogleWebSearchEnabled: false,
      renderGoogleGroundingInMessage: false,
      loggingVerbosity: KickLogVerbosity.normal,
      logRetentionCount: defaultLogRetentionCount,
      unsafeRawLoggingEnabled: false,
      customModels: const [],
    );
  }

  AppSettings copyWith({
    String? apiKey,
    bool? apiKeyRequired,
    Object? appLocale = _appLocaleUnset,
    ThemeMode? themeMode,
    bool? useSystemFont,
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
    int? logRetentionCount,
    bool? unsafeRawLoggingEnabled,
    List<String>? customModels,
  }) {
    final resolvedAllowLan = allowLan ?? this.allowLan;
    return AppSettings(
      apiKey: apiKey ?? this.apiKey,
      apiKeyRequired: apiKeyRequired ?? this.apiKeyRequired,
      appLocale: identical(appLocale, _appLocaleUnset)
          ? this.appLocale
          : _normalizeAppLocale(appLocale as Locale?),
      themeMode: themeMode ?? this.themeMode,
      useSystemFont: useSystemFont ?? this.useSystemFont,
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
      logRetentionCount: normalizeLogRetentionCount(logRetentionCount ?? this.logRetentionCount),
      unsafeRawLoggingEnabled: unsafeRawLoggingEnabled ?? this.unsafeRawLoggingEnabled,
      customModels: customModels ?? this.customModels,
    );
  }

  Map<String, String> toStorageMap() {
    return {
      'api_key_required': apiKeyRequired.toString(),
      'app_locale': _appLocaleToStorageValue(appLocale),
      'theme_mode': themeMode.name,
      'use_system_font': useSystemFont.toString(),
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
      'log_retention_count': logRetentionCount.toString(),
      'unsafe_raw_logging_enabled': unsafeRawLoggingEnabled.toString(),
      'custom_models': customModels.join('\n'),
    };
  }

  Map<String, Object?> toBackupJson() {
    return {
      'api_key': apiKey,
      'api_key_required': apiKeyRequired,
      'app_locale': _appLocaleToStorageValue(appLocale),
      'theme_mode': themeMode.name,
      'use_system_font': useSystemFont,
      'use_dynamic_color': useDynamicColor,
      'has_acknowledged_disclaimer': hasAcknowledgedDisclaimer,
      'analytics_consent_enabled': analyticsConsentEnabled,
      'host': host,
      'port': port,
      'allow_lan': allowLan,
      'android_background_runtime': androidBackgroundRuntime,
      'windows_launch_at_startup': windowsLaunchAtStartup,
      'request_max_retries': requestMaxRetries,
      'retry_429_delay_seconds': retry429DelaySeconds,
      'mark_429_as_unhealthy': mark429AsUnhealthy,
      'default_google_web_search_enabled': defaultGoogleWebSearchEnabled,
      'render_google_grounding_in_message': renderGoogleGroundingInMessage,
      'logging_verbosity': loggingVerbosity.name,
      'log_retention_count': logRetentionCount,
      'unsafe_raw_logging_enabled': unsafeRawLoggingEnabled,
      'custom_models': List<String>.from(customModels),
    };
  }

  factory AppSettings.fromBackupJson(Map<String, Object?> json) {
    final apiKey = _readRequiredString(json['api_key'], fieldName: 'api_key');
    final allowLan = _readBool(json['allow_lan'], defaultValue: false);
    return AppSettings(
      apiKey: apiKey,
      apiKeyRequired: _readBool(json['api_key_required'], defaultValue: true),
      appLocale: _readAppLocale(json['app_locale']),
      themeMode: ThemeMode.values.firstWhere(
        (value) => value.name == json['theme_mode'],
        orElse: () => ThemeMode.system,
      ),
      useSystemFont: _readBool(json['use_system_font'], defaultValue: false),
      useDynamicColor: _readBool(json['use_dynamic_color'], defaultValue: true),
      hasAcknowledgedDisclaimer: _readBool(
        json['has_acknowledged_disclaimer'],
        defaultValue: false,
      ),
      analyticsConsentEnabled: _readBool(json['analytics_consent_enabled'], defaultValue: false),
      host: _normalizeHost(_readString(json['host']), allowLan: allowLan),
      port: _normalizeUserPort(_readInt(json['port'])),
      allowLan: allowLan,
      androidBackgroundRuntime: _readBool(json['android_background_runtime'], defaultValue: true),
      windowsLaunchAtStartup: _readBool(json['windows_launch_at_startup'], defaultValue: false),
      requestMaxRetries: _normalizeRequestMaxRetries(_readInt(json['request_max_retries'])),
      retry429DelaySeconds: _normalizeRetry429DelaySeconds(
        _readInt(json['retry_429_delay_seconds']),
      ),
      mark429AsUnhealthy: _readBool(json['mark_429_as_unhealthy'], defaultValue: false),
      defaultGoogleWebSearchEnabled: _readBool(
        json['default_google_web_search_enabled'],
        defaultValue: false,
      ),
      renderGoogleGroundingInMessage: _readBool(
        json['render_google_grounding_in_message'],
        defaultValue: false,
      ),
      loggingVerbosity: KickLogVerbosity.values.firstWhere(
        (value) => value.name == json['logging_verbosity'],
        orElse: () => KickLogVerbosity.normal,
      ),
      logRetentionCount: normalizeLogRetentionCount(_readInt(json['log_retention_count'])),
      unsafeRawLoggingEnabled: _readBool(json['unsafe_raw_logging_enabled'], defaultValue: false),
      customModels: _readStringList(json['custom_models']),
    );
  }

  factory AppSettings.fromStorageMap(Map<String, String> values, {required String apiKey}) {
    final allowLan = values['allow_lan'] == 'true';
    return AppSettings(
      apiKey: apiKey,
      apiKeyRequired: values['api_key_required'] != 'false',
      appLocale: _readAppLocale(values['app_locale']),
      themeMode: ThemeMode.values.firstWhere(
        (value) => value.name == values['theme_mode'],
        orElse: () => ThemeMode.system,
      ),
      useSystemFont: values['use_system_font'] == 'true',
      useDynamicColor: values['use_dynamic_color'] != 'false',
      hasAcknowledgedDisclaimer: values['has_acknowledged_disclaimer'] == 'true',
      analyticsConsentEnabled: values['analytics_consent_enabled'] == 'true',
      host: _normalizeHost(values['host'], allowLan: allowLan),
      port: _normalizeUserPort(int.tryParse(values['port'] ?? '')),
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
      logRetentionCount: normalizeLogRetentionCount(
        int.tryParse(values['log_retention_count'] ?? ''),
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

String _appLocaleToStorageValue(Locale? value) {
  return _normalizeAppLocale(value)?.languageCode ?? _systemAppLocaleStorageValue;
}

Locale? _normalizeAppLocale(Locale? value) {
  final languageCode = value?.languageCode.trim().toLowerCase();
  return switch (languageCode) {
    'en' => const Locale('en'),
    'ru' => const Locale('ru'),
    _ => null,
  };
}

String _normalizeHost(String? value, {required bool allowLan}) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return _defaultProxyHost;
  }
  if (_looksLikeHostWithSchemeOrPath(trimmed)) {
    return _defaultProxyHost;
  }
  if (!allowLan && trimmed == '0.0.0.0') {
    return _defaultProxyHost;
  }
  return trimmed;
}

bool _looksLikeHostWithSchemeOrPath(String value) {
  return value.contains('://') ||
      value.contains('/') ||
      value.contains('\\') ||
      value.contains('?') ||
      value.contains('#') ||
      RegExp(r'\s').hasMatch(value);
}

int _normalizeUserPort(int? value) {
  if (value == null || value < _minProxyPort || value > _maxProxyPort) {
    return _defaultProxyPort;
  }
  return value;
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

int normalizeLogRetentionCount(int? value) {
  if (value == null) {
    return defaultLogRetentionCount;
  }
  if (value < minLogRetentionCount) {
    return minLogRetentionCount;
  }
  if (value > maxLogRetentionCount) {
    return maxLogRetentionCount;
  }
  return value;
}

String _readRequiredString(Object? value, {required String fieldName}) {
  final text = _readString(value);
  if (text == null || text.isEmpty) {
    throw FormatException('Backup settings are missing "$fieldName".');
  }
  return text;
}

String? _readString(Object? value) {
  return switch (value) {
    String text => text.trim(),
    _ => null,
  };
}

Locale? _readAppLocale(Object? value) {
  final text = _readString(value);
  if (text == null || text.isEmpty || text.toLowerCase() == _systemAppLocaleStorageValue) {
    return null;
  }

  final languageCode = text.replaceAll('_', '-').split('-').first;
  return _normalizeAppLocale(Locale(languageCode));
}

bool _readBool(Object? value, {required bool defaultValue}) {
  return switch (value) {
    bool flag => flag,
    String text => text.trim().toLowerCase() == 'true',
    num number => number != 0,
    _ => defaultValue,
  };
}

int? _readInt(Object? value) {
  return switch (value) {
    int number => number,
    num number => number.round(),
    String text => int.tryParse(text.trim()),
    _ => null,
  };
}

List<String> _readStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
