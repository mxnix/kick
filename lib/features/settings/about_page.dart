import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:m3e_collection/m3e_collection.dart' as m3e;
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_metadata.dart';
import '../../core/errors/user_facing_error_formatter.dart';
import '../../core/theme/kick_icons.dart';
import '../../l10n/kick_localizations.dart';
import '../app_shell/app_shell.dart';
import '../app_state/providers.dart';
import '../shared/app_update_banner.dart';
import '../shared/kick_actions.dart';
import '../shared/kick_scroll.dart';
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
      data: (settings) => KickSmoothSingleChildScrollView(
        padding: EdgeInsets.only(bottom: AppShell.floatingNavigationClearanceOf(context)),
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
            _AboutAnalyticsCard(
              title: l10n.aboutAnalyticsTitle,
              subtitle: l10n.aboutAnalyticsSubtitle,
              value: settings.analyticsConsentEnabled,
              onChanged: (value) async {
                await ref
                    .read(settingsControllerProvider.notifier)
                    .save(settings.copyWith(analyticsConsentEnabled: value));
              },
            ),
            const SizedBox(height: 14),
            _AboutInfoList(
              cards: [
                _AboutInfoCardData(
                  icon: KickIcons.verifiedUser,
                  title: l10n.aboutLicenseTitle,
                  message: l10n.aboutLicenseMessage,
                  actionLabel: l10n.aboutOpenLicenseButton,
                  url: 'https://github.com/mxnix/kick/blob/main/LICENSE.md',
                ),
                _AboutInfoCardData(
                  icon: KickIcons.security,
                  title: l10n.aboutPrivacyTitle,
                  message: l10n.aboutPrivacyMessage,
                  actionLabel: l10n.aboutOpenPrivacyButton,
                  url: 'https://github.com/mxnix/kick/blob/main/docs/PRIVACY.md',
                ),
                _AboutInfoCardData(
                  icon: KickIcons.warning,
                  title: l10n.aboutDisclaimerTitle,
                  message: l10n.aboutDisclaimerMessage,
                ),
                _AboutInfoCardData(
                  icon: KickIcons.info,
                  title: l10n.aboutCreditsTitle,
                  message: l10n.aboutCreditsMessage,
                ),
              ],
            ),
          ],
        ),
      ),
      error: (error, stackTrace) => EmptyStateCard(
        icon: KickIcons.error,
        title: l10n.settingsLoadErrorTitle,
        message: formatUserFacingError(l10n, error),
      ),
      loading: () => const Center(child: KickLoadingIndicator()),
    );
  }
}

class _AboutAnalyticsCard extends StatelessWidget {
  const _AboutAnalyticsCard({
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
    return KickPanel(
      tone: KickPanelTone.soft,
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
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

class _AboutInfoList extends StatelessWidget {
  const _AboutInfoList({required this.cards});

  final List<_AboutInfoCardData> cards;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return KickPanel(
      tone: KickPanelTone.soft,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in cards.indexed) ...[
            if (entry.$1 > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.32),
                indent: 20,
                endIndent: 20,
              ),
            _AboutInfoRow(data: entry.$2),
          ],
        ],
      ),
    );
  }
}

class _AboutInfoRow extends StatelessWidget {
  const _AboutInfoRow({required this.data});

  final _AboutInfoCardData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(data.icon, color: scheme.onSurfaceVariant, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.title, style: textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  data.message,
                  style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (data.url != null && data.actionLabel != null) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: data.actionLabel!,
              child: IconButton(
                onPressed: () => unawaited(_openAboutLink(context, data.url!)),
                icon: const Icon(KickIcons.openInNew),
                color: scheme.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AboutInfoCardData {
  const _AboutInfoCardData({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.url,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final String? url;
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
          icon: KickIcons.verified,
          title: l10n.aboutUpToDateTitle,
          message: l10n.aboutUpToDateMessage(updateInfo.currentVersion),
          actionLabel: l10n.aboutRetryUpdateCheckButton,
          onPressed: onRetry,
        );
      },
      error: (error, stackTrace) => _AboutActionCard(
        icon: KickIcons.cloudOff,
        title: l10n.aboutUpdateCheckFailedTitle,
        message: l10n.aboutUpdateCheckFailedMessage,
        actionLabel: l10n.aboutRetryUpdateCheckButton,
        onPressed: onRetry,
      ),
      loading: () => _AboutActionCard(
        icon: KickIcons.sync,
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
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: tint),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              KickSecondaryAction(
                onPressed: onPressed,
                icon: onPressed == null ? KickIcons.hourglass : KickIcons.refresh,
                label: actionLabel,
                variant: KickSecondaryActionVariant.text,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
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
        KickIconAction(
          onPressed: () => context.pop(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: KickIcons.back,
          variant: m3e.IconButtonM3EVariant.tonal,
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
    final textTheme = Theme.of(context).textTheme;

    return KickPanel(
      tone: KickPanelTone.accent,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: scheme.surfaceContainerHigh,
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(kickAppIconAssetPath, fit: BoxFit.cover),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appTitle, style: textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      'v$versionLabel',
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(description, style: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

Future<void> _openAboutLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failureMessage = context.l10n.aboutOpenLinkFailedMessage;
  final uri = Uri.tryParse(url);
  if (uri == null) {
    _showAboutLinkOpenFailedMessage(messenger, failureMessage);
    return;
  }
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      _showAboutLinkOpenFailedMessage(messenger, failureMessage);
    }
  } catch (_) {
    if (context.mounted) {
      _showAboutLinkOpenFailedMessage(messenger, failureMessage);
    }
  }
}

void _showAboutLinkOpenFailedMessage(ScaffoldMessengerState? messenger, String failureMessage) {
  if (messenger == null) {
    return;
  }
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
}
