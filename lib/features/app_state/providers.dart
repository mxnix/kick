import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../analytics/kick_analytics.dart';
import '../../app/app_version_reader.dart';
import '../../app/bootstrap.dart';
import '../../core/accounts/account_priority.dart';
import '../../core/logging/internal_log_visibility.dart';
import '../../core/platform/android_auth_keep_alive.dart';
import '../../core/platform/desktop_runtime.dart';
import '../../core/platform/window_bootstrap.dart';
import '../../core/security/proxy_api_key.dart';
import '../../data/models/account_profile.dart';
import '../../data/models/app_log_entry.dart';
import '../../data/models/app_settings.dart';
import '../../l10n/kick_localizations.dart';
import '../../proxy/engine/proxy_controller.dart';
import '../../proxy/gemini/gemini_installation_identity.dart';
import '../../proxy/gemini/gemini_oauth_service.dart';
import '../../proxy/gemini/gemini_project_diagnostics_service.dart';
import '../../proxy/gemini/gemini_usage_models.dart';
import '../../proxy/gemini/gemini_usage_service.dart';
import '../../proxy/kiro/kiro_auth_source.dart';
import '../../proxy/kiro/kiro_link_auth_service.dart';
import '../../proxy/kiro/kiro_usage_service.dart';
import '../../proxy/luma/luma_connect_service.dart';
import '../../proxy/luma/luma_usage_service.dart';
import '../accounts/account_share_service.dart';
import '../home/silly_tavern_push_service.dart';
import '../logs/log_display_items.dart';
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

final proxyActivityProvider = StreamProvider<ProxyActivityEvent>((ref) {
  var sequence = 0;
  return ref
      .watch(proxyControllerProvider)
      .activity
      .map((type) => ProxyActivityEvent(type: type, sequence: sequence++));
});

class ProxyActivityEvent {
  const ProxyActivityEvent({required this.type, required this.sequence});

  final String type;
  final int sequence;
}

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

final kiroUsageServiceProvider = Provider<KiroUsageService>((ref) {
  final service = KiroUsageService();
  ref.onDispose(service.dispose);
  return service;
});

final lumaUsageServiceProvider = Provider<LumaUsageService>((ref) {
  final bootstrap = ref.watch(appBootstrapProvider);
  final service = LumaUsageService(secretStore: bootstrap.secretStore);
  ref.onDispose(service.dispose);
  return service;
});

final lumaConnectServiceProvider = Provider<LumaConnectService>((ref) {
  final bootstrap = ref.watch(appBootstrapProvider);
  return LumaConnectService(secretStore: bootstrap.secretStore);
});

