import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/user_facing_error_formatter.dart';
import '../../l10n/kick_localizations.dart';
import '../app_state/providers.dart';
import '../shared/app_update_banner.dart';
import '../shared/kick_surfaces.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    ref.watch(clockTickerProvider);

    final proxyStatus =
        ref.watch(proxyStatusProvider).asData?.value ??
        ref.watch(proxyControllerProvider).currentState;
    final settings = ref.watch(settingsControllerProvider).asData?.value;
    final accounts = ref.watch(accountsControllerProvider).asData?.value;
    final updateInfo = ref.watch(appUpdateQueryProvider).asData?.value;

    final totalAccounts = accounts?.length ?? 0;
    final activeAccounts = accounts?.where((item) => item.enabled).length ?? 0;
    final showAccountSetup = !proxyStatus.running && accounts != null && activeAccounts == 0;
    final uptimeText = proxyStatus.uptime == null
        ? l10n.uptimeNotStarted
        : l10n.uptimeValue(
            proxyStatus.uptime!.inHours,
            proxyStatus.uptime!.inMinutes % 60,
            proxyStatus.uptime!.inSeconds % 60,
          );
    final proxyEndpoint = _buildProxyEndpoint(
      host: settings?.host ?? proxyStatus.boundHost,
      port: settings?.port ?? proxyStatus.port,
      allowLan: settings?.allowLan ?? false,
    );
    final apiKeyValue = settings == null
        ? l10n.loadingValue
        : settings.apiKeyRequired
        ? _maskSecret(settings.apiKey)
        : l10n.apiKeyDisabledValue;
    final primaryActionLabel = showAccountSetup
        ? (totalAccounts == 0 ? l10n.connectAccountShortButton : l10n.openAccountsButton)
        : (proxyStatus.running ? l10n.stopProxyButton : l10n.startProxyButton);
    final primaryActionIcon = showAccountSetup
        ? (totalAccounts == 0 ? Icons.person_add_alt_1_rounded : Icons.groups_2_rounded)
        : (proxyStatus.running ? Icons.pause_rounded : Icons.play_arrow_rounded);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(title: l10n.homeTitle),
          const SizedBox(height: 28),
          _ProxyStatusHero(
            running: proxyStatus.running,
            startPending: proxyStatus.startPending,
            showInlineStatus: _showInlineStatusForCurrentPlatform(),
            proxyEndpoint: proxyEndpoint,
            apiKeyValue: apiKeyValue,
            activeAccountsText: l10n.activeAccounts(activeAccounts),
            uptimeText: uptimeText,
            copyProxyEndpointTooltip: l10n.copyProxyEndpointTooltip,
            copyApiKeyTooltip: l10n.copyApiKeyTooltip,
            onCopyProxyEndpoint: () =>
                _copyText(context, proxyEndpoint, l10n.proxyEndpointCopiedMessage),
            onCopyApiKey: settings == null || !settings.apiKeyRequired
                ? null
                : () => _copyText(context, settings.apiKey, l10n.apiKeyCopiedMessage),
            primaryActionLabel: primaryActionLabel,
            primaryActionIcon: primaryActionIcon,
            onPrimaryAction: () async {
              if (showAccountSetup) {
                context.go('/accounts');
                return;
              }

              if (proxyStatus.running) {
                await ref.read(proxyControllerProvider).stop();
              } else {
                if (accounts != null && activeAccounts == 0) {
                  _showSnackBar(context, l10n.noActiveAccountsWarning);
                }
                await ref.read(proxyControllerProvider).start();
              }
            },
          ),
          if (showAccountSetup) ...[
            const SizedBox(height: 20),
            _HomeOnboardingCard(proxyEndpoint: proxyEndpoint),
          ],
          if (updateInfo?.hasUpdate == true) ...[
            const SizedBox(height: 20),
            AppUpdateBanner(updateInfo: updateInfo!),
          ],
          if (proxyStatus.lastError != null) ...[
            const SizedBox(height: 20),
            EmptyStateCard(
              icon: Icons.error_rounded,
              title: l10n.lastErrorTitle,
              message: formatUserFacingMessage(l10n, proxyStatus.lastError!),
              action: TextButton(
                onPressed: () => context.go('/logs'),
                child: Text(l10n.openLogsButton),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProxyStatusHero extends StatelessWidget {
  const _ProxyStatusHero({
    required this.running,
    required this.startPending,
    required this.showInlineStatus,
    required this.proxyEndpoint,
    required this.apiKeyValue,
    required this.activeAccountsText,
    required this.uptimeText,
    required this.copyProxyEndpointTooltip,
    required this.copyApiKeyTooltip,
    required this.onCopyProxyEndpoint,
    required this.onCopyApiKey,
    required this.primaryActionLabel,
    required this.primaryActionIcon,
    required this.onPrimaryAction,
  });

  final bool running;
  final bool startPending;
  final bool showInlineStatus;
  final String proxyEndpoint;
  final String apiKeyValue;
  final String activeAccountsText;
  final String uptimeText;
  final String copyProxyEndpointTooltip;
  final String copyApiKeyTooltip;
  final VoidCallback onCopyProxyEndpoint;
  final VoidCallback? onCopyApiKey;
  final String primaryActionLabel;
  final IconData primaryActionIcon;
  final VoidCallback? onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return KickPanel(
      tone: KickPanelTone.soft,
      radius: 36,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KickBadge(
                label: l10n.embeddedProxyTitle,
                leading: const Icon(Icons.hub_rounded),
                emphasis: running,
              ),
              if (showInlineStatus) ...[const Spacer(), _StatusPill(running: running)],
            ],
          ),
          const SizedBox(height: 18),
          _QuickAccessTile(
            title: l10n.proxyEndpointTitle,
            value: proxyEndpoint,
            tooltip: copyProxyEndpointTooltip,
            onCopy: onCopyProxyEndpoint,
          ),
          const SizedBox(height: 12),
          _QuickAccessTile(
            title: l10n.apiKeyTitle,
            value: apiKeyValue,
            tooltip: copyApiKeyTooltip,
            onCopy: onCopyApiKey,
            footer: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.go('/settings?section=access'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(l10n.changeApiKeyLinkLabel),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              KickBadge(label: activeAccountsText, leading: const Icon(Icons.groups_2_rounded)),
              KickBadge(
                label: '${l10n.uptimeTitle}: $uptimeText',
                leading: const Icon(Icons.schedule_rounded),
                tint: scheme.secondary,
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: startPending ? null : onPrimaryAction,
              icon: startPending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(primaryActionIcon),
              label: Text(primaryActionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeOnboardingCard extends StatelessWidget {
  const _HomeOnboardingCard({required this.proxyEndpoint});

  final String proxyEndpoint;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return KickPanel(
      tone: KickPanelTone.accent,
      radius: 32,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.homeOnboardingTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            l10n.homeOnboardingSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          _OnboardingStep(
            number: 1,
            title: l10n.homeOnboardingAccountsTitle,
            message: l10n.homeOnboardingAccountsMessage,
            icon: Icons.person_add_alt_1_rounded,
          ),
          const SizedBox(height: 12),
          _OnboardingStep(
            number: 2,
            title: l10n.homeOnboardingEndpointTitle,
            message: l10n.homeOnboardingEndpointMessage(proxyEndpoint),
            icon: Icons.link_rounded,
          ),
          const SizedBox(height: 12),
          _OnboardingStep(
            number: 3,
            title: l10n.homeOnboardingStartTitle,
            message: l10n.homeOnboardingStartMessage,
            icon: Icons.rocket_launch_rounded,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.homeOnboardingFooter,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _OnboardingStep extends StatelessWidget {
  const _OnboardingStep({
    required this.number,
    required this.title,
    required this.message,
    required this.icon,
  });

  final int number;
  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.34)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                '$number',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.running});

  final bool running;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = running ? scheme.primary : scheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(tone.withValues(alpha: 0.12), scheme.surfaceContainerHigh),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(running ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 16, color: tone),
          const SizedBox(width: 6),
          Text(
            running ? context.l10n.proxyRunningStatus : context.l10n.proxyStoppedStatus,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: tone),
          ),
        ],
      ),
    );
  }
}

bool _showInlineStatusForCurrentPlatform() {
  if (kIsWeb) {
    return true;
  }
  return defaultTargetPlatform != TargetPlatform.windows;
}

class _QuickAccessTile extends StatelessWidget {
  const _QuickAccessTile({
    required this.title,
    required this.value,
    required this.tooltip,
    required this.onCopy,
    this.footer,
  });

  final String title;
  final String value;
  final String tooltip;
  final VoidCallback? onCopy;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(value, style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onCopy,
                tooltip: tooltip,
                icon: const Icon(Icons.content_copy_rounded, size: 20),
              ),
            ],
          ),
          if (footer != null) ...[const SizedBox(height: 6), footer!],
        ],
      ),
    );
  }
}

String _maskSecret(String value) {
  if (value.isEmpty) {
    return '—';
  }
  if (value.length <= 10) {
    return value;
  }
  return '${value.substring(0, 10)}...';
}

String _buildProxyEndpoint({required String host, required int port, required bool allowLan}) {
  final displayHost = (allowLan || host == '0.0.0.0') ? '127.0.0.1' : host;
  return Uri(scheme: 'http', host: displayHost, port: port, path: '/v1').toString();
}

Future<void> _copyText(BuildContext context, String value, String confirmationMessage) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) {
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(confirmationMessage)));
}

void _showSnackBar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
