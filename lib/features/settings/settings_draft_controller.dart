import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/models/app_settings.dart';
import '../../l10n/kick_localizations.dart';

enum SettingsDraftSaveState { saving, saved, validationError, error }

class SettingsDraftController extends ChangeNotifier {
  SettingsDraftController({
    required Future<void> Function(AppSettings settings) saveSettings,
    required Future<String> Function() regenerateApiKey,
    this.saveDebounceDuration = const Duration(milliseconds: 450),
  }) : _saveSettings = saveSettings,
       _regenerateApiKey = regenerateApiKey {
    hostController.addListener(_handleTextSettingsChanged);
    portController.addListener(_handleTextSettingsChanged);
    apiKeyController.addListener(_handleTextSettingsChanged);
    requestRetriesController.addListener(_handleTextSettingsChanged);
    retry429DelayController.addListener(_handleTextSettingsChanged);
    logRetentionController.addListener(_handleTextSettingsChanged);
    customModelsController.addListener(_handleTextSettingsChanged);
  }

  final Future<void> Function(AppSettings settings) _saveSettings;
  final Future<String> Function() _regenerateApiKey;
  final Duration saveDebounceDuration;

  final hostController = TextEditingController();
  final portController = TextEditingController();
  final apiKeyController = TextEditingController();
  final requestRetriesController = TextEditingController();
  final retry429DelayController = TextEditingController();
  final logRetentionController = TextEditingController();
  final customModelsController = TextEditingController();

  Locale? _appLocale;
  ThemeMode _themeMode = ThemeMode.system;
  KickLogVerbosity _verbosity = KickLogVerbosity.normal;
  bool _useDynamicColor = true;
  bool _allowLan = false;
  bool _apiKeyRequired = true;
  bool _androidBackgroundRuntime = true;
  bool _windowsLaunchAtStartup = false;
  bool _unsafeRawLoggingEnabled = false;
  bool _defaultGoogleWebSearchEnabled = false;
  bool _renderGoogleGroundingInMessage = false;
  bool _mark429AsUnhealthy = false;
  bool _initialized = false;
  bool _isHydrating = false;
  bool _saveInFlight = false;
  bool _showSaveStatus = false;
  SettingsDraftSaveState _saveState = SettingsDraftSaveState.saved;
  Object? _saveError;
  AppSettings? _syncedSettings;
  AppSettings? _queuedSettings;
  Completer<void>? _idleCompleter;
  Timer? _saveDebounce;
  Timer? _saveStatusHideTimer;

  Locale? get appLocale => _appLocale;
  ThemeMode get themeMode => _themeMode;
  KickLogVerbosity get verbosity => _verbosity;
  bool get useDynamicColor => _useDynamicColor;
  bool get allowLan => _allowLan;
  bool get apiKeyRequired => _apiKeyRequired;
  bool get androidBackgroundRuntime => _androidBackgroundRuntime;
  bool get windowsLaunchAtStartup => _windowsLaunchAtStartup;
  bool get unsafeRawLoggingEnabled => _unsafeRawLoggingEnabled;
  bool get defaultGoogleWebSearchEnabled => _defaultGoogleWebSearchEnabled;
  bool get renderGoogleGroundingInMessage => _renderGoogleGroundingInMessage;
  bool get mark429AsUnhealthy => _mark429AsUnhealthy;
  bool get showSaveStatus => _showSaveStatus;
  SettingsDraftSaveState get saveState => _saveState;
  Object? get saveError => _saveError;

  void syncWithSettings(AppSettings settings) {
    final previousSettings = _syncedSettings;
    _syncedSettings = settings;
    if (_initialized && previousSettings != null && _settingsEqual(previousSettings, settings)) {
      return;
    }
    _saveDebounce?.cancel();
    _queuedSettings = null;
    _hydrateFromSettings(settings);
  }

  Future<void> settlePendingSaves() async {
    _saveDebounce?.cancel();
    _queuedSettings = null;
    if (_saveInFlight) {
      _idleCompleter ??= Completer<void>();
      await _idleCompleter!.future;
    }
  }

  void setAppLocale(Locale? value) {
    if (_appLocale == value) {
      return;
    }
    _appLocale = value;
    notifyListeners();
    saveImmediately();
  }

  void setThemeMode(ThemeMode value) {
    if (_themeMode == value) {
      return;
    }
    _themeMode = value;
    notifyListeners();
    saveImmediately();
  }

  void setVerbosity(KickLogVerbosity value) {
    if (_verbosity == value) {
      return;
    }
    _verbosity = value;
    notifyListeners();
    saveImmediately();
  }

  void setUseDynamicColor(bool value) {
    if (_useDynamicColor == value) {
      return;
    }
    _useDynamicColor = value;
    notifyListeners();
    saveImmediately();
  }

  void setAllowLan(bool value) {
    if (_allowLan == value) {
      return;
    }
    _allowLan = value;
    notifyListeners();
    saveImmediately();
  }

  void setApiKeyRequired(bool value) {
    if (_apiKeyRequired == value) {
      return;
    }
    _apiKeyRequired = value;
    notifyListeners();
    saveImmediately();
  }

