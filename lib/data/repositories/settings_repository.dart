import 'package:drift/drift.dart';

import '../app_database.dart';
import '../models/app_settings.dart';

class SettingsRepository {
  SettingsRepository(this._database);

  final AppDatabase _database;

  Future<AppSettings?> readSettings({required String apiKey}) async {
    final raw = await readAllRaw();
    return _parseSettings(raw, apiKey: apiKey);
  }

  /// Reads every row from the settings table in a single query. Useful at
  /// bootstrap time when the caller needs both [AppSettings] and auxiliary
  /// keys (window state, tray flag, scrub version, etc.) without paying for a
  /// separate `customSelect` for each lookup.
  Future<Map<String, String>> readAllRaw() async {
    final rows = await _database.customSelect('SELECT key, value FROM settings').get();
    final raw = <String, String>{};
    for (final row in rows) {
      raw[row.read<String>('key')] = row.read<String>('value');
    }
    return raw;
  }

  /// Parses [AppSettings] from a previously fetched raw map, returning `null`
  /// when none of the [AppSettings.storageKeys] are present (i.e. fresh
  /// install).
  static AppSettings? parseSettingsFromRaw(Map<String, String> raw, {required String apiKey}) {
    return _parseSettings(raw, apiKey: apiKey);
  }

  static AppSettings? _parseSettings(Map<String, String> raw, {required String apiKey}) {
    if (raw.isEmpty) {
      return null;
    }

    final filtered = <String, String>{};
    for (final entry in raw.entries) {
      if (AppSettings.storageKeys.contains(entry.key)) {
        filtered[entry.key] = entry.value;
      }
    }
    if (filtered.isEmpty) {
      return null;
    }
    return AppSettings.fromStorageMap(filtered, apiKey: apiKey);
  }

  static String? readNonEmptyString(Map<String, String> raw, String key) {
    final value = raw[key];
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  static bool readBoolFlag(Map<String, String> raw, String key, {bool defaultValue = false}) {
    final value = raw[key]?.trim();
    if (value == null || value.isEmpty) {
      return defaultValue;
    }
    return value == 'true';
  }

  Future<String?> readLegacyApiKey() async {
    final row = await _database
        .customSelect(
          'SELECT value FROM settings WHERE key = ?1 LIMIT 1',
          variables: [const Variable<String>('api_key')],
        )
        .getSingleOrNull();
    final value = row?.read<String>('value').trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  /// Variant of [readLegacyApiKey] that operates on a previously fetched
  /// raw settings map, avoiding an extra `SELECT` round-trip during bootstrap.
  static String? readLegacyApiKeyFromRaw(Map<String, String> raw) {
    final value = raw['api_key']?.trim();
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
      final storageMap = settings.toStorageMap();
      final keys = storageMap.keys.toList(growable: false);
      final placeholders = List.generate(keys.length, (index) => '?${index + 1}').join(', ');
      await _database.customStatement('DELETE FROM settings WHERE key IN ($placeholders)', keys);
      for (final entry in storageMap.entries) {
        await _database.customInsert(
          'INSERT OR REPLACE INTO settings (key, value) VALUES (?1, ?2)',
          variables: [Variable<String>(entry.key), Variable<String>(entry.value)],
        );
      }
      await deleteLegacyApiKey();
    });
  }

  Future<String?> readStringValue(String key) async {
    final row = await _database
        .customSelect(
          'SELECT value FROM settings WHERE key = ?1 LIMIT 1',
          variables: [Variable<String>(key)],
        )
        .getSingleOrNull();
    final value = row?.read<String>('value');
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<void> writeStringValue(String key, String value) async {
    await _database.customInsert(
      'INSERT OR REPLACE INTO settings (key, value) VALUES (?1, ?2)',
      variables: [Variable<String>(key), Variable<String>(value)],
    );
  }

  Future<bool> readBooleanFlag(String key, {bool defaultValue = false}) async {
    final row = await _database
        .customSelect(
          'SELECT value FROM settings WHERE key = ?1 LIMIT 1',
          variables: [Variable<String>(key)],
        )
        .getSingleOrNull();
    final value = row?.read<String>('value').trim();
    if (value == null || value.isEmpty) {
      return defaultValue;
    }
    return value == 'true';
  }

  Future<void> writeBooleanFlag(String key, bool value) async {
    await _database.customInsert(
      'INSERT OR REPLACE INTO settings (key, value) VALUES (?1, ?2)',
      variables: [Variable<String>(key), Variable<String>(value.toString())],
    );
  }
}
