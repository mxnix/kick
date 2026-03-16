import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

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
  static const List<Locale> supportedLocales = <Locale>[Locale('ru')];

  /// No description provided for @appTitle.
  ///
  /// In ru, this message translates to:
  /// **'KiCk'**
  String get appTitle;

  /// No description provided for @shellSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Локальный прокси Gemini CLI'**
  String get shellSubtitle;

  /// No description provided for @connectGoogleAccountTitle.
  ///
  /// In ru, this message translates to:
  /// **'Подключить Google аккаунт'**
  String get connectGoogleAccountTitle;

  /// No description provided for @homeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Главная'**
  String get homeTitle;

  /// No description provided for @proxyRunningStatus.
  ///
  /// In ru, this message translates to:
  /// **'Активно'**
  String get proxyRunningStatus;

  /// No description provided for @proxyStoppedStatus.
  ///
  /// In ru, this message translates to:
  /// **'Остановлено'**
  String get proxyStoppedStatus;

  /// No description provided for @embeddedProxyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Прокси'**
  String get embeddedProxyTitle;

  /// No description provided for @proxyAddress.
  ///
  /// In ru, this message translates to:
  /// **'Адрес: {host}:{port}'**
  String proxyAddress(String host, int port);

  /// No description provided for @proxyEndpointTitle.
  ///
  /// In ru, this message translates to:
  /// **'URL прокси'**
  String get proxyEndpointTitle;

  /// No description provided for @activeAccounts.
  ///
  /// In ru, this message translates to:
  /// **'Активных аккаунтов: {count}'**
  String activeAccounts(int count);

  /// No description provided for @stopProxyButton.
  ///
  /// In ru, this message translates to:
  /// **'Остановить'**
  String get stopProxyButton;

  /// No description provided for @startProxyButton.
  ///
  /// In ru, this message translates to:
  /// **'Запустить'**
  String get startProxyButton;

  /// No description provided for @uptimeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Время работы'**
  String get uptimeTitle;

  /// No description provided for @uptimeNotStarted.
  ///
  /// In ru, this message translates to:
  /// **'Пока не запущен'**
  String get uptimeNotStarted;

  /// No description provided for @uptimeValue.
  ///
  /// In ru, this message translates to:
  /// **'{hours} ч {minutes} мин {seconds} сек'**
  String uptimeValue(int hours, int minutes, int seconds);

  /// No description provided for @versionTitle.
  ///
  /// In ru, this message translates to:
  /// **'Версия'**
  String get versionTitle;

  /// No description provided for @apiKeyTitle.
  ///
  /// In ru, this message translates to:
  /// **'API-ключ'**
  String get apiKeyTitle;

  /// No description provided for @apiKeyDisabledValue.
  ///
  /// In ru, this message translates to:
  /// **'Отключен'**
  String get apiKeyDisabledValue;

  /// No description provided for @changeApiKeyLinkLabel.
  ///
  /// In ru, this message translates to:
  /// **'Изменить ключ'**
  String get changeApiKeyLinkLabel;

  /// No description provided for @loadingValue.
  ///
  /// In ru, this message translates to:
  /// **'Загружается...'**
  String get loadingValue;

  /// No description provided for @lastErrorTitle.
  ///
  /// In ru, this message translates to:
  /// **'Последняя ошибка'**
  String get lastErrorTitle;

  /// No description provided for @openLogsButton.
  ///
  /// In ru, this message translates to:
  /// **'Открыть логи'**
  String get openLogsButton;

  /// No description provided for @accountsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Список аккаунтов'**
  String get accountsTitle;

  /// No description provided for @accountsSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Добавляйте Google аккаунты и управляйте ими'**
  String get accountsSubtitle;

  /// No description provided for @addButton.
  ///
  /// In ru, this message translates to:
  /// **'Добавить'**
  String get addButton;

  /// No description provided for @accountsEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Пока пусто'**
  String get accountsEmptyTitle;

  /// No description provided for @accountsEmptyMessage.
  ///
  /// In ru, this message translates to:
  /// **'Подключите хотя бы один Google аккаунт'**
  String get accountsEmptyMessage;

  /// No description provided for @connectAccountButton.
  ///
  /// In ru, this message translates to:
  /// **'Подключить аккаунт'**
  String get connectAccountButton;

  /// No description provided for @accountsLoadErrorTitle.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить аккаунты'**
  String get accountsLoadErrorTitle;

  /// No description provided for @projectIdChip.
  ///
  /// In ru, this message translates to:
  /// **'PROJECT_ID: {projectId}'**
  String projectIdChip(String projectId);

  /// No description provided for @priorityChip.
  ///
  /// In ru, this message translates to:
  /// **'Роль: {priorityLabel}'**
  String priorityChip(String priorityLabel);

  /// No description provided for @accountCoolingDownStatus.
  ///
  /// In ru, this message translates to:
  /// **'Таймаут'**
  String get accountCoolingDownStatus;

  /// No description provided for @accountReadyStatus.
  ///
  /// In ru, this message translates to:
  /// **'Готов'**
  String get accountReadyStatus;

  /// No description provided for @accountDisabledStatus.
  ///
  /// In ru, this message translates to:
  /// **'Отключен'**
  String get accountDisabledStatus;

  /// No description provided for @unsupportedModelsList.
  ///
  /// In ru, this message translates to:
  /// **'Не использовать для: {models}'**
  String unsupportedModelsList(String models);

  /// No description provided for @editAccountTitle.
  ///
  /// In ru, this message translates to:
  /// **'Редактировать аккаунт'**
  String get editAccountTitle;

  /// No description provided for @editButton.
  ///
  /// In ru, this message translates to:
  /// **'Изменить'**
  String get editButton;

  /// No description provided for @reauthorizeAccountTitle.
  ///
  /// In ru, this message translates to:
  /// **'Переавторизовать аккаунт'**
  String get reauthorizeAccountTitle;

  /// No description provided for @reauthorizeButton.
  ///
  /// In ru, this message translates to:
  /// **'Переавторизовать'**
  String get reauthorizeButton;

  /// No description provided for @resetCooldownTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить статус'**
  String get resetCooldownTooltip;

  /// No description provided for @clearCooldownAction.
  ///
  /// In ru, this message translates to:
  /// **'Снять блокировку'**
  String get clearCooldownAction;

  /// No description provided for @deleteTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get deleteTooltip;

  /// No description provided for @accountUsageOpenTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Лимиты'**
  String get accountUsageOpenTooltip;

  /// No description provided for @accountUsageTitle.
  ///
  /// In ru, this message translates to:
  /// **'Лимиты'**
  String get accountUsageTitle;

  /// No description provided for @accountUsageProviderLabel.
  ///
  /// In ru, this message translates to:
  /// **'Gemini CLI OAuth'**
  String get accountUsageProviderLabel;

  /// No description provided for @accountUsageRefreshTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Обновить'**
  String get accountUsageRefreshTooltip;

  /// No description provided for @accountUsageStatusHealthy.
  ///
  /// In ru, this message translates to:
  /// **'В норме'**
  String get accountUsageStatusHealthy;

  /// No description provided for @accountUsageStatusCoolingDown.
  ///
  /// In ru, this message translates to:
  /// **'Лимит'**
  String get accountUsageStatusCoolingDown;

  /// No description provided for @accountUsageStatusDisabled.
  ///
  /// In ru, this message translates to:
  /// **'Выключен'**
  String get accountUsageStatusDisabled;

  /// No description provided for @accountUsageLoadErrorTitle.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить текущие лимиты'**
  String get accountUsageLoadErrorTitle;

  /// No description provided for @accountUsageRetryButton.
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get accountUsageRetryButton;

  /// No description provided for @accountUsageVerifyAccountButton.
  ///
  /// In ru, this message translates to:
  /// **'Подтвердить аккаунт'**
  String get accountUsageVerifyAccountButton;

  /// No description provided for @accountUsageVerificationOpenFailedMessage.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть страницу подтверждения аккаунта'**
  String get accountUsageVerificationOpenFailedMessage;

  /// No description provided for @accountUsageEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Лимиты недоступны'**
  String get accountUsageEmptyTitle;

  /// No description provided for @accountUsageEmptyMessage.
  ///
  /// In ru, this message translates to:
  /// **'Google не вернул информацию по лимитам для этого аккаунта'**
  String get accountUsageEmptyMessage;

  /// No description provided for @accountUsageMissingTitle.
  ///
  /// In ru, this message translates to:
  /// **'Аккаунт не найден'**
  String get accountUsageMissingTitle;

  /// No description provided for @accountUsageMissingSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Экран лимитов'**
  String get accountUsageMissingSubtitle;

  /// No description provided for @accountUsageMissingMessage.
  ///
  /// In ru, this message translates to:
  /// **'Возможно, аккаунт был удалён или список ещё не успел обновиться'**
  String get accountUsageMissingMessage;

  /// No description provided for @accountUsageResetsAt.
  ///
  /// In ru, this message translates to:
  /// **'Будет сброшено {time}'**
  String accountUsageResetsAt(String time);

  /// No description provided for @accountUsageResetUnknown.
  ///
  /// In ru, this message translates to:
  /// **'Время сброса не получено'**
  String get accountUsageResetUnknown;

  /// No description provided for @accountUsageLastUpdated.
  ///
  /// In ru, this message translates to:
  /// **'Обновлено: {time}'**
  String accountUsageLastUpdated(String time);

  /// No description provided for @settingsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get settingsTitle;

  /// No description provided for @settingsSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Сеть, тема, API-ключ и поведение прокси'**
  String get settingsSubtitle;

  /// No description provided for @themeLabel.
  ///
  /// In ru, this message translates to:
  /// **'Тема'**
  String get themeLabel;

  /// No description provided for @themeModeSystem.
  ///
  /// In ru, this message translates to:
  /// **'Системная'**
  String get themeModeSystem;

  /// No description provided for @themeModeLight.
  ///
  /// In ru, this message translates to:
  /// **'Светлая'**
  String get themeModeLight;

  /// No description provided for @themeModeDark.
  ///
  /// In ru, this message translates to:
  /// **'Тёмная'**
  String get themeModeDark;

  /// No description provided for @dynamicThemeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Динамическая тема'**
  String get dynamicThemeTitle;

  /// No description provided for @dynamicThemeSubtitle.
  ///
  /// In ru, this message translates to:
  /// **''**
  String get dynamicThemeSubtitle;

  /// No description provided for @settingsAppearanceSectionTitle.
  ///
  /// In ru, this message translates to:
  /// **'Внешний вид'**
  String get settingsAppearanceSectionTitle;

  /// No description provided for @settingsAppearanceSectionSummary.
  ///
  /// In ru, this message translates to:
  /// **'Тема, динамические цвета и логирование'**
  String get settingsAppearanceSectionSummary;

  /// No description provided for @settingsNetworkSectionTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сеть'**
  String get settingsNetworkSectionTitle;

  /// No description provided for @settingsNetworkSectionSummary.
  ///
  /// In ru, this message translates to:
  /// **'Хост, порт и доступ из локальной сети'**
  String get settingsNetworkSectionSummary;

  /// No description provided for @settingsReliabilitySectionTitle.
  ///
  /// In ru, this message translates to:
  /// **'Система повторов'**
  String get settingsReliabilitySectionTitle;

  /// No description provided for @settingsReliabilitySectionSummary.
  ///
  /// In ru, this message translates to:
  /// **'Автоповторы и обработка лимитов API'**
  String get settingsReliabilitySectionSummary;

  /// No description provided for @settingsAccessSectionTitle.
  ///
  /// In ru, this message translates to:
  /// **'Доступ и запуск'**
  String get settingsAccessSectionTitle;

  /// No description provided for @settingsAccessSectionSummary.
  ///
  /// In ru, this message translates to:
  /// **'API-ключ и параметры запуска'**
  String get settingsAccessSectionSummary;

  /// No description provided for @apiKeyRequiredTitle.
  ///
  /// In ru, this message translates to:
  /// **'Требовать API-ключ'**
  String get apiKeyRequiredTitle;

  /// No description provided for @apiKeyRequiredSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'При отключении, разрешает запросы без Bearer-токена'**
  String get apiKeyRequiredSubtitle;

  /// No description provided for @settingsModelsSectionTitle.
  ///
  /// In ru, this message translates to:
  /// **'Модели'**
  String get settingsModelsSectionTitle;

  /// No description provided for @settingsModelsSectionSummary.
  ///
  /// In ru, this message translates to:
  /// **'Пользовательские ID моделей'**
  String get settingsModelsSectionSummary;

  /// No description provided for @hostLabel.
  ///
  /// In ru, this message translates to:
  /// **'Хост'**
  String get hostLabel;

  /// No description provided for @hostHelperText.
  ///
  /// In ru, this message translates to:
  /// **'Обычно 127.0.0.1'**
  String get hostHelperText;

  /// No description provided for @portLabel.
  ///
  /// In ru, this message translates to:
  /// **'Порт'**
  String get portLabel;

  /// No description provided for @portHelperText.
  ///
  /// In ru, this message translates to:
  /// **''**
  String get portHelperText;

  /// No description provided for @allowLanTitle.
  ///
  /// In ru, this message translates to:
  /// **'Доступ из LAN / Docker'**
  String get allowLanTitle;

  /// No description provided for @allowLanSubtitle.
  ///
  /// In ru, this message translates to:
  /// **''**
  String get allowLanSubtitle;

  /// No description provided for @androidBackgroundRuntimeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Фоновый запуск на Android'**
  String get androidBackgroundRuntimeTitle;

  /// No description provided for @androidBackgroundRuntimeSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Необходимо для непрерывной работы прокси'**
  String get androidBackgroundRuntimeSubtitle;

  /// No description provided for @requestRetriesLabel.
  ///
  /// In ru, this message translates to:
  /// **'Повторы запросов к Google'**
  String get requestRetriesLabel;

  /// No description provided for @requestRetriesHelperText.
  ///
  /// In ru, this message translates to:
  /// **''**
  String get requestRetriesHelperText;

  /// No description provided for @mark429AsUnhealthyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Отключать аккаунт при превышении лимитов (ошибка 429)'**
  String get mark429AsUnhealthyTitle;

  /// No description provided for @mark429AsUnhealthySubtitle.
  ///
  /// In ru, this message translates to:
  /// **''**
  String get mark429AsUnhealthySubtitle;

  /// No description provided for @loggingLabel.
  ///
  /// In ru, this message translates to:
  /// **'Логирование'**
  String get loggingLabel;

  /// No description provided for @loggingQuiet.
  ///
  /// In ru, this message translates to:
  /// **'Тихое'**
  String get loggingQuiet;

  /// No description provided for @loggingNormal.
  ///
  /// In ru, this message translates to:
  /// **'Обычное'**
  String get loggingNormal;

  /// No description provided for @loggingVerbose.
  ///
  /// In ru, this message translates to:
  /// **'Подробное'**
  String get loggingVerbose;

  /// No description provided for @unsafeRawLoggingTitle.
  ///
  /// In ru, this message translates to:
  /// **'Debug-логи'**
  String get unsafeRawLoggingTitle;

  /// No description provided for @unsafeRawLoggingSubtitle.
  ///
  /// In ru, this message translates to:
  /// **''**
  String get unsafeRawLoggingSubtitle;

  /// No description provided for @customModelsLabel.
  ///
  /// In ru, this message translates to:
  /// **'Пользовательские ID моделей'**
  String get customModelsLabel;

  /// No description provided for @customModelsHelperText.
  ///
  /// In ru, this message translates to:
  /// **'Точный ID модели, по одному на строке'**
  String get customModelsHelperText;

  /// No description provided for @settingsLoadErrorTitle.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить настройки'**
  String get settingsLoadErrorTitle;

  /// No description provided for @aboutTitle.
  ///
  /// In ru, this message translates to:
  /// **'О программе'**
  String get aboutTitle;

  /// No description provided for @aboutMenuSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Информация о программе'**
  String get aboutMenuSubtitle;

  /// No description provided for @aboutDescription.
  ///
  /// In ru, this message translates to:
  /// **'Локальный прокси-сервер, совместимый с OpenAI, для Gemini CLI с нативной оболочкой Flutter'**
  String get aboutDescription;

  /// No description provided for @aboutCheckUpdatesButton.
  ///
  /// In ru, this message translates to:
  /// **'Проверить обновление'**
  String get aboutCheckUpdatesButton;

  /// No description provided for @aboutCheckUpdatesUnavailableMessage.
  ///
  /// In ru, this message translates to:
  /// **'Проверка обновлений пока недоступна :('**
  String get aboutCheckUpdatesUnavailableMessage;

  /// No description provided for @aboutAutoCheckUpdatesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Проверять обновления автоматически'**
  String get aboutAutoCheckUpdatesTitle;

  /// No description provided for @aboutAutoCheckUpdatesSubtitle.
  ///
  /// In ru, this message translates to:
  /// **''**
  String get aboutAutoCheckUpdatesSubtitle;

  /// No description provided for @aboutAnalyticsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Аналитика'**
  String get aboutAnalyticsTitle;

  /// No description provided for @aboutAnalyticsSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Анонимная статистика использования. Помогает делать KiCk лучше.'**
  String get aboutAnalyticsSubtitle;

  /// No description provided for @copyProxyEndpointTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать URL прокси'**
  String get copyProxyEndpointTooltip;

  /// No description provided for @proxyEndpointCopiedMessage.
  ///
  /// In ru, this message translates to:
  /// **'URL прокси скопирован'**
  String get proxyEndpointCopiedMessage;

  /// No description provided for @copyApiKeyTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать API-ключ'**
  String get copyApiKeyTooltip;

  /// No description provided for @apiKeyCopiedMessage.
  ///
  /// In ru, this message translates to:
  /// **'API-ключ скопирован'**
  String get apiKeyCopiedMessage;

  /// No description provided for @apiKeyRegeneratedMessage.
  ///
  /// In ru, this message translates to:
  /// **'Новый API-ключ сохранён'**
  String get apiKeyRegeneratedMessage;

  /// No description provided for @regenerateApiKeyAction.
  ///
  /// In ru, this message translates to:
  /// **'Сгенерировать заново'**
  String get regenerateApiKeyAction;

  /// No description provided for @regenerateApiKeyDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сгенерировать новый API-ключ?'**
  String get regenerateApiKeyDialogTitle;

  /// No description provided for @regenerateApiKeyDialogMessage.
  ///
  /// In ru, this message translates to:
  /// **'Старый ключ будет немедленно отозван. Подключенным клиентам потребуется новый ключ для работы.'**
  String get regenerateApiKeyDialogMessage;

  /// No description provided for @regenerateApiKeyConfirmButton.
  ///
  /// In ru, this message translates to:
  /// **'Сгенерировать'**
  String get regenerateApiKeyConfirmButton;

  /// No description provided for @noActiveAccountsWarning.
  ///
  /// In ru, this message translates to:
  /// **'Активных аккаунтов нет. Прокси всё равно запустится, но не сможет обработать запросы, пока вы не добавите или не включите аккаунт.'**
  String get noActiveAccountsWarning;

  /// No description provided for @pinWindowTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Закрепить поверх остальных окон'**
  String get pinWindowTooltip;

  /// No description provided for @unpinWindowTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Открепить окно'**
  String get unpinWindowTooltip;

  /// No description provided for @disclaimerTitle.
  ///
  /// In ru, this message translates to:
  /// **'Отказ от ответственности'**
  String get disclaimerTitle;

  /// No description provided for @disclaimerBodyLineOne.
  ///
  /// In ru, this message translates to:
  /// **'Данное программное обеспечение предоставляется \"как есть\"'**
  String get disclaimerBodyLineOne;

  /// No description provided for @disclaimerBodyLineTwo.
  ///
  /// In ru, this message translates to:
  /// **'Предназначено исключительно для некоммерческого использования в образовательных и исследовательских целях'**
  String get disclaimerBodyLineTwo;

  /// No description provided for @disclaimerLinkPrefix.
  ///
  /// In ru, this message translates to:
  /// **'Подробнее'**
  String get disclaimerLinkPrefix;

  /// No description provided for @disclaimerAnalyticsConsentLabel.
  ///
  /// In ru, this message translates to:
  /// **'Разрешить отправку анонимной аналитики'**
  String get disclaimerAnalyticsConsentLabel;

  /// No description provided for @logsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Логи'**
  String get logsTitle;

  /// No description provided for @logsSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'История запросов и ошибок'**
  String get logsSubtitle;

  /// No description provided for @logsSearchHint.
  ///
  /// In ru, this message translates to:
  /// **'Поиск по маршруту, сообщению'**
  String get logsSearchHint;

  /// No description provided for @logsTotalCount.
  ///
  /// In ru, this message translates to:
  /// **'Всего: {count}'**
  String logsTotalCount(int count);

  /// No description provided for @logsFilteredCount.
  ///
  /// In ru, this message translates to:
  /// **'После фильтра: {count}'**
  String logsFilteredCount(int count);

  /// No description provided for @logsEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Логи пусты'**
  String get logsEmptyTitle;

  /// No description provided for @logsLoadErrorTitle.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить логи'**
  String get logsLoadErrorTitle;

  /// No description provided for @logsExportTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить лог-файл'**
  String get logsExportTooltip;

  /// No description provided for @logsShareTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Поделиться логами'**
  String get logsShareTooltip;

  /// No description provided for @logsNothingToExportMessage.
  ///
  /// In ru, this message translates to:
  /// **'Нет логов для экспорта'**
  String get logsNothingToExportMessage;

  /// No description provided for @logsExportedMessage.
  ///
  /// In ru, this message translates to:
  /// **'Логи сохранены: {fileName}'**
  String logsExportedMessage(String fileName);

  /// No description provided for @logsExportFailedMessage.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить логи: {error}'**
  String logsExportFailedMessage(String error);

  /// No description provided for @logsShareFailedMessage.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось поделиться логами: {error}'**
  String logsShareFailedMessage(String error);

  /// No description provided for @accountDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Аккаунт Google'**
  String get accountDialogTitle;

  /// No description provided for @projectIdLabel.
  ///
  /// In ru, this message translates to:
  /// **'PROJECT_ID'**
  String get projectIdLabel;

  /// No description provided for @projectIdHint.
  ///
  /// In ru, this message translates to:
  /// **'my-google-cloud-project'**
  String get projectIdHint;

  /// No description provided for @projectIdConsoleLinkLabel.
  ///
  /// In ru, this message translates to:
  /// **'Узнать ID проекта'**
  String get projectIdConsoleLinkLabel;

  /// No description provided for @projectIdRequiredError.
  ///
  /// In ru, this message translates to:
  /// **'Укажите PROJECT_ID'**
  String get projectIdRequiredError;

  /// No description provided for @projectIdLookupFailedMessage.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть Google Cloud Console'**
  String get projectIdLookupFailedMessage;

  /// No description provided for @accountNameLabel.
  ///
  /// In ru, this message translates to:
  /// **'Название'**
  String get accountNameLabel;

  /// No description provided for @accountNameHint.
  ///
  /// In ru, this message translates to:
  /// **'Основной аккаунт'**
  String get accountNameHint;

  /// No description provided for @priorityLabel.
  ///
  /// In ru, this message translates to:
  /// **'Роль в очереди'**
  String get priorityLabel;

  /// No description provided for @priorityHelperText.
  ///
  /// In ru, this message translates to:
  /// **'Основные аккаунты получают запросы в первую очередь. Аккаунты одного уровня чередуются.'**
  String get priorityHelperText;

  /// No description provided for @priorityLevelPrimary.
  ///
  /// In ru, this message translates to:
  /// **'Основной'**
  String get priorityLevelPrimary;

  /// No description provided for @priorityLevelNormal.
  ///
  /// In ru, this message translates to:
  /// **'Обычный'**
  String get priorityLevelNormal;

  /// No description provided for @priorityLevelReserve.
  ///
  /// In ru, this message translates to:
  /// **'Резервный'**
  String get priorityLevelReserve;

  /// No description provided for @blockedModelsLabel.
  ///
  /// In ru, this message translates to:
  /// **'Заблокированные модели'**
  String get blockedModelsLabel;

  /// No description provided for @blockedModelsHelperText.
  ///
  /// In ru, this message translates to:
  /// **'По одной модели на строке'**
  String get blockedModelsHelperText;

  /// No description provided for @cancelButton.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get cancelButton;

  /// No description provided for @continueButton.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get continueButton;

  /// No description provided for @navHome.
  ///
  /// In ru, this message translates to:
  /// **'Главная'**
  String get navHome;

  /// No description provided for @navAccounts.
  ///
  /// In ru, this message translates to:
  /// **'Аккаунты'**
  String get navAccounts;

  /// No description provided for @navSettings.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get navSettings;

  /// No description provided for @navLogs.
  ///
  /// In ru, this message translates to:
  /// **'Логи'**
  String get navLogs;

  /// No description provided for @runtimeChannelName.
  ///
  /// In ru, this message translates to:
  /// **'Фоновый прокси KiCk'**
  String get runtimeChannelName;

  /// No description provided for @runtimeChannelDescription.
  ///
  /// In ru, this message translates to:
  /// **'Удерживает прокси активным в фоне'**
  String get runtimeChannelDescription;

  /// No description provided for @runtimeNotificationTitle.
  ///
  /// In ru, this message translates to:
  /// **'Прокси KiCk запущен'**
  String get runtimeNotificationTitle;

  /// No description provided for @runtimeNotificationReturn.
  ///
  /// In ru, this message translates to:
  /// **'Нажмите, чтобы вернуться в приложение'**
  String get runtimeNotificationReturn;

  /// No description provided for @runtimeNotificationManage.
  ///
  /// In ru, this message translates to:
  /// **'Нажмите, чтобы управлять аккаунтами и настройками'**
  String get runtimeNotificationManage;

  /// No description provided for @runtimeNotificationActive.
  ///
  /// In ru, this message translates to:
  /// **'Прокси активен'**
  String get runtimeNotificationActive;

  /// No description provided for @errorNetworkUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось связаться с серверами Google. Проверьте интернет и попробуйте снова.'**
  String get errorNetworkUnavailable;

  /// No description provided for @errorGoogleServiceUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Сервис Google временно недоступен. Повторите попытку позже.'**
  String get errorGoogleServiceUnavailable;

  /// No description provided for @errorInvalidServiceResponse.
  ///
  /// In ru, this message translates to:
  /// **'Сервер ответил что-то непонятное. Попробуйте ещё раз'**
  String get errorInvalidServiceResponse;

  /// No description provided for @errorUnknown.
  ///
  /// In ru, this message translates to:
  /// **'Произошла неизвестная ошибка. Попробуйте снова.'**
  String get errorUnknown;

  /// No description provided for @errorOauthTokensMissing.
  ///
  /// In ru, this message translates to:
  /// **'Для этого аккаунта не найдены токены авторизации. Переавторизуйте аккаунт'**
  String get errorOauthTokensMissing;

  /// No description provided for @errorAccountNotFound.
  ///
  /// In ru, this message translates to:
  /// **'Аккаунт не найден. Возможно, он уже был удалён.'**
  String get errorAccountNotFound;

  /// No description provided for @errorPortAlreadyInUse.
  ///
  /// In ru, this message translates to:
  /// **'Этот порт уже занят другим приложением. Выберите другой порт в настройках.'**
  String get errorPortAlreadyInUse;

  /// No description provided for @errorPermissionDenied.
  ///
  /// In ru, this message translates to:
  /// **'Системе не хватило разрешений для запуска. Проверьте настройки приложения и повторите попытку.'**
  String get errorPermissionDenied;

  /// No description provided for @errorGoogleRateLimitedRetry.
  ///
  /// In ru, this message translates to:
  /// **'Google временно ограничил запросы для этого аккаунта. Повторите попытку через {retryHint}.'**
  String errorGoogleRateLimitedRetry(String retryHint);

  /// No description provided for @errorGoogleRateLimitedLater.
  ///
  /// In ru, this message translates to:
  /// **'Google временно ограничил запросы для этого аккаунта. Повторите попытку позже.'**
  String get errorGoogleRateLimitedLater;

  /// No description provided for @errorGoogleAccountVerificationRequired.
  ///
  /// In ru, this message translates to:
  /// **'Google просит подтвердить этот аккаунт. Откройте страницу подтверждения и войдите тем же Google-аккаунтом.'**
  String get errorGoogleAccountVerificationRequired;

  /// No description provided for @errorGoogleProjectIdMissing.
  ///
  /// In ru, this message translates to:
  /// **'Google не смог определить корректный PROJECT_ID для этого аккаунта или запроса. Проверьте PROJECT_ID в аккаунте и при необходимости переавторизуйте его.'**
  String get errorGoogleProjectIdMissing;

  /// No description provided for @errorGoogleProjectAccessDenied.
  ///
  /// In ru, this message translates to:
  /// **'Google отклонил запрос для этого проекта или аккаунта. Проверьте PROJECT_ID, выбранный аккаунт и что Gemini Code Assist активирован именно для этого проекта.'**
  String get errorGoogleProjectAccessDenied;

  /// No description provided for @errorAuthExpired.
  ///
  /// In ru, this message translates to:
  /// **'Авторизация истекла или стала недействительной. Переавторизуйте аккаунт и попробуйте снова.'**
  String get errorAuthExpired;

  /// No description provided for @errorGoogleCapacity.
  ///
  /// In ru, this message translates to:
  /// **'Сервера Google временно перегружены. Повторите попытку чуть позже.'**
  String get errorGoogleCapacity;

  /// No description provided for @errorUnsupportedModel.
  ///
  /// In ru, this message translates to:
  /// **'Выбранная модель сейчас недоступна для этого аккаунта.'**
  String get errorUnsupportedModel;

  /// No description provided for @errorInvalidJson.
  ///
  /// In ru, this message translates to:
  /// **'Запрос имеет неверный формат JSON.'**
  String get errorInvalidJson;

  /// No description provided for @errorUnexpectedResponse.
  ///
  /// In ru, this message translates to:
  /// **'Сервис вернул неожиданный ответ. Повторите попытку.'**
  String get errorUnexpectedResponse;

  /// No description provided for @errorQuotaExhausted.
  ///
  /// In ru, this message translates to:
  /// **'Квота этого аккаунта исчерпана. Дождитесь сброса лимита или используйте другой аккаунт.'**
  String get errorQuotaExhausted;

  /// No description provided for @errorQuotaExhaustedRetry.
  ///
  /// In ru, this message translates to:
  /// **'Квота этого аккаунта исчерпана. Повторите попытку через {retryHint} или используйте другой аккаунт.'**
  String errorQuotaExhaustedRetry(String retryHint);

  /// No description provided for @errorInvalidRequestRejected.
  ///
  /// In ru, this message translates to:
  /// **'Запрос имеет неверный формат и был отклонён.'**
  String get errorInvalidRequestRejected;

  /// No description provided for @errorReasoningConfigRejected.
  ///
  /// In ru, this message translates to:
  /// **'Google отклонил параметры reasoning/thinking для этой модели. Верните Reasoning Effort в Auto или уберите кастомный thinking config.'**
  String get errorReasoningConfigRejected;

  /// No description provided for @durationFewSeconds.
  ///
  /// In ru, this message translates to:
  /// **'несколько секунд'**
  String get durationFewSeconds;

  /// No description provided for @durationSeconds.
  ///
  /// In ru, this message translates to:
  /// **'{seconds} сек'**
  String durationSeconds(int seconds);

  /// No description provided for @durationMinutes.
  ///
  /// In ru, this message translates to:
  /// **'{minutes} мин'**
  String durationMinutes(int minutes);

  /// No description provided for @durationMinutesSeconds.
  ///
  /// In ru, this message translates to:
  /// **'{minutes} мин {seconds} сек'**
  String durationMinutesSeconds(int minutes, int seconds);

  /// No description provided for @durationHours.
  ///
  /// In ru, this message translates to:
  /// **'{hours} ч'**
  String durationHours(int hours);

  /// No description provided for @durationHoursMinutes.
  ///
  /// In ru, this message translates to:
  /// **'{hours} ч {minutes} мин'**
  String durationHoursMinutes(int hours, int minutes);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
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
