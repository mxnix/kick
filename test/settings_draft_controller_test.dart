import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/data/models/app_settings.dart';
import 'package:kick/features/settings/settings_draft_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsDraftController', () {
    AppSettings buildSettings() => AppSettings.defaults(apiKey: 'kick_test');

    test('shows validation error and skips saving invalid draft', () async {
      var saveCalls = 0;
      final controller = SettingsDraftController(
        saveSettings: (_) async {
          saveCalls += 1;
        },
        regenerateApiKey: () async => 'regenerated-key',
        saveDebounceDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.syncWithSettings(buildSettings());
      controller.hostController.text = '';

      await Future<void>.delayed(Duration.zero);

      expect(controller.saveState, SettingsDraftSaveState.validationError);
      expect(controller.showSaveStatus, isTrue);
      expect(saveCalls, 0);
    });

    test('queues the latest draft while a save is already running', () async {
      final startedFirstSave = Completer<void>();
      final releaseFirstSave = Completer<void>();
      final savedSettings = <AppSettings>[];
      final controller = SettingsDraftController(
        saveSettings: (settings) async {
          savedSettings.add(settings);
          if (savedSettings.length == 1) {
            startedFirstSave.complete();
            await releaseFirstSave.future;
          }
        },
        regenerateApiKey: () async => 'regenerated-key',
        saveDebounceDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.syncWithSettings(buildSettings());
      controller.hostController.text = '192.168.0.10';

      await startedFirstSave.future;

      controller.portController.text = '4000';
      await Future<void>.delayed(Duration.zero);

      expect(savedSettings, hasLength(1));

      releaseFirstSave.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(savedSettings, hasLength(2));
      expect(savedSettings.first.host, '192.168.0.10');
      expect(savedSettings.first.port, 3000);
      expect(savedSettings.last.host, '192.168.0.10');
      expect(savedSettings.last.port, 4000);
      expect(controller.saveState, SettingsDraftSaveState.saved);
    });

    test('updates the draft after api key regeneration', () async {
      final controller = SettingsDraftController(
        saveSettings: (_) async {},
        regenerateApiKey: () async => 'regenerated-key',
        saveDebounceDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.syncWithSettings(buildSettings());
      final apiKey = await controller.regenerateApiKey();

      expect(apiKey, 'regenerated-key');
      expect(controller.apiKeyController.text, 'regenerated-key');
      expect(controller.saveState, SettingsDraftSaveState.saved);
      expect(controller.showSaveStatus, isTrue);
    });

    test('persists log retention changes when the draft is valid', () async {
      final savedSettings = <AppSettings>[];
      final controller = SettingsDraftController(
        saveSettings: (settings) async {
          savedSettings.add(settings);
        },
        regenerateApiKey: () async => 'regenerated-key',
        saveDebounceDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.syncWithSettings(buildSettings());
      controller.logRetentionController.text = '2400';

      await Future<void>.delayed(Duration.zero);

      expect(savedSettings, isNotEmpty);
      expect(savedSettings.last.logRetentionCount, 2400);
      expect(controller.saveState, SettingsDraftSaveState.saved);
    });

    test('persists explicit app locale changes when the draft is valid', () async {
      final savedSettings = <AppSettings>[];
      final controller = SettingsDraftController(
        saveSettings: (settings) async {
          savedSettings.add(settings);
        },
        regenerateApiKey: () async => 'regenerated-key',
        saveDebounceDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.syncWithSettings(buildSettings());
      controller.setAppLocale(const Locale('ru'));

      await Future<void>.delayed(Duration.zero);

      expect(savedSettings, isNotEmpty);
      expect(savedSettings.last.appLocale, const Locale('ru'));
      expect(controller.saveState, SettingsDraftSaveState.saved);
    });

    test('rehydrates the draft when settings change externally', () async {
      final controller = SettingsDraftController(
        saveSettings: (_) async {},
        regenerateApiKey: () async => 'regenerated-key',
        saveDebounceDuration: const Duration(milliseconds: 10),
      );
      addTearDown(controller.dispose);

      controller.syncWithSettings(buildSettings());
      controller.hostController.text = '192.168.0.10';
      await controller.settlePendingSaves();

      controller.syncWithSettings(
        AppSettings.defaults(
          apiKey: 'restored-key',
        ).copyWith(host: '10.0.0.5', port: 4010, customModels: const ['gemini-2.5-flash']),
      );

      expect(controller.apiKeyController.text, 'restored-key');
      expect(controller.appLocale, isNull);
      expect(controller.hostController.text, '10.0.0.5');
      expect(controller.portController.text, '4010');
      expect(controller.customModelsController.text, 'gemini-2.5-flash');
    });
  });
}
