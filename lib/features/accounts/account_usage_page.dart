import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/gemini_error_actions.dart';
import '../../core/errors/user_facing_error_formatter.dart';
import '../../core/theme/kick_theme.dart';
import '../../data/models/account_profile.dart';
import '../../l10n/kick_localizations.dart';
import '../../proxy/gemini/gemini_usage_models.dart';
import '../app_state/providers.dart';
import '../shared/kick_surfaces.dart';
import 'account_priority_presentation.dart';

class AccountUsagePage extends ConsumerWidget {
  const AccountUsagePage({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final accountsValue = ref.watch(accountsControllerProvider);

    return accountsValue.when(
      data: (accounts) {
        AccountProfile? account;
        for (final item in accounts) {
          if (item.id == accountId) {
            account = item;
            break;
          }
        }

        final resolvedAccount = account;

        if (resolvedAccount == null) {
          return _UsageScaffold(
            title: l10n.accountUsageTitle,
            subtitle: l10n.accountUsageMissingSubtitle,
            child: EmptyStateCard(
              icon: Icons.manage_search_rounded,
              title: l10n.accountUsageMissingTitle,
              message: l10n.accountUsageMissingMessage,
            ),
          );
        }

        final usageValue = ref.watch(accountUsageQueryProvider(resolvedAccount.id));
        return _UsageScaffold(
          title: l10n.accountUsageTitle,
          subtitle: resolvedAccount.email,
          onRefresh: () => ref.refresh(accountUsageQueryProvider(resolvedAccount.id).future),
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(accountUsageQueryProvider(resolvedAccount.id).future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _UsageAccountCard(account: resolvedAccount),
                const SizedBox(height: 16),
                usageValue.when(
                  data: (usage) => _UsageContent(usage: usage),
                  error: (error, stackTrace) => _UsageErrorCard(
                    message: formatUserFacingError(l10n, error),
                    onRetry: () =>
                        ref.refresh(accountUsageQueryProvider(resolvedAccount.id).future),
                    onOpenVerification: _verificationActionForError(context, error),
                  ),
                  loading: () => const _UsageLoadingState(),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
      error: (error, stackTrace) => _UsageScaffold(
        title: l10n.accountUsageTitle,
        subtitle: l10n.accountUsageMissingSubtitle,
        child: EmptyStateCard(
          icon: Icons.error_outline_rounded,
          title: l10n.accountsLoadErrorTitle,
          message: formatUserFacingError(l10n, error),
        ),
      ),
      loading: () => _UsageScaffold(
        title: l10n.accountUsageTitle,
        subtitle: l10n.loadingValue,
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _UsageScaffold extends StatelessWidget {
  const _UsageScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.onRefresh,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _UsageHeader(title: title, subtitle: subtitle, onRefresh: onRefresh),
        const SizedBox(height: 24),
        Expanded(child: child),
      ],
    );
  }
}

class _UsageHeader extends StatelessWidget {
  const _UsageHeader({required this.title, required this.subtitle, this.onRefresh});

  final String title;
  final String subtitle;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        IconButton(
          onPressed: () => context.pop(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (onRefresh != null)
          IconButton(
            onPressed: () => onRefresh!(),
            tooltip: l10n.accountUsageRefreshTooltip,
            icon: const Icon(Icons.refresh_rounded),
          ),
      ],
    );
  }
}

class _UsageAccountCard extends StatelessWidget {
  const _UsageAccountCard({required this.account});

  final AccountProfile account;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final statusIcon = !account.enabled
        ? Icons.pause_circle_outline_rounded
        : account.isCoolingDown
        ? Icons.schedule_rounded
        : Icons.check_circle_rounded;
    final statusLabel = !account.enabled
        ? l10n.accountUsageStatusDisabled
        : account.isCoolingDown
        ? l10n.accountUsageStatusCoolingDown
        : l10n.accountUsageStatusHealthy;
    final statusTint = !account.enabled
        ? scheme.onSurfaceVariant
        : account.isCoolingDown
        ? scheme.error
        : scheme.primary;

    return KickPanel(
      tone: KickPanelTone.soft,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KickBadge(
                label: l10n.accountUsageProviderLabel,
                leading: const Icon(Icons.auto_awesome_rounded),
                emphasis: true,
              ),
              const Spacer(),
              _StatusBadge(icon: statusIcon, label: statusLabel, tint: statusTint),
            ],
          ),
          const SizedBox(height: 16),
          Text(account.label, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            account.email,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              KickBadge(
                label: l10n.projectIdChip(account.projectId),
                leading: const Icon(Icons.badge_outlined),
              ),
              KickBadge(
                label: l10n.priorityChip(accountPriorityLabel(l10n, account.priority)),
                leading: const Icon(Icons.low_priority_rounded),
              ),
            ],
          ),
          if (account.lastQuotaSnapshot?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 14),
            Text(
              account.lastQuotaSnapshot!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _UsageContent extends StatelessWidget {
  const _UsageContent({required this.usage});

  final GeminiUsageSnapshot usage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (usage.buckets.isEmpty) {
      return EmptyStateCard(
        icon: Icons.query_stats_rounded,
        title: l10n.accountUsageEmptyTitle,
        message: l10n.accountUsageEmptyMessage,
      );
    }

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final spacing = 12.0;
            final cardWidth = constraints.maxWidth >= 760
                ? (constraints.maxWidth - spacing) / 2
                : constraints.maxWidth;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: usage.buckets
                  .map(
                    (bucket) => SizedBox(
                      width: cardWidth,
                      child: _UsageBucketCard(bucket: bucket),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
      ],
    );
  }
}

class _UsageBucketCard extends StatelessWidget {
  const _UsageBucketCard({required this.bucket});

  final GeminiUsageBucket bucket;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final used = bucket.usedPercent;

    return KickPanel(
      tone: KickPanelTone.soft,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(bucket.modelId, style: Theme.of(context).textTheme.titleMedium)),
              const SizedBox(width: 12),
              Text(
                '${_formatUsageValue(used)} / 100.00',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _UsageProgressBar(value: used),
          const SizedBox(height: 12),
          Text(
            bucket.resetAt == null
                ? l10n.accountUsageResetUnknown
                : l10n.accountUsageResetsAt(_formatDateTime(l10n, bucket.resetAt!)),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _UsageProgressBar extends StatelessWidget {
  const _UsageProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final normalized = value.clamp(0, 100) / 100;
    final tint = switch (value) {
      >= 90 => scheme.error,
      >= 70 => scheme.tertiary,
      _ => scheme.secondary,
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 8,
        color: scheme.surfaceContainerHighest,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: normalized,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [tint.withValues(alpha: 0.92), tint.withValues(alpha: 0.72)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UsageLoadingState extends StatelessWidget {
  const _UsageLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _UsageErrorCard extends StatelessWidget {
  const _UsageErrorCard({required this.message, required this.onRetry, this.onOpenVerification});

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onOpenVerification;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return EmptyStateCard(
      icon: Icons.error_outline_rounded,
      title: l10n.accountUsageLoadErrorTitle,
      message: message,
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (onOpenVerification != null)
            FilledButton.icon(
              onPressed: onOpenVerification,
              icon: const Icon(Icons.verified_user_rounded),
              label: Text(l10n.accountUsageVerifyAccountButton),
            ),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.accountUsageRetryButton),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.icon, required this.label, required this.tint});

  final IconData icon;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(tint.withValues(alpha: 0.14), scheme.surfaceContainerLow),
        borderRadius: BorderRadius.circular(context.kickTokens.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tint),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: tint)),
        ],
      ),
    );
  }
}

String _formatUsageValue(double value) => value.toStringAsFixed(2);

String _formatDateTime(KickLocalizations l10n, DateTime value) {
  return DateFormat('dd/MM/yyyy, HH:mm', l10n.localeName).format(value);
}

VoidCallback? _verificationActionForError(BuildContext context, Object error) {
  final actionUrl = accountVerificationUrlForError(error);
  if (actionUrl == null) {
    return null;
  }

  return () => unawaited(_openAccountVerificationUrl(context, actionUrl));
}

Future<void> _openAccountVerificationUrl(BuildContext context, String actionUrl) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failureMessage = context.l10n.accountUsageVerificationOpenFailedMessage;
  final uri = Uri.tryParse(actionUrl);
  if (uri == null) {
    _showVerificationOpenFailedMessage(messenger, failureMessage);
    return;
  }

  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _showVerificationOpenFailedMessage(messenger, failureMessage);
    }
  } catch (_) {
    _showVerificationOpenFailedMessage(messenger, failureMessage);
  }
}

void _showVerificationOpenFailedMessage(
  ScaffoldMessengerState? messenger,
  String failureMessage,
) {
  if (messenger == null) {
    return;
  }

  messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
}
