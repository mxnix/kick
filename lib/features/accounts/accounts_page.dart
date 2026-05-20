import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/accounts/account_runtime_notice.dart';
import '../../core/errors/gemini_error_actions.dart';
import '../../core/errors/user_facing_error_formatter.dart';
import '../../core/theme/kick_icons.dart';
import '../../data/models/account_profile.dart';
import '../../l10n/kick_localizations.dart';
import '../../proxy/kiro/kiro_auth_source.dart';
import '../../proxy/kiro/kiro_link_auth_service.dart';
import '../app_shell/app_shell.dart';
import '../app_state/providers.dart';
import '../shared/kick_actions.dart';
import '../shared/kick_haptics.dart';
import '../shared/kick_scroll.dart';
import '../shared/kick_surfaces.dart';
import '../shared/provider_icon.dart';
import 'account_avatar.dart';
import 'account_editor_dialog.dart';
import 'account_priority_presentation.dart';
import 'account_provider_picker_dialog.dart';
import 'account_share_service.dart';
import 'luma_webview_login_dialog.dart';

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

        return KickSmoothSingleChildScrollView(
          padding: EdgeInsets.only(bottom: AppShell.floatingNavigationClearanceOf(context)),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useCompactHeader = constraints.maxWidth < 680;

              Widget buildAddButton({required bool fullWidth}) {
                final button = KickPrimaryAction(
                  onPressed: () => _authenticateNewAccount(context, ref),
                  icon: KickIcons.add,
                  label: l10n.addButton,
                  fullWidth: fullWidth,
                );
                return button;
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
                    const SizedBox(height: 20),
                    _AccountsControlsBar(
                      searchController: _searchController,
                      hasSearch: hasSearch,
                      onSearchChanged: (value) => setState(() => _query = value),
                      onClearSearch: _clearSearch,
                      sortOption: _sortOption,
                      onSortChanged: (value) => setState(() => _sortOption = value),
                    ),
                    const SizedBox(height: 14),
                    _AccountsMetricsBar(
                      totalCount: accounts.length,
                      activeCount: filteredEnabledCount,
                      filteredCount: filteredAccounts.length,
                      highlightFiltered: hasSearch,
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (accounts.isEmpty)
                    EmptyStateCard(
                      icon: KickIcons.addAccount,
                      title: l10n.accountsEmptyTitle,
                      message: l10n.accountsEmptyMessage,
                      action: SizedBox(
                        width: double.infinity,
                        child: KickPrimaryAction(
                          label: l10n.connectAccountButton,
                          icon: KickIcons.addAccount,
                          fullWidth: true,
                          onPressed: () => _authenticateNewAccount(context, ref),
                        ),
                      ),
                    )
                  else if (filteredAccounts.isEmpty)
                    EmptyStateCard(
                      icon: KickIcons.search,
                      title: l10n.accountsFilteredEmptyTitle,
                      message: l10n.accountsFilteredEmptyMessage,
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final spacing = 14.0;
                        final columns = switch (constraints.maxWidth) {
                          >= 1320 => 3,
                          >= 860 => 2,
                          _ => 1,
                        };
                        final cardWidth =
                            (constraints.maxWidth - spacing * (columns - 1)) / columns;

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
        icon: KickIcons.error,
        title: l10n.accountsLoadErrorTitle,
        message: formatUserFacingError(l10n, error),
      ),
      loading: () => const Center(child: KickLoadingIndicator()),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  Future<void> _authenticateNewAccount(BuildContext context, WidgetRef ref) async {
    final pickerResult = await showAccountProviderPickerDialog(context);
    if (!context.mounted || pickerResult == null) {
      return;
    }

    if (pickerResult is AccountProviderPickerImportFromFile) {
      await _importSharedAccount(context, ref);
      return;
    }

    final provider = (pickerResult as AccountProviderPickerSelected).provider;
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
    if (draft.provider == AccountProvider.luma) {
      await _connectLumaAccount(
        context,
        ref,
        label: draft.label,
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
      autoDiagnoseWhenProjectIdMissing: true,
    );
  }

  Future<void> _importSharedAccount(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final shareService = ref.read(accountShareServiceProvider);
    AccountShareImportResult? imported;
    try {
      imported = await shareService.pickAndDecode(dialogTitle: l10n.accountShareImportDialogTitle);
    } on AccountShareException catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_formatAccountShareError(l10n, error))));
      return;
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.accountShareImportFailedMessage)));
      return;
    }

    if (!context.mounted || imported == null) {
      return;
    }

    try {
      final saved = await ref
          .read(accountsControllerProvider.notifier)
          .importSharedAccount(imported);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.accountShareImportedMessage(saved.label))));
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.accountShareImportFailedMessage)));
    }
  }
}

