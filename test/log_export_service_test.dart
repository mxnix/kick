import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kick/analytics/android_background_session_tracker.dart';
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
        message: 'Using account `qwerty123@gmail.com` (Primary) for `gemini-3.1-pro-preview`',
        maskedPayload: '{"messages":[{"role":"user","content":"Hello"}]}',
        rawPayload: '{"stream":true}',
      ),
      AppLogEntry(
        id: '2',
        timestamp: DateTime.utc(2026, 3, 15, 17, 0, 0),
        level: AppLogLevel.info,
        category: androidBackgroundSessionCategory,
        route: '/android/background',
        message: androidBackgroundSessionRecoveredMessage,
        maskedPayload:
            '{"session_id":"bg-1","duration_sec":120,"killed_in_background":true,"proxy_was_running":true}',
      ),
    ]);

    final contents = await result.file.readAsString();
    expect(result.file.existsSync(), isTrue);
    expect(contents, contains('KiCk log export'));
    expect(contents, contains('Diagnostics summary'));
    expect(contents, contains('Levels: info=2'));
    expect(contents, contains('Routes: /android/background=1, /v1/chat/completions=1'));
    expect(contents, contains('Android background sessions: total=1'));
    expect(contents, contains('recovered_after_restart=1'));
    expect(contents, contains('Category: chat.completions'));
    expect(
      contents,
      contains(
        'Message: Using account `q*******3@gmail.com` (Primary) for `gemini-3.1-pro-preview`',
      ),
    );
    expect(contents, contains('Masked payload:'));
    expect(contents, contains('Raw payload:'));
    expect(contents, contains('  "message_count": 1'));
    expect(contents, contains('[Removed from export for safety]'));
    expect(contents, isNot(contains('"content":"Hello"')));
    expect(contents, isNot(contains('qwerty123@gmail.com')));
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
