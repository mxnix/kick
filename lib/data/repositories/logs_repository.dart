import 'package:drift/drift.dart';

import '../../core/logging/log_sanitizer.dart';
import '../app_database.dart';
import '../models/app_log_entry.dart';

class LogsRepository {
  LogsRepository(this._database);

  final AppDatabase _database;

  Future<List<AppLogEntry>> readAll({int limit = 300}) async {
    final rows = await _database
        .customSelect(
          'SELECT * FROM logs ORDER BY timestamp DESC LIMIT ?1',
          variables: [Variable<int>(limit)],
        )
        .get();
    return rows.map((row) => AppLogEntry.fromDatabaseMap(row.data)).toList(growable: false);
  }

  Future<void> insert(AppLogEntry entry) async {
    await _database.customInsert(
      '''
      INSERT INTO logs (
        id, timestamp, level, category, route, message, masked_payload, raw_payload
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
      ''',
      variables: [
        Variable<String>(entry.id),
        Variable<String>(entry.timestamp.toIso8601String()),
        Variable<String>(entry.level.name),
        Variable<String>(entry.category),
        Variable<String>(entry.route ?? ''),
        Variable<String>(entry.message),
        Variable<String>(entry.maskedPayload ?? ''),
        Variable<String>(entry.rawPayload ?? ''),
      ],
    );

    await _database.customStatement('''
      DELETE FROM logs
      WHERE id NOT IN (
        SELECT id FROM logs ORDER BY timestamp DESC LIMIT 500
      )
    ''');
  }

  Future<void> clear() async {
    await _database.customStatement('DELETE FROM logs');
  }

  Future<void> scrubSensitiveEntries({required bool clearRawPayload}) async {
    final entries = await readAll(limit: 500);
    if (entries.isEmpty) {
      return;
    }

    await _database.transaction(() async {
      for (final entry in entries) {
        final sanitizedMaskedPayload = LogSanitizer.sanitizeSerializedPayload(entry.maskedPayload);
        final nextRawPayload = clearRawPayload ? '' : (entry.rawPayload ?? '');
        final currentRawPayload = entry.rawPayload ?? '';
        final nextMaskedPayload = sanitizedMaskedPayload ?? '';
        final currentMaskedPayload = entry.maskedPayload ?? '';

        if (nextMaskedPayload == currentMaskedPayload && nextRawPayload == currentRawPayload) {
          continue;
        }

        await _database.customStatement(
          'UPDATE logs SET masked_payload = ?1, raw_payload = ?2 WHERE id = ?3',
          [nextMaskedPayload, nextRawPayload, entry.id],
        );
      }
    });
  }
}
