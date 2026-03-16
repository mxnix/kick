import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kick/data/app_database.dart';
import 'package:kick/data/models/app_settings.dart';
import 'package:kick/data/repositories/settings_repository.dart';

void main() {
  test('keeps proxy api key out of sqlite settings rows', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick-settings-repo');
    addTearDown(() => tempDirectory.delete(recursive: true));

    final database = await AppDatabase.open('${tempDirectory.path}${Platform.pathSeparator}kick.sqlite');
    addTearDown(database.close);

    final repository = SettingsRepository(database);
    await database.customStatement(
      'INSERT INTO settings (key, value) VALUES (?1, ?2)',
      ['api_key', 'legacy-key'],
    );

    expect(await repository.readLegacyApiKey(), 'legacy-key');

    await repository.writeSettings(AppSettings.defaults(apiKey: 'secure-key'));

    final rows = await database.customSelect('SELECT key FROM settings').get();
    expect(rows.any((row) => row.read<String>('key') == 'api_key'), isFalse);

    final restored = await repository.readSettings(apiKey: 'secure-key');
    expect(restored, isNotNull);
    expect(restored?.apiKey, 'secure-key');
  });
}
