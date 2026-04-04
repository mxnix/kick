import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/accounts/account_runtime_notice.dart';
import '../../core/errors/gemini_error_actions.dart';
import '../../core/errors/user_facing_error_formatter.dart';
import '../../data/models/account_profile.dart';
import '../../l10n/kick_localizations.dart';
import '../../proxy/kiro/kiro_auth_source.dart';
import '../../proxy/kiro/kiro_link_auth_service.dart';
import '../app_state/providers.dart';
import '../shared/kick_surfaces.dart';
import '../shared/provider_icon.dart';
import 'account_editor_dialog.dart';
import 'account_priority_presentation.dart';
import 'account_provider_picker_dialog.dart';

class AccountsPage extends ConsumerStatefulWidget {
  const AccountsPage({super.key});

  @override
  ConsumerState<AccountsPage> createState() => _AccountsPageState();
}

enum _AccountSortOption { attention, priority, label, recentActivity }

class _AccountsPageState extends ConsumerState<AccountsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _AccountSortOption _sortOption = _AccountSortOption.priority;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final accountsValue = ref.watch(accountsControllerProvider);

    return accountsValue.when(
      data: (accounts) {
        final filteredAccounts = _applyAccountSearchAndSort(
          accounts,
          query: _query,
          sortOption: _sortOption,
        );
        final filteredEnabledCount = filteredAccounts.where((account) => account.enabled).length;
        final hasSearch = _query.trim().isNotEmpty;

        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useCompactHeader = constraints.maxWidth < 680;

              Widget buildAddButton({required bool fullWidth}) {
                final button = FilledButton.icon(
                  onPressed: () => _authenticateNewAccount(context, ref),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.addButton),
                );
                if (!fullWidth) {
                  return button;
                }
                return SizedBox(width: double.infinity, child: button);
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeading(
                    title: l10n.accountsTitle,
                    subtitle: l10n.accountsSubtitle,
                    trailing: useCompactHeader ? null : buildAddButton(fullWidth: false),
                  ),
                  if (useCompactHeader) ...[
                    const SizedBox(height: 16),
                    buildAddButton(fullWidth: true),
                  ],
                  if (accounts.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    KickPanel(
                      tone: KickPanelTone.soft,
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                      child: LayoutBuilder(
                        builder: (context, panelConstraints) {
                          final useHorizontalControls = panelConstraints.maxWidth >= 760;
                          final searchField = TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search_rounded),
                              hintText: l10n.accountsSearchHint,
                              suffixIcon: hasSearch
                                  ? IconButton(
                                      onPressed: _clearSearch,
                                      tooltip: MaterialLocalizations.of(context).clearButtonTooltip,
                                      icon: const Icon(Icons.close_rounded),
                                    )
                                  : null,
                            ),
                            onChanged: (value) {
                              setState(() => _query = value);
                            },
                          );
                          final sortField = DropdownButtonFormField<_AccountSortOption>(
                            initialValue: _sortOption,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: l10n.accountsSortLabel,
                              prefixIcon: const Icon(Icons.sort_rounded),
                            ),
                            items: _AccountSortOption.values
                                .map(
                                  (option) => DropdownMenuItem<_AccountSortOption>(
                                    value: option,
                                    child: Text(_accountSortOptionLabel(l10n, option)),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() => _sortOption = value);
                            },
                          );

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (useHorizontalControls)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: searchField),
                                    const SizedBox(width: 12),
                                    SizedBox(width: 260, child: sortField),
                                  ],
                                )
                              else ...[
                                searchField,
                                const SizedBox(height: 12),
                                sortField,
                              ],
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  KickBadge(
                                    label: l10n.accountsTotalCount(accounts.length),
                                    leading: const Icon(Icons.manage_accounts_rounded),
                                  ),
                                  KickBadge(
                                    label: l10n.activeAccounts(filteredEnabledCount),
                                    leading: const Icon(Icons.check_circle_outline_rounded),
                                  ),
                                  KickBadge(
                                    label: l10n.accountsFilteredCount(filteredAccounts.length),
                                    leading: const Icon(Icons.filter_alt_rounded),
                                    emphasis: hasSearch,
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (accounts.isEmpty)
                    EmptyStateCard(
                      icon: Icons.group_add_rounded,
                      title: l10n.accountsEmptyTitle,
                      message: l10n.accountsEmptyMessage,
                      action: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => _authenticateNewAccount(context, ref),
                          child: Text(l10n.connectAccountButton),
                        ),
                      ),
                    )
                  else if (filteredAccounts.isEmpty)
                    EmptyStateCard(
                      icon: Icons.manage_search_rounded,
                      title: l10n.accountsFilteredEmptyTitle,
                      message: l10n.accountsFilteredEmptyMessage,
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final spacing = 14.0;
                        final cardWidth = switch (constraints.maxWidth) {
                          > 980 => (constraints.maxWidth - spacing) / 2,
                          _ => constraints.maxWidth,
                        };

                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: filteredAccounts
                              .map(
                                (account) => SizedBox(
                                  width: cardWidth,
                                  child: _AccountCard(account: account),
                                ),
                              )
                              .toList(growable: false),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        );
      },
      error: (error, stackTrace) => EmptyStateCard(
        icon: Icons.error_rounded,
        title: l10n.accountsLoadErrorTitle,
        message: formatUserFacingError(l10n, error),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  Future<void> _authenticateNewAccount(BuildContext context, WidgetRef ref) async {
    final provider = await showAccountProviderPickerDialog(context);
    if (!context.mounted || provider == null) {
      return;
    }

    final draft = await showAccountEditorDialog(
      context,
      provider: provider,
      title: context.l10n.connectAccountDialogTitle,
    );
    if (!context.mounted || draft == null) {
      return;
    }
    if (draft.provider == AccountProvider.kiro) {
      await _connectKiroAccount(
        context,
        ref,
        label: draft.label,
        kiroBuilderIdStartUrl: draft.kiroBuilderIdStartUrl,
        kiroRegion: draft.kiroRegion,
        priority: draft.priority,
        notSupportedModels: draft.notSupportedModels,
      );
      return;
    }
    await _connectGoogleAccount(
      context,
      ref,
      projectId: draft.projectId,
      label: draft.label,
      priority: draft.priority,
      notSupportedModels: draft.notSupportedModels,
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.account});

  final AccountProfile account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final effectiveUnsupportedModels = account.effectiveNotSupportedModels;
    final priorityLabel = accountPriorityLabel(l10n, account.priority);
    final resetLabel = account.isCoolingDown ? l10n.clearCooldownAction : l10n.resetCooldownTooltip;
    final runtimeNotice = parseAccountRuntimeNotice(account.lastQuotaSnapshot);
    final hasQuotaWarning = account.lastQuotaSnapshot?.trim().isNotEmpty == true;
    final statusLabel = !account.enabled
        ? l10n.accountDisabledStatus
        : runtimeNotice?.kind == AccountRuntimeNoticeKind.termsOfServiceViolation
        ? l10n.accountTermsOfServiceStatus
        : account.isCoolingDown
        ? l10n.accountCoolingDownStatus
        : runtimeNotice?.kind == AccountRuntimeNoticeKind.banCheckPending
        ? l10n.accountBanCheckPendingStatus
        : hasQuotaWarning
        ? l10n.accountQuotaWarningStatus
        : l10n.accountReadyStatus;
    final statusIcon = !account.enabled
        ? Icons.pause_circle_rounded
        : runtimeNotice?.kind == AccountRuntimeNoticeKind.termsOfServiceViolation
        ? Icons.report_gmailerrorred_rounded
        : account.isCoolingDown
        ? Icons.schedule_rounded
        : runtimeNotice?.kind == AccountRuntimeNoticeKind.banCheckPending
        ? Icons.manage_search_rounded
        : hasQuotaWarning
        ? Icons.query_stats_rounded
        : Icons.check_circle_rounded;
    final statusTint = !account.enabled
        ? scheme.onSurfaceVariant
        : runtimeNotice?.kind == AccountRuntimeNoticeKind.termsOfServiceViolation
        ? scheme.error
        : account.isCoolingDown
        ? scheme.error
        : runtimeNotice?.kind == AccountRuntimeNoticeKind.banCheckPending
        ? scheme.tertiary
        : hasQuotaWarning
        ? scheme.tertiary
        : scheme.primary;
    final statusEmphasis = account.enabled && !account.isCoolingDown && !hasQuotaWarning;
    final showRuntimeNoticeBadge =
        hasQuotaWarning &&
        statusLabel != _accountRuntimeNoticeStatusLabel(l10n, account.lastQuotaSnapshot!);

    return KickPanel(
      tone: KickPanelTone.soft,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AccountAvatar(account: account),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account.label, style: textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      account.displayIdentity,
                      style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(
                value: account.enabled,
                onChanged: (value) {
                  ref
                      .read(accountsControllerProvider.notifier)
                      .saveAccount(account.copyWith(enabled: value));
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              KickBadge(
                label: account.provider == AccountProvider.kiro
                    ? l10n.accountProviderKiro
                    : l10n.accountProviderGemini,
                leading: ProviderIcon(provider: account.provider),
              ),
              if (account.provider != AccountProvider.kiro)
                KickBadge(
                  label: account.projectId.trim().isEmpty
                      ? l10n.projectIdAutoChip
                      : l10n.projectIdChip(account.projectId),
                  leading: const Icon(Icons.badge_rounded),
                ),
              KickBadge(
                label: l10n.priorityChip(priorityLabel),
                leading: const Icon(Icons.low_priority_rounded),
              ),
              KickBadge(
                label: statusLabel,
                leading: Icon(statusIcon, size: 16),
                emphasis: statusEmphasis,
                tint: statusTint,
              ),
              if (showRuntimeNoticeBadge)
                KickBadge(
                  label: _accountRuntimeNoticeStatusLabel(l10n, account.lastQuotaSnapshot!),
                  leading: Icon(_accountRuntimeNoticeIcon(runtimeNotice), size: 16),
                  tint: _accountRuntimeNoticeTint(scheme, runtimeNotice),
                ),
            ],
          ),
          if (effectiveUnsupportedModels.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              l10n.unsupportedModelsList(effectiveUnsupportedModels.join(', ')),
              style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (hasQuotaWarning) ...[
            const SizedBox(height: 14),
            Text(
              _formatAccountRuntimeNoticeMessage(l10n, account.lastQuotaSnapshot!),
              style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (runtimeNotice?.kind == AccountRuntimeNoticeKind.termsOfServiceViolation &&
                runtimeNotice?.actionUrl?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => unawaited(_openErrorAction(context, runtimeNotice!.actionUrl!)),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(l10n.accountSubmitAppealButton),
              ),
            ],
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AccountActionButton(
                icon: Icons.edit_rounded,
                label: l10n.editButton,
                onPressed: () async {
                  final draft = await showAccountEditorDialog(
                    context,
                    initial: account,
                    title: l10n.editAccountTitle,
                  );
                  if (!context.mounted || draft == null) {
                    return;
                  }
                  if (account.provider == AccountProvider.kiro) {
                    await _connectKiroAccount(
                      context,
                      ref,
                      existing: account,
                      label: draft.label.isEmpty ? account.label : draft.label,
                      kiroBuilderIdStartUrl: draft.kiroBuilderIdStartUrl,
                      kiroRegion: draft.kiroRegion,
                      priority: draft.priority,
                      notSupportedModels: draft.notSupportedModels,
                    );
                    return;
                  }
                  await ref
                      .read(accountsControllerProvider.notifier)
                      .saveAccount(
                        account.copyWith(
                          label: draft.label.isEmpty ? account.label : draft.label,
                          projectId: draft.projectId,
                          priority: draft.priority,
                          notSupportedModels: draft.notSupportedModels,
                        ),
                      );
                },
              ),
              if (account.supportsUsageDiagnostics)
                _AccountActionButton(
                  icon: Icons.query_stats_rounded,
                  label: l10n.accountUsageOpenTooltip,
                  onPressed: () =>
                      context.pushNamed('account-usage', pathParameters: {'accountId': account.id}),
                ),
              _AccountMoreActionsButton(
                account: account,
                label: l10n.moreButton,
                resetLabel: resetLabel,
                onSelected: (action) {
                  unawaited(_handleAccountMenuAction(context, ref, account, action));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _AccountMenuAction { reauthorize, diagnose, reset, delete }

Future<void> _handleAccountMenuAction(
  BuildContext context,
  WidgetRef ref,
  AccountProfile account,
  _AccountMenuAction action,
) async {
  switch (action) {
    case _AccountMenuAction.reauthorize:
      final draft = await showAccountEditorDialog(
        context,
        initial: account,
        title: context.l10n.reauthorizeAccountTitle,
      );
      if (!context.mounted || draft == null) {
        return;
      }
      await _connectGoogleAccount(
        context,
        ref,
        existing: account,
        projectId: draft.projectId,
        label: draft.label.isEmpty ? account.label : draft.label,
        priority: draft.priority,
        notSupportedModels: draft.notSupportedModels,
      );
      return;
    case _AccountMenuAction.diagnose:
      await _diagnoseProject(context, ref, account);
      return;
    case _AccountMenuAction.reset:
      await ref.read(accountsControllerProvider.notifier).resetHealth(account);
      return;
    case _AccountMenuAction.delete:
      final shouldDelete = await _confirmDeleteAccount(context, account);
      if (!context.mounted || !shouldDelete) {
        return;
      }
      await ref.read(accountsControllerProvider.notifier).deleteAccount(account);
      return;
  }
}

Future<bool> _confirmDeleteAccount(BuildContext context, AccountProfile account) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        icon: const Icon(Icons.delete_rounded),
        title: Text(context.l10n.deleteAccountDialogTitle),
        content: Text(context.l10n.deleteAccountDialogMessage(account.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancelButton),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.deleteAccountConfirmButton),
          ),
        ],
      );
    },
  );

  return confirmed == true;
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.account});

  final AccountProfile account;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final avatarUrl = account.avatarUrl;
    final fallback = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(Icons.account_circle_rounded, color: scheme.onSecondaryContainer, size: 30),
    );

    if (avatarUrl == null || avatarUrl.isEmpty) {
      return fallback;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: 52,
        height: 52,
        child: Image.network(avatarUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}

Future<void> _connectGoogleAccount(
  BuildContext context,
  WidgetRef ref, {
  required String projectId,
  required String label,
  required int priority,
  required List<String> notSupportedModels,
  AccountProfile? existing,
}) async {
  try {
    await ref
        .read(accountsControllerProvider.notifier)
        .connectGoogleAccount(
          existing: existing,
          projectId: projectId,
          label: label,
          priority: priority,
          notSupportedModels: notSupportedModels,
        );
  } catch (error) {
    if (!context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(formatUserFacingError(context.l10n, error))));
  }
}

