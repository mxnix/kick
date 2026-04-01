import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/analytics/kick_analytics.dart';
import 'package:kick/app/bootstrap.dart';
import 'package:kick/data/app_database.dart';
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/data/models/app_settings.dart';
import 'package:kick/data/repositories/accounts_repository.dart';
import 'package:kick/data/repositories/logs_repository.dart';
import 'package:kick/data/repositories/secret_store.dart';
import 'package:kick/data/repositories/settings_repository.dart';
import 'package:kick/features/app_state/providers.dart';
import 'package:kick/proxy/engine/proxy_controller.dart';
import 'package:kick/proxy/gemini/gemini_oauth_service.dart';

void main() {
  test('resetHealth clears runtime unsupported models without removing manual ones', () async {
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
    final account = AccountProfile(
      id: 'primary',
      label: 'Primary',
      email: 'primary@example.com',
      projectId: 'project-1',
      enabled: true,
      priority: 1,
      notSupportedModels: const ['manual-model'],
      runtimeNotSupportedModels: const ['runtime-model'],
      lastUsedAt: null,
      usageCount: 3,
      errorCount: 2,
      cooldownUntil: DateTime.now().add(const Duration(minutes: 5)),
      lastQuotaSnapshot: 'Quota exhausted recently.',
      tokenRef: 'primary-ref',
    );
    await accountsRepository.upsert(account);
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
        apiKey: 'test-key',
      ).copyWith(androidBackgroundRuntime: false),
      initialAccounts: [account],
    );
    final container = ProviderContainer(
      overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
    );

    addTearDown(() async {
      container.dispose();
      await bootstrap.dispose();
    });

    await container.read(accountsControllerProvider.future);
    await container.read(accountsControllerProvider.notifier).resetHealth(account);

    final accounts = await container.read(accountsControllerProvider.future);
    expect(accounts, hasLength(1));

    final updated = accounts.single;
    expect(updated.notSupportedModels, ['google/manual-model']);
    expect(updated.runtimeNotSupportedModels, isEmpty);
    expect(updated.effectiveNotSupportedModels, ['google/manual-model']);
    expect(updated.errorCount, 0);
    expect(updated.cooldownUntil, isNull);
    expect(updated.lastQuotaSnapshot, isNull);
  });
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
