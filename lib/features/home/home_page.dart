import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/user_facing_error_formatter.dart';
import '../../core/theme/kick_icons.dart';
import '../../data/models/app_settings.dart';
import '../../l10n/kick_localizations.dart';
import '../app_shell/app_shell.dart';
import '../app_state/providers.dart';
import '../shared/app_update_banner.dart';
import '../shared/kick_actions.dart';
import '../shared/kick_scroll.dart';
import '../shared/kick_surfaces.dart';
import 'silly_tavern_push_service.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _pushingSillyTavern = false;

  @override
  Widget build(BuildContext context) {
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
        ? (totalAccounts == 0 ? KickIcons.addAccount : KickIcons.accounts)
        : (proxyStatus.running ? KickIcons.pause : KickIcons.play);
    final secondaryCards = <Widget>[
      if (showAccountSetup) _HomeOnboardingCard(proxyEndpoint: proxyEndpoint),
      if (updateInfo?.hasUpdate == true) AppUpdateBanner(updateInfo: updateInfo!),
      if (proxyStatus.lastError != null)
        EmptyStateCard(
          icon: KickIcons.error,
          title: l10n.lastErrorTitle,
          message: formatUserFacingMessage(l10n, proxyStatus.lastError!),
          action: KickSecondaryAction(
            label: l10n.openLogsButton,
            icon: KickIcons.logs,
            variant: KickSecondaryActionVariant.text,
            onPressed: () => context.go('/logs'),
          ),
        ),
    ];

    return KickSmoothSingleChildScrollView(
      padding: EdgeInsets.only(bottom: AppShell.floatingNavigationClearanceOf(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(title: l10n.homeTitle),
          const SizedBox(height: 28),
          _HomeDashboardLayout(
            hero: _ProxyStatusHero(
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
              pushSillyTavernBusy: _pushingSillyTavern,
              onPushSillyTavern: settings == null
                  ? null
                  : () => _pushToSillyTavern(
                      context,
                      settings: settings,
                      proxyEndpoint: proxyEndpoint,
                    ),
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
            secondaryCards: secondaryCards,
          ),
        ],
      ),
    );
  }

  Future<void> _pushToSillyTavern(
    BuildContext context, {
    required AppSettings settings,
    required String proxyEndpoint,
  }) async {
    if (_pushingSillyTavern) {
      return;
    }

    final draft = await _showSillyTavernPushDialog(context, settings);
    if (!mounted || !context.mounted || draft == null) {
      return;
    }

    setState(() => _pushingSillyTavern = true);
    try {
      final result = await ref
          .read(sillyTavernPushServiceProvider)
          .pushProfile(
            sillyTavernUrl: draft.sillyTavernUrl,
            proxyEndpoint: proxyEndpoint,
            apiKey: settings.apiKeyRequired ? settings.apiKey : '',
            profileName: draft.profileName,
            model: draft.model,
          );
      if (!mounted || !context.mounted) {
        return;
      }
      _showSnackBar(context, context.l10n.pushSillyTavernSuccessMessage(result.profileName));
    } catch (error) {
      if (!mounted || !context.mounted) {
        return;
      }
      final message = _formatSillyTavernPushError(context.l10n, error);
      _showSnackBar(context, context.l10n.pushSillyTavernFailedMessage(message));
    } finally {
      if (mounted) {
        setState(() => _pushingSillyTavern = false);
      }
    }
  }
}

class _HomeDashboardLayout extends StatelessWidget {
  const _HomeDashboardLayout({required this.hero, required this.secondaryCards});

  final Widget hero;
  final List<Widget> secondaryCards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useWideLayout = constraints.maxWidth >= 1040 && secondaryCards.isNotEmpty;
        final secondaryColumn = _HomeSecondaryColumn(cards: secondaryCards);

        if (!useWideLayout) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              hero,
              if (secondaryCards.isNotEmpty) ...[const SizedBox(height: 20), secondaryColumn],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 7, child: hero),
            const SizedBox(width: 20),
            Expanded(flex: 5, child: secondaryColumn),
          ],
        );
      },
    );
  }
}