Future<void> _connectKiroAccount(
  BuildContext context,
  WidgetRef ref, {
  required String label,
  required String kiroBuilderIdStartUrl,
  required String kiroRegion,
  required int priority,
  required List<String> notSupportedModels,
  AccountProfile? existing,
}) async {
  final keepAlive = ref.read(androidAuthKeepAliveProvider);
  final keepAliveStarted = await keepAlive.begin(
    notificationTitle: context.l10n.kiroLinkAuthDialogTitle,
  );
  if (!context.mounted) {
    await keepAlive.end(keepAliveStarted);
    return;
  }
  try {
    final resolvedCredentialSourcePath = await _authorizeKiroByLink(
      context,
      ref,
      startUrl: kiroBuilderIdStartUrl,
      region: kiroRegion,
    );
    if (resolvedCredentialSourcePath == null) {
      return;
    }

    await ref
        .read(accountsControllerProvider.notifier)
        .connectKiroAccount(
          existing: existing,
          label: label,
          credentialSourcePath: resolvedCredentialSourcePath,
          priority: priority,
          notSupportedModels: notSupportedModels,
        );
  } catch (error) {
    if (!context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(formatUserFacingError(context.l10n, error))));
  } finally {
    await keepAlive.end(keepAliveStarted);
  }
}