class _AccountsControlsBar extends StatelessWidget {
  const _AccountsControlsBar({
    required this.searchController,
    required this.hasSearch,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.sortOption,
    required this.onSortChanged,
  });

  final TextEditingController searchController;
  final bool hasSearch;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final _AccountSortOption sortOption;
  final ValueChanged<_AccountSortOption> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final materialLocalizations = MaterialLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(KickIcons.search),
                hintText: l10n.accountsSearchHint,
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                suffixIcon: hasSearch
                    ? IconButton(
                        onPressed: onClearSearch,
                        tooltip: materialLocalizations.clearButtonTooltip,
                        icon: const Icon(KickIcons.clear),
                      )
                    : null,
              ),
              onChanged: onSearchChanged,
            ),
          ),
          const SizedBox(width: 4),
          _AccountsSortMenu(sortOption: sortOption, onSortChanged: onSortChanged),
        ],
      ),
    );
  }
}

class _AccountsSortMenu extends StatelessWidget {
  const _AccountsSortMenu({required this.sortOption, required this.onSortChanged});

  final _AccountSortOption sortOption;
  final ValueChanged<_AccountSortOption> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.42)),
        ),
      ),
      menuChildren: [
        for (final option in _AccountSortOption.values)
          MenuItemButton(
            leadingIcon: Icon(
              option == sortOption ? Icons.check_rounded : null,
              size: 18,
              color: option == sortOption ? scheme.primary : null,
            ),
            onPressed: () => onSortChanged(option),
            child: Text(_accountSortOptionLabel(l10n, option)),
          ),
      ],
      builder: (context, controller, child) {
        return Tooltip(
          message: l10n.accountsSortLabel,
          child: IconButton(
            onPressed: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            icon: const Icon(KickIcons.sort),
          ),
        );
      },
    );
  }
}

class _AccountsMetricsBar extends StatelessWidget {
  const _AccountsMetricsBar({
    required this.totalCount,
    required this.activeCount,
    required this.filteredCount,
    required this.highlightFiltered,
  });

  final int totalCount;
  final int activeCount;
  final int filteredCount;
  final bool highlightFiltered;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget buildSegment({
      required IconData icon,
      required String label,
      required String value,
      bool emphasized = false,
    }) {
      final labelColor = emphasized ? scheme.primary : scheme.onSurfaceVariant;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 15, color: labelColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(color: labelColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: textTheme.titleMedium?.copyWith(
                  color: emphasized ? scheme.primary : scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildDivider() {
      return Container(width: 1, height: 34, color: scheme.outlineVariant.withValues(alpha: 0.38));
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            buildSegment(
              icon: KickIcons.manageAccounts,
              label: _accountsMetricLabel(l10n.accountsTotalCount(totalCount)),
              value: '$totalCount',
            ),
            buildDivider(),
            buildSegment(
              icon: KickIcons.check,
              label: _accountsMetricLabel(l10n.activeAccounts(activeCount)),
              value: '$activeCount',
            ),
            buildDivider(),
            buildSegment(
              icon: KickIcons.filter,
              label: _accountsMetricLabel(l10n.accountsFilteredCount(filteredCount)),
              value: '$filteredCount',
              emphasized: highlightFiltered,
            ),
          ],
        ),
      ),
    );
  }

  static String _accountsMetricLabel(String combined) {
    final colon = combined.lastIndexOf(':');
    if (colon <= 0) {
      return combined;
    }
    return combined.substring(0, colon).trim();
  }
}