class _HomeSecondaryColumn extends StatelessWidget {
  const _HomeSecondaryColumn({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in cards.indexed) ...[
          if (entry.$1 > 0) const SizedBox(height: 14),
          entry.$2,
        ],
      ],
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
    required this.pushSillyTavernBusy,
    required this.onPushSillyTavern,
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
  final bool pushSillyTavernBusy;
  final VoidCallback? onPushSillyTavern;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stretchInlineStatus = constraints.maxWidth < 520;

        return KickPanel(
          tone: KickPanelTone.soft,
          radius: 32,
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showInlineStatus)
                stretchInlineStatus
                    ? _StatusPill(running: running, fullWidth: true)
                    : Align(
                        alignment: Alignment.centerRight,
                        child: _StatusPill(running: running),
                      ),
              if (showInlineStatus) const SizedBox(height: 14),
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
              _HomeMetricsGrid(
                activeAccountsText: activeAccountsText,
                uptimeText: uptimeText,
                uptimeTitle: l10n.uptimeTitle,
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _SillyTavernActionButton(
                    tooltip: l10n.pushSillyTavernButton,
                    busy: pushSillyTavernBusy,
                    onPressed: onPushSillyTavern,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: KickPrimaryAction(
                      label: primaryActionLabel,
                      icon: primaryActionIcon,
                      fullWidth: true,
                      busy: startPending,
                      onPressed: onPrimaryAction,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

const _sillyTavernLogoAssetPath = 'assets/st/logo.png';

class _SillyTavernActionButton extends StatelessWidget {
  const _SillyTavernActionButton({
    required this.tooltip,
    required this.busy,
    required this.onPressed,
  });

  final String tooltip;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = Material(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: busy ? null : onPressed,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Center(
            child: busy
                ? const KickLoadingIndicator(size: 22, contained: false)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.asset(
                      _sillyTavernLogoAssetPath,
                      width: 24,
                      height: 24,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, _, _) => const Icon(KickIcons.link, size: 24),
                    ),
                  ),
          ),
        ),
      ),
    );

    return Tooltip(message: tooltip, child: button);
  }
}

class _HomeMetricsGrid extends StatelessWidget {
  const _HomeMetricsGrid({
    required this.activeAccountsText,
    required this.uptimeText,
    required this.uptimeTitle,
  });

  final String activeAccountsText;
  final String uptimeText;
  final String uptimeTitle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final activeLabel = _splitLabelValue(activeAccountsText, fallbackLabel: l10n.navAccounts);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _HomeMetricInline(
              icon: KickIcons.accounts,
              label: activeLabel.$1,
              value: activeLabel.$2,
            ),
          ),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: scheme.outlineVariant.withValues(alpha: 0.32),
          ),
          Expanded(
            child: _HomeMetricInline(
              icon: KickIcons.schedule,
              label: uptimeTitle,
              value: uptimeText,
            ),
          ),
        ],
      ),
    );
  }

  (String, String) _splitLabelValue(String combined, {required String fallbackLabel}) {
    final colon = combined.lastIndexOf(':');
    if (colon <= 0 || colon == combined.length - 1) {
      return (fallbackLabel, combined.trim());
    }
    final label = combined.substring(0, colon).trim();
    final value = combined.substring(colon + 1).trim();
    return (label.isEmpty ? fallbackLabel : label, value);
  }
}