Future<String?> _authorizeKiroByLink(
  BuildContext context,
  WidgetRef ref, {
  required String startUrl,
  required String region,
}) async {
  final service = ref.read(kiroLinkAuthServiceProvider);
  final request = await service.startBuilderIdAuthorization(
    startUrl: startUrl.trim().isEmpty ? defaultKiroBuilderIdStartUrl : startUrl.trim(),
    region: region.trim().isEmpty ? defaultKiroRegion : region.trim(),
  );
  if (!context.mounted) {
    return null;
  }

  final snapshot = await showDialog<KiroAuthSourceSnapshot>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _KiroLinkAuthDialog(request: request, service: service),
  );
  return snapshot?.sourcePath;
}

Future<void> _diagnoseProject(BuildContext context, WidgetRef ref, AccountProfile account) async {
  final l10n = context.l10n;
  final navigator = Navigator.of(context, rootNavigator: true);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(l10n.accountProjectCheckInProgressMessage)),
          ],
        ),
      ),
    ),
  );

  Object? failure;

  try {
    final snapshot = await ref.read(geminiProjectDiagnosticsServiceProvider).diagnose(account);
    if (snapshot.projectId != account.projectId) {
      await ref.read(accountsControllerProvider.notifier).refreshState();
    }
    if (navigator.canPop()) {
      navigator.pop();
    }
    if (!context.mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.verified_rounded),
        title: Text(l10n.accountProjectCheckSuccessTitle),
        content: Text(
          [
            l10n.accountProjectCheckSuccessMessage,
            l10n.projectIdChip(snapshot.projectId),
            l10n.accountProjectCheckModelValue(snapshot.modelVersion ?? snapshot.modelId),
            if (snapshot.traceId?.trim().isNotEmpty == true)
              l10n.accountProjectCheckTraceIdValue(snapshot.traceId!),
          ].join('\n\n'),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.continueButton),
          ),
        ],
      ),
    );
  } catch (error) {
    failure = error;
  }

  if (failure == null) {
    return;
  }

  if (navigator.canPop()) {
    navigator.pop();
  }
  if (!context.mounted) {
    return;
  }

  final action = primaryActionForError(failure);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.error_rounded),
      title: Text(l10n.accountProjectCheckFailureTitle),
      content: Text(formatUserFacingError(l10n, failure!)),
      actions: [
        if (action != null)
          OutlinedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(_openErrorAction(context, action.url));
            },
            child: Text(_errorActionLabel(l10n, action)),
          ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.cancelButton),
        ),
      ],
    ),
  );
}

