import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/kick_theme.dart';
import '../../data/models/app_settings.dart';
import '../../l10n/kick_localizations.dart';
import '../shared/kick_surfaces.dart';
import 'settings_draft_controller.dart';

class SettingsAppearanceSection extends StatelessWidget {
  const SettingsAppearanceSection({
    super.key,
    required this.controller,
    required this.expanded,
    required this.onToggle,
    required this.isDesktopTrayPlatform,
  });

  final SettingsDraftController controller;
  final bool expanded;
  final VoidCallback onToggle;
  final bool isDesktopTrayPlatform;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SettingsExpandableSection(
      title: l10n.settingsAppearanceSectionTitle,
      subtitle: l10n.settingsAppearanceSectionSummary,
      expanded: expanded,
      onToggle: onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.languageLabel, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<Locale?>(
            key: ValueKey(controller.appLocale?.languageCode ?? 'system'),
            initialValue: controller.appLocale,
            isExpanded: true,
            decoration: InputDecoration(helperText: l10n.languageHelperText),
            items: [
              DropdownMenuItem<Locale?>(value: null, child: Text(l10n.languageOptionSystem)),
              ...AppLocalizations.supportedLocales.map(
                (locale) => DropdownMenuItem<Locale?>(
                  value: locale,
                  child: Text(_settingsLanguageLabel(l10n, locale)),
                ),
              ),
            ],
            onChanged: controller.setAppLocale,
          ),
          const SizedBox(height: 18),
          Text(l10n.themeLabel, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text(l10n.themeModeSystem),
                icon: const Icon(Icons.brightness_auto_rounded),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text(l10n.themeModeLight),
                icon: const Icon(Icons.light_mode_rounded),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text(l10n.themeModeDark),
                icon: const Icon(Icons.dark_mode_rounded),
              ),
            ],
            selected: {controller.themeMode},
            onSelectionChanged: (value) => controller.setThemeMode(value.first),
          ),
          const SizedBox(height: 18),
          SettingToggleCard(
            title: l10n.dynamicThemeTitle,
            subtitle: l10n.dynamicThemeSubtitle,
            value: controller.useDynamicColor,
            onChanged: controller.setUseDynamicColor,
          ),
          const SizedBox(height: 18),
          Text(l10n.loggingLabel, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<KickLogVerbosity>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: KickLogVerbosity.quiet, label: Text(l10n.loggingQuiet)),
              ButtonSegment(value: KickLogVerbosity.normal, label: Text(l10n.loggingNormal)),
              ButtonSegment(value: KickLogVerbosity.verbose, label: Text(l10n.loggingVerbose)),
            ],
            selected: {controller.verbosity},
            onSelectionChanged: (value) => controller.setVerbosity(value.first),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: controller.logRetentionController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.logRetentionLabel,
              helperText: l10n.logRetentionHelperText,
              errorText: controller.logRetentionValidationError(l10n),
            ),
          ),
          const SizedBox(height: 18),
          SettingToggleCard(
            title: l10n.unsafeRawLoggingTitle,
            subtitle: l10n.unsafeRawLoggingSubtitle,
            dangerous: true,
            value: controller.unsafeRawLoggingEnabled,
            onChanged: controller.setUnsafeRawLoggingEnabled,
          ),
          if (isDesktopTrayPlatform) ...[
            const SizedBox(height: 18),
            SettingInfoCard(
              icon: Icons.computer_rounded,
              title: l10n.windowsTrayTitle,
              subtitle: l10n.windowsTraySubtitle,
            ),
            const SizedBox(height: 18),
            SettingToggleCard(
              title: l10n.windowsLaunchAtStartupTitle,
              subtitle: l10n.windowsLaunchAtStartupSubtitle,
              value: controller.windowsLaunchAtStartup,
              onChanged: controller.setWindowsLaunchAtStartup,
            ),
          ],
        ],
      ),
    );
  }
}

String _settingsLanguageLabel(KickLocalizations l10n, Locale locale) {
  return switch (locale.languageCode) {
    'ru' => l10n.languageOptionRussian,
    'en' => l10n.languageOptionEnglish,
    _ => locale.toLanguageTag(),
  };
}

class SettingsNetworkSection extends StatelessWidget {
  const SettingsNetworkSection({
    super.key,
    required this.controller,
    required this.expanded,
    required this.onToggle,
  });

  final SettingsDraftController controller;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SettingsExpandableSection(
      title: l10n.settingsNetworkSectionTitle,
      subtitle: l10n.settingsNetworkSectionSummary,
      expanded: expanded,
      onToggle: onToggle,
      child: Column(
        children: [
          TextField(
            controller: controller.hostController,
            decoration: InputDecoration(
              labelText: l10n.hostLabel,
              helperText: l10n.hostHelperText,
              errorText: controller.hostValidationError(l10n),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller.portController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.portLabel,
              helperText: l10n.portHelperText.isEmpty ? null : l10n.portHelperText,
              errorText: controller.portValidationError(l10n),
            ),
          ),
          const SizedBox(height: 18),
          SettingToggleCard(
            title: l10n.allowLanTitle,
            subtitle: l10n.allowLanSubtitle,
            dangerous: true,
            value: controller.allowLan,
            onChanged: controller.setAllowLan,
          ),
        ],
      ),
    );
  }
}

