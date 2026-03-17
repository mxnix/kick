import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../app/app_metadata.dart';
import '../core/logging/log_sanitizer.dart';
import '../data/models/app_log_entry.dart';

const _defaultGlitchTipTracesSampleRate = 0.0;
const _maxSanitizedStringLength = 4096;
const _reportableProxyLogCategories = <String>{
  'chat.completions',
  'responses',
  'proxy.runtime',
  'proxy.unhandled',
};

final GlitchTipBuildConfig _glitchTipBuildConfig = GlitchTipBuildConfig.fromEnvironment();

class GlitchTipBuildConfig {
  const GlitchTipBuildConfig({
    required this.buildChannel,
    required this.dsn,
    required this.environment,
    required this.release,
    required this.tracesSampleRate,
  });

  final String buildChannel;
  final String dsn;
  final String environment;
  final String release;
  final double tracesSampleRate;

  bool get isEnabled => dsn.trim().isNotEmpty;

  static GlitchTipBuildConfig fromEnvironment() {
    const dsn = String.fromEnvironment('SENTRY_DSN');
    const environment = String.fromEnvironment('SENTRY_ENVIRONMENT');
    const release = String.fromEnvironment('SENTRY_RELEASE');
    const tracesSampleRate = String.fromEnvironment('KICK_GLITCHTIP_TRACES_SAMPLE_RATE');

    return resolve(
      isReleaseMode: kReleaseMode,
      dsn: dsn,
      environment: environment,
      release: release,
      tracesSampleRate: tracesSampleRate,
    );
  }

  @visibleForTesting
  static GlitchTipBuildConfig resolve({
    required bool isReleaseMode,
    required String dsn,
    String environment = '',
    String release = '',
    String tracesSampleRate = '',
  }) {
    final buildChannel = isReleaseMode ? 'release' : 'debug';
    final trimmedEnvironment = environment.trim();
    final trimmedRelease = release.trim();

    return GlitchTipBuildConfig(
      buildChannel: buildChannel,
      dsn: dsn.trim(),
      environment: trimmedEnvironment.isEmpty ? buildChannel : trimmedEnvironment,
      release: trimmedRelease.isEmpty ? 'kick@$kickBuildAppVersion' : trimmedRelease,
      tracesSampleRate: _normalizeSampleRate(tracesSampleRate),
    );
  }
}

Future<void> runKickWithGlitchTip(FutureOr<void> Function() appRunner) async {
  if (!_glitchTipBuildConfig.isEnabled) {
    await appRunner();
    return;
  }

  await SentryFlutter.init((options) {
    options.dsn = _glitchTipBuildConfig.dsn;
    options.environment = _glitchTipBuildConfig.environment;
    options.release = _glitchTipBuildConfig.release;
    options.debug = !kReleaseMode;
    options.sendDefaultPii = false;
    options.attachStacktrace = true;
    options.attachThreads = true;
    options.enableLogs = false;
    options.enablePrintBreadcrumbs = false;
    options.enableAutoSessionTracking = false;
    options.maxBreadcrumbs = 100;
    options.beforeBreadcrumb = _sanitizeBreadcrumb;
    options.beforeSend = _sanitizeEvent;
    if (_glitchTipBuildConfig.tracesSampleRate > 0) {
      options.tracesSampleRate = _glitchTipBuildConfig.tracesSampleRate;
    }
  }, appRunner: appRunner);
}

Widget wrapWithGlitchTip({required Widget child}) {
  if (!_glitchTipBuildConfig.isEnabled) {
    return child;
  }
  return SentryWidget(child: child);
}

List<NavigatorObserver> glitchTipNavigatorObservers() {
  if (!_glitchTipBuildConfig.isEnabled) {
    return const <NavigatorObserver>[];
  }
  return <NavigatorObserver>[SentryNavigatorObserver()];
}