class _AccountStatusDot extends StatelessWidget {
  const _AccountStatusDot({required this.color, required this.tooltip});

  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _AccountProviderInlineBadge extends StatelessWidget {
  const _AccountProviderInlineBadge({required this.provider});

  final AccountProvider provider;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final label = switch (provider) {
      AccountProvider.kiro => l10n.accountProviderKiro,
      AccountProvider.gemini => l10n.accountProviderGemini,
      AccountProvider.luma => l10n.accountProviderLuma,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.36)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme(
            data: IconThemeData(size: 14, color: scheme.onSurfaceVariant),
            child: ProviderIcon(provider: provider),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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
        ? Icons.pause_rounded
        : runtimeNotice?.kind == AccountRuntimeNoticeKind.termsOfServiceViolation
        ? KickIcons.report
        : account.isCoolingDown
        ? KickIcons.schedule
        : runtimeNotice?.kind == AccountRuntimeNoticeKind.banCheckPending
        ? KickIcons.search
        : hasQuotaWarning
        ? KickIcons.queryStats
        : KickIcons.check;
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
              _AccountAvatar(
                account: account,
                onAvatarChanged: (avatarUrl) {
                  unawaited(
                    ref
                        .read(accountsControllerProvider.notifier)
                        .saveAccount(
                          avatarUrl == null
                              ? account.copyWith(clearAvatarUrl: true)
                              : account.copyWith(avatarUrl: avatarUrl),
                        ),
                  );
                },
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _AccountStatusDot(color: statusTint, tooltip: statusLabel),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            account.label,
                            style: textTheme.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _AccountProviderInlineBadge(provider: account.provider),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _accountSubtitle(account),
                      style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (account.provider == AccountProvider.gemini) ...[
                      const SizedBox(height: 4),
                      Text(
                        account.projectId.trim().isEmpty
                            ? l10n.projectIdAutoChip
                            : l10n.projectIdChip(account.projectId),
                        style: textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                          letterSpacing: 0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else if (account.provider == AccountProvider.luma) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.lumaSourceChip(_lumaSourceChipValue(account)),
                        style: textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                          letterSpacing: 0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.kiroCredentialSourceChip(_kiroSourceChipValue(account)),
                        style: textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                          letterSpacing: 0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: account.enabled,
                onChanged: (value) {
                  KickHaptics.selection();
                  unawaited(
                    ref
                        .read(accountsControllerProvider.notifier)
                        .saveAccount(account.copyWith(enabled: value)),
                  );
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
                label: l10n.priorityChip(priorityLabel),
                leading: const Icon(KickIcons.lowPriority),
              ),
              if (!statusEmphasis || !account.enabled)
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
              KickSecondaryAction(
                onPressed: () => unawaited(_openErrorAction(context, runtimeNotice!.actionUrl!)),
                icon: KickIcons.openInNew,
                label: l10n.accountSubmitAppealButton,
              ),
            ],
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AccountActionButton(
                icon: KickIcons.edit,
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
                  if (account.provider == AccountProvider.luma) {
                    await ref
                        .read(accountsControllerProvider.notifier)
                        .saveAccount(
                          account.copyWith(
                            label: draft.label.isEmpty ? account.label : draft.label,
                            priority: draft.priority,
                            notSupportedModels: draft.notSupportedModels,
                          ),
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
                  icon: KickIcons.queryStats,
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

enum _AccountMenuAction { reauthorize, diagnose, reset, share, delete }

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
      if (account.provider == AccountProvider.luma) {
        await _connectLumaAccount(
          context,
          ref,
          existing: account,
          label: draft.label.isEmpty ? account.label : draft.label,
          priority: draft.priority,
          notSupportedModels: draft.notSupportedModels,
        );
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
    case _AccountMenuAction.share:
      await _shareAccount(context, ref, account);
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

Future<void> _shareAccount(BuildContext context, WidgetRef ref, AccountProfile account) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final shareService = ref.read(accountShareServiceProvider);
  try {
    final result = await shareService.share(
      account: account,
      dialogTitle: l10n.accountShareExportDialogTitle,
      shareSubject: l10n.accountShareSubject(account.label),
      shareText: l10n.accountShareSubject(account.label),
    );
    if (!context.mounted || result == null) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.accountShareExportedMessage(result.fileName))));
  } catch (_) {
    if (!context.mounted) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.accountShareExportFailedMessage)));
  }
}

String _formatAccountShareError(KickLocalizations l10n, AccountShareException error) {
  return switch (error.code) {
    AccountShareErrorCode.invalidFormat => l10n.accountShareInvalidFormatMessage,
    AccountShareErrorCode.unsupportedVersion => l10n.accountShareUnsupportedVersionMessage,
    AccountShareErrorCode.readFailed => l10n.accountShareReadFailedMessage,
  };
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

class _AccountAvatar extends StatefulWidget {
  const _AccountAvatar({required this.account, required this.onAvatarChanged});

  final AccountProfile account;
  final ValueChanged<String?> onAvatarChanged;

  @override
  State<_AccountAvatar> createState() => _AccountAvatarState();
}

class _AccountAvatarState extends State<_AccountAvatar> {
  bool _pressed = false;

  bool get _supportsCustomAvatar => widget.account.provider != AccountProvider.gemini;

  void _showPreview() {
    setState(() => _pressed = true);
    KickHaptics.light();
    unawaited(
      _showAccountAvatarPreview(context, widget.account).whenComplete(() {
        if (mounted) {
          setState(() => _pressed = false);
        }
      }),
    );
  }

  Future<void> _openAvatarPicker() async {
    KickHaptics.selection();
    final nextAvatar = await _showAvatarPickerDialog(context, widget.account);
    if (!mounted || nextAvatar == _avatarPickerCancelled) {
      return;
    }
    widget.onAvatarChanged(nextAvatar?.trim().isEmpty == true ? null : nextAvatar);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.accountAvatarOpenTooltip,
      child: GestureDetector(
        onTap: () async {
          if (_supportsCustomAvatar) {
            await _openAvatarPicker();
          } else {
            _showPreview();
          }
        },
        onLongPressStart: _supportsCustomAvatar ? (_) => _showPreview() : null,
        onLongPressEnd: _supportsCustomAvatar
            ? (_) {
                if (mounted) {
                  setState(() => _pressed = false);
                }
              }
            : null,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: _AccountAvatarImage(account: widget.account, size: 52, radius: 20),
        ),
      ),
    );
  }
}

class _AccountAvatarImage extends StatelessWidget {
  const _AccountAvatarImage({required this.account, required this.size, required this.radius});

