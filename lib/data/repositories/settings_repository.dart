import 'package:drift/drift.dart';

import '../app_database.dart';
import '../models/app_settings.dart';

class SettingsRepository {
  SettingsRepository(this._database);

  final AppDatabase _database;

  Future<AppSettings?> readSettings({required String apiKey}) async {
    final rows = await _database.customSelect('SELECT key, value FROM settings').get();
    if (rows.isEmpty) {
      return null;
    }

    final map = <String, String>{};
    for (final row in rows) {
      map[row.read<String>('key')] = row.read<String>('value');
    }

    map.remove('api_key');
    if (map.isEmpty) {
      return null;
    }

    return AppSettings.fromStorageMap(map, apiKey: apiKey);
  }

  Future<String?> readLegacyApiKey() async {
    final row = await _database
        .customSelect(
          'SELECT value FROM settings WHERE key = ?1 LIMIT 1',
          variables: [Variable<String>('api_key')],
        )
        .getSingleOrNull();
    final value = row?.read<String>('value').trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<void> deleteLegacyApiKey() async {
    await _database.customStatement('DELETE FROM settings WHERE key = ?1', ['api_key']);
  }

  Future<void> writeSettings(AppSettings settings) async {
    await _database.transaction(() async {
      await _database.customStatement('DELETE FROM settings WHERE key <> ?1', ['api_key']);
      for (final entry in settings.toStorageMap().entries) {
        await _database.customInsert(
          'INSERT INTO settings (key, value) VALUES (?1, ?2)',
          variables: [Variable<String>(entry.key), Variable<String>(entry.value)],
        );
      }
      await deleteLegacyApiKey();
    });
  }
}
