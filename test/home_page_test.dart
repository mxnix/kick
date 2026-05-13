import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/analytics/kick_analytics.dart';
import 'package:kick/app/bootstrap.dart';
import 'package:kick/core/theme/kick_icons.dart';
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
import 'package:kick/features/shared/app_update_banner.dart';
import 'package:kick/features/shared/kick_actions.dart';
import 'package:kick/features/shared/kick_surfaces.dart';
import 'package:kick/l10n/kick_localizations.dart';
import 'package:kick/proxy/engine/proxy_controller.dart';
import 'package:kick/proxy/gemini/gemini_oauth_service.dart';

void main() {
  final enL10n = lookupKickLocalizations(const Locale('en'));
  final ruL10n = lookupKickLocalizations(const Locale('ru'));

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
          installerUrl: 'https://example.com/releases/download/v1.1.0/kick-windows-1.1.0-setup.exe',
          installerFileName: 'kick-windows-1.1.0-setup.exe',
          checksumUrl: 'https://example.com/releases/download/v1.1.0/kick-1.1.0-checksums.txt',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppUpdateBanner), findsOneWidget);
    expect(find.text(enL10n.aboutUpdateAvailableTitle), findsOneWidget);
    expect(find.text(enL10n.aboutDownloadUpdateButton), findsOneWidget);
    expect(find.text(enL10n.aboutOpenReleaseButton), findsOneWidget);
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
    expect(find.text(enL10n.aboutUpdateAvailableTitle), findsNothing);
  });

  testWidgets('shows onboarding when there are no active accounts', (tester) async {
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

    expect(find.text(enL10n.connectAccountShortButton), findsOneWidget);
    expect(find.text(enL10n.homeOnboardingTitle), findsOneWidget);
  });

  testWidgets('shows localhost endpoint for loopback proxy access', (tester) async {
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

    expect(find.textContaining('http://localhost:3000/v1', findRichText: true), findsWidgets);
    expect(find.textContaining('127.0.0.1', findRichText: true), findsNothing);
  });

  testWidgets('hides API key copy action when API key is disabled', (tester) async {
    final bootstrap = await _createBootstrap(
      initialSettings: AppSettings.defaults(
        apiKey: 'test-api-key',
      ).copyWith(apiKeyRequired: false, androidBackgroundRuntime: false),
    );
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

    expect(find.text(enL10n.apiKeyDisabledValue), findsOneWidget);
    expect(find.byTooltip(enL10n.copyApiKeyTooltip), findsNothing);
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
    expect(find.byType(KickLoadingIndicator), findsOneWidget);
  });

  testWidgets('builds the home page with the Russian locale enabled', (tester) async {
    final bootstrap = await _createBootstrap();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await bootstrap.dispose();
    });

    await tester.pumpWidget(
      _TestApp(
        bootstrap: bootstrap,
        locale: const Locale('ru'),
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

    expect(find.text(ruL10n.homeTitle), findsOneWidget);
    expect(find.text(ruL10n.homeOnboardingTitle), findsOneWidget);
  });

  testWidgets('stretches inline proxy status on phone layouts', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;

    AppBootstrap? bootstrap;
    try {
      bootstrap = await _createBootstrap();

      await tester.pumpWidget(
        _TestApp(
          bootstrap: bootstrap,
          locale: const Locale('ru'),
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

      final heroRect = tester.getRect(find.byType(KickPanel).first);
      final statusRect = tester.getRect(find.text(ruL10n.proxyStoppedStatus));
      expect((statusRect.center.dx - heroRect.center.dx).abs(), lessThan(24));
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpWidget(const SizedBox.shrink());
      await bootstrap?.dispose();
    }
  });

  testWidgets('keeps inline proxy status right aligned on wide layouts', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;

    AppBootstrap? bootstrap;
    try {
      bootstrap = await _createBootstrap();

      await tester.pumpWidget(
        _TestApp(
          bootstrap: bootstrap,
          locale: const Locale('ru'),
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

      final heroRect = tester.getRect(find.byType(KickPanel).first);
      final statusRect = tester.getRect(find.text(ruL10n.proxyStoppedStatus));
      expect(statusRect.center.dx, greaterThan(heroRect.center.dx + 80));
      expect(heroRect.right - statusRect.right, lessThan(48));
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpWidget(const SizedBox.shrink());
      await bootstrap?.dispose();
    }
  });

  testWidgets('hides inline proxy status on Linux desktop layouts', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.view.physicalSize = const Size(430, 860);
    tester.view.devicePixelRatio = 1;

    AppBootstrap? bootstrap;
    try {
      bootstrap = await _createBootstrap();

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

      expect(find.text(enL10n.proxyStoppedStatus), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpWidget(const SizedBox.shrink());
      await bootstrap?.dispose();
    }
  });

  testWidgets('primary action elides long labels in narrow layouts', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KickThemeData.build(KickSchemes.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              child: KickPrimaryAction(
                label: 'Очень длинное действие, которое должно поместиться',
                icon: KickIcons.play,
                fullWidth: true,
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}

class _TestApp extends StatelessWidget {
  _TestApp({
    required this.bootstrap,
    required this.updateInfo,
    this.locale,
    ProxyRuntimeState? proxyState,
  }) : proxyState = proxyState ?? ProxyRuntimeState.initial();

  final AppBootstrap bootstrap;
  final AppUpdateInfo updateInfo;
  final Locale? locale;
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
        locale: locale ?? const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: HomePage()),
      ),
    );
  }
}

Future<AppBootstrap> _createBootstrap({AppSettings? initialSettings}) async {
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
  final resolvedInitialSettings =
      initialSettings ??
      AppSettings.defaults(apiKey: 'test-api-key').copyWith(androidBackgroundRuntime: false);

  return AppBootstrap(
    database: database,
    secretStore: secretStore,
    settingsRepository: settingsRepository,
    accountsRepository: accountsRepository,
    logsRepository: logsRepository,
    oauthService: GeminiOAuthService(secretStore: secretStore),
    analytics: analytics,
    proxyController: proxyController,
    initialSettings: resolvedInitialSettings,
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