  final AccountProfile account;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return AccountAvatarImage(account: account, size: size, radius: radius);
  }
}

class _AccountAvatarFallback extends StatelessWidget {
  const _AccountAvatarFallback({required this.account, required this.size, required this.radius});

  final AccountProfile account;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return AccountAvatarFallback(account: account, size: size, radius: radius);
  }
}

const String _avatarPickerCancelled = '__kick_avatar_cancelled__';

Future<String?> _showAvatarPickerDialog(BuildContext context, AccountProfile account) {
  return showDialog<String?>(
    context: context,
    builder: (dialogContext) => _AvatarPickerDialog(account: account),
  );
}

class _AvatarPickerDialog extends StatefulWidget {
  const _AvatarPickerDialog({required this.account});

  final AccountProfile account;

  @override
  State<_AvatarPickerDialog> createState() => _AvatarPickerDialogState();
}

class _AvatarPickerDialogState extends State<_AvatarPickerDialog> {
  bool _pickingFile = false;
  String? _selectedSeed;
  String? _customFileUrl;

  @override
  void initState() {
    super.initState();
    final seeds = _avatarSeedOptions(widget.account);
    final currentAvatar = widget.account.avatarUrl?.trim();
    if (currentAvatar != null && currentAvatar.isNotEmpty) {
      if (_isFileAvatarUrl(currentAvatar)) {
        _customFileUrl = currentAvatar;
      } else {
        for (final seed in seeds) {
          if (_diceBearAvatarUrl(seed) == currentAvatar) {
            _selectedSeed = seed;
            break;
          }
        }
      }
    }
  }

