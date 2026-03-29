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
import 'configuration_backup_service.dart';
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
  bool _backupExpanded = false;
  bool _configurationTransferInProgress = false;

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
                  SettingsBackupSection(
                    expanded: _backupExpanded,
                    onToggle: () {
                      setState(() => _backupExpanded = !_backupExpanded);
                    },
                    onExport: _handleConfigurationExport,
                    onImport: _handleConfigurationRestore,
                    busy: _configurationTransferInProgress,
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
    if (!mounted || confirmed != true) {
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

  Future<void> _handleConfigurationExport() async {
    if (_configurationTransferInProgress) {
      return;
    }

    final l10n = context.l10n;
    _draftController.saveImmediately();
    await _draftController.settlePendingSaves();
    if (!mounted) {
      return;
    }
    final settings = ref.read(settingsControllerProvider).asData?.value;
    if (settings == null) {
      return;
    }

    final exportOptions = await _showBackupExportOptionsDialog();
    if (!mounted || exportOptions == null) {
      return;
    }

    setState(() => _configurationTransferInProgress = true);
    try {
      final accounts = await ref.read(accountsControllerProvider.future);
      if (!mounted) {
        return;
      }
      final result = await ref
          .read(configurationBackupServiceProvider)
          .export(
            settings: settings,
            accounts: accounts,
            options: exportOptions,
            dialogTitle: l10n.settingsBackupExportDialogTitle,
          );
      if (!mounted || result == null) {
        return;
      }
      _showSnackBar(l10n.settingsBackupExportedMessage(result.fileName));
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(
        l10n.settingsBackupExportFailedMessage(_formatConfigurationBackupError(l10n, error)),
      );
    } finally {
      if (mounted) {
        setState(() => _configurationTransferInProgress = false);
      }
    }
  }

  Future<void> _handleConfigurationRestore() async {
    if (_configurationTransferInProgress) {
      return;
    }

    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.settingsBackupRestoreDialogTitle),
          content: Text(l10n.settingsBackupRestoreDialogMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancelButton),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.settingsBackupRestoreConfirmButton),
            ),
          ],
        );
      },
    );
    if (!mounted || confirmed != true) {
      return;
    }

    setState(() => _configurationTransferInProgress = true);
    try {
      await _draftController.settlePendingSaves();
      if (!mounted) {
        return;
      }
      final result = await ref
          .read(configurationBackupServiceProvider)
          .restore(
            dialogTitle: l10n.settingsBackupImportDialogTitle,
            passwordPrompt: _showBackupPasswordDialog,
          );
      if (result == null) {
        return;
      }

      await ref.read(accountsControllerProvider.notifier).refreshState();
      if (!mounted) {
        return;
      }

      final message = result.accountsWithoutTokens > 0
          ? l10n.settingsBackupRestoredMissingTokensMessage(
              result.accountCount,
              result.accountsWithoutTokens,
            )
          : l10n.settingsBackupRestoredMessage(result.accountCount);
      _showSnackBar(message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(
        l10n.settingsBackupRestoreFailedMessage(_formatConfigurationBackupError(l10n, error)),
      );
    } finally {
      if (mounted) {
        setState(() => _configurationTransferInProgress = false);
      }
    }
  }

  Future<ConfigurationBackupExportOptions?> _showBackupExportOptionsDialog() {
    return showDialog<ConfigurationBackupExportOptions>(
      context: context,
      builder: (context) => const _BackupExportOptionsDialog(),
    );
  }

  Future<String?> _showBackupPasswordDialog(ConfigurationBackupPasswordRequest request) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _BackupPasswordDialog(request: request);
      },
    );
  }

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatConfigurationBackupError(KickLocalizations l10n, Object error) {
    if (error is ConfigurationBackupException) {
      return switch (error.code) {
        ConfigurationBackupErrorCode.invalidFormat => l10n.settingsBackupInvalidMessage,
        ConfigurationBackupErrorCode.unsupportedVersion =>
          l10n.settingsBackupUnsupportedVersionMessage,
        ConfigurationBackupErrorCode.readFailed => l10n.settingsBackupReadFailedMessage,
        ConfigurationBackupErrorCode.passwordRequired => l10n.settingsBackupPasswordRequiredMessage,
      };
    }
    return formatUserFacingError(l10n, error);
  }
}

class _BackupExportOptionsDialog extends StatefulWidget {
  const _BackupExportOptionsDialog();

  @override
  State<_BackupExportOptionsDialog> createState() => _BackupExportOptionsDialogState();
}

class _BackupExportOptionsDialogState extends State<_BackupExportOptionsDialog> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _protectWithPassword = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final passwordMismatch =
        _protectWithPassword &&
        password.isNotEmpty &&
        confirmPassword.isNotEmpty &&
        password != confirmPassword;
    final canSubmit =
        !_protectWithPassword ||
        (password.isNotEmpty && confirmPassword.isNotEmpty && !passwordMismatch);

    return AlertDialog(
      title: Text(l10n.settingsBackupExportOptionsDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              value: _protectWithPassword,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.settingsBackupProtectWithPasswordLabel),
              subtitle: Text(l10n.settingsBackupProtectWithPasswordSubtitle),
              onChanged: (value) {
                setState(() {
                  _protectWithPassword = value ?? true;
                });
              },
            ),
            if (_protectWithPassword) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.settingsBackupPasswordLabel,
                  helperText: l10n.settingsBackupPasswordHelperText,
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.settingsBackupPasswordConfirmLabel,
                  errorText: passwordMismatch ? l10n.settingsBackupPasswordsDoNotMatch : null,
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                    },
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                l10n.settingsBackupUnprotectedWarning,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancelButton)),
        FilledButton(
          onPressed: canSubmit
              ? () {
                  Navigator.of(context).pop(
                    _protectWithPassword
                        ? ConfigurationBackupExportOptions.passwordProtected(password: password)
                        : const ConfigurationBackupExportOptions.plainJson(),
                  );
                }
              : null,
          child: Text(l10n.settingsBackupExportConfirmButton),
        ),
      ],
    );
  }
}

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog({required this.request});

  final ConfigurationBackupPasswordRequest request;

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final password = _passwordController.text.trim();

    return AlertDialog(
      title: Text(l10n.settingsBackupPasswordDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.request.invalidPassword
                ? l10n.settingsBackupPasswordDialogInvalidMessage(widget.request.fileName)
                : l10n.settingsBackupPasswordDialogMessage(widget.request.fileName),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            autofocus: true,
            obscureText: _obscurePassword,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (password.isNotEmpty) {
                Navigator.of(context).pop(password);
              }
            },
            decoration: InputDecoration(
              labelText: l10n.settingsBackupPasswordLabel,
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancelButton)),
        FilledButton(
          onPressed: password.isEmpty ? null : () => Navigator.of(context).pop(password),
          child: Text(l10n.settingsBackupPasswordConfirmButton),
        ),
      ],
    );
  }
}

enum _SettingsSectionId {
  access('access');

  const _SettingsSectionId(this.routeValue);

  final String routeValue;
}
