import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/user_facing_error_formatter.dart';
import '../../core/platform/android_foreground_runtime.dart';
import '../../core/theme/kick_theme.dart';
import '../../data/models/app_settings.dart';
import '../../l10n/kick_localizations.dart';
import '../app_state/providers.dart';
import '../shared/kick_surfaces.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.initialSection});

  final String? initialSection;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

enum _SettingsSaveState { saving, saved, validationError, error }

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _requestRetriesController = TextEditingController();
  final _customModelsController = TextEditingController();

  ThemeMode _themeMode = ThemeMode.system;
  KickLogVerbosity _verbosity = KickLogVerbosity.normal;
  bool _useDynamicColor = true;
  bool _allowLan = false;
  bool _apiKeyRequired = true;
  bool _androidBackgroundRuntime = true;
  bool _windowsLaunchAtStartup = false;
  bool _unsafeRawLoggingEnabled = false;
  bool _initialized = false;
  bool _appearanceExpanded = false;
  bool _networkExpanded = false;
  bool _reliabilityExpanded = false;
  bool _accessExpanded = false;
  bool _modelsExpanded = false;
  bool _isHydrating = false;
  bool _saveInFlight = false;
  bool _mark429AsUnhealthy = false;
  _SettingsSaveState _saveState = _SettingsSaveState.saved;
  String? _saveErrorMessage;
  bool _showSaveStatus = false;
  AppSettings? _syncedSettings;
  AppSettings? _queuedSettings;
  Timer? _saveDebounce;
  Timer? _saveStatusHideTimer;

  @override
  void initState() {
    super.initState();
    _accessExpanded = widget.initialSection == _SettingsSectionId.access.routeValue;
    _hostController.addListener(_handleTextSettingsChanged);
    _portController.addListener(_handleTextSettingsChanged);
    _apiKeyController.addListener(_handleTextSettingsChanged);
    _requestRetriesController.addListener(_handleTextSettingsChanged);
    _customModelsController.addListener(_handleTextSettingsChanged);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _saveStatusHideTimer?.cancel();
    _hostController.dispose();
    _portController.dispose();
    _apiKeyController.dispose();
    _requestRetriesController.dispose();
    _customModelsController.dispose();
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
        _syncedSettings = settings;
        if (!_initialized) {
          _applySettings(settings);
        }
        final hostError = _hostValidationError(l10n);
        final portError = _portValidationError(l10n);
        final requestRetriesError = _requestRetriesValidationError(l10n);

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                title: l10n.settingsTitle,
                subtitle: l10n.settingsSubtitle,
                trailing: _showSaveStatus
                    ? _SettingsSaveBadge(state: _saveState, errorMessage: _saveErrorMessage)
                    : null,
              ),
              const SizedBox(height: 24),
              _SettingsSection(
                title: l10n.settingsAppearanceSectionTitle,
                subtitle: l10n.settingsAppearanceSectionSummary,
                expanded: _appearanceExpanded,
                onToggle: () {
                  setState(() => _appearanceExpanded = !_appearanceExpanded);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                      selected: {_themeMode},
                      onSelectionChanged: (value) {
                        setState(() => _themeMode = value.first);
                        _saveImmediately();
                      },
                    ),
                    const SizedBox(height: 18),
                    _SettingToggle(
                      title: l10n.dynamicThemeTitle,
                      subtitle: l10n.dynamicThemeSubtitle,
                      value: _useDynamicColor,
                      onChanged: (value) {
                        setState(() => _useDynamicColor = value);
                        _saveImmediately();
                      },
                    ),
                    const SizedBox(height: 18),
                    Text(l10n.loggingLabel, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    SegmentedButton<KickLogVerbosity>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: KickLogVerbosity.quiet,
                          label: Text(l10n.loggingQuiet),
                        ),
                        ButtonSegment(
                          value: KickLogVerbosity.normal,
                          label: Text(l10n.loggingNormal),
                        ),
                        ButtonSegment(
                          value: KickLogVerbosity.verbose,
                          label: Text(l10n.loggingVerbose),
                        ),
                      ],
                      selected: {_verbosity},
                      onSelectionChanged: (value) {
                        setState(() => _verbosity = value.first);
                        _saveImmediately();
                      },
                    ),
                    const SizedBox(height: 18),
                    _SettingToggle(
                      title: l10n.unsafeRawLoggingTitle,
                      subtitle: l10n.unsafeRawLoggingSubtitle,
                      dangerous: true,
                      value: _unsafeRawLoggingEnabled,
                      onChanged: (value) {
                        setState(() => _unsafeRawLoggingEnabled = value);
                        _saveImmediately();
                      },
                    ),
                    if (isWindowsPlatform) ...[
                      const SizedBox(height: 18),
                      _SettingInfoCard(
                        icon: Icons.desktop_windows_rounded,
                        title: l10n.windowsTrayTitle,
                        subtitle: l10n.windowsTraySubtitle,
                      ),
                      const SizedBox(height: 18),
                      _SettingToggle(
                        title: l10n.windowsLaunchAtStartupTitle,
                        subtitle: l10n.windowsLaunchAtStartupSubtitle,
                        value: _windowsLaunchAtStartup,
                        onChanged: (value) {
                          setState(() => _windowsLaunchAtStartup = value);
                          _saveImmediately();
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SettingsSection(
                title: l10n.settingsNetworkSectionTitle,
                subtitle: l10n.settingsNetworkSectionSummary,
                expanded: _networkExpanded,
                onToggle: () {
                  setState(() => _networkExpanded = !_networkExpanded);
                },
                child: Column(
                  children: [
                    TextField(
                      controller: _hostController,
                      decoration: InputDecoration(
                        labelText: l10n.hostLabel,
                        helperText: l10n.hostHelperText,
                        errorText: hostError,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.portLabel,
                        helperText: l10n.portHelperText.isEmpty ? null : l10n.portHelperText,
                        errorText: portError,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SettingToggle(
                      title: l10n.allowLanTitle,
                      subtitle: l10n.allowLanSubtitle,
                      dangerous: true,
                      value: _allowLan,
                      onChanged: (value) {
                        setState(() => _allowLan = value);
                        _saveImmediately();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SettingsSection(
                title: l10n.settingsReliabilitySectionTitle,
                subtitle: l10n.settingsReliabilitySectionSummary,
                expanded: _reliabilityExpanded,
                onToggle: () {
                  setState(() => _reliabilityExpanded = !_reliabilityExpanded);
                },
                child: Column(
                  children: [
                    TextField(
                      controller: _requestRetriesController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.requestRetriesLabel,
                        helperText: l10n.requestRetriesHelperText.isEmpty
                            ? null
                            : l10n.requestRetriesHelperText,
                        errorText: requestRetriesError,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SettingToggle(
                      title: l10n.mark429AsUnhealthyTitle,
                      subtitle: l10n.mark429AsUnhealthySubtitle,
                      value: _mark429AsUnhealthy,
                      onChanged: (value) {
                        setState(() => _mark429AsUnhealthy = value);
                        _saveImmediately();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SettingsSection(
                title: l10n.settingsAccessSectionTitle,
                subtitle: l10n.settingsAccessSectionSummary,
                expanded: _accessExpanded,
                onToggle: () {
                  setState(() => _accessExpanded = !_accessExpanded);
                },
                child: Column(
                  children: [
                    _SettingToggle(
                      title: l10n.apiKeyRequiredTitle,
                      subtitle: l10n.apiKeyRequiredSubtitle,
                      dangerous: true,
                      value: _apiKeyRequired,
                      onChanged: (value) {
                        setState(() => _apiKeyRequired = value);
                        _saveImmediately();
                      },
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _apiKeyController,
                      decoration: InputDecoration(labelText: l10n.apiKeyTitle),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _handleApiKeyRegeneration,
                        icon: const Icon(Icons.key_rounded),
                        label: Text(l10n.regenerateApiKeyAction),
                      ),
                    ),
                    if (isAndroidPlatform) ...[
                      const SizedBox(height: 18),
                      _SettingToggle(
                        title: l10n.androidBackgroundRuntimeTitle,
                        subtitle: l10n.androidBackgroundRuntimeSubtitle,
                        value: _androidBackgroundRuntime,
                        onChanged: (value) {
                          setState(() => _androidBackgroundRuntime = value);
                          if (value) {
                            unawaited(AndroidForegroundRuntime.ensurePermissions());
                          }
                          _saveImmediately();
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SettingsSection(
                title: l10n.settingsModelsSectionTitle,
                subtitle: l10n.settingsModelsSectionSummary,
                expanded: _modelsExpanded,
                onToggle: () {
                  setState(() => _modelsExpanded = !_modelsExpanded);
                },
                child: TextField(
                  controller: _customModelsController,
                  minLines: 7,
                  maxLines: 10,
                  decoration: InputDecoration(
                    labelText: l10n.customModelsLabel,
                    helperText: l10n.customModelsHelperText,
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _SettingsNavigationTile(
                title: l10n.aboutTitle,
                subtitle: l10n.aboutMenuSubtitle,
                icon: Icons.info_rounded,
                onTap: () => context.push('/settings/about'),
              ),
            ],
          ),
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

  void _applySettings(AppSettings settings) {
    _isHydrating = true;
    _hostController.text = settings.host;
    _portController.text = settings.port.toString();
    _apiKeyController.text = settings.apiKey;
    _requestRetriesController.text = settings.requestMaxRetries.toString();
    _customModelsController.text = settings.customModels.join('\n');
    _apiKeyRequired = settings.apiKeyRequired;
    _themeMode = settings.themeMode;
    _verbosity = settings.loggingVerbosity;
    _useDynamicColor = settings.useDynamicColor;
    _allowLan = settings.allowLan;
    _androidBackgroundRuntime = settings.androidBackgroundRuntime;
    _windowsLaunchAtStartup = settings.windowsLaunchAtStartup;
    _mark429AsUnhealthy = settings.mark429AsUnhealthy;
    _unsafeRawLoggingEnabled = settings.unsafeRawLoggingEnabled;
    _saveState = _SettingsSaveState.saved;
    _saveErrorMessage = null;
    _showSaveStatus = false;
    _initialized = true;
    _isHydrating = false;
  }

  void _handleTextSettingsChanged() {
    if (!_initialized || _isHydrating) {
      return;
    }
    if (_hasBlockingValidationErrors(context.l10n)) {
      _saveDebounce?.cancel();
      _presentSaveStatus(_SettingsSaveState.validationError);
      return;
    }
    setState(() {});
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _presentSaveStatus(_SettingsSaveState.saving);
    _saveDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_persistSettings());
    });
  }

  void _saveImmediately() {
    _saveDebounce?.cancel();
    if (_hasBlockingValidationErrors(context.l10n)) {
      _presentSaveStatus(_SettingsSaveState.validationError);
      return;
    }
    _presentSaveStatus(_SettingsSaveState.saving);
    unawaited(_persistSettings());
  }

  Future<void> _persistSettings() async {
    final l10n = context.l10n;
    final currentSettings = _syncedSettings ?? ref.read(settingsControllerProvider).asData?.value;
    if (currentSettings == null) {
      return;
    }

    final updated = currentSettings.copyWith(
      themeMode: _themeMode,
      useDynamicColor: _useDynamicColor,
      host: _hostController.text.trim(),
      port: int.parse(_portController.text.trim()),
      allowLan: _allowLan,
      androidBackgroundRuntime: _androidBackgroundRuntime,
      windowsLaunchAtStartup: _windowsLaunchAtStartup,
      requestMaxRetries: int.parse(_requestRetriesController.text.trim()),
      mark429AsUnhealthy: _mark429AsUnhealthy,
      loggingVerbosity: _verbosity,
      unsafeRawLoggingEnabled: _unsafeRawLoggingEnabled,
      apiKeyRequired: _apiKeyRequired,
      apiKey: _apiKeyController.text.trim().isEmpty
          ? currentSettings.apiKey
          : _apiKeyController.text.trim(),
      customModels: _customModelsController.text
          .split('\n')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );

    if (_settingsEqual(currentSettings, updated)) {
      if (mounted) {
        setState(() {
          _showSaveStatus = false;
        });
      }
      return;
    }

    _queuedSettings = updated;
    if (_saveInFlight) {
      return;
    }

    _saveInFlight = true;
    try {
      while (_queuedSettings != null) {
        final nextSettings = _queuedSettings!;
        _queuedSettings = null;
        await ref.read(settingsControllerProvider.notifier).save(nextSettings);
        _syncedSettings = nextSettings;
      }
      _presentSaveStatus(_SettingsSaveState.saved, hideAfter: const Duration(seconds: 2));
    } catch (error) {
      _presentSaveStatus(
        _SettingsSaveState.error,
        errorMessage: formatUserFacingError(l10n, error),
      );
    } finally {
      _saveInFlight = false;
    }
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

    _saveDebounce?.cancel();
    final apiKey = await ref.read(settingsControllerProvider.notifier).regenerateApiKey();
    final currentSettings = _syncedSettings ?? ref.read(settingsControllerProvider).asData?.value;
    if (currentSettings != null) {
      _syncedSettings = currentSettings.copyWith(apiKey: apiKey);
    }
    _isHydrating = true;
    _apiKeyController.text = apiKey;
    _isHydrating = false;
    if (!mounted) {
      return;
    }
    _presentSaveStatus(_SettingsSaveState.saved, hideAfter: const Duration(seconds: 2));

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(l10n.apiKeyRegeneratedMessage)));
  }

  void _presentSaveStatus(_SettingsSaveState state, {String? errorMessage, Duration? hideAfter}) {
    _saveStatusHideTimer?.cancel();
    if (!mounted) {
      return;
    }

    setState(() {
      _saveState = state;
      _saveErrorMessage = errorMessage;
      _showSaveStatus = true;
    });

    if (hideAfter != null) {
      _saveStatusHideTimer = Timer(hideAfter, () {
        if (!mounted) {
          return;
        }
        setState(() {
          _showSaveStatus = false;
        });
      });
    }
  }

  String? _hostValidationError(KickLocalizations l10n) {
    final value = _hostController.text.trim();
    if (value.isEmpty) {
      return l10n.hostRequiredError;
    }
    if (RegExp(r'\s').hasMatch(value)) {
      return l10n.hostInvalidError;
    }
    if (value == '0.0.0.0' && !_allowLan) {
      return l10n.hostLanDisabledError;
    }
    return null;
  }

  String? _portValidationError(KickLocalizations l10n) {
    final value = _portController.text.trim();
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 1 || parsed > 65535) {
      return l10n.portInvalidError;
    }
    return null;
  }

  String? _requestRetriesValidationError(KickLocalizations l10n) {
    final value = _requestRetriesController.text.trim();
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 0 || parsed > 20) {
      return l10n.requestRetriesInvalidError;
    }
    return null;
  }

  bool _hasBlockingValidationErrors(KickLocalizations l10n) {
    return _hostValidationError(l10n) != null ||
        _portValidationError(l10n) != null ||
        _requestRetriesValidationError(l10n) != null;
  }

  bool _settingsEqual(AppSettings left, AppSettings right) {
    return left.apiKey == right.apiKey &&
        left.apiKeyRequired == right.apiKeyRequired &&
        left.themeMode == right.themeMode &&
        left.useDynamicColor == right.useDynamicColor &&
        left.hasAcknowledgedDisclaimer == right.hasAcknowledgedDisclaimer &&
        left.analyticsConsentEnabled == right.analyticsConsentEnabled &&
        left.host == right.host &&
        left.port == right.port &&
        left.allowLan == right.allowLan &&
        left.androidBackgroundRuntime == right.androidBackgroundRuntime &&
        left.windowsLaunchAtStartup == right.windowsLaunchAtStartup &&
        left.requestMaxRetries == right.requestMaxRetries &&
        left.mark429AsUnhealthy == right.mark429AsUnhealthy &&
        left.loggingVerbosity == right.loggingVerbosity &&
        left.unsafeRawLoggingEnabled == right.unsafeRawLoggingEnabled &&
        listEquals(left.customModels, right.customModels);
  }
}

enum _SettingsSectionId {
  access('access');

  const _SettingsSectionId(this.routeValue);

  final String routeValue;
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
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

class _SettingsSaveBadge extends StatelessWidget {
  const _SettingsSaveBadge({required this.state, this.errorMessage});

  final _SettingsSaveState state;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    final (label, icon, color) = switch (state) {
      _SettingsSaveState.saving => (l10n.settingsSavingStatus, Icons.sync_rounded, scheme.primary),
      _SettingsSaveState.saved => (
        l10n.settingsSavedStatus,
        Icons.check_circle_rounded,
        scheme.primary,
      ),
      _SettingsSaveState.validationError => (
        l10n.settingsValidationStatus,
        Icons.error_rounded,
        scheme.error,
      ),
      _SettingsSaveState.error => (
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

    if (state != _SettingsSaveState.error || errorMessage == null || errorMessage!.isEmpty) {
      return badge;
    }

    return Tooltip(message: errorMessage!, child: badge);
  }
}

class _SettingInfoCard extends StatelessWidget {
  const _SettingInfoCard({required this.icon, required this.title, required this.subtitle});

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

class _SettingToggle extends StatelessWidget {
  const _SettingToggle({
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

class _SettingsNavigationTile extends StatelessWidget {
  const _SettingsNavigationTile({
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
