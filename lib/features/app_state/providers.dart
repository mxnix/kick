import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../analytics/kick_analytics.dart';
import '../../app/app_version_reader.dart';
import '../../app/bootstrap.dart';
import '../../core/accounts/account_priority.dart';
import '../../core/platform/android_auth_keep_alive.dart';
import '../../core/platform/windows_desktop_runtime.dart';
import '../../core/security/proxy_api_key.dart';
import '../../data/models/account_profile.dart';
import '../../data/models/app_log_entry.dart';
import '../../data/models/app_settings.dart';
import '../../proxy/engine/proxy_controller.dart';
import '../../proxy/gemini/gemini_installation_identity.dart';
import '../../proxy/gemini/gemini_oauth_service.dart';
import '../../proxy/gemini/gemini_project_diagnostics_service.dart';
import '../../proxy/gemini/gemini_usage_models.dart';
import '../../proxy/gemini/gemini_usage_service.dart';
import '../../proxy/kiro/kiro_auth_source.dart';
import '../../proxy/kiro/kiro_link_auth_service.dart';
import '../logs/log_export_service.dart';
import '../settings/app_update_checker.dart';
import '../settings/configuration_backup_service.dart';
import 'proxy_configuration_orchestrator.dart';

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

final androidAuthKeepAliveProvider = Provider<AndroidAuthKeepAlive>((ref) {
  return AndroidAuthKeepAlive(
    isProxyRunning: () => ref.read(proxyControllerProvider).currentState.running,
  );
});

final clockTickerProvider = StreamProvider<DateTime>(
  (ref) => Stream<DateTime>.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
);

final oauthServiceProvider = Provider<GeminiOAuthService>(
  (ref) => ref.watch(appBootstrapProvider).oauthService,
);

final geminiUsageServiceProvider = Provider<GeminiUsageService>((ref) {
  final oauthService = ref.watch(oauthServiceProvider);
  final bootstrap = ref.watch(appBootstrapProvider);
  final service = GeminiUsageService(
    readTokens: oauthService.readTokens,
    refreshTokens: oauthService.refreshTokens,
    persistTokens: oauthService.persistTokens,
    privilegedUserIdLoader: GeminiInstallationIdLoader(
      installationIdPathProvider: () => bootstrap.geminiInstallationIdPath,
    ),
  );
  ref.onDispose(service.dispose);
  return service;
});

final geminiProjectDiagnosticsServiceProvider = Provider<GeminiProjectDiagnosticsService>((ref) {
  final oauthService = ref.watch(oauthServiceProvider);
  final bootstrap = ref.watch(appBootstrapProvider);
  final service = GeminiProjectDiagnosticsService(
    readTokens: oauthService.readTokens,
    refreshTokens: oauthService.refreshTokens,
    persistTokens: oauthService.persistTokens,
    onProjectIdResolved: (account, projectId) async {
      if (account.projectId.trim().isNotEmpty) {
        return;
      }
      await bootstrap.accountsRepository.upsert(account.copyWith(projectId: projectId));
    },
    privilegedUserIdLoader: GeminiInstallationIdLoader(
      installationIdPathProvider: () => bootstrap.geminiInstallationIdPath,
    ),
  );
  ref.onDispose(service.dispose);
  return service;
});

final kiroLinkAuthServiceProvider = Provider<KiroLinkAuthService>((ref) {
  final service = KiroLinkAuthService();
  ref.onDispose(service.dispose);
  return service;
});

final accountUsageQueryProvider = FutureProvider.autoDispose.family<GeminiUsageSnapshot, String>((
  ref,
  accountId,
) async {
  // Keep the provider alive until the current request completes. Popping the
  // page while the fetch was still loading could otherwise dispose the
  // provider mid-flight and surface a Riverpod StateError.
  final keepAliveLink = ref.keepAlive();
  try {
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
    if (!account.supportsUsageDiagnostics) {
      throw StateError('Usage details are not available for this provider.');
    }

    return await ref.watch(geminiUsageServiceProvider).fetchUsage(account);
  } finally {
    keepAliveLink.close();
  }
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
    await bootstrap.logsRepository.setRetentionLimit(settings.logRetentionCount);
    await WindowsDesktopRuntime.applySettings(settings);
    await bootstrap.analytics.setTrackingAllowed(analyticsTrackingAllowed(settings));
    state = AsyncData(settings);
    await ref.read(logsControllerProvider.notifier).refreshState();
  }

  Future<String> regenerateApiKey() async {
    final currentSettings = state.asData?.value ?? ref.read(appBootstrapProvider).initialSettings;
    final nextApiKey = generateProxyApiKey();
    await save(currentSettings.copyWith(apiKey: nextApiKey));
    return nextApiKey;
  }
}

