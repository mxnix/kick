import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/analytics/kick_analytics.dart';
import 'package:kick/app/bootstrap.dart';
import 'package:kick/core/platform/android_auth_keep_alive.dart';
import 'package:kick/data/app_database.dart';
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/data/models/app_settings.dart';
import 'package:kick/data/repositories/accounts_repository.dart';
import 'package:kick/data/repositories/logs_repository.dart';
import 'package:kick/data/repositories/secret_store.dart';
import 'package:kick/data/repositories/settings_repository.dart';
import 'package:kick/features/accounts/accounts_page.dart';
import 'package:kick/features/app_state/providers.dart';
import 'package:kick/l10n/generated/app_localizations.dart';
import 'package:kick/proxy/engine/proxy_controller.dart';
import 'package:kick/proxy/gemini/gemini_oauth_service.dart';
import 'package:kick/proxy/kiro/kiro_auth_source.dart';
import 'package:kick/proxy/kiro/kiro_link_auth_service.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

void main() {
  testWidgets('kiro account card does not show source badge', (tester) async {
    final bootstrap = await _createBootstrap(
      initialAccounts: [
        AccountProfile(
          id: 'kiro-1',
          label: 'Kiro',
          email: 'AWS Builder ID',
          projectId: '',
          provider: AccountProvider.kiro,
          providerRegion: defaultKiroRegion,
          credentialSourceType: builderIdKiroCredentialSourceType,
          credentialSourcePath: r'C:\Users\demo\AppData\Roaming\KiCk\kiro-auth-demo.json',
          enabled: true,
          priority: 0,
          notSupportedModels: const [],
          lastUsedAt: null,
          usageCount: 0,
          errorCount: 0,
          cooldownUntil: null,
          lastQuotaSnapshot: null,
          tokenRef: 'kiro-ref',
        ),
      ],
    );
    final service = _FakeKiroLinkAuthService(
      request: KiroLinkAuthRequest(
        clientId: 'client-id',
        clientSecret: 'client-secret',
        deviceCode: 'device-code',
        userCode: 'PSZF-PDMS',
        verificationUri: 'https://view.awsapps.com/start/#/device',
        verificationUriComplete: 'https://view.awsapps.com/start/#/device?user_code=PSZF-PDMS',
        interval: const Duration(seconds: 1),
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        region: defaultKiroRegion,
        startUrl: defaultKiroBuilderIdStartUrl,
      ),
      completion: Completer<KiroAuthSourceSnapshot>().future,
    );

    addTearDown(() async {
      service.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await bootstrap.dispose();
    });

    await tester.pumpWidget(_TestApp(bootstrap: bootstrap, kiroLinkAuthService: service));
    await tester.pump();
    await tester.pump();

    expect(find.text('Kiro'), findsWidgets);
    expect(find.text('AWS Builder ID'), findsOneWidget);
    expect(find.textContaining('Источник:'), findsNothing);
    expect(find.text('Источник: Builder ID'), findsNothing);
  });

  testWidgets('kiro link authorization dialog removes code copy action', (tester) async {
    final bootstrap = await _createBootstrap();
    final completion = Completer<KiroAuthSourceSnapshot>();
    final service = _FakeKiroLinkAuthService(
      request: KiroLinkAuthRequest(
        clientId: 'client-id',
        clientSecret: 'client-secret',
        deviceCode: 'device-code',
        userCode: 'PSZF-PDMS',
        verificationUri: 'https://view.awsapps.com/start/#/device',
        verificationUriComplete: 'https://view.awsapps.com/start/#/device?user_code=PSZF-PDMS',
        interval: const Duration(seconds: 1),
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        region: defaultKiroRegion,
        startUrl: defaultKiroBuilderIdStartUrl,
      ),
      completion: completion.future,
    );

    addTearDown(() async {
      if (!completion.isCompleted) {
        completion.complete(
          KiroAuthSourceSnapshot(
            sourcePath: r'C:\Users\demo\AppData\Roaming\KiCk\kiro-auth-demo.json',
            sourceType: builderIdKiroCredentialSourceType,
            accessToken: 'access-token',
            refreshToken: 'refresh-token',
            expiry: DateTime.now().add(const Duration(hours: 1)),
            region: defaultKiroRegion,
            profileArn: 'arn:aws:iam::123456789012:user/demo',
            authMethod: builderIdKiroAuthMethod,
            provider: 'kiro',
            clientId: 'client-id',
            clientSecret: 'client-secret',
            startUrl: defaultKiroBuilderIdStartUrl,
          ),
        );
      }
      service.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await bootstrap.dispose();
    });

    await tester.pumpWidget(_TestApp(bootstrap: bootstrap, kiroLinkAuthService: service));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Подключить аккаунт'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kiro'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Авторизация Kiro'), findsOneWidget);
    expect(find.text('Код для сверки'), findsOneWidget);
    expect(find.textContaining('вводить его не нужно'), findsOneWidget);
    expect(find.text('Скопировать код'), findsNothing);
  });

  testWidgets(
    'kiro link authorization dialog shows localized failure snackbar when link open fails',
    (tester) async {
      final bootstrap = await _createBootstrap();
      final completion = Completer<KiroAuthSourceSnapshot>();
      final originalUrlLauncher = UrlLauncherPlatform.instance;
      final service = _FakeKiroLinkAuthService(
        request: KiroLinkAuthRequest(
          clientId: 'client-id',
          clientSecret: 'client-secret',
          deviceCode: 'device-code',
          userCode: 'PSZF-PDMS',
          verificationUri: 'https://view.awsapps.com/start/#/device',
          verificationUriComplete: 'https://view.awsapps.com/start/#/device?user_code=PSZF-PDMS',
          interval: const Duration(seconds: 1),
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
          region: defaultKiroRegion,
          startUrl: defaultKiroBuilderIdStartUrl,
        ),
        completion: completion.future,
      );
      UrlLauncherPlatform.instance = _FailingUrlLauncherPlatform();

      addTearDown(() async {
        UrlLauncherPlatform.instance = originalUrlLauncher;
        if (!completion.isCompleted) {
          completion.complete(
            KiroAuthSourceSnapshot(
              sourcePath: r'C:\Users\demo\AppData\Roaming\KiCk\kiro-auth-demo.json',
              sourceType: builderIdKiroCredentialSourceType,
              accessToken: 'access-token',
              refreshToken: 'refresh-token',
              expiry: DateTime.now().add(const Duration(hours: 1)),
              region: defaultKiroRegion,
              profileArn: 'arn:aws:iam::123456789012:user/demo',
              authMethod: builderIdKiroAuthMethod,
              provider: 'kiro',
              clientId: 'client-id',
              clientSecret: 'client-secret',
              startUrl: defaultKiroBuilderIdStartUrl,
            ),
          );
        }
        service.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await bootstrap.dispose();
      });

      await tester.pumpWidget(_TestApp(bootstrap: bootstrap, kiroLinkAuthService: service));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Подключить аккаунт'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kiro'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final l10n = AppLocalizations.of(tester.element(find.byType(AccountsPage)));
      expect(find.text(l10n.kiroLinkAuthOpenLinkFailedMessage), findsOneWidget);
    },
  );

  testWidgets('kiro link authorization keeps Android auth runtime alive while dialog is open', (
    tester,
  ) async {
    final bootstrap = await _createBootstrap();
    final completion = Completer<KiroAuthSourceSnapshot>();
    String? startedNotificationTitle;
    var stopCalls = 0;
    final keepAlive = AndroidAuthKeepAlive(
      isProxyRunning: () => false,
      startTemporaryRuntime: ({String? notificationTitle}) async {
        startedNotificationTitle = notificationTitle;
        return true;
      },
      stopRuntimeIfRunning: () async {
        stopCalls += 1;
      },
    );
    final service = _FakeKiroLinkAuthService(
      request: KiroLinkAuthRequest(
        clientId: 'client-id',
        clientSecret: 'client-secret',
        deviceCode: 'device-code',
        userCode: 'PSZF-PDMS',
        verificationUri: 'https://view.awsapps.com/start/#/device',
        verificationUriComplete: 'https://view.awsapps.com/start/#/device?user_code=PSZF-PDMS',
        interval: const Duration(seconds: 1),
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        region: defaultKiroRegion,
        startUrl: defaultKiroBuilderIdStartUrl,
      ),
      completion: completion.future,
    );

    addTearDown(() async {
      if (!completion.isCompleted) {
        completion.completeError(StateError('cancelled'));
      }
      service.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await bootstrap.dispose();
    });

    await tester.pumpWidget(
      _TestApp(bootstrap: bootstrap, kiroLinkAuthService: service, androidAuthKeepAlive: keepAlive),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Подключить аккаунт'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kiro'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final l10n = AppLocalizations.of(tester.element(find.byType(AccountsPage)));
    expect(find.text(l10n.kiroLinkAuthDialogTitle), findsOneWidget);
    expect(startedNotificationTitle, l10n.kiroLinkAuthDialogTitle);
    expect(stopCalls, 0);

    await tester.tap(find.widgetWithText(FilledButton, l10n.cancelButton));
    await tester.pumpAndSettle();

    expect(find.text(l10n.kiroLinkAuthDialogTitle), findsNothing);
    expect(stopCalls, 1);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.bootstrap,
    required this.kiroLinkAuthService,
    this.androidAuthKeepAlive,
  });

  final AppBootstrap bootstrap;
  final KiroLinkAuthService kiroLinkAuthService;
  final AndroidAuthKeepAlive? androidAuthKeepAlive;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(bootstrap),
        kiroLinkAuthServiceProvider.overrideWithValue(kiroLinkAuthService),
        if (androidAuthKeepAlive != null)
          androidAuthKeepAliveProvider.overrideWithValue(androidAuthKeepAlive!),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AccountsPage()),
      ),
    );
  }
}

class _FakeKiroLinkAuthService extends KiroLinkAuthService {
  _FakeKiroLinkAuthService({
    required this.request,
    required Future<KiroAuthSourceSnapshot> completion,
  }) : _completion = completion;

  final KiroLinkAuthRequest request;
  final Future<KiroAuthSourceSnapshot> _completion;

  @override
  Future<KiroLinkAuthRequest> startBuilderIdAuthorization({
    String startUrl = defaultKiroBuilderIdStartUrl,
    String region = defaultKiroRegion,
  }) async {
    return request;
  }

  @override
  Future<KiroAuthSourceSnapshot> completeBuilderIdAuthorization(
    KiroLinkAuthRequest request, {
    bool Function()? isCancelled,
  }) {
    return _completion;
  }
}

class _FailingUrlLauncherPlatform extends UrlLauncherPlatform {
  @override
  get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => false;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async => false;
}

Future<AppBootstrap> _createBootstrap({
  List<AccountProfile> initialAccounts = const <AccountProfile>[],
}) async {
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
      apiKey: 'test-api-key',
    ).copyWith(androidBackgroundRuntime: false),
    initialAccounts: initialAccounts,
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