  bool get _hasSelection => _selectedSeed != null || _customFileUrl != null;

  String? _selectedUrl() {
    if (_customFileUrl != null) {
      return _customFileUrl;
    }
    if (_selectedSeed != null) {
      return _diceBearAvatarUrl(_selectedSeed!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final seeds = _avatarSeedOptions(widget.account);
    final previewUrl = _selectedUrl();
    const contentPadding = EdgeInsets.fromLTRB(24, 16, 24, 16);
    const maxContentWidth = 380.0;
    const minDialogWidth = 280.0;
    const dialogHorizontalInset = 40.0 * 2;
    const avatarColumns = 3;
    const avatarGap = 10.0;
    final contentWidth =
        (MediaQuery.sizeOf(context).width - dialogHorizontalInset - contentPadding.horizontal)
            .clamp(minDialogWidth - contentPadding.horizontal, maxContentWidth)
            .toDouble();
    final avatarTileSize = ((contentWidth - (avatarGap * (avatarColumns - 1))) / avatarColumns)
        .clamp(72.0, 120.0)
        .toDouble();

    return AlertDialog(
      icon: const Icon(Icons.account_circle_rounded),
      title: Text(l10n.accountAvatarDialogTitle),
      contentPadding: contentPadding,
      content: SizedBox(
        width: contentWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: _AvatarPickerPreview(
                  account: widget.account,
                  selectedUrl: previewUrl,
                  size: 104,
                  radius: 28,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.accountAvatarStandardAvatarsTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: avatarGap,
                runSpacing: avatarGap,
                children: [
                  for (final seed in seeds)
                    _AvatarOptionTile(
                      url: _diceBearAvatarUrl(seed),
                      size: avatarTileSize,
                      selected: _selectedSeed == seed && _customFileUrl == null,
                      onTap: () {
                        KickHaptics.selection();
                        setState(() {
                          _selectedSeed = seed;
                          _customFileUrl = null;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _pickingFile ? null : _pickFileAvatar,
                    icon: _pickingFile
                        ? const SizedBox.square(
                            dimension: 18,
                            child: KickLoadingIndicator(size: 18, contained: false),
                          )
                        : const Icon(Icons.image_rounded, size: 18),
                    label: Text(l10n.accountAvatarChooseFileButton),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _pickingFile ? null : () => Navigator.of(context).pop(null),
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: Text(l10n.accountAvatarResetButton),
                    style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _pickingFile ? null : () => Navigator.of(context).pop(_avatarPickerCancelled),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: _pickingFile || !_hasSelection
              ? null
              : () => Navigator.of(context).pop(_selectedUrl()),
          child: Text(l10n.accountAvatarApplyButton),
        ),
      ],
    );
  }

  Future<void> _pickFileAvatar() async {
    setState(() => _pickingFile = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (!mounted) {
        return;
      }
      final path = result?.files.single.path;
      if (path == null || path.trim().isEmpty) {
        setState(() => _pickingFile = false);
        return;
      }
      setState(() {
        _customFileUrl = Uri.file(path).toString();
        _selectedSeed = null;
        _pickingFile = false;
      });
    } finally {
      if (mounted && _pickingFile) {
        setState(() => _pickingFile = false);
      }
    }
  }
}

class _AvatarPickerPreview extends StatelessWidget {
  const _AvatarPickerPreview({
    required this.account,
    required this.selectedUrl,
    required this.size,
    required this.radius,
  });

  final AccountProfile account;
  final String? selectedUrl;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = _AccountAvatarFallback(account: account, size: size, radius: radius);
    Widget image;
    if (selectedUrl == null || selectedUrl!.isEmpty) {
      image = _AccountAvatarImage(account: account, size: size, radius: radius);
    } else if (_isFileAvatarUrl(selectedUrl!)) {
      image = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: size,
          height: size,
          child: Image.file(
            File.fromUri(Uri.parse(selectedUrl!)),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          ),
        ),
      );
    } else {
      image = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            selectedUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
            loadingBuilder: (_, child, progress) => progress == null ? child : fallback,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius + 4),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.32), width: 1.5),
      ),
      child: image,
    );
  }
}

