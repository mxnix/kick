import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
      buffer.writeln('Message: ${entry.message}');
      if (entry.maskedPayload?.isNotEmpty == true) {
        final sanitizedMaskedPayload = LogSanitizer.sanitizeSerializedPayload(entry.maskedPayload);
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
}
