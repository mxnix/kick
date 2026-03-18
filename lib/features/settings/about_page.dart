import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_metadata.dart';
import '../../core/errors/user_facing_error_formatter.dart';
import '../../core/theme/kick_theme.dart';
import '../../l10n/kick_localizations.dart';
import '../app_state/providers.dart';
import '../shared/app_update_banner.dart';
import '../shared/kick_surfaces.dart';
import 'app_update_checker.dart';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settingsValue = ref.watch(settingsControllerProvider);
    final appVersionValue = ref.watch(appVersionProvider);
    final updateValue = ref.watch(appUpdateQueryProvider);
    final versionLabel = appVersionValue.maybeWhen(
      data: (version) => version,
      orElse: () => kickBuildAppVersion,
    );

    return settingsValue.when(
      data: (settings) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AboutHeader(title: l10n.aboutTitle),
            const SizedBox(height: 24),
            _AboutHeroCard(
              appTitle: l10n.appTitle,
              versionLabel: versionLabel,
              description: l10n.aboutDescription,
            ),
            const SizedBox(height: 14),
            _AboutUpdatesCard(
              updateValue: updateValue,
              onRetry: () => ref.invalidate(appUpdateQueryProvider),
            ),
            const SizedBox(height: 14),
            _AboutSettingToggle(
              title: l10n.aboutAnalyticsTitle,
              subtitle: l10n.aboutAnalyticsSubtitle,
              value: settings.analyticsConsentEnabled,
              onChanged: (value) async {
                await ref
                    .read(settingsControllerProvider.notifier)
                    .save(settings.copyWith(analyticsConsentEnabled: value));
              },
            ),
          ],
        ),
      ),
      error: (error, stackTrace) => EmptyStateCard(
        icon: Icons.error_rounded,
        title: l10n.settingsLoadErrorTitle,
        message: formatUserFacingError(l10n, error),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _AboutUpdatesCard extends StatelessWidget {
  const _AboutUpdatesCard({required this.updateValue, required this.onRetry});

  final AsyncValue<AppUpdateInfo> updateValue;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return updateValue.when(
      data: (updateInfo) {
        if (updateInfo.hasUpdate) {
          return AppUpdateBanner(updateInfo: updateInfo);
        }

        return _AboutActionCard(
          icon: Icons.verified_rounded,
          title: l10n.aboutUpToDateTitle,
          message: l10n.aboutUpToDateMessage(updateInfo.currentVersion),
          actionLabel: l10n.aboutRetryUpdateCheckButton,
          onPressed: onRetry,
        );
      },
      error: (error, stackTrace) => _AboutActionCard(
        icon: Icons.cloud_off_rounded,
        title: l10n.aboutUpdateCheckFailedTitle,
        message: l10n.aboutUpdateCheckFailedMessage,
        actionLabel: l10n.aboutRetryUpdateCheckButton,
        onPressed: onRetry,
      ),
      loading: () => _AboutActionCard(
        icon: Icons.sync_rounded,
        title: l10n.aboutUpdatesTitle,
        message: l10n.aboutUpdatesChecking,
        actionLabel: l10n.loadingValue,
      ),
    );
  }
}

class _AboutActionCard extends StatelessWidget {
  const _AboutActionCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = scheme.onSurfaceVariant;

    return KickPanel(
      tone: KickPanelTone.soft,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: tint),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(onPressed == null ? Icons.hourglass_top_rounded : Icons.refresh_rounded),
              label: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutHeader extends StatelessWidget {
  const _AboutHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: () => context.pop(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
      ],
    );
  }
}

class _AboutHeroCard extends StatelessWidget {
  const _AboutHeroCard({
    required this.appTitle,
    required this.versionLabel,
    required this.description,
  });

  final String appTitle;
  final String versionLabel;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return KickPanel(
      tone: KickPanelTone.accent,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: scheme.surfaceContainerHigh,
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(kickAppIconAssetPath, fit: BoxFit.cover),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appTitle, style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    KickBadge(
                      label: versionLabel,
                      leading: const Icon(Icons.new_releases_rounded),
                      emphasis: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _AboutSettingToggle extends StatelessWidget {
  const _AboutSettingToggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(context.kickTokens.panelRadius),
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.84),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