Future<void> captureGlitchTipException({
  required Object error,
  StackTrace? stackTrace,
  required String source,
  String? message,
  SentryLevel level = SentryLevel.error,
  Map<String, String> tags = const <String, String>{},
  Map<String, Object?> data = const <String, Object?>{},
  List<String>? fingerprint,
}) async {
  if (!Sentry.isEnabled) {
    return;
  }

  final sanitizedData = _sanitizeContextMap(data);
  final sanitizedMessage = message == null ? null : LogSanitizer.sanitizeText(message);

  await Sentry.captureException(
    error,
    stackTrace: stackTrace,
    message: sanitizedMessage == null ? null : SentryMessage(sanitizedMessage),
    withScope: (scope) async {
      scope.level = level;
      if (fingerprint != null && fingerprint.isNotEmpty) {
        scope.fingerprint = fingerprint;
      }
      await scope.setTag('source', source);
      for (final entry in tags.entries) {
        await scope.setTag(entry.key, LogSanitizer.sanitizeText(entry.value));
      }
      if (sanitizedData.isNotEmpty) {
        await scope.setContexts('kick', sanitizedData);
      }
    },
  );
}

Future<void> captureGlitchTipMessage({
  required String message,
  required String source,
  SentryLevel level = SentryLevel.error,
  String? template,
  Map<String, String> tags = const <String, String>{},
  Map<String, Object?> data = const <String, Object?>{},
  List<String>? fingerprint,
}) async {
  if (!Sentry.isEnabled) {
    return;
  }

  final sanitizedMessage = LogSanitizer.sanitizeText(message);
  final sanitizedTemplate = template == null ? null : LogSanitizer.sanitizeText(template);
  final sanitizedData = _sanitizeContextMap(data);

  await Sentry.captureMessage(
    sanitizedMessage,
    level: level,
    template: sanitizedTemplate,
    withScope: (scope) async {
      if (fingerprint != null && fingerprint.isNotEmpty) {
        scope.fingerprint = fingerprint;
      }
      await scope.setTag('source', source);
      for (final entry in tags.entries) {
        await scope.setTag(entry.key, LogSanitizer.sanitizeText(entry.value));
      }
      if (sanitizedData.isNotEmpty) {
        await scope.setContexts('kick', sanitizedData);
      }
    },
  );
}

Future<void> recordGlitchTipProxyLog(AppLogEntry entry) async {
  if (!Sentry.isEnabled) {
    return;
  }

  final breadcrumbData = _proxyLogContext(entry);
  await Sentry.addBreadcrumb(
    Breadcrumb(
      message: LogSanitizer.sanitizeText(entry.message),
      category: entry.category,
      level: _sentryLevelForLog(entry.level),
      data: breadcrumbData.isEmpty ? null : breadcrumbData,
      type: 'default',
    ),
  );

  if (!shouldCaptureGlitchTipProxyLog(entry)) {
    return;
  }

  await captureGlitchTipMessage(
    message: glitchTipProxyLogEventMessage(entry),
    template: glitchTipProxyLogEventMessage(entry),
    source: 'proxy_log',
    level: _sentryLevelForLog(entry.level),
    tags: <String, String>{
      'log_category': entry.category,
      if (entry.route != null) 'route': entry.route!,
    },
    data: <String, Object?>{
      ...breadcrumbData,
      'log_message': LogSanitizer.sanitizeText(entry.message),
    },
    fingerprint: <String>['kick-proxy', entry.category, entry.route ?? 'none'],
  );
}

@visibleForTesting
bool shouldCaptureGlitchTipProxyLog(AppLogEntry entry) {
  return entry.level == AppLogLevel.error && _reportableProxyLogCategories.contains(entry.category);
}

@visibleForTesting
String glitchTipProxyLogEventMessage(AppLogEntry entry) {
  return switch (entry.category) {
    'proxy.unhandled' => 'Unhandled proxy isolate error',
    'proxy.runtime' => 'Proxy runtime error',
    'chat.completions' => 'Gemini chat completion request failed',
    'responses' => 'Gemini responses request failed',
    _ => 'KiCk proxy error',
  };
}

SentryEvent? _sanitizeEvent(SentryEvent event, Hint hint) {
  event.message = event.message == null ? null : _sanitizeSentryMessage(event.message!);
  event.tags = _sanitizeTagMap(event.tags);
  event.breadcrumbs = event.breadcrumbs
      ?.map((breadcrumb) => _sanitizeBreadcrumb(breadcrumb, hint))
      .whereType<Breadcrumb>()
      .toList(growable: false);
  event.exceptions = event.exceptions?.map(_sanitizeSentryException).toList(growable: false);
  event.request = null;
  event.user = null;
  return event;
}