  void setAndroidBackgroundRuntime(bool value) {
    if (_androidBackgroundRuntime == value) {
      return;
    }
    _androidBackgroundRuntime = value;
    notifyListeners();
    saveImmediately();
  }

  void setWindowsLaunchAtStartup(bool value) {
    if (_windowsLaunchAtStartup == value) {
      return;
    }
    _windowsLaunchAtStartup = value;
    notifyListeners();
    saveImmediately();
  }

  void setUnsafeRawLoggingEnabled(bool value) {
    if (_unsafeRawLoggingEnabled == value) {
      return;
    }
    _unsafeRawLoggingEnabled = value;
    notifyListeners();
    saveImmediately();
  }

  void setDefaultGoogleWebSearchEnabled(bool value) {
    if (_defaultGoogleWebSearchEnabled == value) {
      return;
    }
    _defaultGoogleWebSearchEnabled = value;
    notifyListeners();
    saveImmediately();
  }

  void setRenderGoogleGroundingInMessage(bool value) {
    if (_renderGoogleGroundingInMessage == value) {
      return;
    }
    _renderGoogleGroundingInMessage = value;
    notifyListeners();
    saveImmediately();
  }

  void setMark429AsUnhealthy(bool value) {
    if (_mark429AsUnhealthy == value) {
      return;
    }
    _mark429AsUnhealthy = value;
    notifyListeners();
    saveImmediately();
  }

  String? hostValidationError(KickLocalizations l10n) {
    final value = hostController.text.trim();
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

  String? portValidationError(KickLocalizations l10n) {
    final value = portController.text.trim();
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 1 || parsed > 65535) {
      return l10n.portInvalidError;
    }
    return null;
  }

