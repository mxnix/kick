import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_metadata.dart';
import '../../l10n/kick_localizations.dart';
import '../app_state/providers.dart';

class FirstRunDisclaimerGate extends ConsumerStatefulWidget {
  const FirstRunDisclaimerGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<FirstRunDisclaimerGate> createState() => _FirstRunDisclaimerGateState();
}

class _FirstRunDisclaimerGateState extends ConsumerState<FirstRunDisclaimerGate> {
  bool _dialogQueued = false;
  bool _dialogInProgress = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider).asData?.value;
    if (settings != null &&
        !settings.hasAcknowledgedDisclaimer &&
        !_dialogQueued &&
        !_dialogInProgress) {
      _dialogQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _dialogQueued = false;
        _showDisclaimerIfNeeded();
      });
    }

    return widget.child;
  }

  Future<void> _showDisclaimerIfNeeded() async {
    if (!mounted || _dialogInProgress) {
      return;
    }

    final settings = ref.read(settingsControllerProvider).asData?.value;
    if (settings == null || settings.hasAcknowledgedDisclaimer) {
      return;
    }

    _dialogInProgress = true;
    try {
      final analyticsConsent = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return _FirstRunDisclaimerDialog(
            initialAnalyticsConsent: settings.analyticsConsentEnabled,
          );
        },
      );

      if (!mounted) {
        return;
      }

      final currentSettings = ref.read(settingsControllerProvider).asData?.value ?? settings;
      await ref
          .read(settingsControllerProvider.notifier)
          .save(
            currentSettings.copyWith(
              hasAcknowledgedDisclaimer: true,
              analyticsConsentEnabled: analyticsConsent ?? currentSettings.analyticsConsentEnabled,
            ),
          );
      if (analyticsConsent == true) {
        unawaited(ref.read(analyticsProvider).trackDisclaimerAccepted(analyticsEnabled: true));
      }
    } finally {
      _dialogInProgress = false;
    }
  }
}

class _FirstRunDisclaimerDialog extends StatefulWidget {
  const _FirstRunDisclaimerDialog({required this.initialAnalyticsConsent});

  final bool initialAnalyticsConsent;

  @override
  State<_FirstRunDisclaimerDialog> createState() => _FirstRunDisclaimerDialogState();
}

class _FirstRunDisclaimerDialogState extends State<_FirstRunDisclaimerDialog> {
  late bool _analyticsConsentEnabled = widget.initialAnalyticsConsent;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        icon: const Icon(Icons.waving_hand_rounded),
        title: Text(l10n.welcomeTitle),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.welcomeSubtitle,
                style: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              const _WelcomeStepTile(
                icon: Icons.person_add_alt_1_rounded,
                titleKey: _WelcomeStepTitle.accounts,
                messageKey: _WelcomeStepMessage.accounts,
              ),
              const SizedBox(height: 10),
              const _WelcomeStepTile(
                icon: Icons.home_rounded,
                titleKey: _WelcomeStepTitle.home,
                messageKey: _WelcomeStepMessage.home,
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.34)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.welcomeUsageTitle, style: textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      l10n.welcomeUsageMessage,
                      style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _openRepositoryLink,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(l10n.welcomeRepositoryLinkLabel),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.34)),
                ),
                child: CheckboxListTile(
                  value: _analyticsConsentEnabled,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  visualDensity: VisualDensity.compact,
                  title: Text(l10n.welcomeAnalyticsTitle),
                  subtitle: Text(l10n.welcomeAnalyticsSubtitle),
                  onChanged: (value) {
                    setState(() {
                      _analyticsConsentEnabled = value ?? false;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(_analyticsConsentEnabled);
            },
            child: Text(l10n.continueButton),
          ),
        ],
      ),
    );
  }

  Future<void> _openRepositoryLink() async {
    await launchUrl(Uri.parse(kickRepositoryUrl), mode: LaunchMode.externalApplication);
  }
}

enum _WelcomeStepTitle { accounts, home }

enum _WelcomeStepMessage { accounts, home }

class _WelcomeStepTile extends StatelessWidget {
  const _WelcomeStepTile({required this.icon, required this.titleKey, required this.messageKey});

  final IconData icon;
  final _WelcomeStepTitle titleKey;
  final _WelcomeStepMessage messageKey;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final title = switch (titleKey) {
      _WelcomeStepTitle.accounts => l10n.welcomeStepAccountsTitle,
      _WelcomeStepTitle.home => l10n.welcomeStepHomeTitle,
    };
    final message = switch (messageKey) {
      _WelcomeStepMessage.accounts => l10n.welcomeStepAccountsMessage,
      _WelcomeStepMessage.home => l10n.welcomeStepHomeMessage,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.34)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
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
