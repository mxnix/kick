import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../analytics/kick_analytics.dart';
import '../../app/app_version_reader.dart';
import '../../app/bootstrap.dart';
import '../../core/accounts/account_priority.dart';
import '../../core/security/proxy_api_key.dart';
import '../../data/models/account_profile.dart';
import '../../data/models/app_log_entry.dart';
import '../../data/models/app_settings.dart';
import '../../proxy/engine/proxy_controller.dart';
import '../../proxy/gemini/gemini_oauth_service.dart';
import '../../proxy/gemini/gemini_usage_models.dart';
import '../../proxy/gemini/gemini_usage_service.dart';
import '../logs/log_export_service.dart';
import '../settings/app_update_checker.dart';

final proxyControllerProvider = Provider<KickProxyController>(
  (ref) => ref.watch(appBootstrapProvider).proxyController,
);

final proxyStatusProvider = StreamProvider<ProxyRuntimeState>(
  (ref) => ref.watch(proxyControllerProvider).states,
);

final proxyActivityProvider = StreamProvider<String>(
  (ref) => ref.watch(proxyControllerProvider).activity,
);

final analyticsProvider = Provider<KickAnalytics>(
  (ref) => ref.watch(appBootstrapProvider).analytics,
);

final clockTickerProvider = StreamProvider<DateTime>(
  (ref) => Stream<DateTime>.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
);

final oauthServiceProvider = Provider<GeminiOAuthService>(
  (ref) => ref.watch(appBootstrapProvider).oauthService,
);

final geminiUsageServiceProvider = Provider<GeminiUsageService>((ref) {
  final oauthService = ref.watch(oauthServiceProvider);
  final service = GeminiUsageService(
    readTokens: oauthService.readTokens,
    refreshTokens: oauthService.refreshTokens,
    persistTokens: oauthService.persistTokens,
  );
  ref.onDispose(service.dispose);
  return service;
});

final accountUsageQueryProvider = FutureProvider.autoDispose.family<GeminiUsageSnapshot, String>((
  ref,
  accountId,
) async {
  final accounts = await ref.watch(accountsControllerProvider.future);
  AccountProfile? account;
  for (final item in accounts) {
    if (item.id == accountId) {
      account = item;
      break;
    }
  }
  if (account == null) {
    throw StateError('Account not found.');
  }

  return ref.watch(geminiUsageServiceProvider).fetchUsage(account);
});

final settingsControllerProvider = AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  AppSettings build() {
    return ref.read(appBootstrapProvider).initialSettings;
  }

  Future<void> save(AppSettings settings) async {
    final bootstrap = ref.read(appBootstrapProvider);
    await bootstrap.secretStore.writeProxyApiKey(settings.apiKey);
    await bootstrap.settingsRepository.writeSettings(settings);
    await bootstrap.analytics.setTrackingAllowed(analyticsTrackingAllowed(settings));
    state = AsyncData(settings);
  }

  Future<String> regenerateApiKey() async {
    final currentSettings = state.asData?.value ?? ref.read(appBootstrapProvider).initialSettings;
    final nextApiKey = generateProxyApiKey();
    await save(currentSettings.copyWith(apiKey: nextApiKey));
    return nextApiKey;
  }
}

final accountsControllerProvider = AsyncNotifierProvider<AccountsController, List<AccountProfile>>(
  AccountsController.new,
);

class AccountsController extends AsyncNotifier<List<AccountProfile>> {
  final _uuid = const Uuid();

  @override
  List<AccountProfile> build() {
    return ref.read(appBootstrapProvider).initialAccounts;
  }

  Future<void> refreshState() async {
    final bootstrap = ref.read(appBootstrapProvider);
    state = AsyncData(await bootstrap.accountsRepository.readAll());
  }

  Future<void> connectGoogleAccount({
    required String projectId,
    String? label,
    int priority = defaultAccountPriority,
    List<String> notSupportedModels = const [],
    AccountProfile? existing,
  }) async {
    final bootstrap = ref.read(appBootstrapProvider);
    final reauthorization = existing != null;
    unawaited(bootstrap.analytics.trackAccountConnectStarted(reauthorization: reauthorization));
    try {
      final authResult = await bootstrap.oauthService.authenticate();
      final tokenRef = existing?.tokenRef ?? 'kick.oauth.${_uuid.v4()}';
      await bootstrap.secretStore.writeOAuthTokens(tokenRef, authResult.tokens);

      final profile = AccountProfile(
        id: existing?.id ?? _uuid.v4(),
        label: (label?.trim().isNotEmpty == true ? label!.trim() : authResult.displayName.trim())
            .trim(),
        email: authResult.email,
        projectId: projectId.trim(),
        enabled: true,
        priority: normalizeAccountPriority(priority),
        notSupportedModels: notSupportedModels,
        lastUsedAt: existing?.lastUsedAt,
        usageCount: existing?.usageCount ?? 0,
        errorCount: existing?.errorCount ?? 0,
        cooldownUntil: existing?.cooldownUntil,
        lastQuotaSnapshot: existing?.lastQuotaSnapshot,
        tokenRef: tokenRef,
      );
      await bootstrap.accountsRepository.upsert(profile);
      await refreshState();
      final enabledAccounts = (state.asData?.value ?? const <AccountProfile>[])
          .where((account) => account.enabled)
          .length;
      unawaited(
        bootstrap.analytics.trackAccountConnectSucceeded(
          reauthorization: reauthorization,
          enabledAccounts: enabledAccounts,
        ),
      );
    } catch (error) {
      unawaited(
        bootstrap.analytics.trackAccountConnectFailed(
          reauthorization: reauthorization,
          errorKind: _analyticsErrorKind(error),
        ),
      );
      rethrow;
    }
  }

