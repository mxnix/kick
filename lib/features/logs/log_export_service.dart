import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../analytics/android_background_session_log.dart';
import '../../core/logging/log_sanitizer.dart';
import '../../data/models/app_log_entry.dart';
import '../../data/models/app_settings.dart';
import '../../l10n/kick_localizations.dart';
import 'log_message_localizer.dart';

typedef LogExportDirectoryResolver = Future<Directory> Function();
typedef LogShareCallback = Future<ShareResult> Function(ShareParams params);
typedef LogSaveFileCallback =
    Future<String?> Function({
      required String fileName,
      required Uint8List bytes,
      String? dialogTitle,
    });

class LogExportResult {
  const LogExportResult({required this.fileName, required this.contents, this.file});

  final String fileName;
  final String contents;
  final File? file;
}

class LogExportMetadata {
  const LogExportMetadata({
    this.appVersion,
    this.locale,
    this.query,
    this.level,
    this.category,
    this.retainedEntries,
    this.matchingEntries,
    this.retentionLimit,
    this.loggingVerbosity,
    this.unsafeRawLoggingEnabled,
    this.requestMaxRetries,
    this.retry429DelaySeconds,
    this.mark429AsUnhealthy,
    this.androidBackgroundRuntime,
  });

  final String? appVersion;
  final String? locale;
  final String? query;
  final AppLogLevel? level;
  final String? category;
  final int? retainedEntries;
  final int? matchingEntries;
  final int? retentionLimit;
  final KickLogVerbosity? loggingVerbosity;
  final bool? unsafeRawLoggingEnabled;
  final int? requestMaxRetries;
  final int? retry429DelaySeconds;
  final bool? mark429AsUnhealthy;
  final bool? androidBackgroundRuntime;
}

class LogExportService {
  LogExportService({
    LogExportDirectoryResolver? exportDirectoryResolver,
    LogShareCallback? shareCallback,
    LogSaveFileCallback? saveFileCallback,
    bool? useNativeSaveDialog,
  }) : _exportDirectoryResolver = exportDirectoryResolver ?? _defaultExportDirectory,
       _shareCallback = shareCallback ?? _defaultShare,
       _saveFileCallback = saveFileCallback ?? _defaultSaveFile,
       _useNativeSaveDialog =
           useNativeSaveDialog ?? (Platform.isAndroid || Platform.isWindows || Platform.isLinux);

  final LogExportDirectoryResolver _exportDirectoryResolver;
  final LogShareCallback _shareCallback;
  final LogSaveFileCallback _saveFileCallback;
  final bool _useNativeSaveDialog;

  Future<LogExportResult?> export(
    List<AppLogEntry> entries, {
    String? dialogTitle,
    LogExportMetadata? metadata,
  }) async {
    if (entries.isEmpty) {
      throw StateError('No log entries available for export.');
    }

    final contents = format(entries, metadata: metadata);
    final fileName = _buildFileName();

    if (_useNativeSaveDialog) {
      final savedLocation = await _saveFileCallback(
        dialogTitle: dialogTitle,
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(contents)),
      );
      if (savedLocation == null) {
        return null;
      }

      return LogExportResult(
        fileName: _extractFileName(savedLocation, fallback: fileName),
        contents: contents,
      );
    }

