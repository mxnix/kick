// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'KiCk';

  @override
  String get shellSubtitle => 'Local proxy for Gemini CLI and Kiro';

  @override
  String get connectGoogleAccountTitle => 'Connect Google account';

  @override
  String get homeTitle => 'Home';

  @override
  String get proxyRunningStatus => 'Running';

  @override
  String get proxyStoppedStatus => 'Stopped';

  @override
  String get embeddedProxyTitle => 'Proxy server';

  @override
  String proxyAddress(String host, int port) {
    return 'Address: $host:$port';
  }

  @override
  String get proxyEndpointTitle => 'Proxy address';

  @override
  String activeAccounts(int count) {
    return 'Active accounts: $count';
  }

  @override
  String get stopProxyButton => 'Stop';

  @override
  String get startProxyButton => 'Start';

  @override
  String get openAccountsButton => 'Open accounts window';

  @override
  String get connectAccountShortButton => 'Connect account';

  @override
  String get uptimeTitle => 'Uptime';

  @override
  String get uptimeNotStarted => 'Not started yet';

  @override
  String uptimeValue(int hours, int minutes, int seconds) {
    return '$hours h $minutes min $seconds sec';
  }

  @override
  String get versionTitle => 'Version';

  @override
  String get apiKeyTitle => 'API key';

  @override
  String get apiKeyDisabledValue => 'Not required';

  @override
  String get changeApiKeyLinkLabel => 'Change API key';

  @override
  String get loadingValue => 'Loading...';

  @override
  String get lastErrorTitle => 'Last error';

  @override
  String get openLogsButton => 'Open logs';

  @override
  String get accountsTitle => 'Accounts';

  @override
  String get accountsSubtitle => 'Connect Gemini CLI and Kiro accounts and manage them';

  @override
  String get accountsSearchHint => 'Search by name, email, or project ID';

  @override
  String get accountsSortLabel => 'Sort by';

  @override
  String get accountsSortAttention => 'Attention';

  @override
  String get accountsSortPriority => 'Priority';

  @override
  String get accountsSortAlphabetical => 'Name';

  @override
  String get accountsSortRecentActivity => 'Recent activity';

  @override
  String get addButton => 'Add';

  @override
  String get accountsEmptyTitle => 'No accounts yet';

  @override
  String get accountsEmptyMessage => 'Connect at least one Gemini CLI or Kiro account';

  @override
  String get connectAccountButton => 'Connect account';

  @override
  String get connectAccountDialogTitle => 'Connect account';

  @override
  String get connectAccountProviderPickerTitle => 'Select provider';

  @override
  String get accountsLoadErrorTitle => 'Failed to load accounts';

  @override
  String accountsTotalCount(int count) {
    return 'Total: $count';
  }

  @override
  String accountsFilteredCount(int count) {
    return 'Shown: $count';
  }

  @override
  String get accountsFilteredEmptyTitle => 'No accounts matched the search';

  @override
  String get accountsFilteredEmptyMessage => 'Try another name, email, or project ID.';

  @override
  String get accountProviderLabel => 'Account type';

  @override
  String get accountProviderGemini => 'Gemini CLI';

  @override
  String get accountProviderGeminiCli => 'Gemini CLI';

  @override
  String get accountProviderKiro => 'Kiro';

  @override
  String get kiroBuilderIdStartUrlLabel => 'Builder ID URL';

  @override
  String get kiroBuilderIdStartUrlHelperText => 'You usually don\'t need to change this.';

  @override
  String get kiroRegionLabel => 'AWS region';

  @override
  String get kiroRegionHelperText => 'Usually keep us-east-1.';

  @override
  String kiroCredentialSourceChip(String value) {
    return 'Source: $value';
  }

  @override
  String projectIdChip(String projectId) {
    return 'PROJECT_ID: $projectId';
  }

  @override
  String get projectIdAutoChip => 'PROJECT_ID: auto';

  @override
  String priorityChip(String priorityLabel) {
    return 'Priority: $priorityLabel';
  }

  @override
  String get accountCoolingDownStatus => 'Cooling down';

  @override
  String get accountReadyStatus => 'Ready';

  @override
  String get accountDisabledStatus => 'Disabled';

  @override
  String unsupportedModelsList(String models) {
    return 'Do not use for models: $models';
  }

  @override
  String get editAccountTitle => 'Edit account';

  @override
  String get editButton => 'Edit';

  @override
  String get reauthorizeAccountTitle => 'Reconnect account';

  @override
  String get reauthorizeButton => 'Reconnect';

  @override
  String get accountProjectCheckButton => 'Check project access';

  @override
  String get accountProjectCheckInProgressMessage => 'Checking...';

  @override
  String get accountProjectCheckSuccessTitle => 'Project access confirmed';

  @override
  String get accountProjectCheckSuccessMessage =>
      'KiCk successfully made a test request to Google for this account and project';

  @override
  String accountProjectCheckModelValue(String model) {
    return 'Model: $model';
  }

  @override
  String accountProjectCheckTraceIdValue(String traceId) {
    return 'Trace ID: $traceId';
  }

  @override
  String get accountProjectCheckFailureTitle => 'Check failed';

  @override
  String get resetCooldownTooltip => 'Reset status';

  @override
  String get clearCooldownAction => 'Clear cooldown';

  @override
  String get deleteTooltip => 'Delete';

  @override
  String get accountUsageOpenTooltip => 'Quotas';

  @override
  String get moreButton => 'More';

  @override
  String get deleteAccountDialogTitle => 'Delete account?';

  @override
  String deleteAccountDialogMessage(String label) {
    return 'Account $label will be removed from KiCk. You can reconnect it later if needed.';
  }

  @override
  String get deleteAccountConfirmButton => 'Delete account';

  @override
  String get accountUsageTitle => 'Account quotas';

  @override
  String get accountUsageProviderLabel => 'Gemini CLI authorization (OAuth)';

  @override
  String get accountUsageRefreshTooltip => 'Refresh';

  @override
  String get accountUsageStatusHealthy => 'Available';

  @override
  String get accountUsageStatusCoolingDown => 'Limited';

  @override
  String get accountUsageStatusLowQuota => 'Running low';

  @override
  String get accountUsageStatusDisabled => 'Disabled';

  @override
  String get accountQuotaWarningStatus => 'Running low';

  @override
  String get accountBanCheckPendingStatus => 'Checking ban status';

  @override
  String get accountBanCheckPendingMessage =>
      'Google returned RESOURCE_EXHAUSTED without a reset time';

  @override
  String get accountTermsOfServiceStatus => 'Ban confirmed';

  @override
  String get accountTermsOfServiceMessage =>
      'Google confirmed this account was blocked for violating the ToS. The account has been removed from rotation.';

  @override
  String get accountUsageLoadErrorTitle => 'Failed to load quota data';

  @override
  String get accountUsageRetryButton => 'Retry';

  @override
  String get accountUsageVerifyAccountButton => 'Verify in Google';

  @override
  String get accountSubmitAppealButton => 'Submit appeal';

  @override
  String get openGoogleCloudButton => 'Open Google Cloud';

  @override
  String get accountUsageVerificationOpenFailedMessage =>
      'Failed to open the verification page in Google';

  @override
  String get accountErrorActionOpenFailedMessage => 'Failed to open the Google page';

  @override
  String get accountUsageEmptyTitle => 'Quota data unavailable';

  @override
  String get accountUsageEmptyMessage => 'Google did not provide quota data for this account';

  @override
  String get accountUsageUnavailableTitle => 'Quotas are unavailable for this account';

  @override
  String get accountUsageUnavailableMessage =>
      'The quotas page currently works only for Gemini CLI accounts.';

  @override
  String get accountUsageMissingTitle => 'Account not found';

  @override
  String get accountUsageMissingSubtitle => 'Quota information';

  @override
  String get accountUsageMissingMessage =>
      'The account may already have been deleted, or the list has not refreshed yet';

  @override
  String accountUsageResetsAt(String time) {
    return 'Resets at $time';
  }

  @override
  String get accountUsageResetUnknown => 'The next reset time is unknown';

  @override
  String accountUsageLastUpdated(String time) {
    return 'Data updated: $time';
  }

  @override
  String accountUsageModelCount(int count) {
    return 'Models: $count';
  }

  @override
  String accountUsageAttentionCount(int count) {
    return 'Low remaining: $count';
  }

  @override
  String accountUsageCriticalCount(int count) {
    return 'Nearly exhausted: $count';
  }

  @override
  String accountUsageHealthyCount(int count) {
    return 'Healthy: $count';
  }

  @override
  String accountUsageTokenType(String value) {
    return 'Quota type: $value';
  }

  @override
  String accountUsageUsedPercent(String value) {
    return 'Used $value%';
  }

  @override
  String get accountUsageBucketHealthy => 'Enough';

  @override
  String get accountUsageBucketLow => 'Running low';

  @override
  String get accountUsageBucketCritical => 'Nearly exhausted';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSubtitle => 'Network, appearance, API key, and proxy behavior';

  @override
  String get languageLabel => 'Language';

  @override
  String get languageHelperText => 'System follows your device language';

  @override
  String get languageOptionSystem => 'System';

  @override
  String get languageOptionEnglish => 'English';

  @override
  String get languageOptionRussian => 'Russian';

  @override
  String get themeLabel => 'Theme';

  @override
  String get themeModeSystem => 'System';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get dynamicThemeTitle => 'Dynamic theme';

  @override
  String get dynamicThemeSubtitle => 'Use system dynamic colors';

  @override
  String get settingsAppearanceSectionTitle => 'Appearance and behavior';

  @override
  String get settingsAppearanceSectionSummary => 'Language, theme, logs, and app behavior';

  @override
  String get settingsNetworkSectionTitle => 'Network';

  @override
  String get settingsNetworkSectionSummary => 'Host, port, and local network access';

  @override
  String get settingsReliabilitySectionTitle => 'Retries and limits';

  @override
  String get settingsReliabilitySectionSummary => 'Auto-retries and handling API limits';

  @override
  String get settingsAccessSectionTitle => 'Access and startup';

  @override
  String get settingsAccessSectionSummary => 'API key and app startup';

  @override
  String get apiKeyRequiredTitle => 'Require API key';

  @override
  String get apiKeyRequiredSubtitle =>
      'If disabled, requests will be accepted without a Bearer token';

  @override
  String get windowsTrayTitle => 'Minimize to tray';

  @override
  String get windowsTraySubtitle =>
      'Closing the window will not stop KiCk, it will hide it to the system tray';

  @override
  String get windowsLaunchAtStartupTitle => 'Launch with Windows';

  @override
  String get windowsLaunchAtStartupSubtitle => 'KiCk will start automatically when you sign in';

  @override
  String get windowsTrayNotificationTitle => 'KiCk is still running';

  @override
  String get windowsTrayNotificationBody => 'The app has been minimized to the system tray';

  @override
  String get settingsModelsSectionTitle => 'Models';

  @override
  String get settingsModelsSectionSummary => 'Custom model IDs';

  @override
  String get settingsGoogleSectionTitle => 'Google Search (Gemini CLI only)';

  @override
  String get settingsGoogleSectionSummary => 'Google web search and Gemini CLI settings';

  @override
  String get settingsBackupSectionTitle => 'Backup and restore';

  @override
  String get settingsBackupSectionSummary => 'Transfer settings and accounts between devices';

  @override
  String get settingsBackupInfoTitle =>
      'The backup will include settings, the API key, and OAuth tokens';

  @override
  String get settingsBackupInfoSubtitle =>
      'Keep the file in a safe place! Restoring will completely replace your current settings and account list.';

  @override
  String get hostLabel => 'Host';

  @override
  String get hostHelperText => 'Usually localhost';

  @override
  String get hostRequiredError => 'Enter a host address';

  @override
  String get hostInvalidError => 'The address must not contain spaces';

  @override
  String get hostLanDisabledError => 'To use 0.0.0.0, enable local network access';

  @override
  String get portLabel => 'Port';

  @override
  String get portHelperText => 'Default is 3000';

  @override
  String get portInvalidError => 'Enter a port from 1 to 65535';

  @override
  String get allowLanTitle => 'Local network and Docker access';

  @override
  String get allowLanSubtitle =>
      'The proxy will listen on 0.0.0.0 and be accessible from the local network and containers';

  @override
  String get androidBackgroundRuntimeTitle => 'Background operation on Android';

  @override
  String get androidBackgroundRuntimeSubtitle =>
      'Required so the proxy does not stop when the app is minimized';

  @override
  String get requestRetriesLabel => 'Number of request retries to Google';

  @override
  String get requestRetriesHelperText =>
      'How many times KiCk will retry a request after a temporary error';

  @override
  String get requestRetriesInvalidError => 'Enter a number from 0 to 20';

  @override
  String get retry429DelayLabel => 'Retry interval for 429';

  @override
  String get retry429DelayHelperText =>
      'The interval at which the proxy retries a request after a 429 error';

  @override
  String get retry429DelayInvalidError => 'Enter a number from 1 to 3600';

  @override
  String get mark429AsUnhealthyTitle =>
      'Temporarily remove the account from rotation on a 429 error';

  @override
  String get mark429AsUnhealthySubtitle =>
      'After a 429 error, KiCk will mark the account as temporarily unavailable and switch to another one';

  @override
  String get loggingLabel => 'Logging';

  @override
  String get loggingQuiet => 'Minimal';

  @override
  String get loggingNormal => 'Standard';

  @override
  String get loggingVerbose => 'Verbose';

  @override
  String get logRetentionLabel => 'Log entry limit';

  @override
  String get logRetentionHelperText =>
      'When the limit is reached, the oldest entries will be removed automatically';

  @override
  String logRetentionInvalidError(int min, int max) {
    return 'Enter a number from $min to $max';
  }

  @override
  String get unsafeRawLoggingTitle => 'Raw debug logs';

  @override
  String get unsafeRawLoggingSubtitle =>
      'Stores the contents of requests and responses. Enable only for debugging!';

  @override
  String get defaultGoogleWebSearchTitle => 'Enable web search by default';

  @override
  String get defaultGoogleWebSearchSubtitle =>
      'KiCk will automatically use Google Search if the client did not explicitly override parameters and the request contains no function calls';

  @override
  String get renderGoogleGroundingInMessageTitle => 'Show citations and sources in the response';

  @override
  String get renderGoogleGroundingInMessageSubtitle =>
      'If disabled, source links will remain in metadata and will not be added to the response text itself';

  @override
  String get customModelsLabel => 'Custom model IDs';

  @override
  String get customModelsHelperText => 'One ID per line, for example google/... or kiro/...';

  @override
  String get settingsSavingStatus => 'Saving changes...';

  @override
  String get settingsSavedStatus => 'Changes saved';

  @override
  String get settingsValidationStatus => 'Check the fields with errors';

  @override
  String get settingsSaveFailedStatus => 'Failed to save changes';

  @override
  String get settingsBackupExportButton => 'Save backup';

  @override
  String get settingsBackupImportButton => 'Restore backup';

  @override
  String get settingsBackupExportOptionsDialogTitle => 'Export backup';

  @override
  String get settingsBackupExportDialogTitle => 'Where should the backup be saved?';

  @override
  String get settingsBackupImportDialogTitle => 'Select a backup file';

  @override
  String get settingsBackupExportConfirmButton => 'Continue';

  @override
  String get settingsBackupProtectWithPasswordLabel =>
      'Protect the file with a password (recommended)';

  @override
  String get settingsBackupProtectWithPasswordSubtitle =>
      'Encrypts the backup so tokens and keys cannot be read without the password';

  @override
  String get settingsBackupPasswordLabel => 'Password';

  @override
  String get settingsBackupPasswordConfirmLabel => 'Confirm password';

  @override
  String get settingsBackupPasswordHelperText =>
      'Remember this password: without it, the encrypted backup cannot be restored!';

  @override
  String get settingsBackupPasswordsDoNotMatch => 'Passwords do not match';

  @override
  String get settingsBackupUnprotectedWarning =>
      'Warning! Your tokens and keys will be saved in plain text. Anyone who gets this file will gain access to your data.';

  @override
  String get settingsBackupRestoreDialogTitle => 'Restore configuration?';

  @override
  String get settingsBackupRestoreDialogMessage =>
      'Current settings, the API key, and the account list will be replaced with data from this backup. This action cannot be undone.';

  @override
  String get settingsBackupRestoreConfirmButton => 'Restore';

  @override
  String get settingsBackupPasswordDialogTitle => 'Enter the backup password';

  @override
  String settingsBackupPasswordDialogMessage(String fileName) {
    return 'The file $fileName is password-protected. Enter the password to continue restoring.';
  }

  @override
  String settingsBackupPasswordDialogInvalidMessage(String fileName) {
    return 'Failed to decrypt the file $fileName. Check the password and try again.';
  }

  @override
  String get settingsBackupPasswordConfirmButton => 'Decrypt';

  @override
  String settingsBackupExportedMessage(String fileName) {
    return 'Backup saved to file $fileName';
  }

  @override
  String settingsBackupRestoredMessage(int accountCount) {
    return 'Configuration restored. Accounts: $accountCount';
  }

  @override
  String settingsBackupRestoredMissingTokensMessage(int accountCount, int missingCount) {
    return 'Configuration restored. Accounts: $accountCount, without tokens: $missingCount';
  }

  @override
  String settingsBackupExportFailedMessage(String error) {
    return 'Failed to save backup: $error';
  }

  @override
  String settingsBackupRestoreFailedMessage(String error) {
    return 'Failed to restore backup: $error';
  }

  @override
  String get settingsBackupInvalidMessage =>
      'The backup file is corrupted or has an unsupported format';

  @override
  String get settingsBackupUnsupportedVersionMessage =>
      'This backup was created in a newer version of KiCk and is not supported yet';

  @override
  String get settingsBackupReadFailedMessage => 'Failed to read the selected backup';

  @override
  String get settingsBackupPasswordRequiredMessage => 'A password is required for this backup';

  @override
  String get settingsLoadErrorTitle => 'Failed to load settings';

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutMenuSubtitle => 'Version, updates, and analytics';

  @override
  String get aboutDescription =>
      'A local OpenAI-compatible proxy for Gemini CLI and Kiro in a native Flutter app';

  @override
  String get aboutUpdatesTitle => 'Updates';

  @override
  String get aboutUpdatesChecking => 'Checking for updates on GitHub...';

  @override
  String get aboutUpdateAvailableTitle => 'Update available';

  @override
  String aboutUpdateAvailableMessage(String latestVersion, String currentVersion) {
    return 'Version $latestVersion is available. You currently have $currentVersion installed.';
  }

  @override
  String get aboutUpToDateTitle => 'Up to date';

  @override
  String aboutUpToDateMessage(String currentVersion) {
    return 'You have the latest version installed: $currentVersion.';
  }

  @override
  String get aboutUpdateCheckFailedTitle => 'Failed to check for updates';

  @override
  String get aboutUpdateCheckFailedMessage => 'Failed to get release information from GitHub.';

  @override
  String get aboutDownloadAndInstallButton => 'Download and install';

  @override
  String get aboutOpenReleaseButton => 'Open release';

  @override
  String get aboutRetryUpdateCheckButton => 'Check again';

  @override
  String get aboutAnalyticsTitle => 'Analytics';

  @override
  String get aboutAnalyticsSubtitle => 'Anonymous usage statistics help improve KiCk.';

  @override
  String get copyProxyEndpointTooltip => 'Copy proxy address';

  @override
  String get proxyEndpointCopiedMessage => 'Proxy address copied';

  @override
  String get copyApiKeyTooltip => 'Copy API key';

  @override
  String get apiKeyCopiedMessage => 'API key copied';

  @override
  String get homeOnboardingTitle => 'Getting started';

  @override
  String get homeOnboardingSubtitle => 'A quick guide for the first launch';

  @override
  String get homeOnboardingAccountsTitle => 'Connect an account';

  @override
  String get homeOnboardingAccountsMessage =>
      'Without an active Gemini CLI or Kiro account, KiCk will not be able to process requests.';

  @override
  String get homeOnboardingEndpointTitle => 'Check the proxy address';

  @override
  String homeOnboardingEndpointMessage(String endpoint) {
    return 'When everything is ready, use the address $endpoint in your client.';
  }

  @override
  String get homeOnboardingStartTitle => 'Start the proxy';

  @override
  String get homeOnboardingStartMessage =>
      'After startup, KiCk will begin accepting requests on this device.';

  @override
  String get homeOnboardingFooter =>
      'If an account is already connected, just enable it on the accounts screen and come back here.';

  @override
  String get apiKeyRegeneratedMessage => 'New API key saved';

  @override
  String get regenerateApiKeyAction => 'Create new API key';

  @override
  String get regenerateApiKeyDialogTitle => 'Create a new API key?';

  @override
  String get regenerateApiKeyDialogMessage =>
      'The old key will be revoked immediately. All connected clients will need the new key to keep working.';

  @override
  String get regenerateApiKeyConfirmButton => 'Generate';

  @override
  String get trayOpenWindowAction => 'Open window';

  @override
  String get trayHideToTrayAction => 'Minimize to tray';

  @override
  String get trayExitAction => 'Exit';

  @override
  String get noActiveAccountsWarning =>
      'No active accounts. The proxy will start, but it will not be able to process requests until you add or enable at least one account.';

  @override
  String get pinWindowTooltip => 'Pin window on top';

  @override
  String get unpinWindowTooltip => 'Unpin window';

  @override
  String get welcomeTitle => 'Welcome to KiCk';

  @override
  String get welcomeSubtitle =>
      'KiCk helps you run a local proxy for Gemini CLI and Kiro without terminal commands or extra setup.';

  @override
  String get welcomeStepAccountsTitle => 'Connect an account';

  @override
  String get welcomeStepAccountsMessage =>
      'You can do this on the accounts screen. You can connect Gemini CLI or Kiro.';

  @override
  String get welcomeStepHomeTitle => 'Open Home';

  @override
  String get welcomeStepHomeMessage =>
      'Home always shows the proxy address, API key, and the start button.';

  @override
  String get welcomeUsageTitle => 'Important to know';

  @override
  String get welcomeUsageMessage => 'KiCk is intended for personal, educational, and research use.';

  @override
  String get welcomeAnalyticsTitle => 'Anonymous analytics';

  @override
  String get welcomeAnalyticsSubtitle =>
      'Helps understand where KiCk works well and where it should be improved.';

  @override
  String get welcomeRepositoryLinkLabel => 'Learn more about the project';

  @override
  String get logsTitle => 'Logs';

  @override
  String get logsSubtitle => 'Request and error history';

  @override
  String get logsSearchHint => 'Search by route or message';

  @override
  String get logsRefreshButton => 'Refresh';

  @override
  String get logsClearButton => 'Clear';

  @override
  String get logsClearDialogTitle => 'Clear logs?';

  @override
  String get logsClearDialogMessage =>
      'All entries will be removed from KiCk. This action cannot be undone.';

  @override
  String get logsClearConfirmButton => 'Clear';

  @override
  String get logsLevelAll => 'All levels';

  @override
  String get logsLevelInfo => 'Info';

  @override
  String get logsLevelWarning => 'Warnings';

  @override
  String get logsLevelError => 'Errors';

  @override
  String get logsCategoryAll => 'All categories';

  @override
  String get logsCategoryFilterTitle => 'Categories';

  @override
  String get logsPayloadShowButton => 'Show payload';

  @override
  String get logsPayloadHideButton => 'Hide payload';

  @override
  String get logsCopyEntryButton => 'Copy';

  @override
  String get logsCopiedMessage => 'Log entry copied';

  @override
  String get logsFilteredEmptyTitle => 'Nothing found for the current filters';

  @override
  String get logsFilteredEmptyMessage => 'Try removing some filters or changing the search.';

  @override
  String get logsEntryLevelInfo => 'Info';

  @override
  String get logsEntryLevelWarning => 'Warning';

  @override
  String get logsEntryLevelError => 'Error';

  @override
  String logsTotalCount(int count) {
    return 'Total: $count';
  }

  @override
  String logsFilteredCount(int count) {
    return 'After filtering: $count';
  }

  @override
  String logsLoadedCount(int count) {
    return 'Loaded: $count';
  }

  @override
  String get logsEmptyTitle => 'Logs are empty';

  @override
  String get logsLoadErrorTitle => 'Failed to load logs';

  @override
  String get logsExportTooltip => 'Save all logs for the current filters';

  @override
  String get logsExportDialogTitle => 'Where should the logs be saved?';

  @override
  String get logsShareTooltip => 'Share all logs for the current filters';

  @override
  String get logsLoadMoreButton => 'Load more';

  @override
  String get logsNothingToExportMessage => 'No logs to save';

  @override
  String logsExportedMessage(String fileName) {
    return 'Logs saved to file $fileName';
  }

  @override
  String logsExportFailedMessage(String error) {
    return 'Failed to save logs: $error';
  }

  @override
  String logsShareFailedMessage(String error) {
    return 'Failed to share logs: $error';
  }

  @override
  String get logsExportFileTitle => 'KiCk log export';

  @override
  String get logsExportShareSubject => 'KiCk logs';

  @override
  String get logsExportGeneratedAtLabel => 'Generated at';

  @override
  String logsExportEntriesCount(int count) {
    return 'Entries: $count';
  }

  @override
  String get logsExportSectionEnvironment => 'Environment';

  @override
  String get logsExportAppLabel => 'App';

  @override
  String get logsExportFiltersLabel => 'Filters';

  @override
  String get logsExportScopeLabel => 'Scope';

  @override
  String get logsExportRuntimeSettingsLabel => 'Runtime settings';

  @override
  String get logsExportNoneValue => 'none';

  @override
  String get logsExportNoneDetectedValue => 'none detected';

  @override
  String get logsExportSectionDiagnostics => 'Diagnostics summary';

  @override
  String get logsExportTimeRangeLabel => 'Time range';

  @override
  String get logsExportLevelsLabel => 'Levels';

  @override
  String get logsExportCategoriesLabel => 'Categories';

  @override
  String get logsExportRoutesLabel => 'Routes';

  @override
  String get logsExportModelsLabel => 'Models';

  @override
  String get logsExportStatusCodesLabel => 'Status codes';

  @override
  String get logsExportErrorDetailsLabel => 'Error details';

  @override
  String get logsExportUpstreamReasonsLabel => 'Upstream reasons';

  @override
  String get logsExportRetriedRequestsLabel => 'Retried requests';

  @override
  String get logsExportTokensLabel => 'Tokens';

  @override
  String get logsExportAndroidBackgroundSessionsLabel => 'Android background sessions';

  @override
  String get logsExportTimestampLabel => 'Timestamp';

  @override
  String get logsExportLevelLabel => 'Level';

  @override
  String get logsExportCategoryLabel => 'Category';

  @override
  String get logsExportRouteLabel => 'Route';

  @override
  String get logsExportMessageLabel => 'Message';

  @override
  String get logsExportMaskedPayloadLabel => 'Masked payload';

  @override
  String get logsExportRawPayloadLabel => 'Raw payload';

  @override
  String get logMessageRequestReceived => 'Request received';

  @override
  String get logMessageParsedRequest => 'Parsed request';

  @override
  String get logMessageResponseCompleted => 'Response completed';

  @override
  String get logMessageStreamClientAborted => 'Streaming response aborted by client';

  @override
  String get logMessageRetryScheduled => 'Retry scheduled after request failure';

  @override
  String get logMessageRetryWithAnotherAccount =>
      'Retrying with another account after request failure';

  @override
  String get logMessageRequestSucceededAfterRetries => 'Request succeeded after retries';

  @override
  String get logMessageRequestFailedAfterRetries => 'Request failed after retries';

  @override
  String get logMessageDispatchingStreamingRequest =>
      'Dispatching streaming request to upstream provider';

  @override
  String get logMessageDispatchingRequest => 'Dispatching request to upstream provider';

  @override
  String get logMessageUpstreamPayloadReturned => 'Upstream provider returned a payload';

  @override
  String get logMessageMappedChatCompletion => 'Mapped upstream payload to OpenAI chat completion';

  @override
  String logMessageUsingAccountForModel(String account, String model) {
    return 'Using account $account for $model';
  }

  @override
  String get logMessageProxySessionSummary => 'Proxy session summary';

  @override
  String get logMessageAndroidBackgroundSessionStarted => 'Android background session started';

  @override
  String get logMessageAndroidBackgroundSessionEnded => 'Android background session ended';

  @override
  String get logMessageAndroidBackgroundSessionRecovered =>
      'Android background session recovered after process restart';

  @override
  String get accountDialogTitle => 'Account';

  @override
  String get accountDialogBasicsTitle => 'Basics';

  @override
  String get accountDialogBasicsSubtitle => 'Fields for connecting the selected account type';

  @override
  String get accountDialogAdvancedTitle => 'Advanced settings';

  @override
  String get accountDialogAdvancedSubtitle => 'Priority and model restrictions';

  @override
  String get accountDialogAdvancedHint =>
      'If you don\'t want to configure it manually, you can leave this section as is.';

  @override
  String get projectIdLabel => 'PROJECT_ID';

  @override
  String get projectIdHint => 'my-google-cloud-project';

  @override
  String get projectIdConsoleLinkLabel => 'Where to find the project ID';

  @override
  String get projectIdRequiredError => 'Enter a project ID';

  @override
  String get projectIdLookupFailedMessage => 'Failed to open Google Cloud Console.';

  @override
  String get accountNameLabel => 'Account name';

  @override
  String get accountNameHint => 'For example, main account';

  @override
  String get accountNameHelperText =>
      'If you leave this field empty, KiCk will use the account name.';

  @override
  String get priorityLabel => 'Priority';

  @override
  String get priorityHelperText =>
      'Primary accounts are used first. Accounts with the same priority alternate.';

  @override
  String get priorityLevelPrimary => 'Primary';

  @override
  String get priorityLevelNormal => 'Normal';

  @override
  String get priorityLevelReserve => 'Reserve';

  @override
  String get blockedModelsLabel => 'Unavailable models';

  @override
  String get blockedModelsHelperText => 'One ID per line, for example google/... or kiro/...';

  @override
  String get kiroLinkAuthDialogTitle => 'Kiro authorization';

  @override
  String get kiroLinkAuthDialogMessage =>
      'Open the link, sign in with AWS Builder ID, and confirm access for Kiro. The code is only for verification; you do not need to enter it. KiCk will wait for completion automatically.';

  @override
  String get kiroLinkAuthUserCodeLabel => 'Verification code';

  @override
  String get kiroLinkAuthVerificationUrlLabel => 'Sign-in link';

  @override
  String get kiroLinkAuthWaitingMessage => 'Waiting for you to confirm sign-in in the browser...';

  @override
  String get kiroLinkAuthOpenLinkButton => 'Open link';

  @override
  String get kiroLinkAuthOpenLinkAgainButton => 'Open again';

  @override
  String get kiroLinkAuthOpenLinkFailedMessage => 'Failed to open the sign-in link for Kiro.';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get continueButton => 'Continue';

  @override
  String get navHome => 'Home';

  @override
  String get navAccounts => 'Accounts';

  @override
  String get navSettings => 'Settings';

  @override
  String get navLogs => 'Logs';

  @override
  String get runtimeChannelName => 'KiCk proxy in background';

  @override
  String get runtimeChannelDescription => 'Keeps the proxy running in the background';

  @override
  String get runtimeNotificationTitle => 'KiCk proxy is running';

  @override
  String get runtimeNotificationReturn => 'Tap to return to the app';

  @override
  String get runtimeNotificationManage => 'Tap to open accounts and settings';

  @override
  String get runtimeNotificationActive => 'Proxy is active';

  @override
  String get oauthPageTitleError => 'Authorization error';

  @override
  String get oauthPageTitleSuccess => 'Authorization successful';

  @override
  String get oauthPageStateMismatchMessage => 'State mismatch. You can close this tab.';

  @override
  String get oauthPageGoogleErrorMessage => 'Google returned an error. You can close this tab.';

  @override
  String get oauthPageCodeMissingMessage => 'No code received. You can close this tab.';

  @override
  String get oauthPageCloseTabMessage => 'You can close this tab.';

  @override
  String get accountDisplayNameFallbackGoogle => 'Google account';

  @override
  String get errorNetworkUnavailable =>
      'Could not reach Google\'s servers. Check your internet connection and try again.';

  @override
  String get errorGoogleServiceUnavailable =>
      'Google service is temporarily unavailable. Please try again later.';

  @override
  String get errorInvalidServiceResponse =>
      'The server returned an invalid response. Please try again.';

  @override
  String get errorGoogleAuthFailed => 'Google authorization failed. Please try again.';

  @override
  String get errorGoogleAuthTimedOut =>
      'Google authorization did not finish in time. Return to the app and try again. If this keeps happening on Android, disable battery restrictions for KiCk.';

  @override
  String get errorGoogleAuthBrowserOpenFailed =>
      'Failed to open the browser for Google authorization. Please try again.';

  @override
  String get errorUnknown => 'An unknown error occurred. Please try again.';

  @override
  String get errorOauthTokensMissing =>
      'Authorization tokens for this account were not found. Reconnect the account.';

  @override
  String get errorAccountNotFound => 'Account not found. It may already have been deleted.';

  @override
  String get errorPortAlreadyInUse =>
      'This port is already in use by another app. Choose a different port in settings.';

  @override
  String get errorPermissionDenied =>
      'The app does not have the required system permissions to start. Check app settings and try again.';

  @override
  String errorGoogleRateLimitedRetry(String retryHint) {
    return 'Google has temporarily rate-limited requests for this account. Try again in $retryHint.';
  }

  @override
  String get errorGoogleRateLimitedLater =>
      'Google has temporarily rate-limited requests for this account. Try again later.';

  @override
  String get errorKiroAuthExpired => 'Kiro session expired. Sign in again and try again.';

  @override
  String get errorKiroAuthStartFailed =>
      'Failed to start Kiro authorization. Please try again later.';

  @override
  String get errorKiroAuthCancelled => 'Kiro authorization was canceled.';

  @override
  String get errorKiroAuthTimedOut => 'Kiro authorization timed out. Please try again.';

  @override
  String get errorKiroAuthRejected =>
      'Kiro rejected the authorization. Try starting sign-in again.';

  @override
  String errorKiroRateLimitedRetry(String retryHint) {
    return 'Kiro has temporarily rate-limited requests. Try again in $retryHint.';
  }

  @override
  String get errorKiroRateLimitedLater =>
      'Kiro has temporarily rate-limited requests. Try again later.';

  @override
  String get errorKiroServiceUnavailable =>
      'Kiro service is temporarily unavailable. Please try again later.';

  @override
  String get errorGoogleAccountVerificationRequired =>
      'Google asks you to verify this account. Open the verification page and sign in with the same Google account.';

  @override
  String get errorGoogleProjectIdMissing =>
      'Google could not determine a valid project ID for this account or request. Check the project ID in the account settings and reconnect the account if necessary.';

  @override
  String get errorGoogleProjectApiDisabled =>
      'Gemini for Google Cloud API is disabled for this project. Open Google Cloud, enable the API for the correct project ID, and run the check again.';

  @override
  String get errorGoogleProjectInvalid =>
      'Google rejected this project ID. Make sure you entered an existing project and that the account has access to it.';

  @override
  String get errorGoogleProjectAccessDenied =>
      'Google rejected the request for this project or account. Check the project ID and selected account, and make sure Gemini Code Assist is enabled for this project.';

  @override
  String get errorAuthExpired =>
      'Authorization has expired or is no longer valid. Reconnect the account and try again.';

  @override
  String get errorGoogleCapacity =>
      'Google servers are temporarily overloaded. Please try again a little later.';

  @override
  String get errorUnsupportedModel =>
      'The selected model is currently unavailable for this account.';

  @override
  String get errorInvalidJson => 'The request has an invalid JSON format.';

  @override
  String get errorUnexpectedResponse =>
      'The service returned an unexpected response. Please try again.';

  @override
  String get errorQuotaExhausted =>
      'This account\'s quota has been exhausted. Wait for a reset or use another account.';

  @override
  String errorQuotaExhaustedRetry(String retryHint) {
    return 'This account\'s quota has been exhausted. Try again in $retryHint or use another account.';
  }

  @override
  String get errorQuotaExhaustedNoResetHint =>
      'Google returned RESOURCE_EXHAUSTED without a reset time. KiCk will check this account separately; if the error repeats, use another account';

  @override
  String get errorGoogleTermsOfServiceViolation =>
      'Google disabled this account for violating the ToS. Submit an appeal or use another account.';

  @override
  String get errorInvalidRequestRejected => 'The request has an invalid format and was rejected.';

  @override
  String get errorReasoningConfigRejected =>
      'Google rejected the reasoning/thinking parameters for this model. Enable automatic reasoning mode.';

  @override
  String get durationFewSeconds => 'a few seconds';

  @override
  String durationSeconds(int seconds) {
    return '$seconds sec';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String durationMinutesSeconds(int minutes, int seconds) {
    return '$minutes min $seconds sec';
  }

  @override
  String durationHours(int hours) {
    return '$hours h';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
  }
}
