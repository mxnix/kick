import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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
import 'package:kick/features/accounts/accounts_page.dart';
import 'package:kick/features/app_state/providers.dart';
import 'package:kick/features/home/home_page.dart';
import 'package:kick/features/logs/logs_page.dart';
import 'package:kick/features/settings/app_update_checker.dart';
import 'package:kick/features/settings/settings_page.dart';
import 'package:kick/l10n/kick_localizations.dart';
import 'package:kick/proxy/engine/proxy_controller.dart';
import 'package:kick/proxy/gemini/gemini_oauth_service.dart';

void main() {
  for (final locale in const <Locale>[Locale('en'), Locale('ru'), Locale('uk')]) {
    testWidgets('renders key screens with locale ${locale.languageCode}', (tester) async {
      final bootstrap = await _createBootstrap();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await bootstrap.dispose();
      });

      Future<void> pumpPage(Widget page) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appBootstrapProvider.overrideWithValue(bootstrap),
              clockTickerProvider.overrideWith((ref) => Stream.value(DateTime(2026, 3, 17))),
              appUpdateQueryProvider.overrideWith(
                (ref) => const AppUpdateInfo(
                  currentVersion: '1.0.2',
                  latestVersion: '1.0.2',
                  releaseUrl: 'https://example.com/releases/tag/v1.0.2',
                  hasUpdate: false,
                ),
              ),
            ],
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: page),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
      }

      final l10n = lookupKickLocalizations(locale);

      await pumpPage(const HomePage());
      expect(find.text(l10n.homeTitle), findsOneWidget);

      await pumpPage(const AccountsPage());
      expect(find.text(l10n.accountsTitle), findsOneWidget);

      await pumpPage(const SettingsPage());
      expect(find.text(l10n.settingsTitle), findsOneWidget);

      await pumpPage(const LogsPage());
      expect(find.text(l10n.logsTitle), findsOneWidget);
    });
  }
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
  final initialSettings = AppSettings.defaults(
    apiKey: 'test-api-key',
  ).copyWith(androidBackgroundRuntime: false);

  return AppBootstrap(
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
