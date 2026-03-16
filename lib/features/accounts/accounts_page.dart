import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
        icon: Icons.error_outline_rounded,
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
    final priorityLabel = accountPriorityLabel(l10n, account.priority);
    final resetLabel = account.isCoolingDown ? l10n.clearCooldownAction : l10n.resetCooldownTooltip;
    final statusLabel = !account.enabled
        ? l10n.accountDisabledStatus
        : account.isCoolingDown
        ? l10n.accountCoolingDownStatus
        : l10n.accountReadyStatus;
    final statusIcon = !account.enabled
        ? Icons.pause_circle_outline_rounded
        : account.isCoolingDown
        ? Icons.schedule_rounded
        : Icons.check_circle_rounded;
    final statusTint = !account.enabled
        ? scheme.onSurfaceVariant
        : account.isCoolingDown
        ? scheme.error
        : scheme.primary;
    final statusEmphasis = account.enabled && !account.isCoolingDown;

    return KickPanel(
      tone: KickPanelTone.soft,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer.withValues(alpha: 0.84),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.account_circle_rounded,
                  color: scheme.onSecondaryContainer,
                  size: 30,
                ),
              ),
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
                label: l10n.projectIdChip(account.projectId),
                leading: const Icon(Icons.badge_outlined),
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
            ],
          ),
          if (account.notSupportedModels.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              l10n.unsupportedModelsList(account.notSupportedModels.join(', ')),
              style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AccountActionButton(
                icon: Icons.edit_outlined,
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
                icon: Icons.manage_accounts_outlined,
                label: l10n.reauthorizeButton,
                onPressed: () async {
                  final draft = await showAccountEditorDialog(
                    context,
                    initial: account,
                    title: l10n.reauthorizeAccountTitle,
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
                },
              ),
              _AccountActionButton(
                icon: account.isCoolingDown ? Icons.lock_open_rounded : Icons.restart_alt_rounded,
                label: resetLabel,
                onPressed: () => ref.read(accountsControllerProvider.notifier).resetHealth(account),
              ),
              _AccountActionButton(
                icon: Icons.query_stats_rounded,
                label: l10n.accountUsageOpenTooltip,
                onPressed: () =>
                    context.pushNamed('account-usage', pathParameters: {'accountId': account.id}),
              ),
              _AccountActionButton(
                icon: Icons.delete_outline_rounded,
                label: l10n.deleteTooltip,
                destructive: true,
                onPressed: () =>
                    ref.read(accountsControllerProvider.notifier).deleteAccount(account),
              ),
            ],
          ),
        ],
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

class _AccountActionButton extends StatelessWidget {
  const _AccountActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = destructive ? scheme.error : scheme.onSurface;
    final border = destructive
        ? scheme.error.withValues(alpha: 0.22)
        : scheme.outlineVariant.withValues(alpha: 0.72);

    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        foregroundColor: foreground,
        side: BorderSide(color: border),
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}
