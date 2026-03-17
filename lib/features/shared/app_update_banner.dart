import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/kick_localizations.dart';
import '../settings/app_update_checker.dart';
import 'kick_surfaces.dart';

class AppUpdateBanner extends StatelessWidget {
  const AppUpdateBanner({super.key, required this.updateInfo});

  final AppUpdateInfo updateInfo;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return KickPanel(
      tone: KickPanelTone.accent,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.system_update_rounded, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.aboutUpdateAvailableTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l10n.aboutUpdateAvailableMessage(updateInfo.latestVersion, updateInfo.currentVersion),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _openExternalUrl(updateInfo.releaseUrl),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(l10n.aboutOpenReleaseButton),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
