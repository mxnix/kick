import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

class AppDatabase extends DatabaseConnectionUser {
  static const schemaVersionValue = 2;

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
    onUpgrade: (_, from, to) async {},
    beforeOpen: (_) async {
      await _owner.ensureSchema();
    },
  );
}