String _errorActionLabel(KickLocalizations l10n, GeminiErrorAction action) {
  return switch (action.kind) {
    GeminiErrorActionKind.accountVerification => l10n.accountUsageVerifyAccountButton,
    GeminiErrorActionKind.accountAppeal => l10n.accountSubmitAppealButton,
    GeminiErrorActionKind.projectConfiguration => l10n.openGoogleCloudButton,
  };
}

String _accountRuntimeNoticeStatusLabel(KickLocalizations l10n, String snapshot) {
  final runtimeNotice = parseAccountRuntimeNotice(snapshot);
  return switch (runtimeNotice?.kind) {
    AccountRuntimeNoticeKind.banCheckPending => l10n.accountBanCheckPendingStatus,
    AccountRuntimeNoticeKind.termsOfServiceViolation => l10n.accountTermsOfServiceStatus,
    null => l10n.accountQuotaWarningStatus,
  };
}

String _formatAccountRuntimeNoticeMessage(KickLocalizations l10n, String snapshot) {
  final runtimeNotice = parseAccountRuntimeNotice(snapshot);
  return switch (runtimeNotice?.kind) {
    AccountRuntimeNoticeKind.banCheckPending => l10n.accountBanCheckPendingMessage,
    AccountRuntimeNoticeKind.termsOfServiceViolation => l10n.accountTermsOfServiceMessage,
    null => formatUserFacingMessage(l10n, snapshot),
  };
}

