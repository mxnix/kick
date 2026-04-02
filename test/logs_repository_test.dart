import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/data/app_database.dart';
import 'package:kick/data/models/app_log_entry.dart';
import 'package:kick/data/repositories/logs_repository.dart';

void main() {
  test('keeps only the newest entries within the configured retention limit', () async {
    final database = AppDatabase(NativeDatabase.memory());
    await database.ensureSchema();
    addTearDown(database.close);

    final repository = LogsRepository(database, retentionLimit: 3);
    final baseTime = DateTime.utc(2026, 3, 20, 10);

    for (var index = 0; index < 5; index++) {
      await repository.insert(
        AppLogEntry(
          id: 'log-$index',
          timestamp: baseTime.add(Duration(minutes: index)),
          level: AppLogLevel.info,
          category: 'proxy',
          route: '/v1/chat/completions',
          message: 'Entry $index',
          maskedPayload: '{"index":$index}',
        ),
      );
    }

    final retained = await repository.readAll(limit: null);
    expect(retained.map((entry) => entry.id), ['log-4', 'log-3', 'log-2']);

    await repository.setRetentionLimit(2);

    final trimmed = await repository.readAll(limit: null);
    expect(trimmed.map((entry) => entry.id), ['log-4', 'log-3']);
  });

  test('supports filtered counts, categories, and paginated reads', () async {
    final database = AppDatabase(NativeDatabase.memory());
    await database.ensureSchema();
    addTearDown(database.close);

    final repository = LogsRepository(database, retentionLimit: 20);
    final baseTime = DateTime.utc(2026, 3, 20, 10);
    final entries = <AppLogEntry>[
      AppLogEntry(
        id: 'log-0',
        timestamp: baseTime,
        level: AppLogLevel.info,
        category: 'proxy',
        route: '/v1/chat/completions',
        message: 'Alpha request',
        maskedPayload: '{"step":"request"}',
      ),
      AppLogEntry(
        id: 'log-1',
        timestamp: baseTime.add(const Duration(minutes: 1)),
        level: AppLogLevel.warning,
        category: 'proxy',
        route: '/v1/chat/completions',
        message: 'Alpha retry',
        maskedPayload: '{"step":"retry"}',
      ),
      AppLogEntry(
        id: 'log-2',
        timestamp: baseTime.add(const Duration(minutes: 2)),
        level: AppLogLevel.error,
        category: 'sync',
        route: '/runtime/sync',
        message: 'Beta failure',
        maskedPayload: '{"step":"sync"}',
      ),
      AppLogEntry(
        id: 'log-3',
        timestamp: baseTime.add(const Duration(minutes: 3)),
        level: AppLogLevel.info,
        category: 'proxy',
        route: '/v1/responses',
        message: 'Alpha response',
        maskedPayload: '{"step":"response"}',
      ),
      AppLogEntry(
        id: 'log-4',
        timestamp: baseTime.add(const Duration(minutes: 4)),
        level: AppLogLevel.info,
        category: 'metrics',
        route: '/runtime/metrics',
        message: 'Alpha metrics',
        maskedPayload: '{"step":"metrics"}',
      ),
    ];

    for (final entry in entries) {
      await repository.insert(entry);
    }

    expect(await repository.count(), 5);
    expect(await repository.count(query: 'alpha'), 4);
    expect(await repository.count(query: 'alpha', category: 'proxy'), 3);
    expect(await repository.count(level: AppLogLevel.error), 1);
    expect(await repository.readCategories(), ['metrics', 'proxy', 'sync']);

    final firstPage = await repository.readAll(limit: 2, query: 'alpha');
    final secondPage = await repository.readAll(limit: 2, offset: 2, query: 'alpha');

    expect(firstPage.map((entry) => entry.id), ['log-4', 'log-3']);
    expect(secondPage.map((entry) => entry.id), ['log-1', 'log-0']);
  });

  test('excludes internal categories from reads, counts, and category filters', () async {
    final database = AppDatabase(NativeDatabase.memory());
    await database.ensureSchema();
    addTearDown(database.close);

    final repository = LogsRepository(database, retentionLimit: 20);
    final baseTime = DateTime.utc(2026, 4, 2, 10);
    await repository.insert(
      AppLogEntry(
        id: 'visible-log',
        timestamp: baseTime,
        level: AppLogLevel.info,
        category: 'proxy',
        route: '/v1/chat/completions',
        message: 'Visible request',
        maskedPayload: '{"step":"request"}',
      ),
    );
    await repository.insert(
      AppLogEntry(
        id: 'hidden-log',
        timestamp: baseTime.add(const Duration(minutes: 1)),
        level: AppLogLevel.info,
        category: 'app.lifecycle',
        route: '/android/background',
        message: 'Android background session started',
        maskedPayload: '{"session_id":"bg-1"}',
      ),
    );

    expect(await repository.count(), 2);
    expect(await repository.count(excludedCategories: {'app.lifecycle'}), 1);
    expect(await repository.readCategories(excludedCategories: {'app.lifecycle'}), ['proxy']);
    expect(
      (await repository.readAll(
        limit: null,
        excludedCategories: {'app.lifecycle'},
      )).map((entry) => entry.id),
      ['visible-log'],
    );
  });
}
