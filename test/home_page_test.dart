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
import 'package:kick/features/app_state/providers.dart';
import 'package:kick/features/home/home_page.dart';
import 'package:kick/features/settings/app_update_checker.dart';
import 'package:kick/features/shared/app_update_banner.dart';
import 'package:kick/l10n/generated/app_localizations.dart';
import 'package:kick/proxy/engine/proxy_controller.dart';
import 'package:kick/proxy/gemini/gemini_oauth_service.dart';

void main() {
  testWidgets('shows update banner on home page when update is available', (tester) async {
    final bootstrap = await _createBootstrap();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await bootstrap.dispose();
    });

    await tester.pumpWidget(
      _TestApp(
        bootstrap: bootstrap,
        updateInfo: const AppUpdateInfo(
          currentVersion: '1.0.2',
          latestVersion: '1.1.0',
          releaseUrl: 'https://example.com/releases/tag/v1.1.0',
          hasUpdate: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppUpdateBanner), findsOneWidget);
    expect(find.text('Доступно обновление'), findsOneWidget);
    expect(find.text('Открыть релиз'), findsOneWidget);
  });

  testWidgets('hides update banner on home page when no update is available', (tester) async {
    final bootstrap = await _createBootstrap();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await bootstrap.dispose();
    });

    await tester.pumpWidget(
      _TestApp(
        bootstrap: bootstrap,
        updateInfo: const AppUpdateInfo(
          currentVersion: '1.0.2',
          latestVersion: '1.0.2',
          releaseUrl: 'https://example.com/releases/tag/v1.0.2',
          hasUpdate: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppUpdateBanner), findsNothing);
    expect(find.text('Доступно обновление'), findsNothing);
  });

  testWidgets('disables the start button while proxy startup is pending', (tester) async {
    final bootstrap = await _createBootstrap();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await bootstrap.dispose();
    });

    await tester.pumpWidget(
      _TestApp(
        bootstrap: bootstrap,
        updateInfo: const AppUpdateInfo(
          currentVersion: '1.0.2',
          latestVersion: '1.0.2',
          releaseUrl: 'https://example.com/releases/tag/v1.0.2',
          hasUpdate: false,
        ),
        proxyState: ProxyRuntimeState.initial().copyWith(startPending: true),
      ),
    );
    await tester.pump();
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}

class _TestApp extends StatelessWidget {
  _TestApp({required this.bootstrap, required this.updateInfo, ProxyRuntimeState? proxyState})
    : proxyState = proxyState ?? ProxyRuntimeState.initial();

  final AppBootstrap bootstrap;
  final AppUpdateInfo updateInfo;
  final ProxyRuntimeState proxyState;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(bootstrap),
        clockTickerProvider.overrideWith((ref) => Stream.value(DateTime(2026, 3, 17))),
        proxyStatusProvider.overrideWith((ref) => Stream.value(proxyState)),
        appUpdateQueryProvider.overrideWith((ref) => updateInfo),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: HomePage()),
      ),
    );
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
