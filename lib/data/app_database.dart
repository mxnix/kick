import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

class AppDatabase extends DatabaseConnectionUser {
  static const schemaVersionValue = 3;
  static const Map<String, String> _accountsAdditiveColumns = {
    'enabled': 'INTEGER NOT NULL DEFAULT 1',
    'priority': 'INTEGER NOT NULL DEFAULT 0',
    'not_supported_models': "TEXT NOT NULL DEFAULT ''",
    'last_used_at': 'TEXT',
    'usage_count': 'INTEGER NOT NULL DEFAULT 0',
    'error_count': 'INTEGER NOT NULL DEFAULT 0',
    'cooldown_until': 'TEXT',
    'last_quota_snapshot': 'TEXT',
    'token_ref': "TEXT NOT NULL DEFAULT ''",
  };
  static const Map<String, String> _logsAdditiveColumns = {
    'route': 'TEXT',
    'masked_payload': 'TEXT',
    'raw_payload': 'TEXT',
  };

  AppDatabase(super.executor) {
    _attachedDatabase = _AttachedDatabase(this, executor);
  }

  bool _closed = false;
  late final GeneratedDatabase _attachedDatabase;

  @override
  GeneratedDatabase get attachedDatabase => _attachedDatabase;

  static Future<AppDatabase> open(String filePath) async {
    final executor = NativeDatabase.createInBackground(File(filePath));
    return AppDatabase(executor);
  }

  Future<void> ensureSchema() async {
    await _createBaseSchema();
    await _repairLegacySchema();
    await _createIndexes();
  }

  Future<void> _createBaseSchema() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY,
        label TEXT NOT NULL,
        email TEXT NOT NULL,
        project_id TEXT NOT NULL,
        enabled INTEGER NOT NULL,
        priority INTEGER NOT NULL,
        not_supported_models TEXT NOT NULL,
        last_used_at TEXT,
        usage_count INTEGER NOT NULL,
        error_count INTEGER NOT NULL,
        cooldown_until TEXT,
        last_quota_snapshot TEXT,
        token_ref TEXT NOT NULL
      )
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS logs (
        id TEXT PRIMARY KEY,
        timestamp TEXT NOT NULL,
        level TEXT NOT NULL,
        category TEXT NOT NULL,
        route TEXT,
        message TEXT NOT NULL,
        masked_payload TEXT,
        raw_payload TEXT
      )
    ''');
  }

  Future<void> _createIndexes() async {
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_accounts_priority_label
      ON accounts (priority, label COLLATE NOCASE)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_logs_timestamp
      ON logs (timestamp)
    ''');
  }

  Future<void> _repairLegacySchema() async {
    await _ensureAdditiveColumns('accounts', _accountsAdditiveColumns);
    await _ensureAdditiveColumns('logs', _logsAdditiveColumns);
    await _backfillLegacyAccounts();
  }

  Future<void> _ensureAdditiveColumns(String tableName, Map<String, String> columns) async {
    final existingColumns = await _tableColumns(tableName);
    for (final entry in columns.entries) {
      if (existingColumns.contains(entry.key)) {
        continue;
      }
      await customStatement('ALTER TABLE $tableName ADD COLUMN ${entry.key} ${entry.value}');
    }
  }

  Future<Set<String>> _tableColumns(String tableName) async {
    final rows = await customSelect('PRAGMA table_info($tableName)').get();
    return rows
        .map((row) => row.read<String>('name'))
        .where((name) => name.trim().isNotEmpty)
        .toSet();
  }

  Future<void> _backfillLegacyAccounts() async {
    final columns = await _tableColumns('accounts');

    if (columns.contains('enabled')) {
      await customStatement('UPDATE accounts SET enabled = 1 WHERE enabled IS NULL');
    }
    if (columns.contains('priority')) {
      await customStatement('UPDATE accounts SET priority = 0 WHERE priority IS NULL');
    }
    if (columns.contains('not_supported_models')) {
      await customStatement('''
        UPDATE accounts
        SET not_supported_models = ''
        WHERE not_supported_models IS NULL
      ''');
    }
    if (columns.contains('usage_count')) {
      await customStatement('UPDATE accounts SET usage_count = 0 WHERE usage_count IS NULL');
    }
    if (columns.contains('error_count')) {
      await customStatement('UPDATE accounts SET error_count = 0 WHERE error_count IS NULL');
    }
    if (columns.contains('id') && columns.contains('token_ref')) {
      await customStatement('''
        UPDATE accounts
        SET token_ref = 'kick.oauth.' || id
        WHERE token_ref IS NULL OR TRIM(token_ref) = ''
      ''');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _attachedDatabase.close();
  }
}

class _AttachedDatabase extends GeneratedDatabase {
  _AttachedDatabase(this._owner, super.executor);

  final AppDatabase _owner;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  int get schemaVersion => AppDatabase.schemaVersionValue;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {},
    onUpgrade: (_, from, to) async {
      await _owner.ensureSchema();
    },
    beforeOpen: (_) async {
      await _owner.ensureSchema();
    },
  );
}