class _AvatarOptionTile extends StatelessWidget {
  const _AvatarOptionTile({
    required this.url,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final String url;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = _AvatarOptionFallback(size: size);
    return SizedBox(
      width: size,
      height: size,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.42),
                  width: selected ? 2 : 1,
                ),
                color: selected ? scheme.primary.withValues(alpha: 0.08) : Colors.transparent,
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => fallback,
                    loadingBuilder: (_, child, progress) => progress == null ? child : fallback,
                  ),
                ),
              ),
            ),
            if (selected)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded, size: 14, color: scheme.onPrimary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AvatarOptionFallback extends StatelessWidget {
  const _AvatarOptionFallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      color: scheme.secondaryContainer.withValues(alpha: 0.62),
      child: Icon(
        Icons.account_circle_rounded,
        color: scheme.onSecondaryContainer.withValues(alpha: 0.82),
        size: size * 0.46,
      ),
    );
  }
}

Future<void> _showAccountAvatarPreview(BuildContext context, AccountProfile account) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: _AccountAvatarImage(account: account, size: 260, radius: 52),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.78, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

String _diceBearAvatarUrl(String seed) => diceBearAccountAvatarUrl(seed);

List<String> _avatarSeedOptions(AccountProfile account) {
  final base = account.id.trim().isEmpty ? account.label : account.id;
  return [
    base,
    '$base-orbit',
    '$base-nova',
    '$base-quartz',
    account.label.trim().isEmpty ? '$base-label' : account.label.trim(),
    account.email.trim().isEmpty ? '$base-identity' : account.email.trim(),
  ];
}

bool _isFileAvatarUrl(String value) => isFileAccountAvatarUrl(value);

Future<AccountProfile?> _connectGoogleAccount(
  BuildContext context,
  WidgetRef ref, {
  required String projectId,
  required String label,
  required int priority,
  required List<String> notSupportedModels,
  AccountProfile? existing,
  bool autoDiagnoseWhenProjectIdMissing = false,
}) async {
  AccountProfile? saved;
  try {
    saved = await ref
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
      return null;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(formatUserFacingError(context.l10n, error))));
    return null;
  }

  if (autoDiagnoseWhenProjectIdMissing &&
      saved != null &&
      saved.projectId.trim().isEmpty &&
      context.mounted) {
    await _diagnoseProject(context, ref, saved);
  }

  return saved;
}

Future<void> _connectLumaAccount(
  BuildContext context,
  WidgetRef ref, {
  required String label,
  required int priority,
  required List<String> notSupportedModels,
  AccountProfile? existing,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final service = ref.read(lumaConnectServiceProvider);
  final tokenRef = existing?.tokenRef ?? 'kick.luma.${const Uuid().v4()}';

  final dialogResult = await showLumaConnectFlow(
    context,
    service: service,
    tokenRef: tokenRef,
    labelHint: label,
  );
  if (!context.mounted || dialogResult == null) {
    return;
  }

  try {
    await ref
        .read(accountsControllerProvider.notifier)
        .connectLumaAccount(
          existing: existing,
          connect: dialogResult.connect,
          priority: priority,
          notSupportedModels: notSupportedModels,
        );
    if (!context.mounted) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.lumaConnectSuccessMessage)));
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(formatUserFacingError(l10n, error))));
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
  final request = await service.startSocialAuthorization(
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

  unawaited(
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
                child: KickLoadingIndicator(size: 24, contained: false),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(l10n.accountProjectCheckInProgressMessage)),
            ],
          ),
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
    AccountRuntimeNoticeKind.termsOfServiceViolation => KickIcons.report,
    null => Icons.query_stats_rounded,
  };
}