class SettingsReliabilitySection extends StatelessWidget {
  const SettingsReliabilitySection({
    super.key,
    required this.controller,
    required this.expanded,
    required this.onToggle,
  });

  final SettingsDraftController controller;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SettingsExpandableSection(
      title: l10n.settingsReliabilitySectionTitle,
      subtitle: l10n.settingsReliabilitySectionSummary,
      expanded: expanded,
      onToggle: onToggle,
      child: Column(
        children: [
          TextField(
            controller: controller.requestRetriesController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.requestRetriesLabel,
              helperText: l10n.requestRetriesHelperText.isEmpty
                  ? null
                  : l10n.requestRetriesHelperText,
              errorText: controller.requestRetriesValidationError(l10n),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller.retry429DelayController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.retry429DelayLabel,
              helperText: l10n.retry429DelayHelperText.isEmpty
                  ? null
                  : l10n.retry429DelayHelperText,
              errorText: controller.retry429DelayValidationError(l10n),
            ),
          ),
          const SizedBox(height: 18),
          SettingToggleCard(
            title: l10n.mark429AsUnhealthyTitle,
            subtitle: l10n.mark429AsUnhealthySubtitle,
            value: controller.mark429AsUnhealthy,
            onChanged: controller.setMark429AsUnhealthy,
          ),
        ],
      ),
    );
  }
}

class SettingsAccessSection extends StatelessWidget {
  const SettingsAccessSection({
    super.key,
    required this.controller,
    required this.expanded,
    required this.onToggle,
    required this.isAndroidPlatform,
    required this.onRegenerateApiKey,
    this.onAndroidBackgroundRuntimeEnabled,
  });