IconData _accountRuntimeNoticeIcon(AccountRuntimeNotice? runtimeNotice) {
  return switch (runtimeNotice?.kind) {
    AccountRuntimeNoticeKind.banCheckPending => Icons.manage_search_rounded,
    AccountRuntimeNoticeKind.termsOfServiceViolation => Icons.report_gmailerrorred_rounded,
    null => Icons.query_stats_rounded,
  };
}

Color _accountRuntimeNoticeTint(ColorScheme scheme, AccountRuntimeNotice? runtimeNotice) {
  return switch (runtimeNotice?.kind) {
    AccountRuntimeNoticeKind.termsOfServiceViolation => scheme.error,
    AccountRuntimeNoticeKind.banCheckPending || null => scheme.tertiary,
  };
}

Future<void> _openErrorAction(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failureMessage = context.l10n.accountErrorActionOpenFailedMessage;
  final uri = Uri.tryParse(url);
  if (uri == null) {
    messenger?.showSnackBar(SnackBar(content: Text(failureMessage)));
    return;
  }

  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      messenger?.showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  } catch (_) {
    messenger?.showSnackBar(SnackBar(content: Text(failureMessage)));
  }
}

class _KiroLinkAuthDialog extends StatefulWidget {
  const _KiroLinkAuthDialog({required this.request, required this.service});

