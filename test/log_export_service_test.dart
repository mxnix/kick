import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kick/analytics/android_background_session_log.dart';
import 'package:kick/data/models/app_log_entry.dart';
import 'package:kick/data/models/app_settings.dart';
import 'package:kick/features/logs/log_export_service.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  test('exports logs into a readable text file', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick-log-export');
    addTearDown(() => tempDirectory.delete(recursive: true));

    final service = LogExportService(
      exportDirectoryResolver: () async => tempDirectory,
      shareCallback: (_) async => ShareResult.unavailable,
      useNativeSaveDialog: false,
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

    expect(result, isNotNull);

    final exportedFile = result!.file;
    expect(exportedFile, isNotNull);

    final contents = await exportedFile!.readAsString();
    expect(exportedFile.existsSync(), isTrue);
    expect(contents, contains('KiCk log export'));
    expect(contents, contains('Generated at: '));
    expect(contents, contains(RegExp(r'Generated at: .* UTC[+-]\d{2}:\d{2}')));
    expect(contents, contains('Environment'));
    expect(contents, contains('App: platform='));
    expect(contents, contains('timezone=UTC'));
    expect(contents, isNot(contains('RTZ')));
    expect(contents, contains('Filters: none'));
    expect(contents, contains('Diagnostics summary'));
    expect(
      contents,
      contains(RegExp(r'Time range: .* UTC[+-]\d{2}:\d{2} -> .* UTC[+-]\d{2}:\d{2}')),
    );
    expect(contents, contains('Levels: info=2'));
    expect(contents, contains('Routes: /android/background=1, /v1/chat/completions=1'));
    expect(contents, contains('Android background sessions: total=1'));
    expect(contents, contains('recovered_after_restart=1'));
    expect(contents, contains('Category: chat.completions'));
    expect(contents, contains(RegExp(r'Timestamp: .* UTC[+-]\d{2}:\d{2}')));
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

  test('uses the native save dialog callback when enabled', () async {
    String? capturedDialogTitle;
    String? capturedFileName;
    Uint8List? capturedBytes;

    final service = LogExportService(
      exportDirectoryResolver: () async => Directory.systemTemp,
      shareCallback: (_) async => ShareResult.unavailable,
      useNativeSaveDialog: true,
      saveFileCallback:
          ({required String fileName, required Uint8List bytes, String? dialogTitle}) async {
            capturedDialogTitle = dialogTitle;
            capturedFileName = fileName;
            capturedBytes = bytes;
            return 'content://com.android.externalstorage.documents/document/'
                'primary%3ADownload%2Fkick-logs-custom.log';
          },
    );

    final result = await service.export([
      AppLogEntry(
        id: '1',
        timestamp: DateTime.utc(2026, 3, 15, 17),
        level: AppLogLevel.error,
        category: 'chat.completions',
        route: '/v1/chat/completions',
        message: 'Response completed',
        maskedPayload: '{"preview":"ok"}',
      ),
    ], dialogTitle: 'Куда сохранить логи?');

    expect(result, isNotNull);
    expect(result!.file, isNull);
    expect(result.fileName, 'kick-logs-custom.log');
    expect(capturedDialogTitle, 'Куда сохранить логи?');
    expect(capturedFileName, startsWith('kick-logs-'));
    expect(capturedFileName, endsWith('.log'));
    expect(utf8.decode(capturedBytes!), contains('KiCk log export'));
  });

  test('returns null when the native save dialog is canceled', () async {
    final service = LogExportService(
      exportDirectoryResolver: () async => Directory.systemTemp,
      shareCallback: (_) async => ShareResult.unavailable,
      useNativeSaveDialog: true,
      saveFileCallback:
          ({required String fileName, required Uint8List bytes, String? dialogTitle}) async => null,
    );

    final result = await service.export([
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

    expect(result, isNull);
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

    final sharedFile = result.file;
    expect(sharedFile, isNotNull);
    expect(sharedFile!.existsSync(), isTrue);
    expect(sharedParams, isNotNull);
    expect(sharedParams?.files, isNotNull);
    expect(sharedParams?.files, hasLength(1));
    expect(sharedParams?.files?.single.path, sharedFile.path);
    expect(sharedParams?.subject, 'KiCk logs');
  });

  test('formats export metadata into a compact context section', () {
    final service = LogExportService(
      exportDirectoryResolver: () async => Directory.systemTemp,
      shareCallback: (_) async => ShareResult.unavailable,
      useNativeSaveDialog: false,
    );

    final contents = service.format(
      [
        AppLogEntry(
          id: '1',
          timestamp: DateTime.utc(2026, 3, 15, 17),
          level: AppLogLevel.warning,
          category: 'proxy',
          route: '/v1/chat/completions',
          message: 'Request failed after retries',
          maskedPayload: '''
{"request_id":"req-1","model":"gemini-2.5-flash","status_code":429,"error_detail":"quotaExhausted","upstream_reason":"RATE_LIMIT_EXCEEDED","retry_count":2,"account_failover_count":1,"outcome":"failed","prompt_tokens":120,"completion_tokens":80,"total_tokens":200}
''',
        ),
      ],
      metadata: const LogExportMetadata(
        appVersion: '1.2.3',
        locale: 'ru-RU',
        query: 'quota',
        level: AppLogLevel.warning,
        category: 'proxy',
        retainedEntries: 500,
        matchingEntries: 12,
        retentionLimit: 1000,
        loggingVerbosity: KickLogVerbosity.verbose,
        unsafeRawLoggingEnabled: false,
        requestMaxRetries: 10,
        retry429DelaySeconds: 30,
        mark429AsUnhealthy: true,
        androidBackgroundRuntime: true,
      ),
    );

    expect(contents, contains('App: version=1.2.3'));
    expect(contents, contains('locale=ru-RU'));
    expect(contents, contains('timezone=UTC'));
    expect(contents, isNot(contains('RTZ')));
    expect(contents, contains('Filters: query="quota", level=warning, category=proxy'));
    expect(
      contents,
      contains('Scope: matching_entries=12, retained_entries=500, retention_limit=1000'),
    );
    expect(contents, contains('Runtime settings: verbosity=verbose'));
    expect(contents, contains('Status codes: 429=1'));
    expect(contents, contains('Error details: quotaExhausted=1'));
    expect(contents, contains('Upstream reasons: RATE_LIMIT_EXCEEDED=1'));
    expect(contents, contains('Retried requests: total=1, succeeded=0, failed=1'));
    expect(contents, contains('Tokens: prompt=120, completion=80, total=200'));
  });
}
