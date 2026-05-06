import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/analytics/kick_analytics.dart';
import 'package:kick/app/bootstrap.dart';
import 'package:kick/data/app_database.dart';
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/data/models/app_log_entry.dart';
import 'package:kick/data/models/app_settings.dart';
import 'package:kick/data/repositories/accounts_repository.dart';
import 'package:kick/data/repositories/logs_repository.dart';
import 'package:kick/data/repositories/secret_store.dart';
import 'package:kick/data/repositories/settings_repository.dart';
import 'package:kick/features/app_state/providers.dart';
import 'package:kick/proxy/engine/proxy_controller.dart';
import 'package:kick/proxy/gemini/gemini_oauth_service.dart';

void main() {
  testWidgets('continues proxy sync after a failed configure', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    await database.ensureSchema();
    final secretStore = SecretStore(backend: _MemorySecretStoreBackend());
    final settingsRepository = SettingsRepository(database);
    final accountsRepository = AccountsRepository(database);
    final logsRepository = LogsRepository(database);
    final analytics = KickAnalytics(
      config: const AnalyticsBuildConfig(buildChannel: 'test', appKey: ''),
      transport: const NoOpAnalyticsTransport(),
    );
    final proxyController = _FailOnceProxyController(
      accountsRepository: accountsRepository,
      analytics: analytics,
      logsRepository: logsRepository,
      secretStore: secretStore,
    );
    final initialSettings = AppSettings.defaults(
      apiKey: 'initial-key',
    ).copyWith(androidBackgroundRuntime: false);
    final bootstrap = AppBootstrap(
      database: database,
      secretStore: secretStore,
      settingsRepository: settingsRepository,
      accountsRepository: accountsRepository,
      logsRepository: logsRepository,
      oauthService: GeminiOAuthService(secretStore: secretStore),
      analytics: analytics,
      proxyController: proxyController,
      initialSettings: initialSettings,
      initialAccounts: const <AccountProfile>[],
    );

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await bootstrap.dispose();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
        child: const MaterialApp(home: ProxyConfigurationSync(child: SizedBox.shrink())),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(proxyController.configureCallCount, 1);
    tester.takeException();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProxyConfigurationSync)),
    );
    await container
        .read(settingsControllerProvider.notifier)
        .save(initialSettings.copyWith(port: 4010));
    await tester.pump();
    await tester.pump();

    expect(proxyController.configureCallCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refreshes logs after repeated proxy log activity events', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    await database.ensureSchema();
    final secretStore = SecretStore(backend: _MemorySecretStoreBackend());
    final settingsRepository = SettingsRepository(database);
    final accountsRepository = AccountsRepository(database);
    final logsRepository = LogsRepository(database);
    final analytics = KickAnalytics(
      config: const AnalyticsBuildConfig(buildChannel: 'test', appKey: ''),
      transport: const NoOpAnalyticsTransport(),
    );
    final proxyController = _ActivityProxyController(
      accountsRepository: accountsRepository,
      analytics: analytics,
      logsRepository: logsRepository,
      secretStore: secretStore,
    );
    final bootstrap = AppBootstrap(
      database: database,
      secretStore: secretStore,
      settingsRepository: settingsRepository,
      accountsRepository: accountsRepository,
      logsRepository: logsRepository,
      oauthService: GeminiOAuthService(secretStore: secretStore),
      analytics: analytics,
      proxyController: proxyController,
      initialSettings: AppSettings.defaults(
        apiKey: 'initial-key',
      ).copyWith(androidBackgroundRuntime: false),
      initialAccounts: const <AccountProfile>[],
    );

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await bootstrap.dispose();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
        child: const MaterialApp(home: ProxyConfigurationSync(child: SizedBox.shrink())),
      ),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProxyConfigurationSync)),
    );
    final initial = await container.read(logsControllerProvider.future);
    expect(initial.entries, isEmpty);

    final baseTime = DateTime.utc(2026, 4, 7, 11);
    await logsRepository.insert(
      AppLogEntry(
        id: 'first-log',
        timestamp: baseTime,
        level: AppLogLevel.info,
        category: 'proxy',
        route: '/v1/chat/completions',
        message: 'First entry',
        maskedPayload: '{"index":1}',
      ),
    );
    proxyController.emitActivity('logs');

    final afterFirst = await _pumpUntilLogsVisible(tester, container, expectedCount: 1);
    expect(afterFirst.entries.map((entry) => entry.id), ['first-log']);

    await logsRepository.insert(
      AppLogEntry(
        id: 'second-log',
        timestamp: baseTime.add(const Duration(seconds: 1)),
        level: AppLogLevel.info,
        category: 'proxy',
        route: '/v1/chat/completions',
        message: 'Second entry',
        maskedPayload: '{"index":2}',
      ),
    );
    proxyController.emitActivity('logs');

    final afterSecond = await _pumpUntilLogsVisible(tester, container, expectedCount: 2);
    expect(afterSecond.entries.map((entry) => entry.id).take(2), ['second-log', 'first-log']);
    expect(afterSecond.appearingEntryIds, {'second-log'});
  });
}

class _FailOnceProxyController extends KickProxyController {
  _FailOnceProxyController({
    required super.accountsRepository,
    required super.analytics,
    required super.logsRepository,
    required super.secretStore,
  });

  int configureCallCount = 0;

  @override
  Future<void> configure({
    required AppSettings settings,
    required List<AccountProfile> accounts,
  }) async {
    configureCallCount += 1;
    if (configureCallCount == 1) {
      throw StateError('configure failed once');
    }
  }
}

class _ActivityProxyController extends KickProxyController {
  _ActivityProxyController({
    required super.accountsRepository,
    required super.analytics,
    required super.logsRepository,
    required super.secretStore,
  });

  final _activityController = StreamController<String>.broadcast();

  @override
  Stream<String> get activity => _activityController.stream;

  void emitActivity(String value) {
    _activityController.add(value);
  }

  @override
  Future<void> configure({
    required AppSettings settings,
    required List<AccountProfile> accounts,
  }) async {}

  @override
  Future<void> dispose() async {
    await _activityController.close();
    await super.dispose();
  }
}

Future<LogsViewState> _pumpUntilLogsVisible(
  WidgetTester tester,
  ProviderContainer container, {
  required int expectedCount,
}) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    final state = container.read(logsControllerProvider).asData?.value;
    if (state != null && state.entries.length == expectedCount) {
      return state;
    }
  }
  fail('Expected $expectedCount visible log entries.');
}

class _MemorySecretStoreBackend implements SecretStoreBackend {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
