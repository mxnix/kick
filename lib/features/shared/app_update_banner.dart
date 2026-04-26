import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/kick_localizations.dart';
import '../settings/app_update_checker.dart';
import '../settings/app_update_installer.dart';
import 'kick_surfaces.dart';

class AppUpdateBanner extends ConsumerWidget {
  const AppUpdateBanner({super.key, required this.updateInfo});

  final AppUpdateInfo updateInfo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final installerUrl = updateInfo.installerUrl?.trim();
    final hasInstallerUrl = installerUrl?.isNotEmpty == true;
    final hasInstallerFile = updateInfo.installerFileName?.trim().isNotEmpty == true;
    final supportsNativeInstaller = _supportsNativeInstaller();
    final hasNativeInstaller = hasInstallerUrl && hasInstallerFile && supportsNativeInstaller;
    final flowState = ref.watch(appUpdateControllerProvider);
    final effectiveState = flowState.matches(updateInfo) ? flowState : AppUpdateFlowState.idle;
    final statusMessage = _statusMessageForState(l10n, effectiveState);
    final primaryButtonLabel = _primaryButtonLabel(l10n, effectiveState);
    final primaryAction = hasNativeInstaller
        ? () {
            if (effectiveState.phase == AppUpdatePhase.readyToInstall ||
                effectiveState.phase == AppUpdatePhase.awaitingPermission) {
              return ref.read(appUpdateControllerProvider.notifier).install(updateInfo);
            }
            return ref.read(appUpdateControllerProvider.notifier).download(updateInfo);
          }
        : null;
    final isBusy =
        effectiveState.phase == AppUpdatePhase.downloading ||
        effectiveState.phase == AppUpdatePhase.verifying;

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
          if (statusMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              statusMessage,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (hasNativeInstaller &&
              (isBusy || effectiveState.phase == AppUpdatePhase.readyToInstall)) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: effectiveState.phase == AppUpdatePhase.downloading
                  ? effectiveState.progress
                  : null,
              minHeight: 6,
              borderRadius: BorderRadius.circular(999),
            ),
          ],
          const SizedBox(height: 14),
          if (hasNativeInstaller) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isBusy ? null : () => primaryAction?.call(),
                icon: Icon(_primaryButtonIcon(effectiveState)),
                label: Text(primaryButtonLabel),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: () => _openExternalUrl(updateInfo.releaseUrl),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(l10n.aboutOpenReleaseButton),
              ),
            ),
          ] else if (hasInstallerUrl) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openExternalUrl(installerUrl!),
                icon: const Icon(Icons.download_rounded),
                label: Text(l10n.aboutDownloadAndInstallButton),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: () => _openExternalUrl(updateInfo.releaseUrl),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(l10n.aboutOpenReleaseButton),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
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

  String _primaryButtonLabel(KickLocalizations l10n, AppUpdateFlowState state) {
    return switch (state.phase) {
      AppUpdatePhase.readyToInstall => _installLabelForPlatform(l10n),
      AppUpdatePhase.awaitingPermission => l10n.aboutAllowUnknownSourcesButton,
      AppUpdatePhase.downloading || AppUpdatePhase.verifying => l10n.aboutPreparingUpdateButton,
      AppUpdatePhase.error || AppUpdatePhase.idle => l10n.aboutDownloadUpdateButton,
    };
  }

  IconData _primaryButtonIcon(AppUpdateFlowState state) {
    return switch (state.phase) {
      AppUpdatePhase.readyToInstall => _installIconForPlatform(),
      AppUpdatePhase.awaitingPermission => Icons.security_update_warning_rounded,
      AppUpdatePhase.downloading || AppUpdatePhase.verifying => Icons.downloading_rounded,
      AppUpdatePhase.error || AppUpdatePhase.idle => Icons.download_rounded,
    };
  }

  String? _statusMessageForState(KickLocalizations l10n, AppUpdateFlowState state) {
    return switch (state.phase) {
      AppUpdatePhase.idle => null,
      AppUpdatePhase.downloading =>
        state.progress == null
            ? l10n.aboutUpdateDownloadingIndeterminate
            : l10n.aboutUpdateDownloadingProgress('${(state.progress! * 100).round()}%'),
      AppUpdatePhase.verifying => l10n.aboutUpdateVerifyingMessage,
      AppUpdatePhase.readyToInstall =>
        state.downloadedUpdate?.isChecksumVerified == true
            ? l10n.aboutUpdateReadyVerifiedMessage
            : l10n.aboutUpdateReadyUnverifiedMessage,
      AppUpdatePhase.awaitingPermission => l10n.aboutUpdateUnknownSourcesMessage,
      AppUpdatePhase.error => l10n.aboutUpdateOperationFailedMessage(
        state.errorMessage ?? l10n.errorUnknown,
      ),
    };
  }

  String _installLabelForPlatform(KickLocalizations l10n) {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return l10n.aboutInstallOnRestartButton;
    }
    return l10n.aboutInstallUpdateButton;
  }

  IconData _installIconForPlatform() {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return Icons.restart_alt_rounded;
    }
    return Icons.system_update_alt_rounded;
  }

  bool _supportsNativeInstaller() {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
