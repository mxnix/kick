import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/user_facing_error_formatter.dart';
import '../../core/platform/android_foreground_runtime.dart';
import '../../l10n/kick_localizations.dart';
import '../app_state/providers.dart';
import '../shared/kick_surfaces.dart';
import 'settings_draft_controller.dart';
import 'settings_sections.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.initialSection});

  final String? initialSection;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final SettingsDraftController _draftController;

  bool _appearanceExpanded = false;
  bool _networkExpanded = false;
  bool _reliabilityExpanded = false;
  bool _accessExpanded = false;
  bool _modelsExpanded = false;
  bool _googleExpanded = false;

  @override
  void initState() {
    super.initState();
    _accessExpanded = widget.initialSection == _SettingsSectionId.access.routeValue;
    _draftController = SettingsDraftController(
      saveSettings: (settings) => ref.read(settingsControllerProvider.notifier).save(settings),
      regenerateApiKey: () => ref.read(settingsControllerProvider.notifier).regenerateApiKey(),
    );
  }

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isAndroidPlatform = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final isWindowsPlatform = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final settingsValue = ref.watch(settingsControllerProvider);

    return settingsValue.when(
      data: (settings) {
        _draftController.syncWithSettings(settings);
        return AnimatedBuilder(
          animation: _draftController,
          builder: (context, child) {
            final saveError = _draftController.saveError;
            final saveErrorMessage = saveError == null
                ? null
                : formatUserFacingError(l10n, saveError);

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeading(
                    title: l10n.settingsTitle,
                    subtitle: l10n.settingsSubtitle,
                    trailing: _draftController.showSaveStatus
                        ? SettingsSaveBadge(
                            state: _draftController.saveState,
                            errorMessage: saveErrorMessage,
                          )
                        : null,
                  ),
                  const SizedBox(height: 24),
                  SettingsAppearanceSection(
                    controller: _draftController,
                    expanded: _appearanceExpanded,
                    onToggle: () {
                      setState(() => _appearanceExpanded = !_appearanceExpanded);
                    },
                    isWindowsPlatform: isWindowsPlatform,
                  ),
                  const SizedBox(height: 14),
                  SettingsNetworkSection(
                    controller: _draftController,
                    expanded: _networkExpanded,
                    onToggle: () {
                      setState(() => _networkExpanded = !_networkExpanded);
                    },
                  ),
                  const SizedBox(height: 14),
                  SettingsReliabilitySection(
                    controller: _draftController,
                    expanded: _reliabilityExpanded,
                    onToggle: () {
                      setState(() => _reliabilityExpanded = !_reliabilityExpanded);
                    },
                  ),
                  const SizedBox(height: 14),
                  SettingsAccessSection(
                    controller: _draftController,
                    expanded: _accessExpanded,
                    onToggle: () {
                      setState(() => _accessExpanded = !_accessExpanded);
                    },
                    isAndroidPlatform: isAndroidPlatform,
                    onRegenerateApiKey: _handleApiKeyRegeneration,
                    onAndroidBackgroundRuntimeEnabled: () {
                      unawaited(AndroidForegroundRuntime.ensurePermissions());
                    },
                  ),
                  const SizedBox(height: 14),
                  SettingsModelsSection(
                    controller: _draftController,
                    expanded: _modelsExpanded,
                    onToggle: () {
                      setState(() => _modelsExpanded = !_modelsExpanded);
                    },
                  ),
                  const SizedBox(height: 14),
                  SettingsGoogleSection(
                    controller: _draftController,
                    expanded: _googleExpanded,
                    onToggle: () {
                      setState(() => _googleExpanded = !_googleExpanded);
                    },
                  ),
                  const SizedBox(height: 14),
                  SettingsNavigationTile(
                    title: l10n.aboutTitle,
                    subtitle: l10n.aboutMenuSubtitle,
                    icon: Icons.info_rounded,
                    onTap: () => context.push('/settings/about'),
                  ),
                ],
              ),
            );
          },
        );
      },
      error: (error, stackTrace) => EmptyStateCard(
        icon: Icons.error_rounded,
        title: l10n.settingsLoadErrorTitle,
        message: formatUserFacingError(l10n, error),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }

  Future<void> _handleApiKeyRegeneration() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.regenerateApiKeyDialogTitle),
          content: Text(l10n.regenerateApiKeyDialogMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancelButton),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.regenerateApiKeyConfirmButton),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    await _draftController.regenerateApiKey();
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(l10n.apiKeyRegeneratedMessage)));
  }
}

enum _SettingsSectionId {
  access('access');

  const _SettingsSectionId(this.routeValue);

  final String routeValue;
}
