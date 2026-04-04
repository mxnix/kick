import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('ru')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'KiCk'**
  String get appTitle;

  /// No description provided for @shellSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Local proxy for Gemini CLI and Kiro'**
  String get shellSubtitle;

  /// No description provided for @connectGoogleAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect Google account'**
  String get connectGoogleAccountTitle;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTitle;

  /// No description provided for @proxyRunningStatus.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get proxyRunningStatus;

  /// No description provided for @proxyStoppedStatus.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get proxyStoppedStatus;

  /// No description provided for @embeddedProxyTitle.
  ///
  /// In en, this message translates to:
  /// **'Proxy server'**
  String get embeddedProxyTitle;

  /// No description provided for @proxyAddress.
  ///
  /// In en, this message translates to:
  /// **'Address: {host}:{port}'**
  String proxyAddress(String host, int port);

  /// No description provided for @proxyEndpointTitle.
  ///
  /// In en, this message translates to:
  /// **'Proxy address'**
  String get proxyEndpointTitle;

  /// No description provided for @activeAccounts.
  ///
  /// In en, this message translates to:
  /// **'Active accounts: {count}'**
  String activeAccounts(int count);

  /// No description provided for @stopProxyButton.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stopProxyButton;

  /// No description provided for @startProxyButton.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get startProxyButton;

  /// No description provided for @openAccountsButton.
  ///
  /// In en, this message translates to:
  /// **'Open accounts window'**
  String get openAccountsButton;

  /// No description provided for @connectAccountShortButton.
  ///
  /// In en, this message translates to:
  /// **'Connect account'**
  String get connectAccountShortButton;

  /// No description provided for @uptimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Uptime'**
  String get uptimeTitle;

  /// No description provided for @uptimeNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Not started yet'**
  String get uptimeNotStarted;

  /// No description provided for @uptimeValue.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min {seconds} sec'**
  String uptimeValue(int hours, int minutes, int seconds);

  /// No description provided for @versionTitle.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get versionTitle;

  /// No description provided for @apiKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get apiKeyTitle;

  /// No description provided for @apiKeyDisabledValue.
  ///
  /// In en, this message translates to:
  /// **'Not required'**
  String get apiKeyDisabledValue;

  /// No description provided for @changeApiKeyLinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Change API key'**
  String get changeApiKeyLinkLabel;

  /// No description provided for @loadingValue.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loadingValue;

  /// No description provided for @lastErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Last error'**
  String get lastErrorTitle;

  /// No description provided for @openLogsButton.
  ///
  /// In en, this message translates to:
  /// **'Open logs'**
  String get openLogsButton;

  /// No description provided for @accountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accountsTitle;

  /// No description provided for @accountsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connect Gemini CLI and Kiro accounts and manage them'**
  String get accountsSubtitle;

  /// No description provided for @accountsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name, email, or project ID'**
  String get accountsSearchHint;

  /// No description provided for @accountsSortLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get accountsSortLabel;

  /// No description provided for @accountsSortAttention.
  ///
  /// In en, this message translates to:
  /// **'Attention'**
  String get accountsSortAttention;

  /// No description provided for @accountsSortPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get accountsSortPriority;

  /// No description provided for @accountsSortAlphabetical.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get accountsSortAlphabetical;

  /// No description provided for @accountsSortRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get accountsSortRecentActivity;

  /// No description provided for @addButton.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addButton;

  /// No description provided for @accountsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet'**
  String get accountsEmptyTitle;

  /// No description provided for @accountsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Connect at least one Gemini CLI or Kiro account'**
  String get accountsEmptyMessage;

  /// No description provided for @connectAccountButton.
  ///
  /// In en, this message translates to:
  /// **'Connect account'**
  String get connectAccountButton;

  /// No description provided for @connectAccountDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect account'**
  String get connectAccountDialogTitle;

  /// No description provided for @connectAccountProviderPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Select provider'**
  String get connectAccountProviderPickerTitle;

  /// No description provided for @accountsLoadErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Failed to load accounts'**
  String get accountsLoadErrorTitle;

  /// No description provided for @accountsTotalCount.
  ///
  /// In en, this message translates to:
  /// **'Total: {count}'**
  String accountsTotalCount(int count);

  /// No description provided for @accountsFilteredCount.
  ///
  /// In en, this message translates to:
  /// **'Shown: {count}'**
  String accountsFilteredCount(int count);

  /// No description provided for @accountsFilteredEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No accounts matched the search'**
  String get accountsFilteredEmptyTitle;

  /// No description provided for @accountsFilteredEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Try another name, email, or project ID.'**
  String get accountsFilteredEmptyMessage;

  /// No description provided for @accountProviderLabel.
  ///
  /// In en, this message translates to:
  /// **'Account type'**
  String get accountProviderLabel;

  /// No description provided for @accountProviderGemini.
  ///
  /// In en, this message translates to:
  /// **'Gemini CLI'**
  String get accountProviderGemini;

  /// No description provided for @accountProviderGeminiCli.
  ///
  /// In en, this message translates to:
  /// **'Gemini CLI'**
  String get accountProviderGeminiCli;

  /// No description provided for @accountProviderKiro.
  ///
  /// In en, this message translates to:
  /// **'Kiro'**
  String get accountProviderKiro;

  /// No description provided for @kiroBuilderIdStartUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Builder ID URL'**
  String get kiroBuilderIdStartUrlLabel;

  /// No description provided for @kiroBuilderIdStartUrlHelperText.
  ///
  /// In en, this message translates to:
  /// **'You usually don\'t need to change this.'**
  String get kiroBuilderIdStartUrlHelperText;

  /// No description provided for @kiroRegionLabel.
  ///
  /// In en, this message translates to:
  /// **'AWS region'**
  String get kiroRegionLabel;

  /// No description provided for @kiroRegionHelperText.
  ///
  /// In en, this message translates to:
  /// **'Usually keep us-east-1.'**
  String get kiroRegionHelperText;

  /// No description provided for @kiroCredentialSourceChip.
  ///
  /// In en, this message translates to:
  /// **'Source: {value}'**
  String kiroCredentialSourceChip(String value);

  /// No description provided for @projectIdChip.
  ///
  /// In en, this message translates to:
  /// **'PROJECT_ID: {projectId}'**
  String projectIdChip(String projectId);

  /// No description provided for @projectIdAutoChip.
  ///
  /// In en, this message translates to:
  /// **'PROJECT_ID: auto'**
  String get projectIdAutoChip;

  /// No description provided for @priorityChip.
  ///
  /// In en, this message translates to:
  /// **'Priority: {priorityLabel}'**
  String priorityChip(String priorityLabel);

  /// No description provided for @accountCoolingDownStatus.
  ///
  /// In en, this message translates to:
  /// **'Cooling down'**
  String get accountCoolingDownStatus;

  /// No description provided for @accountReadyStatus.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get accountReadyStatus;

  /// No description provided for @accountDisabledStatus.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get accountDisabledStatus;

  /// No description provided for @unsupportedModelsList.
  ///
  /// In en, this message translates to:
  /// **'Do not use for models: {models}'**
  String unsupportedModelsList(String models);

  /// No description provided for @editAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit account'**
  String get editAccountTitle;

  /// No description provided for @editButton.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editButton;

  /// No description provided for @reauthorizeAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Reconnect account'**
  String get reauthorizeAccountTitle;

  /// No description provided for @reauthorizeButton.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get reauthorizeButton;

  /// No description provided for @accountProjectCheckButton.
  ///
  /// In en, this message translates to:
  /// **'Check project access'**
  String get accountProjectCheckButton;

  /// No description provided for @accountProjectCheckInProgressMessage.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get accountProjectCheckInProgressMessage;

  /// No description provided for @accountProjectCheckSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Project access confirmed'**
  String get accountProjectCheckSuccessTitle;

  /// No description provided for @accountProjectCheckSuccessMessage.
  ///
  /// In en, this message translates to:
  /// **'KiCk successfully made a test request to Google for this account and project'**
  String get accountProjectCheckSuccessMessage;

  /// Shown in the successful project diagnostics dialog after the project check completes.
  ///
  /// In en, this message translates to:
  /// **'Model: {model}'**
  String accountProjectCheckModelValue(String model);

  /// Shown in the successful project diagnostics dialog when Google returns a trace identifier.
  ///
  /// In en, this message translates to:
  /// **'Trace ID: {traceId}'**
  String accountProjectCheckTraceIdValue(String traceId);

  /// No description provided for @accountProjectCheckFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Check failed'**
  String get accountProjectCheckFailureTitle;

  /// No description provided for @resetCooldownTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reset status'**
  String get resetCooldownTooltip;

  /// No description provided for @clearCooldownAction.
  ///
  /// In en, this message translates to:
  /// **'Clear cooldown'**
  String get clearCooldownAction;

  /// No description provided for @deleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteTooltip;

  /// No description provided for @accountUsageOpenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Quotas'**
  String get accountUsageOpenTooltip;

  /// No description provided for @moreButton.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreButton;

  /// No description provided for @deleteAccountDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get deleteAccountDialogTitle;

  /// No description provided for @deleteAccountDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Account {label} will be removed from KiCk. You can reconnect it later if needed.'**
  String deleteAccountDialogMessage(String label);

  /// No description provided for @deleteAccountConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccountConfirmButton;

  /// No description provided for @accountUsageTitle.
  ///
  /// In en, this message translates to:
  /// **'Account quotas'**
  String get accountUsageTitle;

  /// No description provided for @accountUsageProviderLabel.
  ///
  /// In en, this message translates to:
  /// **'Gemini CLI authorization (OAuth)'**
  String get accountUsageProviderLabel;

  /// No description provided for @accountUsageRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get accountUsageRefreshTooltip;

  /// No description provided for @accountUsageStatusHealthy.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get accountUsageStatusHealthy;

  /// No description provided for @accountUsageStatusCoolingDown.
  ///
  /// In en, this message translates to:
  /// **'Limited'**
  String get accountUsageStatusCoolingDown;

  /// No description provided for @accountUsageStatusLowQuota.
  ///
  /// In en, this message translates to:
  /// **'Running low'**
  String get accountUsageStatusLowQuota;

  /// No description provided for @accountUsageStatusDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get accountUsageStatusDisabled;

  /// No description provided for @accountQuotaWarningStatus.
  ///
  /// In en, this message translates to:
  /// **'Running low'**
  String get accountQuotaWarningStatus;

  /// No description provided for @accountBanCheckPendingStatus.
  ///
  /// In en, this message translates to:
  /// **'Checking ban status'**
  String get accountBanCheckPendingStatus;

  /// No description provided for @accountBanCheckPendingMessage.
  ///
  /// In en, this message translates to:
  /// **'Google returned RESOURCE_EXHAUSTED without a reset time'**
  String get accountBanCheckPendingMessage;

  /// No description provided for @accountTermsOfServiceStatus.
  ///
  /// In en, this message translates to:
  /// **'Ban confirmed'**
  String get accountTermsOfServiceStatus;

  /// No description provided for @accountTermsOfServiceMessage.
  ///
  /// In en, this message translates to:
  /// **'Google confirmed this account was blocked for violating the ToS. The account has been removed from rotation.'**
  String get accountTermsOfServiceMessage;

  /// No description provided for @accountUsageLoadErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Failed to load quota data'**
  String get accountUsageLoadErrorTitle;

  /// No description provided for @accountUsageRetryButton.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get accountUsageRetryButton;

  /// No description provided for @accountUsageVerifyAccountButton.
  ///
  /// In en, this message translates to:
  /// **'Verify in Google'**
  String get accountUsageVerifyAccountButton;

  /// No description provided for @accountSubmitAppealButton.
  ///
  /// In en, this message translates to:
  /// **'Submit appeal'**
  String get accountSubmitAppealButton;

  /// No description provided for @openGoogleCloudButton.
  ///
  /// In en, this message translates to:
  /// **'Open Google Cloud'**
  String get openGoogleCloudButton;

  /// No description provided for @accountUsageVerificationOpenFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to open the verification page in Google'**
  String get accountUsageVerificationOpenFailedMessage;

  /// No description provided for @accountErrorActionOpenFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to open the Google page'**
  String get accountErrorActionOpenFailedMessage;

  /// No description provided for @accountUsageEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Quota data unavailable'**
  String get accountUsageEmptyTitle;

  /// No description provided for @accountUsageEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Google did not provide quota data for this account'**
  String get accountUsageEmptyMessage;

  /// No description provided for @accountUsageUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Quotas are unavailable for this account'**
  String get accountUsageUnavailableTitle;

  /// No description provided for @accountUsageUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'The quotas page currently works only for Gemini CLI accounts.'**
  String get accountUsageUnavailableMessage;

  /// No description provided for @accountUsageMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'Account not found'**
  String get accountUsageMissingTitle;

  /// No description provided for @accountUsageMissingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Quota information'**
  String get accountUsageMissingSubtitle;

  /// No description provided for @accountUsageMissingMessage.
  ///
  /// In en, this message translates to:
  /// **'The account may already have been deleted, or the list has not refreshed yet'**
  String get accountUsageMissingMessage;

  /// No description provided for @accountUsageResetsAt.
  ///
  /// In en, this message translates to:
  /// **'Resets at {time}'**
  String accountUsageResetsAt(String time);

  /// No description provided for @accountUsageResetUnknown.
  ///
  /// In en, this message translates to:
  /// **'The next reset time is unknown'**
  String get accountUsageResetUnknown;

  /// No description provided for @accountUsageLastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Data updated: {time}'**
  String accountUsageLastUpdated(String time);

  /// No description provided for @accountUsageModelCount.
  ///
  /// In en, this message translates to:
  /// **'Models: {count}'**
  String accountUsageModelCount(int count);

  /// No description provided for @accountUsageAttentionCount.
  ///
  /// In en, this message translates to:
  /// **'Low remaining: {count}'**
  String accountUsageAttentionCount(int count);

  /// No description provided for @accountUsageCriticalCount.
  ///
  /// In en, this message translates to:
  /// **'Nearly exhausted: {count}'**
  String accountUsageCriticalCount(int count);

  /// No description provided for @accountUsageHealthyCount.
  ///
  /// In en, this message translates to:
  /// **'Healthy: {count}'**
  String accountUsageHealthyCount(int count);

  /// No description provided for @accountUsageTokenType.
  ///
  /// In en, this message translates to:
  /// **'Quota type: {value}'**
  String accountUsageTokenType(String value);

  /// No description provided for @accountUsageUsedPercent.
  ///
  /// In en, this message translates to:
  /// **'Used {value}%'**
  String accountUsageUsedPercent(String value);

  /// No description provided for @accountUsageBucketHealthy.
  ///
  /// In en, this message translates to:
  /// **'Enough'**
  String get accountUsageBucketHealthy;

  /// No description provided for @accountUsageBucketLow.
  ///
  /// In en, this message translates to:
  /// **'Running low'**
  String get accountUsageBucketLow;

  /// No description provided for @accountUsageBucketCritical.
  ///
  /// In en, this message translates to:
  /// **'Nearly exhausted'**
  String get accountUsageBucketCritical;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Network, appearance, API key, and proxy behavior'**
  String get settingsSubtitle;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @languageHelperText.
  ///
  /// In en, this message translates to:
  /// **'System follows your device language'**
  String get languageHelperText;

  /// No description provided for @languageOptionSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageOptionSystem;

  /// No description provided for @languageOptionEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageOptionEnglish;

  /// No description provided for @languageOptionRussian.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get languageOptionRussian;

  /// No description provided for @themeLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeLabel;

  /// No description provided for @themeModeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeModeSystem;

  /// No description provided for @themeModeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeModeLight;

  /// No description provided for @themeModeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeModeDark;

  /// No description provided for @dynamicThemeTitle.
  ///
  /// In en, this message translates to:
  /// **'Dynamic theme'**
  String get dynamicThemeTitle;

  /// No description provided for @dynamicThemeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use system dynamic colors'**
  String get dynamicThemeSubtitle;

  /// No description provided for @settingsAppearanceSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance and behavior'**
  String get settingsAppearanceSectionTitle;

  /// No description provided for @settingsAppearanceSectionSummary.
  ///
  /// In en, this message translates to:
  /// **'Language, theme, logs, and app behavior'**
  String get settingsAppearanceSectionSummary;

  /// No description provided for @settingsNetworkSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get settingsNetworkSectionTitle;

  /// No description provided for @settingsNetworkSectionSummary.
  ///
  /// In en, this message translates to:
  /// **'Host, port, and local network access'**
  String get settingsNetworkSectionSummary;

  /// No description provided for @settingsReliabilitySectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Retries and limits'**
  String get settingsReliabilitySectionTitle;

  /// No description provided for @settingsReliabilitySectionSummary.
  ///
  /// In en, this message translates to:
  /// **'Auto-retries and handling API limits'**
  String get settingsReliabilitySectionSummary;

  /// No description provided for @settingsAccessSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Access and startup'**
  String get settingsAccessSectionTitle;

  /// No description provided for @settingsAccessSectionSummary.
  ///
  /// In en, this message translates to:
  /// **'API key and app startup'**
  String get settingsAccessSectionSummary;

  /// No description provided for @apiKeyRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Require API key'**
  String get apiKeyRequiredTitle;

  /// No description provided for @apiKeyRequiredSubtitle.
  ///
  /// In en, this message translates to:
  /// **'If disabled, requests will be accepted without a Bearer token'**
  String get apiKeyRequiredSubtitle;

  /// No description provided for @windowsTrayTitle.
  ///
  /// In en, this message translates to:
  /// **'Minimize to tray'**
  String get windowsTrayTitle;

  /// No description provided for @windowsTraySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Closing the window will not stop KiCk, it will hide it to the system tray'**
  String get windowsTraySubtitle;

  /// No description provided for @windowsLaunchAtStartupTitle.
  ///
  /// In en, this message translates to:
  /// **'Launch with Windows'**
  String get windowsLaunchAtStartupTitle;

  /// No description provided for @windowsLaunchAtStartupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'KiCk will start automatically when you sign in'**
  String get windowsLaunchAtStartupSubtitle;

  /// No description provided for @windowsTrayNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'KiCk is still running'**
  String get windowsTrayNotificationTitle;

  /// No description provided for @windowsTrayNotificationBody.
  ///
  /// In en, this message translates to:
  /// **'The app has been minimized to the system tray'**
  String get windowsTrayNotificationBody;

  /// No description provided for @settingsModelsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get settingsModelsSectionTitle;

  /// No description provided for @settingsModelsSectionSummary.
  ///
  /// In en, this message translates to:
  /// **'Custom model IDs'**
  String get settingsModelsSectionSummary;

  /// No description provided for @settingsGoogleSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Google Search (Gemini CLI only)'**
  String get settingsGoogleSectionTitle;

  /// No description provided for @settingsGoogleSectionSummary.
  ///
  /// In en, this message translates to:
  /// **'Google web search and Gemini CLI settings'**
  String get settingsGoogleSectionSummary;

  /// No description provided for @settingsBackupSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup and restore'**
  String get settingsBackupSectionTitle;

  /// No description provided for @settingsBackupSectionSummary.
  ///
  /// In en, this message translates to:
  /// **'Transfer settings and accounts between devices'**
  String get settingsBackupSectionSummary;

  /// No description provided for @settingsBackupInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'The backup will include settings, the API key, and OAuth tokens'**
  String get settingsBackupInfoTitle;

  /// No description provided for @settingsBackupInfoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep the file in a safe place! Restoring will completely replace your current settings and account list.'**
  String get settingsBackupInfoSubtitle;

  /// No description provided for @hostLabel.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get hostLabel;

  /// No description provided for @hostHelperText.
  ///
  /// In en, this message translates to:
  /// **'Usually localhost'**
  String get hostHelperText;

  /// No description provided for @hostRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Enter a host address'**
  String get hostRequiredError;

  /// No description provided for @hostInvalidError.
  ///
  /// In en, this message translates to:
  /// **'The address must not contain spaces'**
  String get hostInvalidError;

  /// No description provided for @hostLanDisabledError.
  ///
  /// In en, this message translates to:
  /// **'To use 0.0.0.0, enable local network access'**
  String get hostLanDisabledError;

  /// No description provided for @portLabel.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get portLabel;

  /// No description provided for @portHelperText.
  ///
  /// In en, this message translates to:
  /// **'Default is 3000'**
  String get portHelperText;

  /// No description provided for @portInvalidError.
  ///
  /// In en, this message translates to:
  /// **'Enter a port from 1 to 65535'**
  String get portInvalidError;

  /// No description provided for @allowLanTitle.
  ///
  /// In en, this message translates to:
  /// **'Local network and Docker access'**
  String get allowLanTitle;

  /// No description provided for @allowLanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The proxy will listen on 0.0.0.0 and be accessible from the local network and containers'**
  String get allowLanSubtitle;

  /// No description provided for @androidBackgroundRuntimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Background operation on Android'**
  String get androidBackgroundRuntimeTitle;

  /// No description provided for @androidBackgroundRuntimeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Required so the proxy does not stop when the app is minimized'**
  String get androidBackgroundRuntimeSubtitle;

  /// No description provided for @requestRetriesLabel.
  ///
  /// In en, this message translates to:
  /// **'Number of request retries to Google'**
  String get requestRetriesLabel;

  /// No description provided for @requestRetriesHelperText.
  ///
  /// In en, this message translates to:
  /// **'How many times KiCk will retry a request after a temporary error'**
  String get requestRetriesHelperText;

  /// No description provided for @requestRetriesInvalidError.
  ///
  /// In en, this message translates to:
  /// **'Enter a number from 0 to 20'**
  String get requestRetriesInvalidError;

  /// No description provided for @retry429DelayLabel.
  ///
  /// In en, this message translates to:
  /// **'Retry interval for 429'**
  String get retry429DelayLabel;

  /// No description provided for @retry429DelayHelperText.
  ///
  /// In en, this message translates to:
  /// **'The interval at which the proxy retries a request after a 429 error'**
  String get retry429DelayHelperText;

  /// No description provided for @retry429DelayInvalidError.
  ///
  /// In en, this message translates to:
  /// **'Enter a number from 1 to 3600'**
  String get retry429DelayInvalidError;

  /// No description provided for @mark429AsUnhealthyTitle.
  ///
  /// In en, this message translates to:
  /// **'Temporarily remove the account from rotation on a 429 error'**
  String get mark429AsUnhealthyTitle;

  /// No description provided for @mark429AsUnhealthySubtitle.
  ///
  /// In en, this message translates to:
  /// **'After a 429 error, KiCk will mark the account as temporarily unavailable and switch to another one'**
  String get mark429AsUnhealthySubtitle;

  /// No description provided for @loggingLabel.
  ///
  /// In en, this message translates to:
  /// **'Logging'**
  String get loggingLabel;

  /// No description provided for @loggingQuiet.
  ///
  /// In en, this message translates to:
  /// **'Minimal'**
  String get loggingQuiet;

  /// No description provided for @loggingNormal.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get loggingNormal;

  /// No description provided for @loggingVerbose.
  ///
  /// In en, this message translates to:
  /// **'Verbose'**
  String get loggingVerbose;

  /// No description provided for @logRetentionLabel.
  ///
  /// In en, this message translates to:
  /// **'Log entry limit'**
  String get logRetentionLabel;

  /// No description provided for @logRetentionHelperText.
  ///
  /// In en, this message translates to:
  /// **'When the limit is reached, the oldest entries will be removed automatically'**
  String get logRetentionHelperText;

  /// No description provided for @logRetentionInvalidError.
  ///
  /// In en, this message translates to:
  /// **'Enter a number from {min} to {max}'**
  String logRetentionInvalidError(int min, int max);

  /// No description provided for @unsafeRawLoggingTitle.
  ///
  /// In en, this message translates to:
  /// **'Raw debug logs'**
  String get unsafeRawLoggingTitle;

  /// No description provided for @unsafeRawLoggingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stores the contents of requests and responses. Enable only for debugging!'**
  String get unsafeRawLoggingSubtitle;

  /// No description provided for @defaultGoogleWebSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable web search by default'**
  String get defaultGoogleWebSearchTitle;

  /// No description provided for @defaultGoogleWebSearchSubtitle.
  ///
  /// In en, this message translates to:
  /// **'KiCk will automatically use Google Search if the client did not explicitly override parameters and the request contains no function calls'**
  String get defaultGoogleWebSearchSubtitle;

  /// No description provided for @renderGoogleGroundingInMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Show citations and sources in the response'**
  String get renderGoogleGroundingInMessageTitle;

  /// No description provided for @renderGoogleGroundingInMessageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'If disabled, source links will remain in metadata and will not be added to the response text itself'**
  String get renderGoogleGroundingInMessageSubtitle;

  /// No description provided for @customModelsLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom model IDs'**
  String get customModelsLabel;

  /// No description provided for @customModelsHelperText.
  ///
  /// In en, this message translates to:
  /// **'One ID per line, for example google/... or kiro/...'**
  String get customModelsHelperText;

  /// No description provided for @settingsSavingStatus.
  ///
  /// In en, this message translates to:
  /// **'Saving changes...'**
  String get settingsSavingStatus;

  /// No description provided for @settingsSavedStatus.
  ///
  /// In en, this message translates to:
  /// **'Changes saved'**
  String get settingsSavedStatus;

  /// No description provided for @settingsValidationStatus.
  ///
  /// In en, this message translates to:
  /// **'Check the fields with errors'**
  String get settingsValidationStatus;

  /// No description provided for @settingsSaveFailedStatus.
  ///
  /// In en, this message translates to:
  /// **'Failed to save changes'**
  String get settingsSaveFailedStatus;

  /// No description provided for @settingsBackupExportButton.
  ///
  /// In en, this message translates to:
  /// **'Save backup'**
  String get settingsBackupExportButton;

  /// No description provided for @settingsBackupImportButton.
  ///
  /// In en, this message translates to:
  /// **'Restore backup'**
  String get settingsBackupImportButton;

  /// No description provided for @settingsBackupExportOptionsDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Export backup'**
  String get settingsBackupExportOptionsDialogTitle;

  /// No description provided for @settingsBackupExportDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Where should the backup be saved?'**
  String get settingsBackupExportDialogTitle;

  /// No description provided for @settingsBackupImportDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Select a backup file'**
  String get settingsBackupImportDialogTitle;

  /// No description provided for @settingsBackupExportConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get settingsBackupExportConfirmButton;

  /// No description provided for @settingsBackupProtectWithPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Protect the file with a password (recommended)'**
  String get settingsBackupProtectWithPasswordLabel;

  /// No description provided for @settingsBackupProtectWithPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Encrypts the backup so tokens and keys cannot be read without the password'**
  String get settingsBackupProtectWithPasswordSubtitle;

  /// No description provided for @settingsBackupPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get settingsBackupPasswordLabel;

  /// No description provided for @settingsBackupPasswordConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get settingsBackupPasswordConfirmLabel;

  /// No description provided for @settingsBackupPasswordHelperText.
  ///
  /// In en, this message translates to:
  /// **'Remember this password: without it, the encrypted backup cannot be restored!'**
  String get settingsBackupPasswordHelperText;

  /// No description provided for @settingsBackupPasswordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get settingsBackupPasswordsDoNotMatch;

  /// No description provided for @settingsBackupUnprotectedWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning! Your tokens and keys will be saved in plain text. Anyone who gets this file will gain access to your data.'**
  String get settingsBackupUnprotectedWarning;

  /// No description provided for @settingsBackupRestoreDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore configuration?'**
  String get settingsBackupRestoreDialogTitle;

  /// No description provided for @settingsBackupRestoreDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Current settings, the API key, and the account list will be replaced with data from this backup. This action cannot be undone.'**
  String get settingsBackupRestoreDialogMessage;

  /// No description provided for @settingsBackupRestoreConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get settingsBackupRestoreConfirmButton;

  /// No description provided for @settingsBackupPasswordDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the backup password'**
  String get settingsBackupPasswordDialogTitle;

  /// No description provided for @settingsBackupPasswordDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'The file {fileName} is password-protected. Enter the password to continue restoring.'**
  String settingsBackupPasswordDialogMessage(String fileName);

  /// No description provided for @settingsBackupPasswordDialogInvalidMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to decrypt the file {fileName}. Check the password and try again.'**
  String settingsBackupPasswordDialogInvalidMessage(String fileName);

  /// No description provided for @settingsBackupPasswordConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Decrypt'**
  String get settingsBackupPasswordConfirmButton;

  /// No description provided for @settingsBackupExportedMessage.
  ///
  /// In en, this message translates to:
  /// **'Backup saved to file {fileName}'**
  String settingsBackupExportedMessage(String fileName);

  /// No description provided for @settingsBackupRestoredMessage.
  ///
  /// In en, this message translates to:
  /// **'Configuration restored. Accounts: {accountCount}'**
  String settingsBackupRestoredMessage(int accountCount);

  /// No description provided for @settingsBackupRestoredMissingTokensMessage.
  ///
  /// In en, this message translates to:
  /// **'Configuration restored. Accounts: {accountCount}, without tokens: {missingCount}'**
  String settingsBackupRestoredMissingTokensMessage(int accountCount, int missingCount);

  /// No description provided for @settingsBackupExportFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to save backup: {error}'**
  String settingsBackupExportFailedMessage(String error);

  /// No description provided for @settingsBackupRestoreFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to restore backup: {error}'**
  String settingsBackupRestoreFailedMessage(String error);

  /// No description provided for @settingsBackupInvalidMessage.
  ///
  /// In en, this message translates to:
  /// **'The backup file is corrupted or has an unsupported format'**
  String get settingsBackupInvalidMessage;

  /// No description provided for @settingsBackupUnsupportedVersionMessage.
  ///
  /// In en, this message translates to:
  /// **'This backup was created in a newer version of KiCk and is not supported yet'**
  String get settingsBackupUnsupportedVersionMessage;

  /// No description provided for @settingsBackupReadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to read the selected backup'**
  String get settingsBackupReadFailedMessage;

  /// No description provided for @settingsBackupPasswordRequiredMessage.
  ///
  /// In en, this message translates to:
  /// **'A password is required for this backup'**
  String get settingsBackupPasswordRequiredMessage;

  /// No description provided for @settingsLoadErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Failed to load settings'**
  String get settingsLoadErrorTitle;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// No description provided for @aboutMenuSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Version, updates, and analytics'**
  String get aboutMenuSubtitle;

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'A local OpenAI-compatible proxy for Gemini CLI and Kiro in a native Flutter app'**
  String get aboutDescription;

  /// No description provided for @aboutUpdatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get aboutUpdatesTitle;

  /// No description provided for @aboutUpdatesChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates on GitHub...'**
  String get aboutUpdatesChecking;

  /// No description provided for @aboutUpdateAvailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get aboutUpdateAvailableTitle;

  /// No description provided for @aboutUpdateAvailableMessage.
  ///
  /// In en, this message translates to:
  /// **'Version {latestVersion} is available. You currently have {currentVersion} installed.'**
  String aboutUpdateAvailableMessage(String latestVersion, String currentVersion);

  /// No description provided for @aboutUpToDateTitle.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get aboutUpToDateTitle;

  /// No description provided for @aboutUpToDateMessage.
  ///
  /// In en, this message translates to:
  /// **'You have the latest version installed: {currentVersion}.'**
  String aboutUpToDateMessage(String currentVersion);

  /// No description provided for @aboutUpdateCheckFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Failed to check for updates'**
  String get aboutUpdateCheckFailedTitle;

  /// No description provided for @aboutUpdateCheckFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to get release information from GitHub.'**
  String get aboutUpdateCheckFailedMessage;

  /// No description provided for @aboutDownloadAndInstallButton.
  ///
  /// In en, this message translates to:
  /// **'Download and install'**
  String get aboutDownloadAndInstallButton;

  /// No description provided for @aboutOpenReleaseButton.
  ///
  /// In en, this message translates to:
  /// **'Open release'**
  String get aboutOpenReleaseButton;

  /// No description provided for @aboutRetryUpdateCheckButton.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get aboutRetryUpdateCheckButton;

  /// No description provided for @aboutAnalyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get aboutAnalyticsTitle;

  /// No description provided for @aboutAnalyticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Anonymous usage statistics help improve KiCk.'**
  String get aboutAnalyticsSubtitle;

  /// No description provided for @copyProxyEndpointTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy proxy address'**
  String get copyProxyEndpointTooltip;

  /// No description provided for @proxyEndpointCopiedMessage.
  ///
  /// In en, this message translates to:
  /// **'Proxy address copied'**
  String get proxyEndpointCopiedMessage;

  /// No description provided for @copyApiKeyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy API key'**
  String get copyApiKeyTooltip;

  /// No description provided for @apiKeyCopiedMessage.
  ///
  /// In en, this message translates to:
  /// **'API key copied'**
  String get apiKeyCopiedMessage;

  /// No description provided for @homeOnboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Getting started'**
  String get homeOnboardingTitle;

  /// No description provided for @homeOnboardingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A quick guide for the first launch'**
  String get homeOnboardingSubtitle;

  /// No description provided for @homeOnboardingAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect an account'**
  String get homeOnboardingAccountsTitle;

  /// No description provided for @homeOnboardingAccountsMessage.
  ///
  /// In en, this message translates to:
  /// **'Without an active Gemini CLI or Kiro account, KiCk will not be able to process requests.'**
  String get homeOnboardingAccountsMessage;

  /// No description provided for @homeOnboardingEndpointTitle.
  ///
  /// In en, this message translates to:
  /// **'Check the proxy address'**
  String get homeOnboardingEndpointTitle;

  /// No description provided for @homeOnboardingEndpointMessage.
  ///
  /// In en, this message translates to:
  /// **'When everything is ready, use the address {endpoint} in your client.'**
  String homeOnboardingEndpointMessage(String endpoint);

  /// No description provided for @homeOnboardingStartTitle.
  ///
  /// In en, this message translates to:
  /// **'Start the proxy'**
  String get homeOnboardingStartTitle;

  /// No description provided for @homeOnboardingStartMessage.
  ///
  /// In en, this message translates to:
  /// **'After startup, KiCk will begin accepting requests on this device.'**
  String get homeOnboardingStartMessage;

  /// No description provided for @homeOnboardingFooter.
  ///
  /// In en, this message translates to:
  /// **'If an account is already connected, just enable it on the accounts screen and come back here.'**
  String get homeOnboardingFooter;

  /// No description provided for @apiKeyRegeneratedMessage.
  ///
  /// In en, this message translates to:
  /// **'New API key saved'**
  String get apiKeyRegeneratedMessage;

  /// No description provided for @regenerateApiKeyAction.
  ///
  /// In en, this message translates to:
  /// **'Create new API key'**
  String get regenerateApiKeyAction;

  /// No description provided for @regenerateApiKeyDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Create a new API key?'**
  String get regenerateApiKeyDialogTitle;

  /// No description provided for @regenerateApiKeyDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'The old key will be revoked immediately. All connected clients will need the new key to keep working.'**
  String get regenerateApiKeyDialogMessage;

  /// No description provided for @regenerateApiKeyConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get regenerateApiKeyConfirmButton;

  /// No description provided for @trayOpenWindowAction.
  ///
  /// In en, this message translates to:
  /// **'Open window'**
  String get trayOpenWindowAction;

  /// No description provided for @trayHideToTrayAction.
  ///
  /// In en, this message translates to:
  /// **'Minimize to tray'**
  String get trayHideToTrayAction;

  /// No description provided for @trayExitAction.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get trayExitAction;

  /// No description provided for @noActiveAccountsWarning.
  ///
  /// In en, this message translates to:
  /// **'No active accounts. The proxy will start, but it will not be able to process requests until you add or enable at least one account.'**
  String get noActiveAccountsWarning;

  /// No description provided for @pinWindowTooltip.
  ///
  /// In en, this message translates to:
  /// **'Pin window on top'**
  String get pinWindowTooltip;

  /// No description provided for @unpinWindowTooltip.
  ///
  /// In en, this message translates to:
  /// **'Unpin window'**
  String get unpinWindowTooltip;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to KiCk'**
  String get welcomeTitle;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'KiCk helps you run a local proxy for Gemini CLI and Kiro without terminal commands or extra setup.'**
  String get welcomeSubtitle;

  /// No description provided for @welcomeStepAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect an account'**
  String get welcomeStepAccountsTitle;

  /// No description provided for @welcomeStepAccountsMessage.
  ///
  /// In en, this message translates to:
  /// **'You can do this on the accounts screen. You can connect Gemini CLI or Kiro.'**
  String get welcomeStepAccountsMessage;

  /// No description provided for @welcomeStepHomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Open Home'**
  String get welcomeStepHomeTitle;

  /// No description provided for @welcomeStepHomeMessage.
  ///
  /// In en, this message translates to:
  /// **'Home always shows the proxy address, API key, and the start button.'**
  String get welcomeStepHomeMessage;

  /// No description provided for @welcomeUsageTitle.
  ///
  /// In en, this message translates to:
  /// **'Important to know'**
  String get welcomeUsageTitle;

  /// No description provided for @welcomeUsageMessage.
  ///
  /// In en, this message translates to:
  /// **'KiCk is intended for personal, educational, and research use.'**
  String get welcomeUsageMessage;

  /// No description provided for @welcomeAnalyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Anonymous analytics'**
  String get welcomeAnalyticsTitle;

  /// No description provided for @welcomeAnalyticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Helps understand where KiCk works well and where it should be improved.'**
  String get welcomeAnalyticsSubtitle;

  /// No description provided for @welcomeRepositoryLinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Learn more about the project'**
  String get welcomeRepositoryLinkLabel;

  /// No description provided for @logsTitle.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logsTitle;

  /// No description provided for @logsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Request and error history'**
  String get logsSubtitle;

  /// No description provided for @logsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by route or message'**
  String get logsSearchHint;

  /// No description provided for @logsRefreshButton.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get logsRefreshButton;

  /// No description provided for @logsClearButton.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get logsClearButton;

  /// No description provided for @logsClearDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear logs?'**
  String get logsClearDialogTitle;

  /// No description provided for @logsClearDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'All entries will be removed from KiCk. This action cannot be undone.'**
  String get logsClearDialogMessage;

  /// No description provided for @logsClearConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get logsClearConfirmButton;

  /// No description provided for @logsLevelAll.
  ///
  /// In en, this message translates to:
  /// **'All levels'**
  String get logsLevelAll;

  /// No description provided for @logsLevelInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get logsLevelInfo;

  /// No description provided for @logsLevelWarning.
  ///
  /// In en, this message translates to:
  /// **'Warnings'**
  String get logsLevelWarning;

  /// No description provided for @logsLevelError.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get logsLevelError;

  /// No description provided for @logsCategoryAll.
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get logsCategoryAll;

  /// No description provided for @logsCategoryFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get logsCategoryFilterTitle;

  /// No description provided for @logsPayloadShowButton.
  ///
  /// In en, this message translates to:
  /// **'Show payload'**
  String get logsPayloadShowButton;

  /// No description provided for @logsPayloadHideButton.
  ///
  /// In en, this message translates to:
  /// **'Hide payload'**
  String get logsPayloadHideButton;

  /// No description provided for @logsCopyEntryButton.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get logsCopyEntryButton;

  /// No description provided for @logsCopiedMessage.
  ///
  /// In en, this message translates to:
  /// **'Log entry copied'**
  String get logsCopiedMessage;

  /// No description provided for @logsFilteredEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing found for the current filters'**
  String get logsFilteredEmptyTitle;

  /// No description provided for @logsFilteredEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Try removing some filters or changing the search.'**
  String get logsFilteredEmptyMessage;

  /// No description provided for @logsEntryLevelInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get logsEntryLevelInfo;

  /// No description provided for @logsEntryLevelWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get logsEntryLevelWarning;

  /// No description provided for @logsEntryLevelError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get logsEntryLevelError;

  /// No description provided for @logsTotalCount.
  ///
  /// In en, this message translates to:
  /// **'Total: {count}'**
  String logsTotalCount(int count);

  /// No description provided for @logsFilteredCount.
  ///
  /// In en, this message translates to:
  /// **'After filtering: {count}'**
  String logsFilteredCount(int count);

  /// No description provided for @logsLoadedCount.
  ///
  /// In en, this message translates to:
  /// **'Loaded: {count}'**
  String logsLoadedCount(int count);

  /// No description provided for @logsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Logs are empty'**
  String get logsEmptyTitle;

  /// No description provided for @logsLoadErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Failed to load logs'**
  String get logsLoadErrorTitle;

  /// No description provided for @logsExportTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save all logs for the current filters'**
  String get logsExportTooltip;

  /// No description provided for @logsExportDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Where should the logs be saved?'**
  String get logsExportDialogTitle;

  /// No description provided for @logsShareTooltip.
  ///
  /// In en, this message translates to:
  /// **'Share all logs for the current filters'**
  String get logsShareTooltip;

  /// No description provided for @logsLoadMoreButton.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get logsLoadMoreButton;

  /// No description provided for @logsNothingToExportMessage.
  ///
  /// In en, this message translates to:
  /// **'No logs to save'**
  String get logsNothingToExportMessage;

  /// No description provided for @logsExportedMessage.
  ///
  /// In en, this message translates to:
  /// **'Logs saved to file {fileName}'**
  String logsExportedMessage(String fileName);

  /// No description provided for @logsExportFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to save logs: {error}'**
  String logsExportFailedMessage(String error);

  /// No description provided for @logsShareFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to share logs: {error}'**
  String logsShareFailedMessage(String error);

  /// No description provided for @logsExportFileTitle.
  ///
  /// In en, this message translates to:
  /// **'KiCk log export'**
  String get logsExportFileTitle;

  /// No description provided for @logsExportShareSubject.
  ///
  /// In en, this message translates to:
  /// **'KiCk logs'**
  String get logsExportShareSubject;

  /// No description provided for @logsExportGeneratedAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Generated at'**
  String get logsExportGeneratedAtLabel;

  /// No description provided for @logsExportEntriesCount.
  ///
  /// In en, this message translates to:
  /// **'Entries: {count}'**
  String logsExportEntriesCount(int count);

  /// No description provided for @logsExportSectionEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get logsExportSectionEnvironment;

  /// No description provided for @logsExportAppLabel.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get logsExportAppLabel;

  /// No description provided for @logsExportFiltersLabel.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get logsExportFiltersLabel;

  /// No description provided for @logsExportScopeLabel.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get logsExportScopeLabel;

  /// No description provided for @logsExportRuntimeSettingsLabel.
  ///
  /// In en, this message translates to:
  /// **'Runtime settings'**
  String get logsExportRuntimeSettingsLabel;

  /// No description provided for @logsExportNoneValue.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get logsExportNoneValue;

  /// No description provided for @logsExportNoneDetectedValue.
  ///
  /// In en, this message translates to:
  /// **'none detected'**
  String get logsExportNoneDetectedValue;

  /// No description provided for @logsExportSectionDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics summary'**
  String get logsExportSectionDiagnostics;

  /// No description provided for @logsExportTimeRangeLabel.
  ///
  /// In en, this message translates to:
  /// **'Time range'**
  String get logsExportTimeRangeLabel;

  /// No description provided for @logsExportLevelsLabel.
  ///
  /// In en, this message translates to:
  /// **'Levels'**
  String get logsExportLevelsLabel;

  /// No description provided for @logsExportCategoriesLabel.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get logsExportCategoriesLabel;

  /// No description provided for @logsExportRoutesLabel.
  ///
  /// In en, this message translates to:
  /// **'Routes'**
  String get logsExportRoutesLabel;

  /// No description provided for @logsExportModelsLabel.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get logsExportModelsLabel;

  /// No description provided for @logsExportStatusCodesLabel.
  ///
  /// In en, this message translates to:
  /// **'Status codes'**
  String get logsExportStatusCodesLabel;

  /// No description provided for @logsExportErrorDetailsLabel.
  ///
  /// In en, this message translates to:
  /// **'Error details'**
  String get logsExportErrorDetailsLabel;

  /// No description provided for @logsExportUpstreamReasonsLabel.
  ///
  /// In en, this message translates to:
  /// **'Upstream reasons'**
  String get logsExportUpstreamReasonsLabel;

  /// No description provided for @logsExportRetriedRequestsLabel.
  ///
  /// In en, this message translates to:
  /// **'Retried requests'**
  String get logsExportRetriedRequestsLabel;

  /// No description provided for @logsExportTokensLabel.
  ///
  /// In en, this message translates to:
  /// **'Tokens'**
  String get logsExportTokensLabel;

  /// No description provided for @logsExportAndroidBackgroundSessionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Android background sessions'**
  String get logsExportAndroidBackgroundSessionsLabel;

  /// No description provided for @logsExportTimestampLabel.
  ///
  /// In en, this message translates to:
  /// **'Timestamp'**
  String get logsExportTimestampLabel;

  /// No description provided for @logsExportLevelLabel.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get logsExportLevelLabel;

  /// No description provided for @logsExportCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get logsExportCategoryLabel;

  /// No description provided for @logsExportRouteLabel.
  ///
  /// In en, this message translates to:
  /// **'Route'**
  String get logsExportRouteLabel;

  /// No description provided for @logsExportMessageLabel.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get logsExportMessageLabel;

  /// No description provided for @logsExportMaskedPayloadLabel.
  ///
  /// In en, this message translates to:
  /// **'Masked payload'**
  String get logsExportMaskedPayloadLabel;

  /// No description provided for @logsExportRawPayloadLabel.
  ///
  /// In en, this message translates to:
  /// **'Raw payload'**
  String get logsExportRawPayloadLabel;

  /// No description provided for @logMessageRequestReceived.
  ///
  /// In en, this message translates to:
  /// **'Request received'**
  String get logMessageRequestReceived;

  /// No description provided for @logMessageParsedRequest.
  ///
  /// In en, this message translates to:
  /// **'Parsed request'**
  String get logMessageParsedRequest;

  /// No description provided for @logMessageResponseCompleted.
  ///
  /// In en, this message translates to:
  /// **'Response completed'**
  String get logMessageResponseCompleted;

  /// No description provided for @logMessageStreamClientAborted.
  ///
  /// In en, this message translates to:
  /// **'Streaming response aborted by client'**
  String get logMessageStreamClientAborted;

  /// No description provided for @logMessageRetryScheduled.
  ///
  /// In en, this message translates to:
  /// **'Retry scheduled after request failure'**
  String get logMessageRetryScheduled;

  /// No description provided for @logMessageRetryWithAnotherAccount.
  ///
  /// In en, this message translates to:
  /// **'Retrying with another account after request failure'**
  String get logMessageRetryWithAnotherAccount;

  /// No description provided for @logMessageRequestSucceededAfterRetries.
  ///
  /// In en, this message translates to:
  /// **'Request succeeded after retries'**
  String get logMessageRequestSucceededAfterRetries;

  /// No description provided for @logMessageRequestFailedAfterRetries.
  ///
  /// In en, this message translates to:
  /// **'Request failed after retries'**
  String get logMessageRequestFailedAfterRetries;

  /// No description provided for @logMessageDispatchingStreamingRequest.
  ///
  /// In en, this message translates to:
  /// **'Dispatching streaming request to upstream provider'**
  String get logMessageDispatchingStreamingRequest;

  /// No description provided for @logMessageDispatchingRequest.
  ///
  /// In en, this message translates to:
  /// **'Dispatching request to upstream provider'**
  String get logMessageDispatchingRequest;

  /// No description provided for @logMessageUpstreamPayloadReturned.
  ///
  /// In en, this message translates to:
  /// **'Upstream provider returned a payload'**
  String get logMessageUpstreamPayloadReturned;

  /// No description provided for @logMessageMappedChatCompletion.
  ///
  /// In en, this message translates to:
  /// **'Mapped upstream payload to OpenAI chat completion'**
  String get logMessageMappedChatCompletion;

  /// No description provided for @logMessageUsingAccountForModel.
  ///
  /// In en, this message translates to:
  /// **'Using account {account} for {model}'**
  String logMessageUsingAccountForModel(String account, String model);

  /// No description provided for @logMessageProxySessionSummary.
  ///
  /// In en, this message translates to:
  /// **'Proxy session summary'**
  String get logMessageProxySessionSummary;

  /// No description provided for @logMessageAndroidBackgroundSessionStarted.
  ///
  /// In en, this message translates to:
  /// **'Android background session started'**
  String get logMessageAndroidBackgroundSessionStarted;

  /// No description provided for @logMessageAndroidBackgroundSessionEnded.
  ///
  /// In en, this message translates to:
  /// **'Android background session ended'**
  String get logMessageAndroidBackgroundSessionEnded;

  /// No description provided for @logMessageAndroidBackgroundSessionRecovered.
  ///
  /// In en, this message translates to:
  /// **'Android background session recovered after process restart'**
  String get logMessageAndroidBackgroundSessionRecovered;

  /// No description provided for @accountDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountDialogTitle;

  /// No description provided for @accountDialogBasicsTitle.
  ///
  /// In en, this message translates to:
  /// **'Basics'**
  String get accountDialogBasicsTitle;

  /// No description provided for @accountDialogBasicsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fields for connecting the selected account type'**
  String get accountDialogBasicsSubtitle;

  /// No description provided for @accountDialogAdvancedTitle.
  ///
  /// In en, this message translates to:
  /// **'Advanced settings'**
  String get accountDialogAdvancedTitle;

  /// No description provided for @accountDialogAdvancedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Priority and model restrictions'**
  String get accountDialogAdvancedSubtitle;

  /// No description provided for @accountDialogAdvancedHint.
  ///
  /// In en, this message translates to:
  /// **'If you don\'t want to configure it manually, you can leave this section as is.'**
  String get accountDialogAdvancedHint;

  /// No description provided for @projectIdLabel.
  ///
  /// In en, this message translates to:
  /// **'PROJECT_ID'**
  String get projectIdLabel;

  /// No description provided for @projectIdHint.
  ///
  /// In en, this message translates to:
  /// **'my-google-cloud-project'**
  String get projectIdHint;

  /// No description provided for @projectIdConsoleLinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Where to find the project ID'**
  String get projectIdConsoleLinkLabel;

  /// No description provided for @projectIdRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Enter a project ID'**
  String get projectIdRequiredError;

  /// No description provided for @projectIdLookupFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to open Google Cloud Console.'**
  String get projectIdLookupFailedMessage;

  /// No description provided for @accountNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Account name'**
  String get accountNameLabel;

  /// No description provided for @accountNameHint.
  ///
  /// In en, this message translates to:
  /// **'For example, main account'**
  String get accountNameHint;

  /// No description provided for @accountNameHelperText.
  ///
  /// In en, this message translates to:
  /// **'If you leave this field empty, KiCk will use the account name.'**
  String get accountNameHelperText;

  /// No description provided for @priorityLabel.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priorityLabel;

  /// No description provided for @priorityHelperText.
  ///
  /// In en, this message translates to:
  /// **'Primary accounts are used first. Accounts with the same priority alternate.'**
  String get priorityHelperText;

  /// No description provided for @priorityLevelPrimary.
  ///
  /// In en, this message translates to:
  /// **'Primary'**
  String get priorityLevelPrimary;

  /// No description provided for @priorityLevelNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get priorityLevelNormal;

  /// No description provided for @priorityLevelReserve.
  ///
  /// In en, this message translates to:
  /// **'Reserve'**
  String get priorityLevelReserve;

  /// No description provided for @blockedModelsLabel.
  ///
  /// In en, this message translates to:
  /// **'Unavailable models'**
  String get blockedModelsLabel;

  /// No description provided for @blockedModelsHelperText.
  ///
  /// In en, this message translates to:
  /// **'One ID per line, for example google/... or kiro/...'**
  String get blockedModelsHelperText;

  /// No description provided for @kiroLinkAuthDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Kiro authorization'**
  String get kiroLinkAuthDialogTitle;

  /// No description provided for @kiroLinkAuthDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Open the link, sign in with AWS Builder ID, and confirm access for Kiro. The code is only for verification; you do not need to enter it. KiCk will wait for completion automatically.'**
  String get kiroLinkAuthDialogMessage;

  /// No description provided for @kiroLinkAuthUserCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get kiroLinkAuthUserCodeLabel;

  /// No description provided for @kiroLinkAuthVerificationUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Sign-in link'**
  String get kiroLinkAuthVerificationUrlLabel;

  /// No description provided for @kiroLinkAuthWaitingMessage.
  ///
  /// In en, this message translates to:
  /// **'Waiting for you to confirm sign-in in the browser...'**
  String get kiroLinkAuthWaitingMessage;

  /// No description provided for @kiroLinkAuthOpenLinkButton.
  ///
  /// In en, this message translates to:
  /// **'Open link'**
  String get kiroLinkAuthOpenLinkButton;

  /// No description provided for @kiroLinkAuthOpenLinkAgainButton.
  ///
  /// In en, this message translates to:
  /// **'Open again'**
  String get kiroLinkAuthOpenLinkAgainButton;

  /// No description provided for @kiroLinkAuthOpenLinkFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to open the sign-in link for Kiro.'**
  String get kiroLinkAuthOpenLinkFailedMessage;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navAccounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get navAccounts;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navLogs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get navLogs;

  /// No description provided for @runtimeChannelName.
  ///
  /// In en, this message translates to:
  /// **'KiCk proxy in background'**
  String get runtimeChannelName;

  /// No description provided for @runtimeChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Keeps the proxy running in the background'**
  String get runtimeChannelDescription;

  /// No description provided for @runtimeNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'KiCk proxy is running'**
  String get runtimeNotificationTitle;

  /// No description provided for @runtimeNotificationReturn.
  ///
  /// In en, this message translates to:
  /// **'Tap to return to the app'**
  String get runtimeNotificationReturn;

  /// No description provided for @runtimeNotificationManage.
  ///
  /// In en, this message translates to:
  /// **'Tap to open accounts and settings'**
  String get runtimeNotificationManage;

  /// No description provided for @runtimeNotificationActive.
  ///
  /// In en, this message translates to:
  /// **'Proxy is active'**
  String get runtimeNotificationActive;

  /// No description provided for @oauthPageTitleError.
  ///
  /// In en, this message translates to:
  /// **'Authorization error'**
  String get oauthPageTitleError;

  /// No description provided for @oauthPageTitleSuccess.
  ///
  /// In en, this message translates to:
  /// **'Authorization successful'**
  String get oauthPageTitleSuccess;

  /// No description provided for @oauthPageStateMismatchMessage.
  ///
  /// In en, this message translates to:
  /// **'State mismatch. You can close this tab.'**
  String get oauthPageStateMismatchMessage;

  /// No description provided for @oauthPageGoogleErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Google returned an error. You can close this tab.'**
  String get oauthPageGoogleErrorMessage;

  /// No description provided for @oauthPageCodeMissingMessage.
  ///
  /// In en, this message translates to:
  /// **'No code received. You can close this tab.'**
  String get oauthPageCodeMissingMessage;

  /// No description provided for @oauthPageCloseTabMessage.
  ///
  /// In en, this message translates to:
  /// **'You can close this tab.'**
  String get oauthPageCloseTabMessage;

  /// No description provided for @accountDisplayNameFallbackGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google account'**
  String get accountDisplayNameFallbackGoogle;

  /// No description provided for @errorNetworkUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach Google\'s servers. Check your internet connection and try again.'**
  String get errorNetworkUnavailable;

  /// No description provided for @errorGoogleServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Google service is temporarily unavailable. Please try again later.'**
  String get errorGoogleServiceUnavailable;

  /// No description provided for @errorInvalidServiceResponse.
  ///
  /// In en, this message translates to:
  /// **'The server returned an invalid response. Please try again.'**
  String get errorInvalidServiceResponse;

  /// No description provided for @errorGoogleAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'Google authorization failed. Please try again.'**
  String get errorGoogleAuthFailed;

  /// No description provided for @errorGoogleAuthTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Google authorization did not finish in time. Return to the app and try again. If this keeps happening on Android, disable battery restrictions for KiCk.'**
  String get errorGoogleAuthTimedOut;

  /// No description provided for @errorGoogleAuthBrowserOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open the browser for Google authorization. Please try again.'**
  String get errorGoogleAuthBrowserOpenFailed;

  /// No description provided for @errorUnknown.
  ///
  /// In en, this message translates to:
  /// **'An unknown error occurred. Please try again.'**
  String get errorUnknown;

  /// No description provided for @errorOauthTokensMissing.
  ///
  /// In en, this message translates to:
  /// **'Authorization tokens for this account were not found. Reconnect the account.'**
  String get errorOauthTokensMissing;

  /// No description provided for @errorAccountNotFound.
  ///
  /// In en, this message translates to:
  /// **'Account not found. It may already have been deleted.'**
  String get errorAccountNotFound;

  /// No description provided for @errorPortAlreadyInUse.
  ///
  /// In en, this message translates to:
  /// **'This port is already in use by another app. Choose a different port in settings.'**
  String get errorPortAlreadyInUse;

  /// No description provided for @errorPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'The app does not have the required system permissions to start. Check app settings and try again.'**
  String get errorPermissionDenied;

  /// No description provided for @errorGoogleRateLimitedRetry.
  ///
  /// In en, this message translates to:
  /// **'Google has temporarily rate-limited requests for this account. Try again in {retryHint}.'**
  String errorGoogleRateLimitedRetry(String retryHint);

  /// No description provided for @errorGoogleRateLimitedLater.
  ///
  /// In en, this message translates to:
  /// **'Google has temporarily rate-limited requests for this account. Try again later.'**
  String get errorGoogleRateLimitedLater;

  /// No description provided for @errorKiroAuthExpired.
  ///
  /// In en, this message translates to:
  /// **'Kiro session expired. Sign in again and try again.'**
  String get errorKiroAuthExpired;

  /// No description provided for @errorKiroAuthStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to start Kiro authorization. Please try again later.'**
  String get errorKiroAuthStartFailed;

  /// No description provided for @errorKiroAuthCancelled.
  ///
  /// In en, this message translates to:
  /// **'Kiro authorization was canceled.'**
  String get errorKiroAuthCancelled;

  /// No description provided for @errorKiroAuthTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Kiro authorization timed out. Please try again.'**
  String get errorKiroAuthTimedOut;

  /// No description provided for @errorKiroAuthRejected.
  ///
  /// In en, this message translates to:
  /// **'Kiro rejected the authorization. Try starting sign-in again.'**
  String get errorKiroAuthRejected;

  /// No description provided for @errorKiroRateLimitedRetry.
  ///
  /// In en, this message translates to:
  /// **'Kiro has temporarily rate-limited requests. Try again in {retryHint}.'**
  String errorKiroRateLimitedRetry(String retryHint);

  /// No description provided for @errorKiroRateLimitedLater.
  ///
  /// In en, this message translates to:
  /// **'Kiro has temporarily rate-limited requests. Try again later.'**
  String get errorKiroRateLimitedLater;

  /// No description provided for @errorKiroServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Kiro service is temporarily unavailable. Please try again later.'**
  String get errorKiroServiceUnavailable;

  /// No description provided for @errorGoogleAccountVerificationRequired.
  ///
  /// In en, this message translates to:
  /// **'Google asks you to verify this account. Open the verification page and sign in with the same Google account.'**
  String get errorGoogleAccountVerificationRequired;

  /// No description provided for @errorGoogleProjectIdMissing.
  ///
  /// In en, this message translates to:
  /// **'Google could not determine a valid project ID for this account or request. Check the project ID in the account settings and reconnect the account if necessary.'**
  String get errorGoogleProjectIdMissing;

  /// No description provided for @errorGoogleProjectApiDisabled.
  ///
  /// In en, this message translates to:
  /// **'Gemini for Google Cloud API is disabled for this project. Open Google Cloud, enable the API for the correct project ID, and run the check again.'**
  String get errorGoogleProjectApiDisabled;

  /// No description provided for @errorGoogleProjectInvalid.
  ///
  /// In en, this message translates to:
  /// **'Google rejected this project ID. Make sure you entered an existing project and that the account has access to it.'**
  String get errorGoogleProjectInvalid;

  /// No description provided for @errorGoogleProjectAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'Google rejected the request for this project or account. Check the project ID and selected account, and make sure Gemini Code Assist is enabled for this project.'**
  String get errorGoogleProjectAccessDenied;

  /// No description provided for @errorAuthExpired.
  ///
  /// In en, this message translates to:
  /// **'Authorization has expired or is no longer valid. Reconnect the account and try again.'**
  String get errorAuthExpired;

  /// No description provided for @errorGoogleCapacity.
  ///
  /// In en, this message translates to:
  /// **'Google servers are temporarily overloaded. Please try again a little later.'**
  String get errorGoogleCapacity;

  /// No description provided for @errorUnsupportedModel.
  ///
  /// In en, this message translates to:
  /// **'The selected model is currently unavailable for this account.'**
  String get errorUnsupportedModel;

  /// No description provided for @errorInvalidJson.
  ///
  /// In en, this message translates to:
  /// **'The request has an invalid JSON format.'**
  String get errorInvalidJson;

  /// No description provided for @errorUnexpectedResponse.
  ///
  /// In en, this message translates to:
  /// **'The service returned an unexpected response. Please try again.'**
  String get errorUnexpectedResponse;

  /// No description provided for @errorQuotaExhausted.
  ///
  /// In en, this message translates to:
  /// **'This account\'s quota has been exhausted. Wait for a reset or use another account.'**
  String get errorQuotaExhausted;

  /// No description provided for @errorQuotaExhaustedRetry.
  ///
  /// In en, this message translates to:
  /// **'This account\'s quota has been exhausted. Try again in {retryHint} or use another account.'**
  String errorQuotaExhaustedRetry(String retryHint);

  /// No description provided for @errorQuotaExhaustedNoResetHint.
  ///
  /// In en, this message translates to:
  /// **'Google returned RESOURCE_EXHAUSTED without a reset time. KiCk will check this account separately; if the error repeats, use another account'**
  String get errorQuotaExhaustedNoResetHint;

  /// No description provided for @errorGoogleTermsOfServiceViolation.
  ///
  /// In en, this message translates to:
  /// **'Google disabled this account for violating the ToS. Submit an appeal or use another account.'**
  String get errorGoogleTermsOfServiceViolation;

  /// No description provided for @errorInvalidRequestRejected.
  ///
  /// In en, this message translates to:
  /// **'The request has an invalid format and was rejected.'**
  String get errorInvalidRequestRejected;

  /// No description provided for @errorReasoningConfigRejected.
  ///
  /// In en, this message translates to:
  /// **'Google rejected the reasoning/thinking parameters for this model. Enable automatic reasoning mode.'**
  String get errorReasoningConfigRejected;

  /// No description provided for @durationFewSeconds.
  ///
  /// In en, this message translates to:
  /// **'a few seconds'**
  String get durationFewSeconds;

  /// No description provided for @durationSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} sec'**
  String durationSeconds(int seconds);

  /// No description provided for @durationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String durationMinutes(int minutes);

  /// No description provided for @durationMinutesSeconds.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min {seconds} sec'**
  String durationMinutesSeconds(int minutes, int seconds);

  /// No description provided for @durationHours.
  ///
  /// In en, this message translates to:
  /// **'{hours} h'**
  String durationHours(int hours);

  /// No description provided for @durationHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min'**
  String durationHoursMinutes(int hours, int minutes);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
