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
        unawaited(
          ref.read(analyticsProvider).trackDisclaimerAccepted(analyticsEnabled: true),
        );
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

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(l10n.disclaimerTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.disclaimerBodyLineOne, style: textTheme.bodyLarge),
              const SizedBox(height: 8),
              Text(l10n.disclaimerBodyLineTwo, style: textTheme.bodyLarge),
              const SizedBox(height: 12),
              InkWell(
                onTap: _openRepositoryLink,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    l10n.disclaimerLinkPrefix,
                    style: textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              CheckboxListTile(
                value: _analyticsConsentEnabled,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l10n.disclaimerAnalyticsConsentLabel),
                onChanged: (value) {
                  setState(() {
                    _analyticsConsentEnabled = value ?? false;
                  });
                },
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