Color _accountRuntimeNoticeTint(ColorScheme scheme, AccountRuntimeNotice? runtimeNotice) {
  return switch (runtimeNotice?.kind) {
    AccountRuntimeNoticeKind.termsOfServiceViolation => scheme.error,
    AccountRuntimeNoticeKind.banCheckPending || null => scheme.tertiary,
  };
}

String _kiroSourceChipValue(AccountProfile account) {
  final region = account.providerRegion?.trim();
  if (region != null && region.isNotEmpty) {
    return region;
  }

  final sourceType = account.credentialSourceType?.trim().toLowerCase();
  return switch (sourceType) {
    builderIdKiroCredentialSourceType => 'AWS Builder ID',
    manualKiroCredentialSourceType => 'Kiro token file',
    defaultKiroCredentialSourceType => 'Kiro local session',
    _ => defaultKiroRegion,
  };
}

String _lumaSourceChipValue(AccountProfile account) {
  final region = account.providerRegion?.trim();
  if (region != null && region.isNotEmpty) {
    return region;
  }
  final method = account.credentialSourceType?.trim();
  if (method != null && method.isNotEmpty) {
    return method;
  }
  return 'WorkOS';
}

String _accountSubtitle(AccountProfile account) {
  final identity = account.displayIdentity;
  if (account.provider != AccountProvider.kiro) {
    return identity;
  }

  final trimmed = identity.trim();
  if (trimmed.isEmpty) {
    return identity;
  }

  if (trimmed.contains('@')) {
    return trimmed;
  }

  final lower = trimmed.toLowerCase();
  final alreadyQualified =
      lower == 'kiro' ||
      lower.startsWith('kiro ') ||
      lower.startsWith('kiro•') ||
      lower.startsWith('kiro •') ||
      trimmed.contains(' • ');
  if (alreadyQualified) {
    return identity;
  }

  return 'Kiro • $trimmed';
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
              if (widget.request.userCode.trim().isNotEmpty) ...[
                _KiroAuthFactRow(
                  icon: Icons.password_rounded,
                  label: l10n.kiroLinkAuthUserCodeLabel,
                  value: widget.request.userCode,
                ),
                const SizedBox(height: 8),
              ],
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
                      child: KickLoadingIndicator(size: 18, contained: false),
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
      var opened = await launchUrl(
        Uri.parse(widget.request.verificationUriComplete),
        mode: Platform.isAndroid ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication,
      );
      if (!opened && Platform.isAndroid) {
        opened = await launchUrl(
          Uri.parse(widget.request.verificationUriComplete),
          mode: LaunchMode.externalApplication,
        );
      }
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
    return KickSecondaryAction(onPressed: onPressed, icon: icon, label: label);
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
        if (account.provider == AccountProvider.gemini || account.provider == AccountProvider.luma)
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
          leadingIcon: const Icon(Icons.ios_share_rounded, size: 18),
          onPressed: () => onSelected(_AccountMenuAction.share),
          child: Text(l10n.accountShareAction),
        ),
        MenuItemButton(
          leadingIcon: Icon(Icons.delete_rounded, size: 18, color: scheme.error),
          style: ButtonStyle(foregroundColor: WidgetStatePropertyAll(scheme.error)),
          onPressed: () => onSelected(_AccountMenuAction.delete),
          child: Text(l10n.deleteTooltip),
        ),
      ],
      builder: (context, controller, child) {
        return KickSecondaryAction(
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          icon: KickIcons.more,
          label: label,
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
