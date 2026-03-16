import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_metadata.dart';
import '../../core/errors/user_facing_error_formatter.dart';
import '../../core/theme/kick_theme.dart';
import '../../l10n/kick_localizations.dart';
import '../app_state/providers.dart';
import '../shared/kick_surfaces.dart';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settingsValue = ref.watch(settingsControllerProvider);

    return settingsValue.when(
      data: (settings) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AboutHeader(title: l10n.aboutTitle),
            const SizedBox(height: 24),
            _AboutHeroCard(
              appTitle: l10n.appTitle,
              versionLabel: kickAppVersion,
              description: l10n.aboutDescription,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showUpdateUnavailableMessage(context, l10n),
                icon: const Icon(Icons.system_update_rounded),
                label: Text(l10n.aboutCheckUpdatesButton),
              ),
            ),
            const SizedBox(height: 14),
            _AboutSettingToggle(
              title: l10n.aboutAutoCheckUpdatesTitle,
              subtitle: l10n.aboutAutoCheckUpdatesSubtitle,
              value: settings.autoCheckUpdatesEnabled,
              onChanged: (value) async {
                await ref
                    .read(settingsControllerProvider.notifier)
                    .save(settings.copyWith(autoCheckUpdatesEnabled: value));
              },
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
        icon: Icons.error_outline_rounded,
        title: l10n.settingsLoadErrorTitle,
        message: formatUserFacingError(l10n, error),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }

  void _showUpdateUnavailableMessage(BuildContext context, KickLocalizations l10n) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(l10n.aboutCheckUpdatesUnavailableMessage)));
  }
}

class _AboutHeader extends StatelessWidget {
  const _AboutHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back_rounded)),
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
                      leading: const Icon(Icons.sell_rounded),
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
