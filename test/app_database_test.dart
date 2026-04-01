import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/data/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('close releases drift tracking for subsequent database instances', () async {
    final messages = <String>[];
    final originalDebugPrint = driftRuntimeOptions.debugPrint;
    final originalSuppressWarnings = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.debugPrint = messages.add;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;

    try {
      final first = AppDatabase(NativeDatabase.memory());
      await first.ensureSchema();
      await first.close();

      final second = AppDatabase(NativeDatabase.memory());
      await second.ensureSchema();
      await second.close();
    } finally {
      driftRuntimeOptions.debugPrint = originalDebugPrint;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = originalSuppressWarnings;
    }

    expect(
      messages.where(
        (message) =>
            message.contains('created the database class _AttachedDatabase multiple times'),
      ),
      isEmpty,
    );
  });

  test('repairs legacy databases with missing additive columns', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick-app-db-test-');
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    final databasePath = p.join(tempDirectory.path, 'kick.sqlite');
    final legacyDatabase = sqlite3.sqlite3.open(databasePath);
    try {
      legacyDatabase.execute('''
        CREATE TABLE settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
      legacyDatabase.execute('''
        CREATE TABLE accounts (
          id TEXT PRIMARY KEY,
          label TEXT NOT NULL,
          email TEXT NOT NULL,
          project_id TEXT NOT NULL
        )
      ''');
      legacyDatabase.execute('''
        CREATE TABLE logs (
          id TEXT PRIMARY KEY,
          timestamp TEXT NOT NULL,
          level TEXT NOT NULL,
          category TEXT NOT NULL,
          message TEXT NOT NULL
        )
      ''');
      legacyDatabase.execute("""
        INSERT INTO accounts (id, label, email, project_id)
        VALUES ('account-1', 'Primary', 'user@example.com', 'project-1')
      """);
      legacyDatabase.execute("""
        INSERT INTO logs (id, timestamp, level, category, message)
        VALUES ('log-1', '2026-03-17T00:00:00.000', 'info', 'proxy', 'Ready')
      """);
    } finally {
      legacyDatabase.close();
    }

    final database = AppDatabase(NativeDatabase(File(databasePath)));
    addTearDown(database.close);

    final accountColumns = await _tableColumns(database, 'accounts');
    final logColumns = await _tableColumns(database, 'logs');
    final accountRow = await database
        .customSelect(
          '''
          SELECT
            provider,
            provider_region,
            credential_source_type,
            credential_source_path,
            provider_profile_arn,
            enabled,
            priority,
            not_supported_models,
            runtime_not_supported_models,
            google_subject_id,
            avatar_url,
            usage_count,
            error_count,
            token_ref
          FROM accounts
          WHERE id = ?1
        ''',
          variables: [Variable<String>('account-1')],
        )
        .getSingle();

    expect(
      accountColumns,
      containsAll(<String>{
        'enabled',
        'priority',
        'provider',
        'provider_region',
        'credential_source_type',
        'credential_source_path',
        'provider_profile_arn',
        'not_supported_models',
        'runtime_not_supported_models',
        'google_subject_id',
        'avatar_url',
        'last_used_at',
        'usage_count',
        'error_count',
        'cooldown_until',
        'last_quota_snapshot',
        'token_ref',
      }),
    );
    expect(logColumns, containsAll(<String>{'route', 'masked_payload', 'raw_payload'}));
    expect(accountRow.read<String>('provider'), 'gemini');
    expect(accountRow.read<String?>('provider_region'), anyOf(equals(null), isEmpty));
    expect(accountRow.read<String?>('credential_source_type'), anyOf(equals(null), isEmpty));
    expect(accountRow.read<String?>('credential_source_path'), anyOf(equals(null), isEmpty));
    expect(accountRow.read<String?>('provider_profile_arn'), anyOf(equals(null), isEmpty));
    expect(accountRow.read<int>('enabled'), 1);
    expect(accountRow.read<int>('priority'), 0);
    expect(accountRow.read<String>('not_supported_models'), '');
    expect(accountRow.read<String>('runtime_not_supported_models'), '');
    expect(accountRow.read<String?>('google_subject_id'), anyOf(equals(null), isEmpty));
    expect(accountRow.read<String?>('avatar_url'), anyOf(equals(null), isEmpty));
    expect(accountRow.read<int>('usage_count'), 0);
    expect(accountRow.read<int>('error_count'), 0);
    expect(accountRow.read<String>('token_ref'), 'kick.oauth.account-1');
  });
}

Future<Set<String>> _tableColumns(AppDatabase database, String tableName) async {
  final rows = await database.customSelect('PRAGMA table_info($tableName)').get();
  return rows.map((row) => row.read<String>('name')).toSet();
}
