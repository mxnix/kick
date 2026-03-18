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
  /// **'Локальный прокси для Gemini CLI'**
  String get shellSubtitle;

  /// No description provided for @connectGoogleAccountTitle.
  ///
  /// In ru, this message translates to:
  /// **'Подключить Google-аккаунт'**
  String get connectGoogleAccountTitle;

  /// No description provided for @homeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Главная'**
  String get homeTitle;

  /// No description provided for @proxyRunningStatus.
  ///
  /// In ru, this message translates to:
  /// **'Запущен'**
  String get proxyRunningStatus;

  /// No description provided for @proxyStoppedStatus.
  ///
  /// In ru, this message translates to:
  /// **'Остановлен'**
  String get proxyStoppedStatus;

  /// No description provided for @embeddedProxyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Прокси-сервер'**
  String get embeddedProxyTitle;

  /// No description provided for @proxyAddress.
  ///
  /// In ru, this message translates to:
  /// **'Адрес: {host}:{port}'**
  String proxyAddress(String host, int port);

  /// No description provided for @proxyEndpointTitle.
  ///
  /// In ru, this message translates to:
  /// **'Адрес прокси'**
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

  /// No description provided for @openAccountsButton.
  ///
  /// In ru, this message translates to:
  /// **'Открыть окно с аккаунтами'**
  String get openAccountsButton;

  /// No description provided for @connectAccountShortButton.
  ///
  /// In ru, this message translates to:
  /// **'Подключить аккаунт'**
  String get connectAccountShortButton;

  /// No description provided for @uptimeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Время работы'**
  String get uptimeTitle;

  /// No description provided for @uptimeNotStarted.
  ///
  /// In ru, this message translates to:
  /// **'Еще не запущен'**
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
  /// **'Не требуется'**
  String get apiKeyDisabledValue;

  /// No description provided for @changeApiKeyLinkLabel.
  ///
  /// In ru, this message translates to:
  /// **'Изменить API-ключ'**
  String get changeApiKeyLinkLabel;

  /// No description provided for @loadingValue.
  ///
  /// In ru, this message translates to:
  /// **'Загрузка...'**
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
  /// **'Аккаунты'**
  String get accountsTitle;

  /// No description provided for @accountsSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Подключайте Google-аккаунты и управляйте ими'**
  String get accountsSubtitle;

  /// No description provided for @addButton.
  ///
  /// In ru, this message translates to:
  /// **'Добавить'**
  String get addButton;

  /// No description provided for @accountsEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Аккаунтов пока нет'**
  String get accountsEmptyTitle;

  /// No description provided for @accountsEmptyMessage.
  ///
  /// In ru, this message translates to:
  /// **'Подключите хотя бы один Google-аккаунт'**
  String get accountsEmptyMessage;

  /// No description provided for @connectAccountButton.
  ///
  /// In ru, this message translates to:
  /// **'Подключить Google-аккаунт'**
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
  /// **'Приоритет: {priorityLabel}'**
  String priorityChip(String priorityLabel);

  /// No description provided for @accountCoolingDownStatus.
  ///
  /// In ru, this message translates to:
  /// **'На паузе'**
  String get accountCoolingDownStatus;

  /// No description provided for @accountReadyStatus.
  ///
  /// In ru, this message translates to:
  /// **'Готов к работе'**
  String get accountReadyStatus;

  /// No description provided for @accountDisabledStatus.
  ///
  /// In ru, this message translates to:
  /// **'Выключен'**
  String get accountDisabledStatus;

  /// No description provided for @unsupportedModelsList.
  ///
  /// In ru, this message translates to:
  /// **'Не использовать для моделей: {models}'**
  String unsupportedModelsList(String models);

  /// No description provided for @editAccountTitle.
  ///
  /// In ru, this message translates to:
  /// **'Редактирование аккаунта'**
  String get editAccountTitle;

  /// No description provided for @editButton.
  ///
  /// In ru, this message translates to:
  /// **'Редактировать'**
  String get editButton;

  /// No description provided for @reauthorizeAccountTitle.
  ///
  /// In ru, this message translates to:
  /// **'Переподключить аккаунт'**
  String get reauthorizeAccountTitle;

  /// No description provided for @reauthorizeButton.
  ///
  /// In ru, this message translates to:
  /// **'Переподключить'**
  String get reauthorizeButton;

  /// No description provided for @accountProjectCheckButton.
  ///
  /// In ru, this message translates to:
  /// **'Проверить доступ к проекту'**
  String get accountProjectCheckButton;

  /// No description provided for @accountProjectCheckInProgressMessage.
  ///
  /// In ru, this message translates to:
  /// **'Проверка...'**
  String get accountProjectCheckInProgressMessage;

  /// No description provided for @accountProjectCheckSuccessTitle.
  ///
  /// In ru, this message translates to:
  /// **'Доступ к проекту подтвержден'**
  String get accountProjectCheckSuccessTitle;

  /// No description provided for @accountProjectCheckSuccessMessage.
  ///
  /// In ru, this message translates to:
  /// **'KiCk смог выполнить тестовый запрос к Google для этого аккаунта и проекта'**
  String get accountProjectCheckSuccessMessage;

  /// No description provided for @accountProjectCheckFailureTitle.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось проверить'**
  String get accountProjectCheckFailureTitle;

  /// No description provided for @resetCooldownTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить состояние'**
  String get resetCooldownTooltip;

  /// No description provided for @clearCooldownAction.
  ///
  /// In ru, this message translates to:
  /// **'Снять паузу'**
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

  /// No description provided for @moreButton.
  ///
  /// In ru, this message translates to:
  /// **'Еще'**
  String get moreButton;

  /// No description provided for @deleteAccountDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Удалить аккаунт?'**
  String get deleteAccountDialogTitle;

  /// No description provided for @deleteAccountDialogMessage.
  ///
  /// In ru, this message translates to:
  /// **'Аккаунт {label} будет удален из KiCk. При необходимости его можно подключить снова позже.'**
  String deleteAccountDialogMessage(String label);

  /// No description provided for @deleteAccountConfirmButton.
  ///
  /// In ru, this message translates to:
  /// **'Удалить аккаунт'**
  String get deleteAccountConfirmButton;

  /// No description provided for @accountUsageTitle.
  ///
  /// In ru, this message translates to:
  /// **'Лимиты аккаунта'**
  String get accountUsageTitle;

  /// No description provided for @accountUsageProviderLabel.
  ///
  /// In ru, this message translates to:
  /// **'Авторизация Gemini CLI (OAuth)'**
  String get accountUsageProviderLabel;

  /// No description provided for @accountUsageRefreshTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Обновить'**
  String get accountUsageRefreshTooltip;

  /// No description provided for @accountUsageStatusHealthy.
  ///
  /// In ru, this message translates to:
  /// **'Доступен'**
  String get accountUsageStatusHealthy;

  /// No description provided for @accountUsageStatusCoolingDown.
  ///
  /// In ru, this message translates to:
  /// **'Ограничен'**
  String get accountUsageStatusCoolingDown;

  /// No description provided for @accountUsageStatusLowQuota.
  ///
  /// In ru, this message translates to:
  /// **'Лимит заканчивается'**
  String get accountUsageStatusLowQuota;

  /// No description provided for @accountUsageStatusDisabled.
  ///
  /// In ru, this message translates to:
  /// **'Выключен'**
  String get accountUsageStatusDisabled;

  /// No description provided for @accountQuotaWarningStatus.
  ///
  /// In ru, this message translates to:
  /// **'Лимит заканчивается'**
  String get accountQuotaWarningStatus;

  /// No description provided for @accountUsageLoadErrorTitle.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить данные по лимитам'**
  String get accountUsageLoadErrorTitle;

  /// No description provided for @accountUsageRetryButton.
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get accountUsageRetryButton;

  /// No description provided for @accountUsageVerifyAccountButton.
  ///
  /// In ru, this message translates to:
  /// **'Подтвердить в Google'**
  String get accountUsageVerifyAccountButton;

  /// No description provided for @openGoogleCloudButton.
  ///
  /// In ru, this message translates to:
  /// **'Открыть Google Cloud'**
  String get openGoogleCloudButton;

  /// No description provided for @accountUsageVerificationOpenFailedMessage.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть страницу подтверждения в Google'**
  String get accountUsageVerificationOpenFailedMessage;

  /// No description provided for @accountErrorActionOpenFailedMessage.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть страницу Google'**
  String get accountErrorActionOpenFailedMessage;

  /// No description provided for @accountUsageEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Данные по лимитам недоступны'**
  String get accountUsageEmptyTitle;

  /// No description provided for @accountUsageEmptyMessage.
  ///
  /// In ru, this message translates to:
  /// **'Google не прислал данные по лимитам для этого аккаунта'**
  String get accountUsageEmptyMessage;

  /// No description provided for @accountUsageMissingTitle.
  ///
  /// In ru, this message translates to:
  /// **'Аккаунт не найден'**
  String get accountUsageMissingTitle;

  /// No description provided for @accountUsageMissingSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Информация по лимитам'**
  String get accountUsageMissingSubtitle;

  /// No description provided for @accountUsageMissingMessage.
  ///
  /// In ru, this message translates to:
  /// **'Возможно, аккаунт уже удален или список еще не успел обновиться'**
  String get accountUsageMissingMessage;

  /// No description provided for @accountUsageResetsAt.
  ///
  /// In ru, this message translates to:
  /// **'Сбросится {time}'**
  String accountUsageResetsAt(String time);

  /// No description provided for @accountUsageResetUnknown.
  ///
  /// In ru, this message translates to:
  /// **'Время следующего сброса неизвестно'**
  String get accountUsageResetUnknown;

  /// No description provided for @accountUsageLastUpdated.
  ///
  /// In ru, this message translates to:
  /// **'Данные обновлены: {time}'**
  String accountUsageLastUpdated(String time);

  /// No description provided for @accountUsageModelCount.
  ///
  /// In ru, this message translates to:
  /// **'Моделей: {count}'**
  String accountUsageModelCount(int count);

  /// No description provided for @accountUsageAttentionCount.
  ///
  /// In ru, this message translates to:
  /// **'Низкий остаток: {count}'**
  String accountUsageAttentionCount(int count);

  /// No description provided for @accountUsageCriticalCount.
  ///
  /// In ru, this message translates to:
  /// **'Почти исчерпано: {count}'**
  String accountUsageCriticalCount(int count);

  /// No description provided for @accountUsageHealthyCount.
  ///
  /// In ru, this message translates to:
  /// **'В норме: {count}'**
  String accountUsageHealthyCount(int count);

  /// No description provided for @accountUsageTokenType.
  ///
  /// In ru, this message translates to:
  /// **'Тип лимита: {value}'**
  String accountUsageTokenType(String value);

  /// No description provided for @accountUsageUsedPercent.
  ///
  /// In ru, this message translates to:
  /// **'Израсходовано {value}%'**
  String accountUsageUsedPercent(String value);

  /// No description provided for @accountUsageBucketHealthy.
  ///
  /// In ru, this message translates to:
  /// **'Достаточно'**
  String get accountUsageBucketHealthy;

  /// No description provided for @accountUsageBucketLow.
  ///
  /// In ru, this message translates to:
  /// **'Заканчивается'**
  String get accountUsageBucketLow;

  /// No description provided for @accountUsageBucketCritical.
  ///
  /// In ru, this message translates to:
  /// **'Почти исчерпано'**
  String get accountUsageBucketCritical;

  /// No description provided for @settingsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get settingsTitle;

  /// No description provided for @settingsSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Сеть, оформление, API-ключ и работа прокси'**
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
  /// **'Использовать динамические цвета системы'**
  String get dynamicThemeSubtitle;

  /// No description provided for @settingsAppearanceSectionTitle.
  ///
  /// In ru, this message translates to:
  /// **'Оформление и поведение'**
  String get settingsAppearanceSectionTitle;

  /// No description provided for @settingsAppearanceSectionSummary.
  ///
  /// In ru, this message translates to:
  /// **'Тема, логи и работа приложения'**
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
  /// **'Повторы и лимиты'**
  String get settingsReliabilitySectionTitle;

  /// No description provided for @settingsReliabilitySectionSummary.
  ///
  /// In ru, this message translates to:
  /// **'Автоповторы и реакция на ограничения API'**
  String get settingsReliabilitySectionSummary;

  /// No description provided for @settingsAccessSectionTitle.
  ///
  /// In ru, this message translates to:
  /// **'Доступ и запуск'**
  String get settingsAccessSectionTitle;

  /// No description provided for @settingsAccessSectionSummary.
  ///
  /// In ru, this message translates to:
  /// **'API-ключ и запуск приложения'**
  String get settingsAccessSectionSummary;

  /// No description provided for @apiKeyRequiredTitle.
  ///
  /// In ru, this message translates to:
  /// **'Требовать API-ключ'**
  String get apiKeyRequiredTitle;

  /// No description provided for @apiKeyRequiredSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Если выключить, запросы будут приниматься без Bearer-токена'**
  String get apiKeyRequiredSubtitle;

  /// No description provided for @windowsTrayTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сворачивать в трей'**
  String get windowsTrayTitle;

  /// No description provided for @windowsTraySubtitle.
  ///
  /// In ru, this message translates to:
  /// **'При закрытии окно не завершает работу, а скрывает KiCk в системный трей'**
  String get windowsTraySubtitle;

  /// No description provided for @windowsLaunchAtStartupTitle.
  ///
  /// In ru, this message translates to:
  /// **'Запускать вместе с Windows'**
  String get windowsLaunchAtStartupTitle;

  /// No description provided for @windowsLaunchAtStartupSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'KiCk будет автоматически запускаться при входе в систему'**
  String get windowsLaunchAtStartupSubtitle;

  /// No description provided for @windowsTrayNotificationTitle.
  ///
  /// In ru, this message translates to:
  /// **'KiCk продолжает работать'**
  String get windowsTrayNotificationTitle;

  /// No description provided for @windowsTrayNotificationBody.
  ///
  /// In ru, this message translates to:
  /// **'Приложение свернуто в системный трей'**
  String get windowsTrayNotificationBody;

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

  /// No description provided for @hostRequiredError.
  ///
  /// In ru, this message translates to:
  /// **'Укажите адрес хоста'**
  String get hostRequiredError;

  /// No description provided for @hostInvalidError.
  ///
  /// In ru, this message translates to:
  /// **'Адрес не должен содержать пробелы'**
  String get hostInvalidError;

  /// No description provided for @hostLanDisabledError.
  ///
  /// In ru, this message translates to:
  /// **'Чтобы использовать 0.0.0.0, включите доступ из локальной сети'**
  String get hostLanDisabledError;

  /// No description provided for @portLabel.
  ///
  /// In ru, this message translates to:
  /// **'Порт'**
  String get portLabel;

  /// No description provided for @portHelperText.
  ///
  /// In ru, this message translates to:
  /// **'По умолчанию 3000'**
  String get portHelperText;

  /// No description provided for @portInvalidError.
  ///
  /// In ru, this message translates to:
  /// **'Укажите порт от 1 до 65535'**
  String get portInvalidError;

  /// No description provided for @allowLanTitle.
  ///
  /// In ru, this message translates to:
  /// **'Доступ из локальной сети и Docker'**
  String get allowLanTitle;

  /// No description provided for @allowLanSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Прокси будет слушать 0.0.0.0 и станет доступен из локальной сети и контейнеров'**
  String get allowLanSubtitle;

  /// No description provided for @androidBackgroundRuntimeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Работа в фоне на Android'**
  String get androidBackgroundRuntimeTitle;

  /// No description provided for @androidBackgroundRuntimeSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Нужно, чтобы прокси не останавливался при сворачивании приложения'**
  String get androidBackgroundRuntimeSubtitle;

  /// No description provided for @requestRetriesLabel.
  ///
  /// In ru, this message translates to:
  /// **'Количество повторов запросов к Google'**
  String get requestRetriesLabel;

  /// No description provided for @requestRetriesHelperText.
  ///
  /// In ru, this message translates to:
  /// **'Сколько раз KiCk повторит запрос после временной ошибки'**
  String get requestRetriesHelperText;

  /// No description provided for @requestRetriesInvalidError.
  ///
  /// In ru, this message translates to:
  /// **'Укажите число от 0 до 20'**
  String get requestRetriesInvalidError;

  /// No description provided for @mark429AsUnhealthyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Временно выводить аккаунт из ротации при ошибке 429'**
  String get mark429AsUnhealthyTitle;

  /// No description provided for @mark429AsUnhealthySubtitle.
  ///
  /// In ru, this message translates to:
  /// **'После ошибки 429 KiCk пометит аккаунт как временно недоступный и переключится на другой'**
  String get mark429AsUnhealthySubtitle;

  /// No description provided for @loggingLabel.
  ///
  /// In ru, this message translates to:
  /// **'Логирование'**
  String get loggingLabel;

  /// No description provided for @loggingQuiet.
  ///
  /// In ru, this message translates to:
  /// **'Минимальное'**
  String get loggingQuiet;

  /// No description provided for @loggingNormal.
  ///
  /// In ru, this message translates to:
  /// **'Стандартное'**
  String get loggingNormal;

  /// No description provided for @loggingVerbose.
  ///
  /// In ru, this message translates to:
  /// **'Подробное'**
  String get loggingVerbose;

  /// No description provided for @unsafeRawLoggingTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сырые логи отладки'**
  String get unsafeRawLoggingTitle;

  /// No description provided for @unsafeRawLoggingSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Сохраняет содержимое запросов и ответов. Включайте только для отладки!'**
  String get unsafeRawLoggingSubtitle;

  /// No description provided for @customModelsLabel.
  ///
  /// In ru, this message translates to:
  /// **'Пользовательские ID моделей'**
  String get customModelsLabel;

  /// No description provided for @customModelsHelperText.
  ///
  /// In ru, this message translates to:
  /// **'Указывайте точный ID модели, по одному на строке'**
  String get customModelsHelperText;

  /// No description provided for @settingsSavingStatus.
  ///
  /// In ru, this message translates to:
  /// **'Сохраняем изменения...'**
  String get settingsSavingStatus;

  /// No description provided for @settingsSavedStatus.
  ///
  /// In ru, this message translates to:
  /// **'Изменения сохранены'**
  String get settingsSavedStatus;

  /// No description provided for @settingsValidationStatus.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте поля с ошибками'**
  String get settingsValidationStatus;

  /// No description provided for @settingsSaveFailedStatus.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить изменения'**
  String get settingsSaveFailedStatus;

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
  /// **'Версия, обновления и аналитика'**
  String get aboutMenuSubtitle;

  /// No description provided for @aboutDescription.
  ///
  /// In ru, this message translates to:
  /// **'Локальный OpenAI-совместимый прокси для Gemini CLI в нативном Flutter-приложении'**
  String get aboutDescription;

  /// No description provided for @aboutUpdatesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Обновления'**
  String get aboutUpdatesTitle;

  /// No description provided for @aboutUpdatesChecking.
  ///
  /// In ru, this message translates to:
  /// **'Проверяем обновления на GitHub...'**
  String get aboutUpdatesChecking;

  /// No description provided for @aboutUpdateAvailableTitle.
  ///
  /// In ru, this message translates to:
  /// **'Доступно обновление'**
  String get aboutUpdateAvailableTitle;

  /// No description provided for @aboutUpdateAvailableMessage.
  ///
  /// In ru, this message translates to:
  /// **'Доступна версия {latestVersion}. Сейчас у вас установлена {currentVersion}.'**
  String aboutUpdateAvailableMessage(String latestVersion, String currentVersion);

  /// No description provided for @aboutUpToDateTitle.
  ///
  /// In ru, this message translates to:
  /// **'Обновлений нет'**
  String get aboutUpToDateTitle;

  /// No description provided for @aboutUpToDateMessage.
  ///
  /// In ru, this message translates to:
  /// **'У вас установлена актуальная версия: {currentVersion}.'**
  String aboutUpToDateMessage(String currentVersion);

  /// No description provided for @aboutUpdateCheckFailedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось проверить обновления'**
  String get aboutUpdateCheckFailedTitle;

  /// No description provided for @aboutUpdateCheckFailedMessage.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось получить информацию о релизах с GitHub.'**
  String get aboutUpdateCheckFailedMessage;

  /// No description provided for @aboutOpenReleaseButton.
  ///
  /// In ru, this message translates to:
  /// **'Открыть релиз'**
  String get aboutOpenReleaseButton;

  /// No description provided for @aboutRetryUpdateCheckButton.
  ///
  /// In ru, this message translates to:
  /// **'Проверить еще раз'**
  String get aboutRetryUpdateCheckButton;

  /// No description provided for @aboutAnalyticsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Аналитика'**
  String get aboutAnalyticsTitle;

  /// No description provided for @aboutAnalyticsSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Анонимная статистика использования помогает улучшать KiCk.'**
  String get aboutAnalyticsSubtitle;

  /// No description provided for @copyProxyEndpointTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать адрес прокси'**
  String get copyProxyEndpointTooltip;

  /// No description provided for @proxyEndpointCopiedMessage.
  ///
  /// In ru, this message translates to:
  /// **'Адрес прокси скопирован'**
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

  /// No description provided for @homeOnboardingTitle.
  ///
  /// In ru, this message translates to:
  /// **'С чего начать'**
  String get homeOnboardingTitle;

  /// No description provided for @homeOnboardingSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Небольшая подсказка для первого запуска'**
  String get homeOnboardingSubtitle;

  /// No description provided for @homeOnboardingAccountsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Подключите аккаунт'**
  String get homeOnboardingAccountsTitle;

  /// No description provided for @homeOnboardingAccountsMessage.
  ///
  /// In ru, this message translates to:
  /// **'Без активного аккаунта KiCk не сможет обрабатывать запросы.'**
  String get homeOnboardingAccountsMessage;

  /// No description provided for @homeOnboardingEndpointTitle.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте адрес прокси'**
  String get homeOnboardingEndpointTitle;

  /// No description provided for @homeOnboardingEndpointMessage.
  ///
  /// In ru, this message translates to:
  /// **'Когда все будет готово, используйте адрес {endpoint} в своем клиенте.'**
  String homeOnboardingEndpointMessage(String endpoint);

  /// No description provided for @homeOnboardingStartTitle.
  ///
  /// In ru, this message translates to:
  /// **'Запустите прокси'**
  String get homeOnboardingStartTitle;

  /// No description provided for @homeOnboardingStartMessage.
  ///
  /// In ru, this message translates to:
  /// **'После запуска KiCk начнет принимать запросы на этом устройстве.'**
  String get homeOnboardingStartMessage;

  /// No description provided for @homeOnboardingFooter.
  ///
  /// In ru, this message translates to:
  /// **'Если аккаунт уже подключен, просто включите его на экране аккаунтов и вернитесь сюда.'**
  String get homeOnboardingFooter;

  /// No description provided for @apiKeyRegeneratedMessage.
  ///
  /// In ru, this message translates to:
  /// **'Новый API-ключ сохранен'**
  String get apiKeyRegeneratedMessage;

  /// No description provided for @regenerateApiKeyAction.
  ///
  /// In ru, this message translates to:
  /// **'Создать новый API-ключ'**
  String get regenerateApiKeyAction;

  /// No description provided for @regenerateApiKeyDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Создать новый API-ключ?'**
  String get regenerateApiKeyDialogTitle;

  /// No description provided for @regenerateApiKeyDialogMessage.
  ///
  /// In ru, this message translates to:
  /// **'Старый ключ будет сразу отозван. Всем подключенным клиентам понадобится новый ключ для работы.'**
  String get regenerateApiKeyDialogMessage;

  /// No description provided for @regenerateApiKeyConfirmButton.
  ///
  /// In ru, this message translates to:
  /// **'Сгенерировать'**
  String get regenerateApiKeyConfirmButton;

  /// No description provided for @trayOpenWindowAction.
  ///
  /// In ru, this message translates to:
  /// **'Открыть окно'**
  String get trayOpenWindowAction;

  /// No description provided for @trayHideToTrayAction.
  ///
  /// In ru, this message translates to:
  /// **'Свернуть в трей'**
  String get trayHideToTrayAction;

  /// No description provided for @trayExitAction.
  ///
  /// In ru, this message translates to:
  /// **'Выйти'**
  String get trayExitAction;

  /// No description provided for @noActiveAccountsWarning.
  ///
  /// In ru, this message translates to:
  /// **'Нет активных аккаунтов. Прокси запустится, но не сможет обрабатывать запросы, пока вы не добавите или не включите хотя бы один аккаунт.'**
  String get noActiveAccountsWarning;

  /// No description provided for @pinWindowTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Закрепить окно поверх остальных'**
  String get pinWindowTooltip;

  /// No description provided for @unpinWindowTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Убрать закрепление окна'**
  String get unpinWindowTooltip;

  /// No description provided for @welcomeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Добро пожаловать в KiCk'**
  String get welcomeTitle;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'KiCk помогает запустить локальный прокси для Gemini CLI без терминала и лишних настроек.'**
  String get welcomeSubtitle;

  /// No description provided for @welcomeStepAccountsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Подключите Google-аккаунт'**
  String get welcomeStepAccountsTitle;

  /// No description provided for @welcomeStepAccountsMessage.
  ///
  /// In ru, this message translates to:
  /// **'Это можно сделать на экране аккаунтов. Если аккаунт уже есть, просто включите его.'**
  String get welcomeStepAccountsMessage;

  /// No description provided for @welcomeStepHomeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Откройте главную'**
  String get welcomeStepHomeTitle;

  /// No description provided for @welcomeStepHomeMessage.
  ///
  /// In ru, this message translates to:
  /// **'На главной всегда видны адрес прокси, API-ключ и кнопка запуска.'**
  String get welcomeStepHomeMessage;

  /// No description provided for @welcomeUsageTitle.
  ///
  /// In ru, this message translates to:
  /// **'Важно знать'**
  String get welcomeUsageTitle;

  /// No description provided for @welcomeUsageMessage.
  ///
  /// In ru, this message translates to:
  /// **'KiCk предназначен для личного, учебного и исследовательского использования.'**
  String get welcomeUsageMessage;

  /// No description provided for @welcomeAnalyticsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Анонимная аналитика'**
  String get welcomeAnalyticsTitle;

  /// No description provided for @welcomeAnalyticsSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Помогает понять, где KiCk работает хорошо, а где его стоит улучшить.'**
  String get welcomeAnalyticsSubtitle;

  /// No description provided for @welcomeRepositoryLinkLabel.
  ///
  /// In ru, this message translates to:
  /// **'Подробнее о проекте'**
  String get welcomeRepositoryLinkLabel;

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
  /// **'Поиск по маршруту или сообщению'**
  String get logsSearchHint;

  /// No description provided for @logsRefreshButton.
  ///
  /// In ru, this message translates to:
  /// **'Обновить'**
  String get logsRefreshButton;

  /// No description provided for @logsClearButton.
  ///
  /// In ru, this message translates to:
  /// **'Очистить'**
  String get logsClearButton;

  /// No description provided for @logsClearDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Очистить логи?'**
  String get logsClearDialogTitle;

  /// No description provided for @logsClearDialogMessage.
  ///
  /// In ru, this message translates to:
  /// **'Все записи будут удалены из KiCk. Это действие нельзя отменить.'**
  String get logsClearDialogMessage;

  /// No description provided for @logsClearConfirmButton.
  ///
  /// In ru, this message translates to:
  /// **'Очистить'**
  String get logsClearConfirmButton;

  /// No description provided for @logsLevelAll.
  ///
  /// In ru, this message translates to:
  /// **'Все уровни'**
  String get logsLevelAll;

  /// No description provided for @logsLevelInfo.
  ///
  /// In ru, this message translates to:
  /// **'Инфо'**
  String get logsLevelInfo;

  /// No description provided for @logsLevelWarning.
  ///
  /// In ru, this message translates to:
  /// **'Предупреждения'**
  String get logsLevelWarning;

  /// No description provided for @logsLevelError.
  ///
  /// In ru, this message translates to:
  /// **'Ошибки'**
  String get logsLevelError;

  /// No description provided for @logsCategoryAll.
  ///
  /// In ru, this message translates to:
  /// **'Все категории'**
  String get logsCategoryAll;

  /// No description provided for @logsCategoryFilterTitle.
  ///
  /// In ru, this message translates to:
  /// **'Категории'**
  String get logsCategoryFilterTitle;

  /// No description provided for @logsPayloadShowButton.
  ///
  /// In ru, this message translates to:
  /// **'Показать payload'**
  String get logsPayloadShowButton;

  /// No description provided for @logsPayloadHideButton.
  ///
  /// In ru, this message translates to:
  /// **'Скрыть payload'**
  String get logsPayloadHideButton;

  /// No description provided for @logsCopyEntryButton.
  ///
  /// In ru, this message translates to:
  /// **'Копировать'**
  String get logsCopyEntryButton;

  /// No description provided for @logsCopiedMessage.
  ///
  /// In ru, this message translates to:
  /// **'Запись лога скопирована'**
  String get logsCopiedMessage;

  /// No description provided for @logsFilteredEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'По текущим фильтрам ничего не найдено'**
  String get logsFilteredEmptyTitle;

  /// No description provided for @logsFilteredEmptyMessage.
  ///
  /// In ru, this message translates to:
  /// **'Попробуйте убрать часть фильтров или изменить поиск.'**
  String get logsFilteredEmptyMessage;

  /// No description provided for @logsEntryLevelInfo.
  ///
  /// In ru, this message translates to:
  /// **'Инфо'**
  String get logsEntryLevelInfo;

  /// No description provided for @logsEntryLevelWarning.
  ///
  /// In ru, this message translates to:
  /// **'Предупреждение'**
  String get logsEntryLevelWarning;

  /// No description provided for @logsEntryLevelError.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка'**
  String get logsEntryLevelError;

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
  /// **'Сохранить логи в файл'**
  String get logsExportTooltip;

  /// No description provided for @logsShareTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Поделиться логами'**
  String get logsShareTooltip;

  /// No description provided for @logsNothingToExportMessage.
  ///
  /// In ru, this message translates to:
  /// **'Нет логов для сохранения'**
  String get logsNothingToExportMessage;

  /// No description provided for @logsExportedMessage.
  ///
  /// In ru, this message translates to:
  /// **'Логи сохранены в файл {fileName}'**
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
  /// **'Google-аккаунт'**
  String get accountDialogTitle;

  /// No description provided for @accountDialogBasicsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Основное'**
  String get accountDialogBasicsTitle;

  /// No description provided for @accountDialogBasicsSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Эти поля нужны для подключения аккаунта'**
  String get accountDialogBasicsSubtitle;

  /// No description provided for @accountDialogAdvancedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Расширенные настройки'**
  String get accountDialogAdvancedTitle;

  /// No description provided for @accountDialogAdvancedSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Приоритет и ограничения по моделям'**
  String get accountDialogAdvancedSubtitle;

  /// No description provided for @accountDialogAdvancedHint.
  ///
  /// In ru, this message translates to:
  /// **'Если не хочется настраивать вручную, этот блок можно оставить как есть.'**
  String get accountDialogAdvancedHint;

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
  /// **'Где посмотреть ID проекта'**
  String get projectIdConsoleLinkLabel;

  /// No description provided for @projectIdRequiredError.
  ///
  /// In ru, this message translates to:
  /// **'Укажите ID проекта'**
  String get projectIdRequiredError;

  /// No description provided for @projectIdLookupFailedMessage.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть Google Cloud Console.'**
  String get projectIdLookupFailedMessage;

  /// No description provided for @accountNameLabel.
  ///
  /// In ru, this message translates to:
  /// **'Название аккаунта'**
  String get accountNameLabel;

  /// No description provided for @accountNameHint.
  ///
  /// In ru, this message translates to:
  /// **'Например, основной аккаунт'**
  String get accountNameHint;

  /// No description provided for @accountNameHelperText.
  ///
  /// In ru, this message translates to:
  /// **'Если оставить поле пустым, KiCk подставит имя из Google.'**
  String get accountNameHelperText;

  /// No description provided for @priorityLabel.
  ///
  /// In ru, this message translates to:
  /// **'Приоритет'**
  String get priorityLabel;

  /// No description provided for @priorityHelperText.
  ///
  /// In ru, this message translates to:
  /// **'Сначала используются основные аккаунты. Аккаунты с одинаковым приоритетом чередуются.'**
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
  /// **'Недоступные модели'**
  String get blockedModelsLabel;

  /// No description provided for @blockedModelsHelperText.
  ///
  /// In ru, this message translates to:
  /// **'Укажите по одному ID модели на строке'**
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
  /// **'Прокси KiCk в фоне'**
  String get runtimeChannelName;

  /// No description provided for @runtimeChannelDescription.
  ///
  /// In ru, this message translates to:
  /// **'Поддерживает работу прокси в фоновом режиме'**
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
  /// **'Нажмите, чтобы открыть аккаунты и настройки'**
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
  /// **'Сервер вернул непонятный ответ. Попробуйте еще раз.'**
  String get errorInvalidServiceResponse;

  /// No description provided for @errorGoogleAuthTimedOut.
  ///
  /// In ru, this message translates to:
  /// **'Авторизация Google не завершилась вовремя. Вернитесь в приложение и попробуйте снова. Если это повторяется на Android, отключите для KiCk ограничения батареи.'**
  String get errorGoogleAuthTimedOut;

  /// No description provided for @errorUnknown.
  ///
  /// In ru, this message translates to:
  /// **'Произошла неизвестная ошибка. Попробуйте снова.'**
  String get errorUnknown;

  /// No description provided for @errorOauthTokensMissing.
  ///
  /// In ru, this message translates to:
  /// **'Для этого аккаунта не найдены токены авторизации. Переподключите аккаунт.'**
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
  /// **'Не хватило системных разрешений для запуска. Проверьте настройки приложения и повторите попытку.'**
  String get errorPermissionDenied;

  /// No description provided for @errorGoogleRateLimitedRetry.
  ///
  /// In ru, this message translates to:
  /// **'Google временно ограничил запросы для этого аккаунта. Попробуйте снова через {retryHint}.'**
  String errorGoogleRateLimitedRetry(String retryHint);

  /// No description provided for @errorGoogleRateLimitedLater.
  ///
  /// In ru, this message translates to:
  /// **'Google временно ограничил запросы для этого аккаунта. Попробуйте снова позже.'**
  String get errorGoogleRateLimitedLater;

  /// No description provided for @errorGoogleAccountVerificationRequired.
  ///
  /// In ru, this message translates to:
  /// **'Google просит подтвердить этот аккаунт. Откройте страницу подтверждения и войдите под тем же Google-аккаунтом.'**
  String get errorGoogleAccountVerificationRequired;

  /// No description provided for @errorGoogleProjectIdMissing.
  ///
  /// In ru, this message translates to:
  /// **'Google не смог определить корректный ID проекта для этого аккаунта или запроса. Проверьте ID проекта в настройках аккаунта и при необходимости переподключите его.'**
  String get errorGoogleProjectIdMissing;

  /// No description provided for @errorGoogleProjectApiDisabled.
  ///
  /// In ru, this message translates to:
  /// **'Gemini for Google Cloud API отключен для этого проекта. Откройте Google Cloud, включите API для нужного ID проекта и повторите проверку.'**
  String get errorGoogleProjectApiDisabled;

  /// No description provided for @errorGoogleProjectInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Google отклонил этот ID проекта. Проверьте, что указали существующий проект и что у аккаунта есть доступ именно к нему.'**
  String get errorGoogleProjectInvalid;

  /// No description provided for @errorGoogleProjectAccessDenied.
  ///
  /// In ru, this message translates to:
  /// **'Google отклонил запрос для этого проекта или аккаунта. Проверьте ID проекта, выбранный аккаунт и убедитесь, что Gemini Code Assist включен именно для этого проекта.'**
  String get errorGoogleProjectAccessDenied;

  /// No description provided for @errorAuthExpired.
  ///
  /// In ru, this message translates to:
  /// **'Срок действия авторизации истек или она стала недействительной. Переподключите аккаунт и попробуйте снова.'**
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
  /// **'Лимит этого аккаунта исчерпан. Дождитесь сброса или используйте другой аккаунт.'**
  String get errorQuotaExhausted;

  /// No description provided for @errorQuotaExhaustedRetry.
  ///
  /// In ru, this message translates to:
  /// **'Лимит этого аккаунта исчерпан. Попробуйте снова через {retryHint} или используйте другой аккаунт.'**
  String errorQuotaExhaustedRetry(String retryHint);

  /// No description provided for @errorInvalidRequestRejected.
  ///
  /// In ru, this message translates to:
  /// **'Запрос имеет неверный формат и был отклонён.'**
  String get errorInvalidRequestRejected;

  /// No description provided for @errorReasoningConfigRejected.
  ///
  /// In ru, this message translates to:
  /// **'Google отклонил параметры reasoning/thinking для этой модели. Включите автоматический режим размышлений (reasoning).'**
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