  Future<void> saveAccount(AccountProfile account) async {
    final bootstrap = ref.read(appBootstrapProvider);
    await bootstrap.accountsRepository.upsert(
      account.copyWith(priority: normalizeAccountPriority(account.priority)),
    );
    await refreshState();
  }

  Future<void> deleteAccount(AccountProfile account) async {
    final bootstrap = ref.read(appBootstrapProvider);
    await bootstrap.accountsRepository.delete(account.id);
    await bootstrap.secretStore.deleteOAuthTokens(account.tokenRef);
    await refreshState();
  }

  Future<void> resetHealth(AccountProfile account) async {
    await saveAccount(
      account.copyWith(errorCount: 0, clearCooldown: true, clearQuotaSnapshot: true),
    );
  }
}

final logsControllerProvider = AsyncNotifierProvider<LogsController, List<AppLogEntry>>(
  LogsController.new,
);

final logExportServiceProvider = Provider<LogExportService>((ref) => LogExportService());

final appVersionReaderProvider = Provider<AppVersionReader>((ref) => const AppVersionReader());

final appVersionProvider = FutureProvider<String>((ref) {
  return ref.watch(appVersionReaderProvider).readVersion();
});

final appUpdateCheckerProvider = Provider<AppUpdateChecker>((ref) {
  final checker = AppUpdateChecker();
  ref.onDispose(checker.dispose);
  return checker;
});

final appUpdateQueryProvider = FutureProvider.autoDispose<AppUpdateInfo>((ref) async {
  final currentVersion = await ref.watch(appVersionProvider.future);
  return ref.watch(appUpdateCheckerProvider).checkForUpdates(currentVersion: currentVersion);
});

class LogsController extends AsyncNotifier<List<AppLogEntry>> {
  @override
  Future<List<AppLogEntry>> build() async {
    final bootstrap = ref.read(appBootstrapProvider);
    return bootstrap.logsRepository.readAll();
  }

  Future<void> refreshState() async {
    final bootstrap = ref.read(appBootstrapProvider);
    state = AsyncData(await bootstrap.logsRepository.readAll());
  }

  Future<void> clear() async {
    final bootstrap = ref.read(appBootstrapProvider);
    await bootstrap.logsRepository.clear();
    state = const AsyncData(<AppLogEntry>[]);
  }
}

class ProxyConfigurationSync extends ConsumerStatefulWidget {
  const ProxyConfigurationSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ProxyConfigurationSync> createState() => _ProxyConfigurationSyncState();
}

String _analyticsErrorKind(Object error) {
  final type = error.runtimeType.toString().trim();
  return type.isEmpty ? 'unknown' : type;
}

class _ProxyConfigurationSyncState extends ConsumerState<ProxyConfigurationSync> {
  ProviderSubscription<AsyncValue<AppSettings>>? _settingsSub;
  ProviderSubscription<AsyncValue<List<AccountProfile>>>? _accountsSub;
  ProviderSubscription<AsyncValue<String>>? _activitySub;
  Future<void>? _pendingSync;
  bool _syncRequested = false;
  bool _suppressAccountsSync = false;

  @override
  void initState() {
    super.initState();
    _settingsSub = ref.listenManual(
      settingsControllerProvider,
      (previous, next) => _scheduleSync(),
      fireImmediately: true,
    );
    _accountsSub = ref.listenManual(accountsControllerProvider, (previous, next) {
      if (_suppressAccountsSync) {
        return;
      }
      _scheduleSync();
    }, fireImmediately: true);
    _activitySub = ref.listenManual(proxyActivityProvider, (_, next) {
      final activity = next.asData?.value;
      if (activity == 'accounts') {
        unawaited(_refreshAccountsFromRuntime());
      } else if (activity == 'logs') {
        unawaited(ref.read(logsControllerProvider.notifier).refreshState());
      }
    });
  }

  @override
  void dispose() {
    _settingsSub?.close();
    _accountsSub?.close();
    _activitySub?.close();
    super.dispose();
  }

  void _scheduleSync() {
    _syncRequested = true;
    _pendingSync ??= Future<void>.microtask(() async {
      try {
        while (_syncRequested) {
          _syncRequested = false;
          final settings = ref.read(settingsControllerProvider).asData?.value;
          final accounts = ref.read(accountsControllerProvider).asData?.value;
          try {
            if (settings != null && accounts != null) {
              await ref.read(proxyControllerProvider).configure(settings: settings, accounts: accounts);
            }
          } catch (error, stackTrace) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'kick',
                context: ErrorDescription('while synchronizing proxy configuration'),
              ),
            );
          }
        }
      } finally {
        _pendingSync = null;
      }
    });
  }

  Future<void> _refreshAccountsFromRuntime() async {
    _suppressAccountsSync = true;
    try {
      await ref.read(accountsControllerProvider.notifier).refreshState();
    } finally {
      _suppressAccountsSync = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