final accountUsageQueryProvider = FutureProvider.autoDispose.family<GeminiUsageSnapshot, String>((
  ref,
  accountId,
) async {
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

    final snapshot = await switch (account.provider) {
      AccountProvider.gemini => ref.watch(geminiUsageServiceProvider).fetchUsage(account),
      AccountProvider.kiro => ref.watch(kiroUsageServiceProvider).fetchUsage(account),
      AccountProvider.luma => ref.watch(lumaUsageServiceProvider).fetchUsage(account),
    };

    if (snapshot.resolvedEmail != null &&
        snapshot.resolvedEmail!.trim().isNotEmpty &&
        snapshot.resolvedEmail!.trim() != account.email.trim()) {
      final bootstrap = ref.read(appBootstrapProvider);
      await bootstrap.accountsRepository.upsert(
        account.copyWith(email: snapshot.resolvedEmail!.trim()),
      );
      await ref.read(accountsControllerProvider.notifier).refreshState();
    }

    return snapshot;
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
    final initialSettings = ref.read(appBootstrapProvider).initialSettings;
    setKickLocaleOverride(initialSettings.appLocale);
    return initialSettings;
  }

  Future<void> save(AppSettings settings) async {
    final bootstrap = ref.read(appBootstrapProvider);
    await bootstrap.secretStore.writeProxyApiKey(settings.apiKey);
    await bootstrap.settingsRepository.writeSettings(settings);
    await bootstrap.logsRepository.setRetentionLimit(settings.logRetentionCount);
    setKickLocaleOverride(settings.appLocale);
    _refreshWindowTitleSafely();
    await DesktopRuntime.applySettings(settings);
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

  void _refreshWindowTitleSafely() {
    unawaited(
      WindowBootstrap.refreshTitle().catchError((Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint('[settings] window title refresh failed: $error');
        }
      }),
    );
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

final accountShareServiceProvider = Provider<AccountShareService>((ref) {
  final bootstrap = ref.watch(appBootstrapProvider);
  return AccountShareService(readTokens: bootstrap.secretStore.readOAuthTokens);
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

  Future<AccountProfile?> connectGoogleAccount({
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
          provider: KickAnalytics.providerName(AccountProvider.gemini),
        ),
      );
      return profile;
    } catch (error) {
      unawaited(
        bootstrap.analytics.trackAccountConnectFailed(
          reauthorization: reauthorization,
          errorKind: _analyticsErrorKind(error),
          provider: KickAnalytics.providerName(AccountProvider.gemini),
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
      var source = await loadEffectiveKiroAuthSource(sourcePath: credentialSourcePath);
      if (source == null) {
        throw StateError('Kiro credentials were not found at the configured path.');
      }

      source = await _materializeKiroSourceForAccount(source, existing);

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
        providerProfileArn: resolveKiroProfileArn(
          source.profileArn,
          fallback: existing?.providerProfileArn,
        ),
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

      // Attempt to resolve the real email from Kiro usage API.
      unawaited(
        Future<void>(() async {
          try {
            final usageService = KiroUsageService();
            try {
              final snapshot = await usageService.fetchUsage(profile);
              if (snapshot.resolvedEmail != null &&
                  snapshot.resolvedEmail!.trim().isNotEmpty &&
                  snapshot.resolvedEmail!.trim() != profile.email.trim()) {
                await bootstrap.accountsRepository.upsert(
                  profile.copyWith(email: snapshot.resolvedEmail!.trim()),
                );
                await refreshState();
              }
            } finally {
              usageService.dispose();
            }
          } catch (_) {
            // Non-critical: email will be resolved on next usage fetch.
          }
        }),
      );

      final enabledAccounts = (state.asData?.value ?? const <AccountProfile>[])
          .where((account) => account.enabled)
          .length;
      unawaited(
        bootstrap.analytics.trackAccountConnectSucceeded(
          reauthorization: reauthorization,
          enabledAccounts: enabledAccounts,
          provider: KickAnalytics.providerName(AccountProvider.kiro),
        ),
      );
    } catch (error) {
      unawaited(
        bootstrap.analytics.trackAccountConnectFailed(
          reauthorization: reauthorization,
          errorKind: _analyticsErrorKind(error),
          provider: KickAnalytics.providerName(AccountProvider.kiro),
        ),
      );
      rethrow;
    }
  }

  Future<AccountProfile> connectLumaAccount({
    required LumaConnectResult connect,
    int priority = defaultAccountPriority,
    List<String> notSupportedModels = const [],
    AccountProfile? existing,
  }) async {
    final bootstrap = ref.read(appBootstrapProvider);
    final reauthorization = existing != null;
    unawaited(bootstrap.analytics.trackAccountConnectStarted(reauthorization: reauthorization));
    try {
      final profile = AccountProfile(
        id: existing?.id ?? _uuid.v4(),
        label: connect.label.trim().isNotEmpty ? connect.label.trim() : (existing?.label ?? 'Luma'),
        email: connect.email.trim().isNotEmpty ? connect.email.trim() : (existing?.email ?? ''),
        projectId: '',
        provider: AccountProvider.luma,
        providerRegion: connect.tier ?? existing?.providerRegion,
        credentialSourceType: 'workos',
        credentialSourcePath: existing?.credentialSourcePath,
        providerProfileArn: connect.session.realmId ?? existing?.providerProfileArn,
        avatarUrl: existing?.avatarUrl,
        enabled: true,
        priority: normalizeAccountPriority(priority),
        notSupportedModels: notSupportedModels,
        runtimeNotSupportedModels: existing?.runtimeNotSupportedModels ?? const <String>[],
        lastUsedAt: existing?.lastUsedAt,
        usageCount: existing?.usageCount ?? 0,
        errorCount: existing?.errorCount ?? 0,
        cooldownUntil: existing?.cooldownUntil,
        lastQuotaSnapshot: existing?.lastQuotaSnapshot,
        tokenRef: connect.tokenRef,
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
          provider: KickAnalytics.providerName(AccountProvider.luma),
        ),
      );
      return profile;
    } catch (error) {
      unawaited(
        bootstrap.analytics.trackAccountConnectFailed(
          reauthorization: reauthorization,
          errorKind: _analyticsErrorKind(error),
          provider: KickAnalytics.providerName(AccountProvider.luma),
        ),
      );
      rethrow;
    }
  }

  Future<void> saveAccount(AccountProfile account) async {
    final bootstrap = ref.read(appBootstrapProvider);
    final previous = await _findAccount(account.id);
    await bootstrap.accountsRepository.upsert(
      account.copyWith(priority: normalizeAccountPriority(account.priority)),
    );
    await refreshState();
    if (previous != null && previous.enabled != account.enabled) {
      _emitAccountStateChanged(
        action: account.enabled ? 'enabled' : 'disabled',
        provider: account.provider,
      );
    }
  }

  Future<void> deleteAccount(AccountProfile account) async {
    final bootstrap = ref.read(appBootstrapProvider);
    await bootstrap.accountsRepository.delete(account.id);
    if (account.provider == AccountProvider.luma) {
      await bootstrap.secretStore.deleteLumaSession(account.tokenRef);
    } else if (account.usesSecretStoreTokens) {
      await bootstrap.secretStore.deleteOAuthTokens(account.tokenRef);
    } else {
      await deleteManagedKiroCredentialSource(account.credentialSourcePath);
    }
    await refreshState();
    _emitAccountStateChanged(action: 'removed', provider: account.provider);
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

  Future<AccountProfile> importSharedAccount(AccountShareImportResult shared) async {
    final bootstrap = ref.read(appBootstrapProvider);
    final source = shared.account;

    final newId = _uuid.v4();
    final newTokenRef = switch (source.provider) {
      AccountProvider.gemini => 'kick.oauth.${_uuid.v4()}',
      AccountProvider.kiro => 'kick.kiro.${_uuid.v4()}',
      AccountProvider.luma => 'kick.luma.${_uuid.v4()}',
    };

    var profile = source.copyWith(
      id: newId,
      tokenRef: newTokenRef,
      enabled: true,
      usageCount: 0,
      errorCount: 0,
      clearCooldown: true,
      clearQuotaSnapshot: true,
      clearLastUsedAt: true,
      runtimeNotSupportedModels: const <String>[],
      priority: normalizeAccountPriority(source.priority),
    );

    if (source.provider == AccountProvider.kiro) {
      final managedState = shared.kiroManagedCredentialState;
      if (managedState != null) {
        final shareService = ref.read(accountShareServiceProvider);
        final restored = await shareService.materializeKiroManagedCredential(managedState);
        if (restored != null) {
          profile = profile.copyWith(
            credentialSourcePath: restored.sourcePath,
            credentialSourceType: restored.sourceType,
            providerRegion: restored.effectiveRegion,
            providerProfileArn: resolveKiroProfileArn(
              restored.profileArn,
              fallback: source.providerProfileArn,
            ),
          );
        }
      } else if (source.credentialSourceType == defaultKiroCredentialSourceType) {
        final defaultPath = resolveKiroCredentialSourcePath(null);
        profile = profile.copyWith(
          credentialSourcePath: defaultPath,
          clearCredentialSourcePath: defaultPath == null,
        );
      }
    } else if (source.provider == AccountProvider.luma) {
      // Luma stub does not persist any secret material yet.
    } else if (shared.tokens != null) {
      await bootstrap.secretStore.writeOAuthTokens(newTokenRef, shared.tokens!);
    }

    await bootstrap.accountsRepository.upsert(profile);
    await refreshState();
    _emitAccountStateChanged(action: 'imported', provider: profile.provider);
    return profile;
  }

  Future<AccountProfile?> _findAccount(String id) async {
    final accounts = state.asData?.value;
    if (accounts != null) {
      for (final account in accounts) {
        if (account.id == id) {
          return account;
        }
      }
    }
    return null;
  }

  void _emitAccountStateChanged({required String action, required AccountProvider provider}) {
    final analytics = ref.read(appBootstrapProvider).analytics;
    final accounts = state.asData?.value ?? const <AccountProfile>[];
    final enabled = accounts.where((account) => account.enabled).length;
    unawaited(
      analytics.trackAccountStateChanged(
        action: action,
        provider: KickAnalytics.providerName(provider),
        enabledAccounts: enabled,
        totalAccounts: accounts.length,
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
    required this.displayItems,
    required this.categories,
    required this.totalCount,
    required this.filteredCount,
    required this.query,
    required this.selectedLevel,
    required this.selectedCategory,
    this.appearingEntryIds = const <String>{},
    this.isLoadingMore = false,
  });

  final List<AppLogEntry> entries;
  final List<LogDisplayItem> displayItems;
  final List<String> categories;
  final int totalCount;
  final int filteredCount;
  final String query;
  final AppLogLevel? selectedLevel;
  final String? selectedCategory;
  final Set<String> appearingEntryIds;
  final bool isLoadingMore;

  bool get hasActiveFilters =>
      query.trim().isNotEmpty || selectedLevel != null || selectedCategory != null;

  bool get hasMore => entries.length < filteredCount;

  LogsViewState copyWith({
    List<AppLogEntry>? entries,
    List<LogDisplayItem>? displayItems,
    List<String>? categories,
    int? totalCount,
    int? filteredCount,
    String? query,
    Object? selectedLevel = _logsFieldUnset,
    Object? selectedCategory = _logsFieldUnset,
    Set<String>? appearingEntryIds,
    bool? isLoadingMore,
  }) {
    final nextEntries = entries ?? this.entries;
    return LogsViewState(
      entries: nextEntries,
      displayItems:
          displayItems ?? (entries == null ? this.displayItems : buildLogDisplayItems(nextEntries)),
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
      appearingEntryIds: appearingEntryIds ?? this.appearingEntryIds,
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
  ref.listen<AsyncValue<ProxyActivityEvent>>(proxyActivityProvider, (previous, next) {
    orchestrator.onProxyActivity(next.asData?.value.type);
  });
  ref.onDispose(orchestrator.dispose);

  return orchestrator;
});

final logExportServiceProvider = Provider<LogExportService>((ref) => LogExportService());

final sillyTavernPushServiceProvider = Provider<SillyTavernPushService>((ref) {
  final service = SillyTavernPushService();
  ref.onDispose(service.dispose);
  return service;
});

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
  final analytics = ref.watch(analyticsProvider);
  try {
    final info = await ref
        .watch(appUpdateCheckerProvider)
        .checkForUpdates(currentVersion: currentVersion);
    unawaited(
      analytics.trackUpdateCheckCompleted(
        hasUpdate: info.hasUpdate,
        installerAvailable: info.installerUrl?.trim().isNotEmpty == true,
      ),
    );
    return info;
  } catch (error) {
    unawaited(
      analytics.trackUpdateCheckCompleted(
        hasUpdate: false,
        installerAvailable: false,
        errorKind: error.runtimeType.toString(),
      ),
    );
    rethrow;
  }
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
      markAppearingEntries: current != null,
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
        excludedCategories: internalUserHiddenLogCategories,
      );
      if (revision != _loadRevision) {
        return;
      }
      final entries = [...current.entries, ...nextEntries];
      state = AsyncData(
        current.copyWith(
          entries: entries,
          displayItems: buildLogDisplayItems(entries),
          filteredCount: nextEntries.isEmpty ? current.entries.length : current.filteredCount,
          appearingEntryIds: const <String>{},
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
      excludedCategories: internalUserHiddenLogCategories,
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
    bool markAppearingEntries = false,
  }) async {
    final revision = ++_loadRevision;
    final previous = markAppearingEntries ? state.asData?.value : null;
    try {
      final next = await _readState(
        query: query,
        level: level,
        category: category,
        previous: previous,
      );
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
    LogsViewState? previous,
  }) async {
    final bootstrap = ref.read(appBootstrapProvider);
    final categories = await bootstrap.logsRepository.readCategories(
      excludedCategories: internalUserHiddenLogCategories,
    );
    final normalizedCategory = categories.contains(category) ? category : null;
    final totalCount = await bootstrap.logsRepository.count(
      excludedCategories: internalUserHiddenLogCategories,
    );
    final filteredCount = await bootstrap.logsRepository.count(
      query: query,
      level: level,
      category: normalizedCategory,
      excludedCategories: internalUserHiddenLogCategories,
    );
    final entries = await bootstrap.logsRepository.readAll(
      limit: _logsPageSize,
      query: query,
      level: level,
      category: normalizedCategory,
      excludedCategories: internalUserHiddenLogCategories,
    );
    final previousEntryIds = previous?.entries.map((entry) => entry.id).toSet() ?? const <String>{};
    final appearingEntryIds = previous == null
        ? const <String>{}
        : entries
              .where((entry) => !previousEntryIds.contains(entry.id))
              .map((entry) => entry.id)
              .toSet();

    return LogsViewState(
      entries: entries,
      displayItems: buildLogDisplayItems(entries),
      categories: categories,
      totalCount: totalCount,
      filteredCount: filteredCount,
      query: query,
      selectedLevel: level,
      selectedCategory: normalizedCategory,
      appearingEntryIds: appearingEntryIds,
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

Future<KiroAuthSourceSnapshot> _materializeKiroSourceForAccount(
  KiroAuthSourceSnapshot source,
  AccountProfile? existing,
) async {
  final sourcePath = source.sourcePath.trim();
  final existingManagedPath = existing?.credentialSourcePath?.trim();
  final canReuseExistingManagedPath =
      existingManagedPath != null &&
      existingManagedPath.isNotEmpty &&
      existingManagedPath != sourcePath &&
      await isManagedKiroCredentialSourcePath(existingManagedPath);
  final shouldSnapshotMutableDefaultSource = isDefaultKiroCredentialSourcePath(sourcePath);
  final shouldReplacePreviousManagedBuilderSource =
      source.sourceType == builderIdKiroCredentialSourceType && canReuseExistingManagedPath;

  if (!shouldSnapshotMutableDefaultSource && !shouldReplacePreviousManagedBuilderSource) {
    return source;
  }

  final outputPath = canReuseExistingManagedPath ? existingManagedPath : null;
  final previousSourcePath = sourcePath;
  final persisted = await persistKiroAuthSourceSnapshot(source, outputPath: outputPath);
  if (previousSourcePath != persisted.sourcePath &&
      await isManagedKiroCredentialSourcePath(previousSourcePath)) {
    try {
      await deleteManagedKiroCredentialSource(previousSourcePath);
    } catch (_) {}
  }
  return persisted;
}

String _analyticsErrorKind(Object error) {
  final type = error.runtimeType.toString().trim();
  return type.isEmpty ? 'unknown' : type;
}
