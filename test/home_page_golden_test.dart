import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/analytics/kick_analytics.dart';
import 'package:kick/app/bootstrap.dart';
import 'package:kick/core/theme/kick_theme.dart';
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
import 'package:kick/l10n/generated/app_localizations.dart';
import 'package:kick/proxy/engine/proxy_controller.dart';
import 'package:kick/proxy/gemini/gemini_oauth_service.dart';

void main() {
  testWidgets('home page matches desktop light golden', (tester) async {
    await _expectHomePageGolden(
      tester,
      goldenFile: 'goldens/home_page.png',
      physicalSize: const Size(2880, 2200),
      devicePixelRatio: 2,
      themeMode: ThemeMode.light,
    );
  });

  testWidgets('home page matches phone dark golden', (tester) async {
    await _expectHomePageGolden(
      tester,
      goldenFile: 'goldens/home_page_phone_dark.png',
      physicalSize: const Size(1170, 2532),
      devicePixelRatio: 3,
      themeMode: ThemeMode.dark,
    );
  });
}

Future<void> _expectHomePageGolden(
  WidgetTester tester, {
  required String goldenFile,
  required Size physicalSize,
  required double devicePixelRatio,
  required ThemeMode themeMode,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final bootstrap = await _createBootstrap(themeMode: themeMode);
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
      themeMode: themeMode,
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();

  await expectLater(find.byType(Scaffold), matchesGoldenFile(goldenFile));
}

class _TestApp extends StatelessWidget {
  _TestApp({
    required this.bootstrap,
    required this.updateInfo,
    required this.themeMode,
    ProxyRuntimeState? proxyState,
  }) : proxyState = proxyState ?? ProxyRuntimeState.initial();

  final AppBootstrap bootstrap;
  final AppUpdateInfo updateInfo;
  final ThemeMode themeMode;
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
        debugShowCheckedModeBanner: false,
        theme: KickThemeData.build(KickSchemes.light),
        darkTheme: KickThemeData.build(KickSchemes.dark),
        themeMode: themeMode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: HomePage()),
      ),
    );
  }
}

Future<AppBootstrap> _createBootstrap({required ThemeMode themeMode}) async {
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
  ).copyWith(androidBackgroundRuntime: false, themeMode: themeMode, useDynamicColor: false);

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