  final KiroLinkAuthRequest request;
  final KiroLinkAuthService service;

  @override
  State<_KiroLinkAuthDialog> createState() => _KiroLinkAuthDialogState();
}

class _KiroLinkAuthDialogState extends State<_KiroLinkAuthDialog> {
  Object? _error;
  bool _cancelled = false;
  bool _openingLink = false;
  bool _linkOpenedOnce = false;

  @override
  void initState() {
    super.initState();
    unawaited(_openLink());
    unawaited(_waitForAuthorization());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: Icon(_error == null ? Icons.link_rounded : Icons.error_outline_rounded),
        title: Text(l10n.kiroLinkAuthDialogTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _error == null
                    ? l10n.kiroLinkAuthDialogMessage
                    : formatUserFacingError(l10n, _error!),
              ),
              const SizedBox(height: 16),
              _KiroAuthFactRow(
                icon: Icons.password_rounded,
                label: l10n.kiroLinkAuthUserCodeLabel,
                value: widget.request.userCode,
              ),
              const SizedBox(height: 8),
              _KiroAuthFactRow(
                icon: Icons.public_rounded,
                label: l10n.kiroLinkAuthVerificationUrlLabel,
                value: widget.request.verificationUriComplete,
              ),
              if (_error == null) ...[
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(l10n.kiroLinkAuthWaitingMessage)),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _openingLink ? null : _openLink,
            child: Text(
              _linkOpenedOnce
                  ? l10n.kiroLinkAuthOpenLinkAgainButton
                  : l10n.kiroLinkAuthOpenLinkButton,
            ),
          ),
          FilledButton(
            onPressed: _dismiss,
            child: Text(_error == null ? l10n.cancelButton : l10n.continueButton),
          ),
        ],
      ),
    );
  }

  Future<void> _waitForAuthorization() async {
    try {
      final snapshot = await widget.service.completeBuilderIdAuthorization(
        widget.request,
        isCancelled: () => _cancelled,
      );
      if (!mounted || _cancelled) {
        return;
      }
      Navigator.of(context).pop(snapshot);
    } catch (error) {
      if (!mounted || _cancelled) {
        return;
      }
      setState(() => _error = error);
    }
  }

  Future<void> _openLink() async {
    setState(() => _openingLink = true);
    try {
      final opened = await launchUrl(
        Uri.parse(widget.request.verificationUriComplete),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) {
        return;
      }
      setState(() => _linkOpenedOnce = _linkOpenedOnce || opened);
      if (!opened) {
        _showOpenLinkFailedSnackBar();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showOpenLinkFailedSnackBar();
    } finally {
      if (mounted) {
        setState(() => _openingLink = false);
      }
    }
  }

  void _showOpenLinkFailedSnackBar() {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(context.l10n.kiroLinkAuthOpenLinkFailedMessage)));
  }

  void _dismiss() {
    _cancelled = true;
    Navigator.of(context).pop();
  }
}