  final SettingsDraftController controller;
  final bool expanded;
  final VoidCallback onToggle;
  final bool isAndroidPlatform;
  final Future<void> Function() onRegenerateApiKey;
  final VoidCallback? onAndroidBackgroundRuntimeEnabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SettingsExpandableSection(
      title: l10n.settingsAccessSectionTitle,
      subtitle: l10n.settingsAccessSectionSummary,
      expanded: expanded,
      onToggle: onToggle,
      child: Column(
        children: [
          SettingToggleCard(
            title: l10n.apiKeyRequiredTitle,
            subtitle: l10n.apiKeyRequiredSubtitle,
            dangerous: true,
            value: controller.apiKeyRequired,
            onChanged: controller.setApiKeyRequired,
          ),
          const SizedBox(height: 18),
          TextField(
            controller: controller.apiKeyController,
            decoration: InputDecoration(labelText: l10n.apiKeyTitle),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                unawaited(onRegenerateApiKey());
              },
              icon: const Icon(Icons.key_rounded),
              label: Text(l10n.regenerateApiKeyAction),
            ),
          ),
          if (isAndroidPlatform) ...[
            const SizedBox(height: 18),
            SettingToggleCard(
              title: l10n.androidBackgroundRuntimeTitle,
              subtitle: l10n.androidBackgroundRuntimeSubtitle,
              value: controller.androidBackgroundRuntime,
              onChanged: (value) {
                controller.setAndroidBackgroundRuntime(value);
                if (value) {
                  onAndroidBackgroundRuntimeEnabled?.call();
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

class SettingsModelsSection extends StatelessWidget {
  const SettingsModelsSection({
    super.key,
    required this.controller,
    required this.expanded,
    required this.onToggle,
  });

  final SettingsDraftController controller;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SettingsExpandableSection(
      title: l10n.settingsModelsSectionTitle,
      subtitle: l10n.settingsModelsSectionSummary,
      expanded: expanded,
      onToggle: onToggle,
      child: TextField(
        controller: controller.customModelsController,
        minLines: 7,
        maxLines: 10,
        decoration: InputDecoration(
          labelText: l10n.customModelsLabel,
          helperText: l10n.customModelsHelperText,
          alignLabelWithHint: true,
        ),
      ),
    );
  }
}

class SettingsGoogleSection extends StatelessWidget {
  const SettingsGoogleSection({
    super.key,
    required this.controller,
    required this.expanded,
    required this.onToggle,
  });

  final SettingsDraftController controller;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SettingsExpandableSection(
      title: l10n.settingsGoogleSectionTitle,
      subtitle: l10n.settingsGoogleSectionSummary,
      expanded: expanded,
      onToggle: onToggle,
      child: Column(
        children: [
          SettingToggleCard(
            title: l10n.defaultGoogleWebSearchTitle,
            subtitle: l10n.defaultGoogleWebSearchSubtitle,
            value: controller.defaultGoogleWebSearchEnabled,
            onChanged: controller.setDefaultGoogleWebSearchEnabled,
          ),
          const SizedBox(height: 18),
          SettingToggleCard(
            title: l10n.renderGoogleGroundingInMessageTitle,
            subtitle: l10n.renderGoogleGroundingInMessageSubtitle,
            value: controller.renderGoogleGroundingInMessage,
            onChanged: controller.setRenderGoogleGroundingInMessage,
          ),
        ],
      ),
    );
  }
}

class SettingsBackupSection extends StatelessWidget {
  const SettingsBackupSection({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.onExport,
    required this.onImport,
    this.busy = false,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final Future<void> Function() onExport;
  final Future<void> Function() onImport;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SettingsExpandableSection(
      title: l10n.settingsBackupSectionTitle,
      subtitle: l10n.settingsBackupSectionSummary,
      expanded: expanded,
      onToggle: onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingInfoCard(
            icon: Icons.security_rounded,
            title: l10n.settingsBackupInfoTitle,
            subtitle: l10n.settingsBackupInfoSubtitle,
          ),
          const SizedBox(height: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SettingsActionButton(
                variant: _SettingsActionButtonVariant.outlined,
                busy: busy,
                icon: Icons.download_rounded,
                label: l10n.settingsBackupExportButton,
                onPressed: () {
                  unawaited(onExport());
                },
              ),
              const SizedBox(height: 12),
              _SettingsActionButton(
                variant: _SettingsActionButtonVariant.filled,
                busy: busy,
                icon: Icons.settings_backup_restore_rounded,
                label: l10n.settingsBackupImportButton,
                onPressed: () {
                  unawaited(onImport());
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _SettingsActionButtonVariant { outlined, filled }

class _SettingsActionButton extends StatelessWidget {
  const _SettingsActionButton({
    required this.variant,
    required this.busy,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final _SettingsActionButtonVariant variant;
  final bool busy;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final child = _SettingsActionButtonContent(icon: icon, label: label);
    final style = switch (variant) {
      _SettingsActionButtonVariant.outlined => OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
      ),
      _SettingsActionButtonVariant.filled => FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
      ),
    };

    return SizedBox(
      width: double.infinity,
      child: switch (variant) {
        _SettingsActionButtonVariant.outlined => OutlinedButton(
          onPressed: busy ? null : onPressed,
          style: style,
          child: child,
        ),
        _SettingsActionButtonVariant.filled => FilledButton(
          onPressed: busy ? null : onPressed,
          style: style,
          child: child,
        ),
      },
    );
  }
}

class _SettingsActionButtonContent extends StatelessWidget {
  const _SettingsActionButtonContent({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(alignment: Alignment.centerLeft, child: Icon(icon, size: 18)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsExpandableSection extends StatelessWidget {
  const SettingsExpandableSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return KickPanel(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(context.kickTokens.panelRadius),
        child: Material(
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: textTheme.titleLarge),
                            if (subtitle != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                subtitle!,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: context.kickTokens.shortDuration,
                        curve: context.kickTokens.standardCurve,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ClipRect(
                child: AnimatedAlign(
                  duration: context.kickTokens.mediumDuration,
                  curve: context.kickTokens.emphasizedCurve,
                  alignment: Alignment.topCenter,
                  heightFactor: expanded ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !expanded,
                    child: AnimatedOpacity(
                      duration: context.kickTokens.shortDuration,
                      curve: context.kickTokens.standardCurve,
                      opacity: expanded ? 1 : 0,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [const Divider(), const SizedBox(height: 18), child],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsSaveBadge extends StatelessWidget {
  const SettingsSaveBadge({super.key, required this.state, this.errorMessage});

  final SettingsDraftSaveState state;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    final (label, icon, color) = switch (state) {
      SettingsDraftSaveState.saving => (
        l10n.settingsSavingStatus,
        Icons.sync_rounded,
        scheme.primary,
      ),
      SettingsDraftSaveState.saved => (
        l10n.settingsSavedStatus,
        Icons.check_circle_rounded,
        scheme.primary,
      ),
      SettingsDraftSaveState.validationError => (
        l10n.settingsValidationStatus,
        Icons.error_rounded,
        scheme.error,
      ),
      SettingsDraftSaveState.error => (
        l10n.settingsSaveFailedStatus,
        Icons.cloud_off_rounded,
        scheme.error,
      ),
    };

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.12), scheme.surfaceContainerLow),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color)),
        ],
      ),
    );

    if (state != SettingsDraftSaveState.error || errorMessage == null || errorMessage!.isEmpty) {
      return badge;
    }

    return Tooltip(message: errorMessage!, child: badge);
  }
}

class SettingInfoCard extends StatelessWidget {
  const SettingInfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.84),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
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
        ],
      ),
    );
  }
}

class SettingToggleCard extends StatelessWidget {
  const SettingToggleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.dangerous = false,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool dangerous;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accentColor = dangerous ? scheme.error : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (dangerous) ...[
                      Icon(Icons.warning_amber_rounded, size: 18, color: accentColor),
                      const SizedBox(width: 8),
                    ],
                    Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                  ],
                ),
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

class SettingsNavigationTile extends StatelessWidget {
  const SettingsNavigationTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return KickPanel(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(context.kickTokens.panelRadius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
