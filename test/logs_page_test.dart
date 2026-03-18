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
import 'package:kick/features/logs/logs_page.dart';
import 'package:kick/l10n/generated/app_localizations.dart';
import 'package:kick/proxy/engine/proxy_controller.dart';
import 'package:kick/proxy/gemini/gemini_oauth_service.dart';

void main() {
  testWidgets('keeps log entries reachable when filters contain many categories', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final bootstrap = await _createBootstrap();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await bootstrap.dispose();
    });

    final baseTime = DateTime(2026, 3, 18, 4, 0);
    for (var index = 0; index < 24; index++) {
      await bootstrap.logsRepository.insert(
        AppLogEntry(
          id: 'log-$index',
          timestamp: baseTime.add(Duration(minutes: index)),
          level: AppLogLevel.info,
          category: 'category.$index',
          route: '/runtime/session',
          message: 'Log entry $index',
          maskedPayload: '{"index": $index}',
        ),
      );
    }

    await tester.pumpWidget(_TestApp(bootstrap: bootstrap));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final scrollView = find.descendant(
      of: find.byType(LogsPage),
      matching: find.byType(CustomScrollView),
    );

    expect(scrollView, findsOneWidget);

    await tester.dragUntilVisible(find.text('Log entry 0'), scrollView, const Offset(0, -300));

    expect(find.text('Log entry 0'), findsOneWidget);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.bootstrap});

  final AppBootstrap bootstrap;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: LogsPage()),
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
