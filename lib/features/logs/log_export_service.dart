import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../analytics/android_background_session_tracker.dart';
import '../../core/logging/log_sanitizer.dart';
import '../../data/models/app_log_entry.dart';

typedef LogExportDirectoryResolver = Future<Directory> Function();
typedef LogShareCallback = Future<ShareResult> Function(ShareParams params);

class LogExportResult {
  const LogExportResult({required this.file, required this.contents});

  final File file;
  final String contents;
}

class LogExportService {
  LogExportService({
    LogExportDirectoryResolver? exportDirectoryResolver,
    LogShareCallback? shareCallback,
  }) : _exportDirectoryResolver = exportDirectoryResolver ?? _defaultExportDirectory,
       _shareCallback = shareCallback ?? _defaultShare;

  final LogExportDirectoryResolver _exportDirectoryResolver;
  final LogShareCallback _shareCallback;

  Future<LogExportResult> export(List<AppLogEntry> entries) async {
    if (entries.isEmpty) {
      throw StateError('No log entries available for export.');
    }

    final directory = await _exportDirectoryResolver();
    await directory.create(recursive: true);

    final file = File(p.join(directory.path, _buildFileName()));
    final contents = format(entries);
    await file.writeAsString(contents, flush: true);
    return LogExportResult(file: file, contents: contents);
  }

  Future<LogExportResult> share(List<AppLogEntry> entries) async {
    final result = await export(entries);
    await _shareCallback(
      ShareParams(
        files: [
          XFile(result.file.path, name: p.basename(result.file.path), mimeType: 'text/plain'),
        ],
        subject: 'KiCk logs',
        text: 'KiCk log export',
      ),
    );
    return result;
  }

  String format(List<AppLogEntry> entries) {
    if (entries.isEmpty) {
      throw StateError('No log entries available for export.');
    }

    final buffer = StringBuffer()
      ..writeln('KiCk log export')
      ..writeln('Generated at: ${DateTime.now().toIso8601String()}')
      ..writeln('Entries: ${entries.length}')
      ..writeln()
      ..writeln(_formatDiagnosticsSummary(entries))
      ..writeln();

    for (final entry in entries) {
      buffer
        ..writeln(
          '--------------------------------------------------------------------------------',
        )
        ..writeln('Timestamp: ${entry.timestamp.toIso8601String()}')
        ..writeln('Level: ${entry.level.name}')
        ..writeln('Category: ${entry.category}');
      if (entry.route?.isNotEmpty == true) {
        buffer.writeln('Route: ${entry.route}');
      }
      buffer.writeln('Message: ${LogSanitizer.sanitizeText(entry.message)}');
      if (entry.maskedPayload?.isNotEmpty == true) {
        final sanitizedMaskedPayload = LogSanitizer.formatPayloadForDisplay(entry.maskedPayload);
        buffer
          ..writeln()
          ..writeln('Masked payload:')
          ..writeln(sanitizedMaskedPayload);
      }
      if (entry.rawPayload?.isNotEmpty == true) {
        buffer
          ..writeln()
          ..writeln('Raw payload:')
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

  String _formatDiagnosticsSummary(List<AppLogEntry> entries) {
    final sorted = entries.toList(growable: false)
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    final first = sorted.first;
    final last = sorted.last;
    final levelCounts = <String, int>{};
    final categoryCounts = <String, int>{};
    final routeCounts = <String, int>{};
    final backgroundDurations = <int>[];
    var recoveredBackgroundSessions = 0;

    for (final entry in sorted) {
      levelCounts.update(entry.level.name, (value) => value + 1, ifAbsent: () => 1);
      categoryCounts.update(entry.category, (value) => value + 1, ifAbsent: () => 1);
      if (entry.route?.isNotEmpty == true) {
        routeCounts.update(entry.route!, (value) => value + 1, ifAbsent: () => 1);
      }
      if (entry.category == androidBackgroundSessionCategory &&
          (entry.message == androidBackgroundSessionEndedMessage ||
              entry.message == androidBackgroundSessionRecoveredMessage)) {
        final payload = _decodePayload(entry.maskedPayload);
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
      ..writeln('Diagnostics summary')
      ..writeln(
        'Time range: ${first.timestamp.toIso8601String()} -> ${last.timestamp.toIso8601String()}',
      )
      ..writeln('Levels: ${_formatCountMap(levelCounts)}')
      ..writeln('Categories: ${_formatCountMap(categoryCounts)}')
      ..writeln(routeCounts.isEmpty ? 'Routes: none' : 'Routes: ${_formatCountMap(routeCounts)}');

    if (backgroundDurations.isEmpty) {
      diagnostics.writeln('Android background sessions: none detected');
    } else {
      final totalDuration = backgroundDurations.fold<int>(0, (sum, value) => sum + value);
      final maxDuration = backgroundDurations.reduce((left, right) => left > right ? left : right);
      diagnostics.writeln(
        'Android background sessions: total=${backgroundDurations.length}, '
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