Breadcrumb? _sanitizeBreadcrumb(Breadcrumb? breadcrumb, Hint hint) {
  if (breadcrumb == null) {
    return null;
  }

  breadcrumb.message = breadcrumb.message == null
      ? null
      : LogSanitizer.sanitizeText(breadcrumb.message!);
  breadcrumb.data = _sanitizeDynamicMap(breadcrumb.data);
  return breadcrumb;
}

SentryMessage _sanitizeSentryMessage(SentryMessage message) {
  message.formatted = LogSanitizer.sanitizeText(message.formatted);
  message.template = message.template == null ? null : LogSanitizer.sanitizeText(message.template!);
  return message;
}

SentryException _sanitizeSentryException(SentryException exception) {
  exception.value = exception.value == null ? null : LogSanitizer.sanitizeText(exception.value!);
  return exception;
}

Map<String, String>? _sanitizeTagMap(Map<String, String>? values) {
  if (values == null || values.isEmpty) {
    return null;
  }

  final sanitized = <String, String>{};
  for (final entry in values.entries) {
    sanitized[entry.key] = LogSanitizer.sanitizeText(entry.value);
  }
  return sanitized;
}

Map<String, dynamic>? _sanitizeDynamicMap(Map<String, dynamic>? values) {
  if (values == null || values.isEmpty) {
    return null;
  }

  final sanitized = _sanitizeContextMap(values);
  return sanitized.isEmpty ? null : sanitized;
}

Map<String, dynamic> _sanitizeContextMap(Map<String, Object?> values) {
  final sanitized = <String, dynamic>{};
  for (final entry in values.entries) {
    final key = entry.key.trim();
    if (key.isEmpty) {
      continue;
    }
    final value = _sanitizeContextValue(entry.value);
    if (value == null) {
      continue;
    }
    sanitized[key] = value;
  }
  return sanitized;
}

dynamic _sanitizeContextValue(Object? value) {
  final sanitized = LogSanitizer.sanitizeJsonValue(value);
  return _normalizeSanitizedValue(sanitized);
}

dynamic _normalizeSanitizedValue(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is bool || value is num) {
    return value;
  }
  if (value is String) {
    final sanitized = LogSanitizer.sanitizeText(value);
    if (sanitized.length <= _maxSanitizedStringLength) {
      return sanitized;
    }
    return '${sanitized.substring(0, _maxSanitizedStringLength)}...';
  }
  if (value is List) {
    final items = value
        .map(_normalizeSanitizedValue)
        .where((item) => item != null)
        .toList(growable: false);
    return items.isEmpty ? null : items;
  }
  if (value is Map) {
    final map = <String, dynamic>{};
    for (final entry in value.entries) {
      final normalized = _normalizeSanitizedValue(entry.value);
      if (normalized == null) {
        continue;
      }
      map[entry.key.toString()] = normalized;
    }
    return map.isEmpty ? null : map;
  }
  return LogSanitizer.sanitizeText(value.toString());
}

Map<String, dynamic> _proxyLogContext(AppLogEntry entry) {
  final context = <String, dynamic>{
    'level': entry.level.name,
    'category': entry.category,
    if (entry.route != null) 'route': entry.route,
  };

  final payload = _decodeMaskedPayload(entry.maskedPayload);
  if (payload != null) {
    context['masked_payload'] = payload;
  }

  return context;
}

dynamic _decodeMaskedPayload(String? payload) {
  final sanitized = LogSanitizer.sanitizeSerializedPayload(payload);
  if (sanitized == null || sanitized.isEmpty) {
    return null;
  }

  try {
    return _normalizeSanitizedValue(jsonDecode(sanitized));
  } catch (_) {
    return _normalizeSanitizedValue(sanitized);
  }
}

SentryLevel _sentryLevelForLog(AppLogLevel level) {
  return switch (level) {
    AppLogLevel.info => SentryLevel.info,
    AppLogLevel.warning => SentryLevel.warning,
    AppLogLevel.error => SentryLevel.error,
  };
}

double _normalizeSampleRate(String raw) {
  final parsed = double.tryParse(raw.trim());
  if (parsed == null) {
    return _defaultGlitchTipTracesSampleRate;
  }
  if (parsed < 0) {
    return 0.0;
  }
  if (parsed > 1) {
    return 1.0;
  }
  return parsed;
}
