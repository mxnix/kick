import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/analytics/kick_analytics.dart';
import 'package:kick/app/bootstrap.dart';
import 'package:kick/data/app_database.dart';
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/data/models/app_settings.dart';
import 'package:kick/data/models/oauth_tokens.dart';
import 'package:kick/data/repositories/accounts_repository.dart';
import 'package:kick/data/repositories/logs_repository.dart';
import 'package:kick/data/repositories/secret_store.dart';
import 'package:kick/data/repositories/settings_repository.dart';
import 'package:kick/features/accounts/account_usage_page.dart';
import 'package:kick/features/app_state/providers.dart';
import 'package:kick/l10n/generated/app_localizations.dart';
import 'package:kick/proxy/engine/proxy_controller.dart';
import 'package:kick/proxy/gemini/gemini_oauth_service.dart';
import 'package:kick/proxy/gemini/gemini_usage_models.dart';
import 'package:kick/proxy/gemini/gemini_usage_service.dart';

void main() {
  testWidgets('closing account usage page while loading does not crash', (tester) async {
    final bootstrap = await _createBootstrap(initialAccounts: const [_account]);
    final completer = Completer<GeminiUsageSnapshot>();
    final usageService = _FakeGeminiUsageService((_) => completer.future);

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await bootstrap.dispose();
    });

    await tester.pumpWidget(_TestApp(bootstrap: bootstrap, usageService: usageService));
    await tester.pump();

    expect(find.byType(AccountUsagePage), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(_UsageHost.hidePageKey));
    await tester.pump();

    expect(find.byType(AccountUsagePage), findsNothing);
    expect(find.text('hidden'), findsOneWidget);

    completer.complete(
      GeminiUsageSnapshot(
        fetchedAt: DateTime(2026, 3, 19, 15),
        subscriptionTitle: 'Gemini CLI OAuth',
        buckets: const [],
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.bootstrap, required this.usageService});

  final AppBootstrap bootstrap;
  final GeminiUsageService usageService;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(bootstrap),
        geminiUsageServiceProvider.overrideWithValue(usageService),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _UsageHost(),
      ),
    );
  }
}

class _UsageHost extends StatefulWidget {
  const _UsageHost();

  static const hidePageKey = Key('hide-account-usage-page');

  @override
  State<_UsageHost> createState() => _UsageHostState();
}

class _UsageHostState extends State<_UsageHost> {
  var _showUsagePage = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        key: _UsageHost.hidePageKey,
        onPressed: () {
          setState(() {
            _showUsagePage = false;
          });
        },
        child: const Icon(Icons.close),
      ),
      body: _showUsagePage ? const AccountUsagePage(accountId: _accountId) : const Text('hidden'),
    );
  }
}

class _FakeGeminiUsageService extends GeminiUsageService {
  _FakeGeminiUsageService(this._fetchUsage)
    : super(readTokens: _readTokens, refreshTokens: _refreshTokens, persistTokens: _persistTokens);

  final Future<GeminiUsageSnapshot> Function(AccountProfile account) _fetchUsage;

  @override
  Future<GeminiUsageSnapshot> fetchUsage(AccountProfile account) {
    return _fetchUsage(account);
  }

  @override
  void dispose() {}

  static Future<OAuthTokens?> _readTokens(String tokenRef) async => null;

  static Future<OAuthTokens> _refreshTokens(OAuthTokens tokens) async {
    throw UnimplementedError('refreshTokens should not be called in this test');
  }

  static Future<void> _persistTokens(String tokenRef, OAuthTokens tokens) async {}
}

Future<AppBootstrap> _createBootstrap({required List<AccountProfile> initialAccounts}) async {
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

const _accountId = 'account-1';

const _account = AccountProfile(
  id: _accountId,
  label: 'Test account',
  email: 'test@example.com',
  projectId: 'project-1',
  enabled: true,
  priority: 0,
  notSupportedModels: <String>[],
  lastUsedAt: null,
  usageCount: 0,
  errorCount: 0,
  cooldownUntil: null,
  lastQuotaSnapshot: null,
  tokenRef: 'token-1',
);