class _KiroAuthFactRow extends StatelessWidget {
  const _KiroAuthFactRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 2),
              SelectableText(
                value,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountActionButton extends StatelessWidget {
  const _AccountActionButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.72)),
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _AccountMoreActionsButton extends StatelessWidget {
  const _AccountMoreActionsButton({
    required this.account,
    required this.label,
    required this.resetLabel,
    required this.onSelected,
  });

  final AccountProfile account;
  final String label;
  final String resetLabel;
  final ValueChanged<_AccountMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        surfaceTintColor: WidgetStatePropertyAll(scheme.surfaceTint),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.42)),
        ),
      ),
      menuChildren: [
        if (account.provider == AccountProvider.gemini)
          MenuItemButton(
            leadingIcon: const Icon(Icons.manage_accounts_rounded, size: 18),
            onPressed: () => onSelected(_AccountMenuAction.reauthorize),
            child: Text(l10n.reauthorizeButton),
          ),
        if (account.provider == AccountProvider.gemini)
          MenuItemButton(
            leadingIcon: const Icon(Icons.fact_check_rounded, size: 18),
            onPressed: () => onSelected(_AccountMenuAction.diagnose),
            child: Text(l10n.accountProjectCheckButton),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.restart_alt_rounded, size: 18),
          onPressed: () => onSelected(_AccountMenuAction.reset),
          child: Text(resetLabel),
        ),
        MenuItemButton(
          leadingIcon: Icon(Icons.delete_rounded, size: 18, color: scheme.error),
          style: ButtonStyle(foregroundColor: WidgetStatePropertyAll(scheme.error)),
          onPressed: () => onSelected(_AccountMenuAction.delete),
          child: Text(l10n.deleteTooltip),
        ),
      ],
      builder: (context, controller, child) {
        return OutlinedButton.icon(
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            foregroundColor: scheme.onSurface,
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.72)),
            visualDensity: VisualDensity.compact,
          ),
          icon: const Icon(Icons.more_horiz_rounded, size: 18),
          label: Text(label),
        );
      },
    );
  }
}

List<AccountProfile> _applyAccountSearchAndSort(
  List<AccountProfile> accounts, {
  required String query,
  required _AccountSortOption sortOption,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final filtered = accounts.where((account) => _accountMatchesQuery(account, normalizedQuery));
  final sorted = filtered.toList(growable: false)
    ..sort((left, right) => _compareAccounts(left, right, sortOption));
  return sorted;
}

bool _accountMatchesQuery(AccountProfile account, String query) {
  if (query.isEmpty) {
    return true;
  }

  final haystack = <String>[
    account.label,
    account.displayIdentity,
    account.email,
    account.projectId,
    account.provider.name,
    account.provider == AccountProvider.kiro ? 'aws builder id' : 'gemini cli',
  ].join('\n').toLowerCase();

  return haystack.contains(query);
}

int _compareAccounts(AccountProfile left, AccountProfile right, _AccountSortOption sortOption) {
  final primary = switch (sortOption) {
    _AccountSortOption.attention => _accountAttentionRank(
      left,
    ).compareTo(_accountAttentionRank(right)),
    _AccountSortOption.priority => right.priority.compareTo(left.priority),
    _AccountSortOption.label => _compareText(left.label, right.label),
    _AccountSortOption.recentActivity => _compareDateDesc(left.lastUsedAt, right.lastUsedAt),
  };
  if (primary != 0) {
    return primary;
  }

  final secondary = switch (sortOption) {
    _AccountSortOption.attention => right.priority.compareTo(left.priority),
    _AccountSortOption.priority => _accountAttentionRank(
      left,
    ).compareTo(_accountAttentionRank(right)),
    _AccountSortOption.label => right.priority.compareTo(left.priority),
    _AccountSortOption.recentActivity => right.usageCount.compareTo(left.usageCount),
  };
  if (secondary != 0) {
    return secondary;
  }

  return _compareText(left.label, right.label);
}

int _accountAttentionRank(AccountProfile account) {
  final runtimeNotice = parseAccountRuntimeNotice(account.lastQuotaSnapshot);
  if (runtimeNotice?.kind == AccountRuntimeNoticeKind.termsOfServiceViolation) {
    return 0;
  }
  if (runtimeNotice?.kind == AccountRuntimeNoticeKind.banCheckPending) {
    return 1;
  }
  if (account.lastQuotaSnapshot?.trim().isNotEmpty == true) {
    return 2;
  }
  if (account.isCoolingDown) {
    return 3;
  }
  if (account.enabled) {
    return 4;
  }
  return 5;
}

int _compareDateDesc(DateTime? left, DateTime? right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  return right.compareTo(left);
}

int _compareText(String left, String right) {
  return left.toLowerCase().compareTo(right.toLowerCase());
}

String _accountSortOptionLabel(KickLocalizations l10n, _AccountSortOption option) {
  return switch (option) {
    _AccountSortOption.attention => l10n.accountsSortAttention,
    _AccountSortOption.priority => l10n.accountsSortPriority,
    _AccountSortOption.label => l10n.accountsSortAlphabetical,
    _AccountSortOption.recentActivity => l10n.accountsSortRecentActivity,
  };
}
