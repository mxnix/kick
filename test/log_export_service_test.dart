import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kick/data/models/app_log_entry.dart';
import 'package:kick/features/logs/log_export_service.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  test('exports logs into a readable text file', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick-log-export');
    addTearDown(() => tempDirectory.delete(recursive: true));

    final service = LogExportService(
      exportDirectoryResolver: () async => tempDirectory,
      shareCallback: (_) async => ShareResult.unavailable,
    );

    final result = await service.export([
      AppLogEntry(
        id: '1',
        timestamp: DateTime.utc(2026, 3, 15, 16, 57, 47),
        level: AppLogLevel.info,
        category: 'chat.completions',
        route: '/v1/chat/completions',
        message: 'Request received',
        maskedPayload: '{"messages":[{"role":"user","content":"Hello"}]}',
        rawPayload: '{"stream":true}',
      ),
    ]);

    final contents = await result.file.readAsString();
    expect(result.file.existsSync(), isTrue);
    expect(contents, contains('KiCk log export'));
    expect(contents, contains('Category: chat.completions'));
    expect(contents, contains('Masked payload:'));
    expect(contents, contains('Raw payload:'));
    expect(contents, contains('"message_count":1'));
    expect(contents, contains('[Removed from export for safety]'));
    expect(contents, isNot(contains('"content":"Hello"')));
  });

  test('shares the exported log file through the configured callback', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick-log-share');
    addTearDown(() => tempDirectory.delete(recursive: true));

    ShareParams? sharedParams;
    final service = LogExportService(
      exportDirectoryResolver: () async => tempDirectory,
      shareCallback: (params) async {
        sharedParams = params;
        return const ShareResult('shared', ShareResultStatus.success);
      },
    );

    final result = await service.share([
      AppLogEntry(
        id: '1',
        timestamp: DateTime.utc(2026, 3, 15, 17),
        level: AppLogLevel.error,
        category: 'chat.completions',
        route: '/v1/chat/completions',
        message: 'Response completed',
        maskedPayload: '{"preview":"ok"}',
      ),
    ]);

    expect(result.file.existsSync(), isTrue);
    expect(sharedParams, isNotNull);
    expect(sharedParams?.files, isNotNull);
    expect(sharedParams?.files, hasLength(1));
    expect(sharedParams?.files?.single.path, result.file.path);
    expect(sharedParams?.subject, 'KiCk logs');
  });
}
