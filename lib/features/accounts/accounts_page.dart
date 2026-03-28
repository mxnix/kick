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
import '../app_state/providers.dart';
import '../shared/kick_surfaces.dart';
import 'account_editor_dialog.dart';
import 'account_priority_presentation.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final accountsValue = ref.watch(accountsControllerProvider);

    return accountsValue.when(
      data: (accounts) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                title: l10n.accountsTitle,
                subtitle: l10n.accountsSubtitle,
                trailing: FilledButton.icon(
                  onPressed: () => _authenticateNewAccount(context, ref),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.addButton),
                ),
              ),
              const SizedBox(height: 24),
              if (accounts.isEmpty)
                EmptyStateCard(
                  icon: Icons.group_add_rounded,
                  title: l10n.accountsEmptyTitle,
                  message: l10n.accountsEmptyMessage,
                  action: FilledButton(
                    onPressed: () => _authenticateNewAccount(context, ref),
                    child: Text(l10n.connectAccountButton),
                  ),
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
                      children: accounts
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

  Future<void> _authenticateNewAccount(BuildContext context, WidgetRef ref) async {
    final draft = await showAccountEditorDialog(
      context,
      title: context.l10n.connectGoogleAccountTitle,
    );
    if (!context.mounted || draft == null) {
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
    final statusLabel = !account.enabled
        ? l10n.accountDisabledStatus
        : account.isCoolingDown
        ? l10n.accountCoolingDownStatus
        : l10n.accountReadyStatus;
    final statusIcon = !account.enabled
        ? Icons.pause_circle_rounded
        : account.isCoolingDown
        ? Icons.schedule_rounded
        : Icons.check_circle_rounded;
    final statusTint = !account.enabled
        ? scheme.onSurfaceVariant
        : account.isCoolingDown
        ? scheme.error
        : scheme.primary;
    final statusEmphasis = account.enabled && !account.isCoolingDown;
    final hasQuotaWarning = account.lastQuotaSnapshot?.trim().isNotEmpty == true;

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
                      account.email,
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
                label: account.projectId.trim().isEmpty
                    ? '${l10n.projectIdLabel}: auto'
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
              if (hasQuotaWarning)
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
              _AccountActionButton(
                icon: Icons.query_stats_rounded,
                label: l10n.accountUsageOpenTooltip,
                onPressed: () =>
                    context.pushNamed('account-usage', pathParameters: {'accountId': account.id}),
              ),
              _AccountMoreActionsButton(
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
            'PROJECT_ID: ${snapshot.projectId}',
            'Model: ${snapshot.modelVersion ?? snapshot.modelId}',
            if (snapshot.traceId?.trim().isNotEmpty == true) 'Trace ID: ${snapshot.traceId}',
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
    required this.label,
    required this.resetLabel,
    required this.onSelected,
  });

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
        MenuItemButton(
          leadingIcon: const Icon(Icons.manage_accounts_rounded, size: 18),
          onPressed: () => onSelected(_AccountMenuAction.reauthorize),
          child: Text(l10n.reauthorizeButton),
        ),
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