  String? requestRetriesValidationError(KickLocalizations l10n) {
    final value = requestRetriesController.text.trim();
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 0 || parsed > 20) {
      return l10n.requestRetriesInvalidError;
    }
    return null;
  }

  String? retry429DelayValidationError(KickLocalizations l10n) {
    final value = retry429DelayController.text.trim();
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 1 || parsed > 3600) {
      return l10n.retry429DelayInvalidError;
    }
    return null;
  }

  String? logRetentionValidationError(KickLocalizations l10n) {
    final value = logRetentionController.text.trim();
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < minLogRetentionCount || parsed > maxLogRetentionCount) {
      return l10n.logRetentionInvalidError(minLogRetentionCount, maxLogRetentionCount);
    }
    return null;
  }

  Future<String> regenerateApiKey() async {
    _saveDebounce?.cancel();
    final apiKey = await _regenerateApiKey();
    final currentSettings = _syncedSettings;
    if (currentSettings != null) {
      _syncedSettings = currentSettings.copyWith(apiKey: apiKey);
    }
    _isHydrating = true;
    apiKeyController.text = apiKey;
    _isHydrating = false;
    _presentSaveStatus(SettingsDraftSaveState.saved, hideAfter: const Duration(seconds: 2));
    return apiKey;
  }

  void saveImmediately() {
    _saveDebounce?.cancel();
    if (_hasBlockingValidationErrors()) {
      _presentSaveStatus(SettingsDraftSaveState.validationError);
      return;
    }
    _presentSaveStatus(SettingsDraftSaveState.saving);
    unawaited(_persistSettings());
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _saveStatusHideTimer?.cancel();
    hostController.dispose();
    portController.dispose();
    apiKeyController.dispose();
    requestRetriesController.dispose();
    retry429DelayController.dispose();
    logRetentionController.dispose();
    customModelsController.dispose();
    super.dispose();
  }

  void _hydrateFromSettings(AppSettings settings) {
    _isHydrating = true;
    hostController.text = settings.host;
    portController.text = settings.port.toString();
    apiKeyController.text = settings.apiKey;
    requestRetriesController.text = settings.requestMaxRetries.toString();
    retry429DelayController.text = settings.retry429DelaySeconds.toString();
    logRetentionController.text = settings.logRetentionCount.toString();
    customModelsController.text = settings.customModels.join('\n');
    _apiKeyRequired = settings.apiKeyRequired;
    _appLocale = settings.appLocale;
    _themeMode = settings.themeMode;
    _verbosity = settings.loggingVerbosity;
    _useDynamicColor = settings.useDynamicColor;
    _allowLan = settings.allowLan;
    _androidBackgroundRuntime = settings.androidBackgroundRuntime;
    _windowsLaunchAtStartup = settings.windowsLaunchAtStartup;
    _mark429AsUnhealthy = settings.mark429AsUnhealthy;
    _unsafeRawLoggingEnabled = settings.unsafeRawLoggingEnabled;
    _defaultGoogleWebSearchEnabled = settings.defaultGoogleWebSearchEnabled;
    _renderGoogleGroundingInMessage = settings.renderGoogleGroundingInMessage;
    _saveState = SettingsDraftSaveState.saved;
    _saveError = null;
    _showSaveStatus = false;
    _initialized = true;
    _isHydrating = false;
  }

  void _handleTextSettingsChanged() {
    if (!_initialized || _isHydrating) {
      return;
    }
    if (_hasBlockingValidationErrors()) {
      _saveDebounce?.cancel();
      _presentSaveStatus(SettingsDraftSaveState.validationError);
      return;
    }
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _presentSaveStatus(SettingsDraftSaveState.saving);
    _saveDebounce = Timer(saveDebounceDuration, () {
      unawaited(_persistSettings());
    });
  }

  Future<void> _persistSettings() async {
    final currentSettings = _syncedSettings;
    if (currentSettings == null) {
      return;
    }

    final updated = currentSettings.copyWith(
      appLocale: _appLocale,
      themeMode: _themeMode,
      useDynamicColor: _useDynamicColor,
      host: hostController.text.trim(),
      port: int.parse(portController.text.trim()),
      allowLan: _allowLan,
      androidBackgroundRuntime: _androidBackgroundRuntime,
      windowsLaunchAtStartup: _windowsLaunchAtStartup,
      requestMaxRetries: int.parse(requestRetriesController.text.trim()),
      retry429DelaySeconds: int.parse(retry429DelayController.text.trim()),
      logRetentionCount: int.parse(logRetentionController.text.trim()),
      mark429AsUnhealthy: _mark429AsUnhealthy,
      defaultGoogleWebSearchEnabled: _defaultGoogleWebSearchEnabled,
      renderGoogleGroundingInMessage: _renderGoogleGroundingInMessage,
      loggingVerbosity: _verbosity,
      unsafeRawLoggingEnabled: _unsafeRawLoggingEnabled,
      apiKeyRequired: _apiKeyRequired,
      apiKey: apiKeyController.text.trim().isEmpty
          ? currentSettings.apiKey
          : apiKeyController.text.trim(),
      customModels: customModelsController.text
          .split('\n')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );

    if (_settingsEqual(currentSettings, updated)) {
      _saveError = null;
      _showSaveStatus = false;
      notifyListeners();
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
        await _saveSettings(nextSettings);
        _syncedSettings = nextSettings;
      }
      _presentSaveStatus(SettingsDraftSaveState.saved, hideAfter: const Duration(seconds: 2));
    } catch (error) {
      _presentSaveStatus(SettingsDraftSaveState.error, error: error);
    } finally {
      _saveInFlight = false;
      final idleCompleter = _idleCompleter;
      if (idleCompleter != null && !idleCompleter.isCompleted) {
        idleCompleter.complete();
      }
      _idleCompleter = null;
    }
  }

  void _presentSaveStatus(SettingsDraftSaveState state, {Object? error, Duration? hideAfter}) {
    _saveStatusHideTimer?.cancel();
    _saveState = state;
    _saveError = error;
    _showSaveStatus = true;
    notifyListeners();

    if (hideAfter != null) {
      _saveStatusHideTimer = Timer(hideAfter, () {
        _showSaveStatus = false;
        notifyListeners();
      });
    }
  }

  bool _hasBlockingValidationErrors() {
    return hostController.text.trim().isEmpty ||
        RegExp(r'\s').hasMatch(hostController.text.trim()) ||
        (hostController.text.trim() == '0.0.0.0' && !_allowLan) ||
        !_isValidPort(portController.text.trim()) ||
        !_isValidRequestRetries(requestRetriesController.text.trim()) ||
        !_isValidRetry429Delay(retry429DelayController.text.trim()) ||
        !_isValidLogRetention(logRetentionController.text.trim());
  }

  bool _isValidPort(String value) {
    final parsed = int.tryParse(value);
    return parsed != null && parsed >= 1 && parsed <= 65535;
  }

  bool _isValidRequestRetries(String value) {
    final parsed = int.tryParse(value);
    return parsed != null && parsed >= 0 && parsed <= 20;
  }

  bool _isValidRetry429Delay(String value) {
    final parsed = int.tryParse(value);
    return parsed != null && parsed >= 1 && parsed <= 3600;
  }

  bool _isValidLogRetention(String value) {
    final parsed = int.tryParse(value);
    return parsed != null && parsed >= minLogRetentionCount && parsed <= maxLogRetentionCount;
  }

  bool _settingsEqual(AppSettings left, AppSettings right) {
    return left.apiKey == right.apiKey &&
        left.apiKeyRequired == right.apiKeyRequired &&
        left.appLocale == right.appLocale &&
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
        left.retry429DelaySeconds == right.retry429DelaySeconds &&
        left.mark429AsUnhealthy == right.mark429AsUnhealthy &&
        left.defaultGoogleWebSearchEnabled == right.defaultGoogleWebSearchEnabled &&
        left.renderGoogleGroundingInMessage == right.renderGoogleGroundingInMessage &&
        left.loggingVerbosity == right.loggingVerbosity &&
        left.logRetentionCount == right.logRetentionCount &&
        left.unsafeRawLoggingEnabled == right.unsafeRawLoggingEnabled &&
        listEquals(left.customModels, right.customModels);
  }
}