final configurationBackupServiceProvider = Provider<ConfigurationBackupService>((ref) {
  final bootstrap = ref.watch(appBootstrapProvider);
  return ConfigurationBackupService(
    readTokens: bootstrap.secretStore.readOAuthTokens,
    readCurrentAccounts: bootstrap.accountsRepository.readAll,
    readCurrentSettings: () async =>
        ref.read(settingsControllerProvider).asData?.value ?? bootstrap.initialSettings,
    saveSettings: ref.read(settingsControllerProvider.notifier).save,
    replaceAccounts: bootstrap.accountsRepository.replaceAll,
    writeTokens: bootstrap.secretStore.writeOAuthTokens,
    deleteTokens: bootstrap.secretStore.deleteOAuthTokens,
  );
});

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
    final keepAlive = ref.read(androidAuthKeepAliveProvider);
    final keepAliveStarted = await keepAlive.begin();
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
        googleSubjectId: authResult.googleSubjectId ?? existing?.googleSubjectId,
        avatarUrl: authResult.avatarUrl,
        enabled: true,
        priority: normalizeAccountPriority(priority),
        notSupportedModels: notSupportedModels,
        runtimeNotSupportedModels: existing?.runtimeNotSupportedModels ?? const <String>[],
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
    } finally {
      await keepAlive.end(keepAliveStarted);
    }
  }

  Future<void> connectKiroAccount({
    String? label,
    String? credentialSourcePath,
    int priority = defaultAccountPriority,
    List<String> notSupportedModels = const [],
    AccountProfile? existing,
  }) async {
    final bootstrap = ref.read(appBootstrapProvider);
    final reauthorization = existing != null;
    unawaited(bootstrap.analytics.trackAccountConnectStarted(reauthorization: reauthorization));
    try {
      var source = await loadKiroAuthSource(sourcePath: credentialSourcePath);
      if (source == null) {
        throw StateError('Kiro credentials were not found at the configured path.');
      }

      final existingManagedPath = existing?.credentialSourcePath?.trim();
      if (source.sourceType == builderIdKiroCredentialSourceType &&
          existingManagedPath != null &&
          existingManagedPath.isNotEmpty &&
          existingManagedPath != source.sourcePath &&
          await isManagedKiroCredentialSourcePath(existingManagedPath)) {
        final previousSourcePath = source.sourcePath;
        source = await persistKiroAuthSourceSnapshot(source, outputPath: existingManagedPath);
        if (previousSourcePath.trim() != source.sourcePath.trim()) {
          try {
            await deleteManagedKiroCredentialSource(previousSourcePath);
          } catch (_) {
            // Best-effort cleanup for the temporary Builder ID snapshot.
          }
        }
      }

      final resolvedLabel = label?.trim().isNotEmpty == true
          ? label!.trim()
          : source.displayIdentity;
      final profile = AccountProfile(
        id: existing?.id ?? _uuid.v4(),
        label: resolvedLabel,
        email: source.displayIdentity,
        projectId: '',
        provider: AccountProvider.kiro,
        providerRegion: source.effectiveRegion,
        credentialSourceType: source.sourceType,
        credentialSourcePath: source.sourcePath,
        providerProfileArn: source.profileArn ?? existing?.providerProfileArn,
        enabled: true,
        priority: normalizeAccountPriority(priority),
        notSupportedModels: notSupportedModels,
        runtimeNotSupportedModels: existing?.runtimeNotSupportedModels ?? const <String>[],
        lastUsedAt: existing?.lastUsedAt,
        usageCount: existing?.usageCount ?? 0,
        errorCount: existing?.errorCount ?? 0,
        cooldownUntil: existing?.cooldownUntil,
        lastQuotaSnapshot: existing?.lastQuotaSnapshot,
        tokenRef: existing?.tokenRef ?? 'kick.kiro.${_uuid.v4()}',
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
    if (account.usesSecretStoreTokens) {
      await bootstrap.secretStore.deleteOAuthTokens(account.tokenRef);
    } else {
      await deleteManagedKiroCredentialSource(account.credentialSourcePath);
    }
    await refreshState();
  }

  Future<void> resetHealth(AccountProfile account) async {
    await saveAccount(
      account.copyWith(
        errorCount: 0,
        runtimeNotSupportedModels: const <String>[],
        clearCooldown: true,
        clearQuotaSnapshot: true,
      ),
    );
  }
}

const _logsPageSize = 100;
const _logsFieldUnset = Object();

final logsControllerProvider = AsyncNotifierProvider<LogsController, LogsViewState>(
  LogsController.new,
);

class LogsViewState {
  const LogsViewState({
    required this.entries,
    required this.categories,
    required this.totalCount,
    required this.filteredCount,
    required this.query,
    required this.selectedLevel,
    required this.selectedCategory,
    this.isLoadingMore = false,
  });

  final List<AppLogEntry> entries;
  final List<String> categories;
  final int totalCount;
  final int filteredCount;
  final String query;
  final AppLogLevel? selectedLevel;
  final String? selectedCategory;
  final bool isLoadingMore;

  bool get hasActiveFilters =>
      query.trim().isNotEmpty || selectedLevel != null || selectedCategory != null;

  bool get hasMore => entries.length < filteredCount;

  LogsViewState copyWith({
    List<AppLogEntry>? entries,
    List<String>? categories,
    int? totalCount,
    int? filteredCount,
    String? query,
    Object? selectedLevel = _logsFieldUnset,
    Object? selectedCategory = _logsFieldUnset,
    bool? isLoadingMore,
  }) {
    return LogsViewState(
      entries: entries ?? this.entries,
      categories: categories ?? this.categories,
      totalCount: totalCount ?? this.totalCount,
      filteredCount: filteredCount ?? this.filteredCount,
      query: query ?? this.query,
      selectedLevel: identical(selectedLevel, _logsFieldUnset)
          ? this.selectedLevel
          : selectedLevel as AppLogLevel?,
      selectedCategory: identical(selectedCategory, _logsFieldUnset)
          ? this.selectedCategory
          : selectedCategory as String?,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

final proxyConfigurationOrchestratorProvider = Provider<ProxyConfigurationOrchestrator>((ref) {
  final orchestrator = ProxyConfigurationOrchestrator(
    readSettings: () => ref.read(settingsControllerProvider).asData?.value,
    readAccounts: () => ref.read(accountsControllerProvider).asData?.value,
    syncConfiguration: ({required settings, required accounts}) {
      return ref.read(proxyControllerProvider).configure(settings: settings, accounts: accounts);
    },
    refreshAccounts: () => ref.read(accountsControllerProvider.notifier).refreshState(),
    refreshLogs: () => ref.read(logsControllerProvider.notifier).refreshState(),
  );

  ref.listen<AsyncValue<AppSettings>>(
    settingsControllerProvider,
    (previous, next) => orchestrator.onSettingsChanged(),
    fireImmediately: true,
  );
  ref.listen<AsyncValue<List<AccountProfile>>>(
    accountsControllerProvider,
    (previous, next) => orchestrator.onAccountsChanged(),
    fireImmediately: true,
  );
  ref.listen<AsyncValue<String>>(proxyActivityProvider, (previous, next) {
    orchestrator.onProxyActivity(next.asData?.value);
  });
  ref.onDispose(orchestrator.dispose);

  return orchestrator;
});

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

class LogsController extends AsyncNotifier<LogsViewState> {
  int _loadRevision = 0;

  @override
  Future<LogsViewState> build() async {
    return _readState();
  }

  Future<void> refreshState() async {
    final current = state.asData?.value;
    await _reload(
      query: current?.query ?? '',
      level: current?.selectedLevel,
      category: current?.selectedCategory,
    );
  }

  Future<void> updateQuery(String query) async {
    final current = state.asData?.value;
    if (current != null && current.query == query) {
      return;
    }
    await _reload(query: query, level: current?.selectedLevel, category: current?.selectedCategory);
  }

  Future<void> updateLevel(AppLogLevel? level) async {
    final current = state.asData?.value;
    if (current != null && current.selectedLevel == level) {
      return;
    }
    await _reload(query: current?.query ?? '', level: level, category: current?.selectedCategory);
  }

  Future<void> updateCategory(String? category) async {
    final current = state.asData?.value;
    final normalizedCategory = category?.trim().isEmpty == true ? null : category?.trim();
    if (current != null && current.selectedCategory == normalizedCategory) {
      return;
    }
    await _reload(
      query: current?.query ?? '',
      level: current?.selectedLevel,
      category: normalizedCategory,
    );
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || current.isLoadingMore || !current.hasMore) {
      return;
    }

    final revision = _loadRevision;
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final bootstrap = ref.read(appBootstrapProvider);
      final nextEntries = await bootstrap.logsRepository.readAll(
        limit: _logsPageSize,
        offset: current.entries.length,
        query: current.query,
        level: current.selectedLevel,
        category: current.selectedCategory,
      );
      if (revision != _loadRevision) {
        return;
      }
      state = AsyncData(
        current.copyWith(
          entries: [...current.entries, ...nextEntries],
          filteredCount: nextEntries.isEmpty ? current.entries.length : current.filteredCount,
          isLoadingMore: false,
        ),
      );
    } catch (error, stackTrace) {
      if (revision != _loadRevision) {
        return;
      }
      state = AsyncError(error, stackTrace);
    }
  }

  Future<List<AppLogEntry>> readAllMatchingEntries() async {
    final bootstrap = ref.read(appBootstrapProvider);
    final current = state.asData?.value;
    return bootstrap.logsRepository.readAll(
      limit: null,
      query: current?.query ?? '',
      level: current?.selectedLevel,
      category: current?.selectedCategory,
    );
  }

  Future<void> clear() async {
    final bootstrap = ref.read(appBootstrapProvider);
    await bootstrap.logsRepository.clear();
    await refreshState();
  }

  Future<void> _reload({
    required String query,
    required AppLogLevel? level,
    required String? category,
  }) async {
    final revision = ++_loadRevision;
    try {
      final next = await _readState(query: query, level: level, category: category);
      if (revision != _loadRevision) {
        return;
      }
      state = AsyncData(next);
    } catch (error, stackTrace) {
      if (revision != _loadRevision) {
        return;
      }
      state = AsyncError(error, stackTrace);
    }
  }

  Future<LogsViewState> _readState({
    String query = '',
    AppLogLevel? level,
    String? category,
  }) async {
    final bootstrap = ref.read(appBootstrapProvider);
    final categories = await bootstrap.logsRepository.readCategories();
    final normalizedCategory = categories.contains(category) ? category : null;
    final totalCount = await bootstrap.logsRepository.count();
    final filteredCount = await bootstrap.logsRepository.count(
      query: query,
      level: level,
      category: normalizedCategory,
    );
    final entries = await bootstrap.logsRepository.readAll(
      limit: _logsPageSize,
      query: query,
      level: level,
      category: normalizedCategory,
    );

    return LogsViewState(
      entries: entries,
      categories: categories,
      totalCount: totalCount,
      filteredCount: filteredCount,
      query: query,
      selectedLevel: level,
      selectedCategory: normalizedCategory,
      isLoadingMore: false,
    );
  }
}

class ProxyConfigurationSync extends ConsumerWidget {
  const ProxyConfigurationSync({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(proxyConfigurationOrchestratorProvider);
    return child;
  }
}

String _analyticsErrorKind(Object error) {
  final type = error.runtimeType.toString().trim();
  return type.isEmpty ? 'unknown' : type;
}