class _HomeMetricInline extends StatelessWidget {
  const _HomeMetricInline({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SillyTavernPushDraft {
  const _SillyTavernPushDraft({
    required this.sillyTavernUrl,
    required this.profileName,
    required this.model,
  });

  final String sillyTavernUrl;
  final String profileName;
  final String model;
}

Future<_SillyTavernPushDraft?> _showSillyTavernPushDialog(
  BuildContext context,
  AppSettings settings,
) {
  return showDialog<_SillyTavernPushDraft>(
    context: context,
    builder: (context) => _SillyTavernPushDialog(settings: settings),
  );
}

class _SillyTavernPushDialog extends StatefulWidget {
  const _SillyTavernPushDialog({required this.settings});

  final AppSettings settings;

  @override
  State<_SillyTavernPushDialog> createState() => _SillyTavernPushDialogState();
}

class _SillyTavernPushDialogState extends State<_SillyTavernPushDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _profileNameController;
  late final TextEditingController _modelController;
  bool _profileNameInitialized = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: 'http://127.0.0.1:8000');
    _profileNameController = TextEditingController();
    _modelController = TextEditingController(text: _defaultSillyTavernModel(widget.settings));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_profileNameInitialized) {
      return;
    }
    _profileNameInitialized = true;
    _profileNameController.text = context.l10n.appTitle;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _profileNameController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          _sillyTavernLogoAssetPath,
          width: 34,
          height: 34,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, _, _) => const Icon(KickIcons.link),
        ),
      ),
      title: Text(l10n.pushSillyTavernDialogTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.pushSillyTavernDialogMessage,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: l10n.pushSillyTavernUrlLabel,
                hintText: 'http://127.0.0.1:8000',
                prefixIcon: const Icon(KickIcons.link),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _profileNameController,
              decoration: InputDecoration(
                labelText: l10n.pushSillyTavernProfileNameLabel,
                prefixIcon: const Icon(KickIcons.label),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelController,
              decoration: InputDecoration(
                labelText: l10n.pushSillyTavernModelLabel,
                prefixIcon: const Icon(KickIcons.hub),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancelButton)),
        FilledButton(
          onPressed: () {
            final url = _urlController.text.trim();
            final name = _profileNameController.text.trim();
            final model = _modelController.text.trim();
            if (url.isEmpty || name.isEmpty || model.isEmpty) {
              return;
            }
            Navigator.of(
              context,
            ).pop(_SillyTavernPushDraft(sillyTavernUrl: url, profileName: name, model: model));
          },
          child: Text(l10n.pushSillyTavernConfirmButton),
        ),
      ],
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
            icon: KickIcons.addAccount,
          ),
          const SizedBox(height: 12),
          _OnboardingStep(
            number: 2,
            title: l10n.homeOnboardingEndpointTitle,
            message: l10n.homeOnboardingEndpointMessage(proxyEndpoint),
            icon: KickIcons.link,
          ),
          const SizedBox(height: 12),
          _OnboardingStep(
            number: 3,
            title: l10n.homeOnboardingStartTitle,
            message: l10n.homeOnboardingStartMessage,
            icon: KickIcons.rocket,
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
  const _StatusPill({required this.running, this.fullWidth = false});

  final bool running;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = running ? scheme.primary : scheme.outline;
    return Container(
      width: fullWidth ? double.infinity : null,
      alignment: fullWidth ? Alignment.center : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(tone.withValues(alpha: 0.12), scheme.surfaceContainerHigh),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(running ? KickIcons.play : KickIcons.pause, size: 16, color: tone),
          const SizedBox(width: 6),
          Text(
            running ? context.l10n.proxyRunningStatus : context.l10n.proxyStoppedStatus,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
              if (onCopy != null) ...[
                const SizedBox(width: 8),
                KickIconAction(onPressed: onCopy, tooltip: tooltip, icon: KickIcons.copy),
              ],
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
  final displayHost = _buildClientFacingHost(host: host, allowLan: allowLan);
  return Uri(scheme: 'http', host: displayHost, port: port, path: '/v1').toString();
}

String _buildClientFacingHost({required String host, required bool allowLan}) {
  final trimmedHost = host.trim();
  final normalizedHost = trimmedHost.toLowerCase();

  if (allowLan || normalizedHost == '0.0.0.0') {
    return 'localhost';
  }

  if (_isLoopbackHost(normalizedHost)) {
    return 'localhost';
  }

  return trimmedHost;
}

bool _isLoopbackHost(String host) {
  return host == 'localhost' ||
      host == '::1' ||
      host == '[::1]' ||
      host == '0:0:0:0:0:0:0:1' ||
      host.startsWith('127.');
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

String _defaultSillyTavernModel(AppSettings settings) {
  for (final model in settings.customModels) {
    final trimmed = model.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return 'google/gemini-2.5-pro';
}

String _formatSillyTavernPushError(KickLocalizations l10n, Object error) {
  if (error is SillyTavernPushException) {
    return switch (error.failure) {
      SillyTavernPushFailure.invalidUrl => l10n.pushSillyTavernErrorInvalidUrl,
      SillyTavernPushFailure.missingCsrfToken => l10n.pushSillyTavernErrorMissingCsrf,
      SillyTavernPushFailure.httpError => l10n.pushSillyTavernErrorHttp(
        error.statusCode ?? 0,
        error.path ?? '/api',
      ),
      SillyTavernPushFailure.invalidJson => l10n.pushSillyTavernErrorInvalidJson,
    };
  }
  return error.toString();
}