    return _writeExportFile(fileName: fileName, contents: contents);
  }

  Future<LogExportResult> share(List<AppLogEntry> entries, {LogExportMetadata? metadata}) async {
    if (entries.isEmpty) {
      throw StateError('No log entries available for export.');
    }

    final l10n = _resolveLocalizations(metadata);
    final result = await _writeExportFile(
      fileName: _buildFileName(),
      contents: format(entries, metadata: metadata),
    );
    await _shareCallback(
      ShareParams(
        files: [XFile(result.file!.path, name: result.fileName, mimeType: 'text/plain')],
        subject: l10n.logsExportShareSubject,
        text: l10n.logsExportFileTitle,
      ),
    );
    return result;
  }

  String format(List<AppLogEntry> entries, {LogExportMetadata? metadata}) {
    if (entries.isEmpty) {
      throw StateError('No log entries available for export.');
    }

    final l10n = _resolveLocalizations(metadata);
    final generatedAt = DateTime.now();
    final buffer = StringBuffer()
      ..writeln(l10n.logsExportFileTitle)
      ..writeln('${l10n.logsExportGeneratedAtLabel}: ${_formatTimestampWithOffset(generatedAt)}')
      ..writeln(l10n.logsExportEntriesCount(entries.length));

    final environmentSection = _formatEnvironmentSection(
      l10n: l10n,
      metadata: metadata,
      generatedAt: generatedAt,
    );
    if (environmentSection.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(environmentSection);
    }

    final summarySection = _formatDiagnosticsSummary(entries, l10n: l10n);
    if (summarySection.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(summarySection);
    }

    buffer.writeln();

    for (final entry in entries) {
      buffer
        ..writeln(
          '--------------------------------------------------------------------------------',
        )
        ..writeln(
          '${l10n.logsExportTimestampLabel}: ${_formatTimestampWithOffset(entry.timestamp)}',
        )
        ..writeln('${l10n.logsExportLevelLabel}: ${_localizedLevelName(l10n, entry.level)}')
        ..writeln('${l10n.logsExportCategoryLabel}: ${entry.category}');
      if (entry.route?.isNotEmpty == true) {
        buffer.writeln('${l10n.logsExportRouteLabel}: ${entry.route}');
      }
      buffer.writeln(
        '${l10n.logsExportMessageLabel}: ${localizeLogMessage(l10n, LogSanitizer.sanitizeText(entry.message))}',
      );
      if (entry.maskedPayload?.isNotEmpty == true) {
        final sanitizedMaskedPayload = LogSanitizer.formatPayloadForDisplay(entry.maskedPayload);
        buffer
          ..writeln()
          ..writeln('${l10n.logsExportMaskedPayloadLabel}:')
          ..writeln(sanitizedMaskedPayload);
      }
      if (entry.rawPayload?.isNotEmpty == true) {
        buffer
          ..writeln()
          ..writeln('${l10n.logsExportRawPayloadLabel}:')
          ..writeln(LogSanitizer.removedFromExportNotice);
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  static String _buildFileName() {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return 'kick-logs-$timestamp.log';
  }

  Future<LogExportResult> _writeExportFile({
    required String fileName,
    required String contents,
  }) async {
    final directory = await _exportDirectoryResolver();
    await directory.create(recursive: true);

    final file = File(p.join(directory.path, fileName));
    await file.writeAsString(contents, flush: true);
    return LogExportResult(fileName: fileName, contents: contents, file: file);
  }

  static Future<Directory> _defaultExportDirectory() async {
    if (Platform.isAndroid) {
      final externalDirectory = await getExternalStorageDirectory();
      if (externalDirectory != null) {
        return Directory(p.join(externalDirectory.path, 'exports'));
      }
    }

    final downloadsDirectory = await getDownloadsDirectory();
    if (downloadsDirectory != null) {
      return Directory(p.join(downloadsDirectory.path, 'kick'));
    }

    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(p.join(supportDirectory.path, 'exports'));
  }

  static Future<ShareResult> _defaultShare(ShareParams params) {
    return SharePlus.instance.share(params);
  }

  static Future<String?> _defaultSaveFile({
    required String fileName,
    required Uint8List bytes,
    String? dialogTitle,
  }) {
    return FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['log'],
      bytes: bytes,
      lockParentWindow: Platform.isWindows,
    );
  }

  static String _extractFileName(String savedLocation, {required String fallback}) {
    final decodedLocation = Uri.decodeFull(savedLocation);
    final decodedBaseName = p.basename(decodedLocation);
    if (_isUsefulFileName(decodedBaseName)) {
      return decodedBaseName;
    }

    final uri = Uri.tryParse(savedLocation);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final lastSegment = Uri.decodeComponent(uri.pathSegments.last);
      final uriBaseName = p.basename(lastSegment);
      if (_isUsefulFileName(uriBaseName)) {
        return uriBaseName;
      }
    }

    return fallback;
  }

  static bool _isUsefulFileName(String candidate) {
    return candidate.isNotEmpty && candidate != '.' && candidate != '/' && candidate != '\\';
  }

  String _formatEnvironmentSection({
    required KickLocalizations l10n,
    required LogExportMetadata? metadata,
    required DateTime generatedAt,
  }) {
    final details = <String>[
      if (metadata?.appVersion?.trim().isNotEmpty == true)
        'version=${metadata!.appVersion!.trim()}',
      'platform=${Platform.operatingSystem}',
      if (metadata?.locale?.trim().isNotEmpty == true) 'locale=${metadata!.locale!.trim()}',
      'timezone=${_formatUtcOffset(generatedAt.timeZoneOffset)}',
    ];
    final filters = <String>[
      if (metadata?.query?.trim().isNotEmpty == true) 'query="${metadata!.query!.trim()}"',
      if (metadata?.level != null) 'level=${metadata!.level!.name}',
      if (metadata?.category?.trim().isNotEmpty == true) 'category=${metadata!.category!.trim()}',
    ];
    final scope = <String>[
      if (metadata?.matchingEntries != null) 'matching_entries=${metadata!.matchingEntries}',
      if (metadata?.retainedEntries != null) 'retained_entries=${metadata!.retainedEntries}',
      if (metadata?.retentionLimit != null) 'retention_limit=${metadata!.retentionLimit}',
    ];
    final runtimeSettings = <String>[
      if (metadata?.loggingVerbosity != null) 'verbosity=${metadata!.loggingVerbosity!.name}',
      if (metadata?.unsafeRawLoggingEnabled != null)
        'unsafe_raw_logging=${metadata!.unsafeRawLoggingEnabled}',
      if (metadata?.requestMaxRetries != null) 'request_max_retries=${metadata!.requestMaxRetries}',
      if (metadata?.retry429DelaySeconds != null)
        'retry_429_delay_sec=${metadata!.retry429DelaySeconds}',
      if (metadata?.mark429AsUnhealthy != null)
        'mark_429_as_unhealthy=${metadata!.mark429AsUnhealthy}',
      if (metadata?.androidBackgroundRuntime != null)
        'android_background_runtime=${metadata!.androidBackgroundRuntime}',
    ];

    final section = StringBuffer()..writeln(l10n.logsExportSectionEnvironment);
    if (details.isNotEmpty) {
      section.writeln('${l10n.logsExportAppLabel}: ${details.join(', ')}');
    }
    section.writeln(
      filters.isEmpty
          ? '${l10n.logsExportFiltersLabel}: ${l10n.logsExportNoneValue}'
          : '${l10n.logsExportFiltersLabel}: ${filters.join(', ')}',
    );
    if (scope.isNotEmpty) {
      section.writeln('${l10n.logsExportScopeLabel}: ${scope.join(', ')}');
    }
    if (runtimeSettings.isNotEmpty) {
      section.writeln('${l10n.logsExportRuntimeSettingsLabel}: ${runtimeSettings.join(', ')}');
    }
    return section.toString().trimRight();
  }

  String _formatDiagnosticsSummary(List<AppLogEntry> entries, {required KickLocalizations l10n}) {
    final sorted = entries.toList(growable: false)
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    final first = sorted.first;
    final last = sorted.last;
    final levelCounts = <String, int>{};
    final categoryCounts = <String, int>{};
    final routeCounts = <String, int>{};
    final modelCounts = <String, int>{};
    final requestModels = <String, String>{};
    final statusCodeCounts = <String, int>{};
    final errorDetailCounts = <String, int>{};
    final upstreamReasonCounts = <String, int>{};
    final backgroundDurations = <int>[];
    var retriedRequests = 0;
    var retriedSucceeded = 0;
    var retriedFailed = 0;
    var totalRetryCount = 0;
    var maxRetryCount = 0;
    var totalAccountFailovers = 0;
    var maxAccountFailovers = 0;
    var totalPromptTokens = 0;
    var totalCompletionTokens = 0;
    var totalTokens = 0;
    var totalCachedTokens = 0;
    var totalReasoningTokens = 0;
    var hasTokenMetrics = false;
    var recoveredBackgroundSessions = 0;

    for (final entry in sorted) {
      levelCounts.update(entry.level.name, (value) => value + 1, ifAbsent: () => 1);
      categoryCounts.update(entry.category, (value) => value + 1, ifAbsent: () => 1);
      if (entry.route?.isNotEmpty == true) {
        routeCounts.update(entry.route!, (value) => value + 1, ifAbsent: () => 1);
      }
      final payload = _decodePayload(entry.maskedPayload);
      final requestId = _readNonEmptyString(payload['request_id']);
      final model = _readNonEmptyString(payload['model']);
      if (requestId != null && model != null) {
        requestModels.putIfAbsent(requestId, () => model);
      } else if (model != null) {
        modelCounts.update(model, (value) => value + 1, ifAbsent: () => 1);
      }

      final statusCode = _readInt(payload['final_status_code']) ?? _readInt(payload['status_code']);
      if (statusCode != null) {
        statusCodeCounts.update(statusCode.toString(), (value) => value + 1, ifAbsent: () => 1);
      }

      final errorDetail =
          _readNonEmptyString(payload['final_error_detail']) ??
          _readNonEmptyString(payload['error_detail']);
      if (errorDetail != null) {
        errorDetailCounts.update(errorDetail, (value) => value + 1, ifAbsent: () => 1);
      }

      final upstreamReason =
          _readNonEmptyString(payload['final_upstream_reason']) ??
          _readNonEmptyString(payload['upstream_reason']);
      if (upstreamReason != null) {
        upstreamReasonCounts.update(upstreamReason, (value) => value + 1, ifAbsent: () => 1);
      }

      final retryCount = _readInt(payload['retry_count']);
      if (retryCount != null) {
        retriedRequests += 1;
        totalRetryCount += retryCount;
        if (retryCount > maxRetryCount) {
          maxRetryCount = retryCount;
        }

        final accountFailovers = _readInt(payload['account_failover_count']) ?? 0;
        totalAccountFailovers += accountFailovers;
        if (accountFailovers > maxAccountFailovers) {
          maxAccountFailovers = accountFailovers;
        }

        switch (_readNonEmptyString(payload['outcome'])) {
          case 'succeeded':
            retriedSucceeded += 1;
          case 'failed':
            retriedFailed += 1;
        }
      }

      totalPromptTokens += _readInt(payload['prompt_tokens']) ?? 0;
      totalCompletionTokens += _readInt(payload['completion_tokens']) ?? 0;
      totalTokens += _readInt(payload['total_tokens']) ?? 0;
      totalCachedTokens += _readInt(payload['cached_tokens']) ?? 0;
      totalReasoningTokens += _readInt(payload['reasoning_tokens']) ?? 0;
      hasTokenMetrics =
          hasTokenMetrics ||
          payload.containsKey('prompt_tokens') ||
          payload.containsKey('completion_tokens') ||
          payload.containsKey('total_tokens') ||
          payload.containsKey('cached_tokens') ||
          payload.containsKey('reasoning_tokens');

      if (entry.category == androidBackgroundSessionCategory &&
          (entry.message == androidBackgroundSessionEndedMessage ||
              entry.message == androidBackgroundSessionRecoveredMessage)) {
        final durationSec = payload['duration_sec'] as int?;
        if (durationSec != null && durationSec >= 0) {
          backgroundDurations.add(durationSec);
        }
        if (entry.message == androidBackgroundSessionRecoveredMessage) {
          recoveredBackgroundSessions += 1;
        }
      }
    }

    final diagnostics = StringBuffer()
      ..writeln(l10n.logsExportSectionDiagnostics)
      ..writeln(
        '${l10n.logsExportTimeRangeLabel}: ${_formatTimestampWithOffset(first.timestamp)} -> ${_formatTimestampWithOffset(last.timestamp)}',
      )
      ..writeln('${l10n.logsExportLevelsLabel}: ${_formatCountMap(levelCounts)}')
      ..writeln('${l10n.logsExportCategoriesLabel}: ${_formatCountMap(categoryCounts)}')
      ..writeln(
        routeCounts.isEmpty
            ? '${l10n.logsExportRoutesLabel}: ${l10n.logsExportNoneValue}'
            : '${l10n.logsExportRoutesLabel}: ${_formatCountMap(routeCounts)}',
      );

    for (final model in requestModels.values) {
      modelCounts.update(model, (value) => value + 1, ifAbsent: () => 1);
    }
    if (modelCounts.isNotEmpty) {
      diagnostics.writeln('${l10n.logsExportModelsLabel}: ${_formatCountMap(modelCounts)}');
    }
    if (statusCodeCounts.isNotEmpty) {
      diagnostics.writeln(
        '${l10n.logsExportStatusCodesLabel}: ${_formatCountMap(statusCodeCounts)}',
      );
    }
    if (errorDetailCounts.isNotEmpty) {
      diagnostics.writeln(
        '${l10n.logsExportErrorDetailsLabel}: ${_formatCountMap(errorDetailCounts)}',
      );
    }
    if (upstreamReasonCounts.isNotEmpty) {
      diagnostics.writeln(
        '${l10n.logsExportUpstreamReasonsLabel}: ${_formatCountMap(upstreamReasonCounts)}',
      );
    }
    if (retriedRequests > 0) {
      diagnostics.writeln(
        '${l10n.logsExportRetriedRequestsLabel}: total=$retriedRequests, '
        'succeeded=$retriedSucceeded, '
        'failed=$retriedFailed, '
        'avg_retry_count=${(totalRetryCount / retriedRequests).toStringAsFixed(1)}, '
        'max_retry_count=$maxRetryCount, '
        'total_account_failovers=$totalAccountFailovers, '
        'max_account_failovers=$maxAccountFailovers',
      );
    }
    if (hasTokenMetrics) {
      diagnostics.writeln(
        '${l10n.logsExportTokensLabel}: prompt=$totalPromptTokens, '
        'completion=$totalCompletionTokens, '
        'total=$totalTokens, '
        'cached=$totalCachedTokens, '
        'reasoning=$totalReasoningTokens',
      );
    }

    if (backgroundDurations.isEmpty) {
      diagnostics.writeln(
        '${l10n.logsExportAndroidBackgroundSessionsLabel}: ${l10n.logsExportNoneDetectedValue}',
      );
    } else {
      final totalDuration = backgroundDurations.fold<int>(0, (sum, value) => sum + value);
      final maxDuration = backgroundDurations.reduce((left, right) => left > right ? left : right);
      diagnostics.writeln(
        '${l10n.logsExportAndroidBackgroundSessionsLabel}: total=${backgroundDurations.length}, '
        'recovered_after_restart=$recoveredBackgroundSessions, '
        'avg_duration_sec=${(totalDuration / backgroundDurations.length).round()}, '
        'max_duration_sec=$maxDuration',
      );
    }

    return diagnostics.toString().trimRight();
  }

  String _formatCountMap(Map<String, int> counts) {
    final entries = counts.entries.toList(growable: false)
      ..sort((left, right) {
        final countComparison = right.value.compareTo(left.value);
        if (countComparison != 0) {
          return countComparison;
        }
        return left.key.compareTo(right.key);
      });
    return entries.map((entry) => '${entry.key}=${entry.value}').join(', ');
  }

  String _formatUtcOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final absoluteOffset = offset.abs();
    final hours = absoluteOffset.inHours.toString().padLeft(2, '0');
    final minutes = (absoluteOffset.inMinutes % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }

  String _formatTimestampWithOffset(DateTime timestamp) {
    return '${timestamp.toIso8601String()} ${_formatUtcOffset(timestamp.timeZoneOffset)}';
  }

  String _localizedLevelName(KickLocalizations l10n, AppLogLevel level) {
    return switch (level) {
      AppLogLevel.info => l10n.logsEntryLevelInfo,
      AppLogLevel.warning => l10n.logsEntryLevelWarning,
      AppLogLevel.error => l10n.logsEntryLevelError,
    };
  }

  KickLocalizations _resolveLocalizations(LogExportMetadata? metadata) {
    return lookupKickLocalizations(_parseLocale(metadata?.locale) ?? const Locale('en'));
  }

  Locale? _parseLocale(String? value) {
    final localeTag = value?.trim();
    if (localeTag == null || localeTag.isEmpty || localeTag.toLowerCase() == 'system') {
      return null;
    }
    final subtags = localeTag.replaceAll('_', '-').split('-');
    if (subtags.isEmpty || subtags.first.trim().isEmpty) {
      return null;
    }
    return Locale.fromSubtags(
      languageCode: subtags.first,
      scriptCode: subtags.length >= 2 && subtags[1].length == 4 ? subtags[1] : null,
      countryCode: switch (subtags.length) {
        >= 3 when subtags[1].length == 4 => subtags[2],
        >= 2 when subtags[1].length != 4 => subtags[1],
        _ => null,
      },
    );
  }

  String? _readNonEmptyString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  int? _readInt(Object? value) {
    return switch (value) {
      int number => number,
      num number => number.round(),
      String text => int.tryParse(text.trim()),
      _ => null,
    };
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
}
