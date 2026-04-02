import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/analytics/android_background_session_log.dart';
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
  test('pages log state while keeping full matching export available', () async {
    final bootstrap = await _createBootstrap();
    final baseTime = DateTime.utc(2026, 3, 21, 12);
    for (var index = 0; index < 130; index++) {
      await bootstrap.logsRepository.insert(
        AppLogEntry(
          id: 'log-$index',
          timestamp: baseTime.add(Duration(minutes: index)),
          level: AppLogLevel.info,
          category: 'proxy',
          route: '/v1/chat/completions',
          message: 'Window entry $index',
          maskedPayload: '{"index":$index}',
        ),
      );
    }

    final container = ProviderContainer(
      overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
    );

    addTearDown(() async {
      container.dispose();
      await bootstrap.dispose();
    });

    final initial = await container.read(logsControllerProvider.future);
    expect(initial.totalCount, 130);
    expect(initial.filteredCount, 130);
    expect(initial.entries, hasLength(100));
    expect(initial.hasMore, isTrue);

    final exported = await container.read(logsControllerProvider.notifier).readAllMatchingEntries();
    expect(exported, hasLength(130));

    await container.read(logsControllerProvider.notifier).loadMore();

    final afterLoadMore = await container.read(logsControllerProvider.future);
    expect(afterLoadMore.entries, hasLength(130));
    expect(afterLoadMore.hasMore, isFalse);
  });

  test('hides internal lifecycle logs from the visible log state and export', () async {
    final bootstrap = await _createBootstrap();
    final baseTime = DateTime.utc(2026, 4, 2, 10);
    await bootstrap.logsRepository.insert(
      AppLogEntry(
        id: 'visible-log',
        timestamp: baseTime,
        level: AppLogLevel.info,
        category: 'proxy',
        route: '/v1/chat/completions',
        message: 'Visible entry',
        maskedPayload: '{"index":1}',
      ),
    );
    await bootstrap.logsRepository.insert(
      AppLogEntry(
        id: 'hidden-log',
        timestamp: baseTime.add(const Duration(minutes: 1)),
        level: AppLogLevel.info,
        category: androidBackgroundSessionCategory,
        route: '/android/background',
        message: androidBackgroundSessionStartedMessage,
        maskedPayload: '{"session_id":"bg-1"}',
      ),
    );

    final container = ProviderContainer(
      overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
    );

    addTearDown(() async {
      container.dispose();
      await bootstrap.dispose();
    });

    final state = await container.read(logsControllerProvider.future);
    expect(state.totalCount, 1);
    expect(state.filteredCount, 1);
    expect(state.categories, ['proxy']);
    expect(state.entries.map((entry) => entry.id), ['visible-log']);

    final exported = await container.read(logsControllerProvider.notifier).readAllMatchingEntries();
    expect(exported.map((entry) => entry.id), ['visible-log']);
  });
}

Future<AppBootstrap> _createBootstrap() async {
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
  final proxyController = KickProxyController(
    accountsRepository: accountsRepository,
    analytics: analytics,
    logsRepository: logsRepository,
    secretStore: secretStore,
  );

  return AppBootstrap(
    database: database,
    secretStore: secretStore,
    settingsRepository: settingsRepository,
    accountsRepository: accountsRepository,
    logsRepository: logsRepository,
    oauthService: GeminiOAuthService(secretStore: secretStore),
    analytics: analytics,
    proxyController: proxyController,
    initialSettings: AppSettings.defaults(
      apiKey: 'test-key',
    ).copyWith(androidBackgroundRuntime: false),
    initialAccounts: const <AccountProfile>[],
  );
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
