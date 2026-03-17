// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'KiCk';

  @override
  String get shellSubtitle => 'Локальный прокси Gemini CLI';

  @override
  String get connectGoogleAccountTitle => 'Подключить Google аккаунт';

  @override
  String get homeTitle => 'Главная';

  @override
  String get proxyRunningStatus => 'Активно';

  @override
  String get proxyStoppedStatus => 'Остановлено';

  @override
  String get embeddedProxyTitle => 'Прокси';

  @override
  String proxyAddress(String host, int port) {
    return 'Адрес: $host:$port';
  }

  @override
  String get proxyEndpointTitle => 'URL прокси';

  @override
  String activeAccounts(int count) {
    return 'Активных аккаунтов: $count';
  }

  @override
  String get stopProxyButton => 'Остановить';

  @override
  String get startProxyButton => 'Запустить';

  @override
  String get uptimeTitle => 'Время работы';

  @override
  String get uptimeNotStarted => 'Пока не запущен';

  @override
  String uptimeValue(int hours, int minutes, int seconds) {
    return '$hours ч $minutes мин $seconds сек';
  }

  @override
  String get versionTitle => 'Версия';

  @override
  String get apiKeyTitle => 'API-ключ';

  @override
  String get apiKeyDisabledValue => 'Отключен';

  @override
  String get changeApiKeyLinkLabel => 'Изменить ключ';

  @override
  String get loadingValue => 'Загружается...';

  @override
  String get lastErrorTitle => 'Последняя ошибка';

  @override
  String get openLogsButton => 'Открыть логи';

  @override
  String get accountsTitle => 'Список аккаунтов';

  @override
  String get accountsSubtitle => 'Добавляйте Google аккаунты и управляйте ими';

  @override
  String get addButton => 'Добавить';

  @override
  String get accountsEmptyTitle => 'Пока пусто';

  @override
  String get accountsEmptyMessage => 'Подключите хотя бы один Google аккаунт';

  @override
  String get connectAccountButton => 'Подключить аккаунт';

  @override
  String get accountsLoadErrorTitle => 'Не удалось загрузить аккаунты';

  @override
  String projectIdChip(String projectId) {
    return 'PROJECT_ID: $projectId';
  }

  @override
  String priorityChip(String priorityLabel) {
    return 'Роль: $priorityLabel';
  }

  @override
  String get accountCoolingDownStatus => 'Таймаут';

  @override
  String get accountReadyStatus => 'Готов';

  @override
  String get accountDisabledStatus => 'Отключен';

  @override
  String unsupportedModelsList(String models) {
    return 'Не использовать для: $models';
  }

  @override
  String get editAccountTitle => 'Редактировать аккаунт';

  @override
  String get editButton => 'Изменить';

  @override
  String get reauthorizeAccountTitle => 'Переавторизовать аккаунт';

  @override
  String get reauthorizeButton => 'Переавторизовать';

  @override
  String get resetCooldownTooltip => 'Сбросить статус';

  @override
  String get clearCooldownAction => 'Снять блокировку';

  @override
  String get deleteTooltip => 'Удалить';

  @override
  String get accountUsageOpenTooltip => 'Лимиты';

  @override
  String get accountUsageTitle => 'Лимиты';

  @override
  String get accountUsageProviderLabel => 'Gemini CLI OAuth';

  @override
  String get accountUsageRefreshTooltip => 'Обновить';

  @override
  String get accountUsageStatusHealthy => 'В норме';

  @override
  String get accountUsageStatusCoolingDown => 'Лимит';

  @override
  String get accountUsageStatusDisabled => 'Выключен';

  @override
  String get accountUsageLoadErrorTitle => 'Не удалось загрузить текущие лимиты';

  @override
  String get accountUsageRetryButton => 'Повторить';

  @override
  String get accountUsageVerifyAccountButton => 'Подтвердить аккаунт';

  @override
  String get accountUsageVerificationOpenFailedMessage =>
      'Не удалось открыть страницу подтверждения аккаунта';

  @override
  String get accountUsageEmptyTitle => 'Лимиты недоступны';

  @override
  String get accountUsageEmptyMessage =>
      'Google не вернул информацию по лимитам для этого аккаунта';

  @override
  String get accountUsageMissingTitle => 'Аккаунт не найден';

  @override
  String get accountUsageMissingSubtitle => 'Экран лимитов';

  @override
  String get accountUsageMissingMessage =>
      'Возможно, аккаунт был удалён или список ещё не успел обновиться';

  @override
  String accountUsageResetsAt(String time) {
    return 'Будет сброшено $time';
  }

  @override
  String get accountUsageResetUnknown => 'Время сброса не получено';

  @override
  String accountUsageLastUpdated(String time) {
    return 'Обновлено: $time';
  }

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsSubtitle => 'Сеть, тема, API-ключ и поведение прокси';

  @override
  String get themeLabel => 'Тема';

  @override
  String get themeModeSystem => 'Системная';

  @override
  String get themeModeLight => 'Светлая';

  @override
  String get themeModeDark => 'Тёмная';

  @override
  String get dynamicThemeTitle => 'Динамическая тема';

  @override
  String get dynamicThemeSubtitle => 'Использовать системные динамические цвета';

  @override
  String get settingsAppearanceSectionTitle => 'Внешний вид и поведение';

  @override
  String get settingsAppearanceSectionSummary => 'Тема, логи и поведение программы';

  @override
  String get settingsNetworkSectionTitle => 'Сеть';

  @override
  String get settingsNetworkSectionSummary => 'Хост, порт и доступ из локальной сети';

  @override
  String get settingsReliabilitySectionTitle => 'Система повторов';

  @override
  String get settingsReliabilitySectionSummary => 'Автоповторы и обработка лимитов API';

  @override
  String get settingsAccessSectionTitle => 'Доступ и запуск';

  @override
  String get settingsAccessSectionSummary => 'API-ключ и параметры запуска';

  @override
  String get apiKeyRequiredTitle => 'Требовать API-ключ';

  @override
  String get apiKeyRequiredSubtitle => 'При отключении, разрешает запросы без Bearer-токена';

  @override
  String get windowsTrayTitle => 'Работа из трея';

  @override
  String get windowsTraySubtitle => 'Закрытие окна скрывает KiCk в системный трей';

  @override
  String get windowsLaunchAtStartupTitle => 'Запускать вместе с Windows';

  @override
  String get windowsLaunchAtStartupSubtitle => 'При входе в систему KiCk будет стартовать в трее';

  @override
  String get windowsTrayNotificationTitle => 'KiCk продолжает работать';

  @override
  String get windowsTrayNotificationBody => 'Приложение скрыто в системный трей';

  @override
  String get settingsModelsSectionTitle => 'Модели';

  @override
  String get settingsModelsSectionSummary => 'Пользовательские ID моделей';

  @override
  String get hostLabel => 'Хост';

  @override
  String get hostHelperText => 'Обычно 127.0.0.1';

  @override
  String get portLabel => 'Порт';

  @override
  String get portHelperText => 'По умолчанию 3000';

  @override
  String get allowLanTitle => 'Доступ из LAN / Docker';

  @override
  String get allowLanSubtitle =>
      'Открывает прокси на 0.0.0.0 и делает его доступным из локальной сети и контейнеров';

  @override
  String get androidBackgroundRuntimeTitle => 'Фоновый запуск на Android';

  @override
  String get androidBackgroundRuntimeSubtitle => 'Необходимо для непрерывной работы прокси';

  @override
  String get requestRetriesLabel => 'Повторы запросов к Google';

  @override
  String get requestRetriesHelperText => 'Сколько раз KiCk повторит временно запрос при неудаче';

  @override
  String get mark429AsUnhealthyTitle => 'Отключать аккаунт при превышении лимитов (ошибка 429)';

  @override
  String get mark429AsUnhealthySubtitle =>
      'Помечает аккаунт как временно непригодный после ошибок 429, чтобы быстрее переключаться на другие';

  @override
  String get loggingLabel => 'Логирование';

  @override
  String get loggingQuiet => 'Тихое';

  @override
  String get loggingNormal => 'Обычное';

  @override
  String get loggingVerbose => 'Подробное';

  @override
  String get unsafeRawLoggingTitle => 'Debug-логи';

  @override
  String get unsafeRawLoggingSubtitle => 'Сохраняет сырые запросы. Используйте только для отладки';

  @override
  String get customModelsLabel => 'Пользовательские ID моделей';

  @override
  String get customModelsHelperText => 'Точный ID модели, по одному на строке';

  @override
  String get settingsLoadErrorTitle => 'Не удалось загрузить настройки';

  @override
  String get aboutTitle => 'О программе';

  @override
  String get aboutMenuSubtitle => 'Информация о программе';

  @override
  String get aboutDescription =>
      'Локальный прокси-сервер, совместимый с OpenAI, для Gemini CLI с нативной оболочкой Flutter';

  @override
  String get aboutUpdatesTitle => 'Обновления';

  @override
  String get aboutUpdatesChecking => 'Проверяем наличие новой версии на GitHub...';

  @override
  String get aboutUpdateAvailableTitle => 'Доступно обновление';

  @override
  String aboutUpdateAvailableMessage(String latestVersion, String currentVersion) {
    return 'Найдена версия $latestVersion. Сейчас установлена $currentVersion.';
  }

  @override
  String get aboutUpToDateTitle => 'Обновлений нет';

  @override
  String aboutUpToDateMessage(String currentVersion) {
    return 'У вас уже установлена актуальная версия $currentVersion.';
  }

  @override
  String get aboutUpdateCheckFailedTitle => 'Не удалось проверить обновления';

  @override
  String get aboutUpdateCheckFailedMessage => 'Что-то пошло не так';

  @override
  String get aboutOpenReleaseButton => 'Открыть релиз';

  @override
  String get aboutRetryUpdateCheckButton => 'Проверить снова';

  @override
  String get aboutAnalyticsTitle => 'Аналитика';

  @override
  String get aboutAnalyticsSubtitle =>
      'Анонимная статистика использования. Помогает делать KiCk лучше.';

  @override
  String get copyProxyEndpointTooltip => 'Скопировать URL прокси';

  @override
  String get proxyEndpointCopiedMessage => 'URL прокси скопирован';

  @override
  String get copyApiKeyTooltip => 'Скопировать API-ключ';

  @override
  String get apiKeyCopiedMessage => 'API-ключ скопирован';

  @override
  String get apiKeyRegeneratedMessage => 'Новый API-ключ сохранён';

  @override
  String get regenerateApiKeyAction => 'Сгенерировать заново';

  @override
  String get regenerateApiKeyDialogTitle => 'Сгенерировать новый API-ключ?';

  @override
  String get regenerateApiKeyDialogMessage =>
      'Старый ключ будет немедленно отозван. Подключенным клиентам потребуется новый ключ для работы.';

  @override
  String get regenerateApiKeyConfirmButton => 'Сгенерировать';

  @override
  String get trayOpenWindowAction => 'Открыть окно';

  @override
  String get trayHideToTrayAction => 'Скрыть в трей';

  @override
  String get trayExitAction => 'Выход';

  @override
  String get noActiveAccountsWarning =>
      'Активных аккаунтов нет. Прокси всё равно запустится, но не сможет обработать запросы, пока вы не добавите или не включите аккаунт.';

  @override
  String get pinWindowTooltip => 'Закрепить поверх остальных окон';

  @override
  String get unpinWindowTooltip => 'Открепить окно';

  @override
  String get disclaimerTitle => 'Отказ от ответственности';

  @override
  String get disclaimerBodyLineOne => 'Данное программное обеспечение предоставляется \"как есть\"';

  @override
  String get disclaimerBodyLineTwo =>
      'Предназначено исключительно для некоммерческого использования в образовательных и исследовательских целях';

  @override
  String get disclaimerLinkPrefix => 'Подробнее';

  @override
  String get disclaimerAnalyticsConsentLabel => 'Разрешить отправку анонимной аналитики';

  @override
  String get logsTitle => 'Логи';

  @override
  String get logsSubtitle => 'История запросов и ошибок';

  @override
  String get logsSearchHint => 'Поиск по маршруту, сообщению';

  @override
  String logsTotalCount(int count) {
    return 'Всего: $count';
  }

  @override
  String logsFilteredCount(int count) {
    return 'После фильтра: $count';
  }

  @override
  String get logsEmptyTitle => 'Логи пусты';

  @override
  String get logsLoadErrorTitle => 'Не удалось загрузить логи';

  @override
  String get logsExportTooltip => 'Сохранить лог-файл';

  @override
  String get logsShareTooltip => 'Поделиться логами';

  @override
  String get logsNothingToExportMessage => 'Нет логов для экспорта';

  @override
  String logsExportedMessage(String fileName) {
    return 'Логи сохранены: $fileName';
  }

  @override
  String logsExportFailedMessage(String error) {
    return 'Не удалось сохранить логи: $error';
  }

  @override
  String logsShareFailedMessage(String error) {
    return 'Не удалось поделиться логами: $error';
  }

  @override
  String get accountDialogTitle => 'Аккаунт Google';

  @override
  String get projectIdLabel => 'PROJECT_ID';

  @override
  String get projectIdHint => 'my-google-cloud-project';

  @override
  String get projectIdConsoleLinkLabel => 'Узнать ID проекта';

  @override
  String get projectIdRequiredError => 'Укажите PROJECT_ID';

  @override
  String get projectIdLookupFailedMessage => 'Не удалось открыть Google Cloud Console';

  @override
  String get accountNameLabel => 'Название';

  @override
  String get accountNameHint => 'Основной аккаунт';

  @override
  String get priorityLabel => 'Роль в очереди';

  @override
  String get priorityHelperText =>
      'Основные аккаунты получают запросы в первую очередь. Аккаунты одного уровня чередуются.';

  @override
  String get priorityLevelPrimary => 'Основной';

  @override
  String get priorityLevelNormal => 'Обычный';

  @override
  String get priorityLevelReserve => 'Резервный';

  @override
  String get blockedModelsLabel => 'Заблокированные модели';

  @override
  String get blockedModelsHelperText => 'По одной модели на строке';

  @override
  String get cancelButton => 'Отмена';

  @override
  String get continueButton => 'Продолжить';

  @override
  String get navHome => 'Главная';

  @override
  String get navAccounts => 'Аккаунты';

  @override
  String get navSettings => 'Настройки';

  @override
  String get navLogs => 'Логи';

  @override
  String get runtimeChannelName => 'Фоновый прокси KiCk';

  @override
  String get runtimeChannelDescription => 'Удерживает прокси активным в фоне';

  @override
  String get runtimeNotificationTitle => 'Прокси KiCk запущен';

  @override
  String get runtimeNotificationReturn => 'Нажмите, чтобы вернуться в приложение';

  @override
  String get runtimeNotificationManage => 'Нажмите, чтобы управлять аккаунтами и настройками';

  @override
  String get runtimeNotificationActive => 'Прокси активен';

  @override
  String get errorNetworkUnavailable =>
      'Не удалось связаться с серверами Google. Проверьте интернет и попробуйте снова.';

  @override
  String get errorGoogleServiceUnavailable =>
      'Сервис Google временно недоступен. Повторите попытку позже.';

  @override
  String get errorInvalidServiceResponse => 'Сервер ответил что-то непонятное. Попробуйте ещё раз';

  @override
  String get errorGoogleAuthTimedOut =>
      'Авторизация Google не завершилась вовремя. Вернитесь в приложение и попробуйте снова. Если это повторяется на Android, отключите для KiCk ограничения батареи.';

  @override
  String get errorUnknown => 'Произошла неизвестная ошибка. Попробуйте снова.';

  @override
  String get errorOauthTokensMissing =>
      'Для этого аккаунта не найдены токены авторизации. Переавторизуйте аккаунт';

  @override
  String get errorAccountNotFound => 'Аккаунт не найден. Возможно, он уже был удалён.';

  @override
  String get errorPortAlreadyInUse =>
      'Этот порт уже занят другим приложением. Выберите другой порт в настройках.';

  @override
  String get errorPermissionDenied =>
      'Системе не хватило разрешений для запуска. Проверьте настройки приложения и повторите попытку.';

  @override
  String errorGoogleRateLimitedRetry(String retryHint) {
    return 'Google временно ограничил запросы для этого аккаунта. Повторите попытку через $retryHint.';
  }

  @override
  String get errorGoogleRateLimitedLater =>
      'Google временно ограничил запросы для этого аккаунта. Повторите попытку позже.';

  @override
  String get errorGoogleAccountVerificationRequired =>
      'Google просит подтвердить этот аккаунт. Откройте страницу подтверждения и войдите тем же Google-аккаунтом.';

  @override
  String get errorGoogleProjectIdMissing =>
      'Google не смог определить корректный PROJECT_ID для этого аккаунта или запроса. Проверьте PROJECT_ID в аккаунте и при необходимости переавторизуйте его.';

  @override
  String get errorGoogleProjectAccessDenied =>
      'Google отклонил запрос для этого проекта или аккаунта. Проверьте PROJECT_ID, выбранный аккаунт и что Gemini Code Assist активирован именно для этого проекта.';

  @override
  String get errorAuthExpired =>
      'Авторизация истекла или стала недействительной. Переавторизуйте аккаунт и попробуйте снова.';

  @override
  String get errorGoogleCapacity =>
      'Сервера Google временно перегружены. Повторите попытку чуть позже.';

  @override
  String get errorUnsupportedModel => 'Выбранная модель сейчас недоступна для этого аккаунта.';

  @override
  String get errorInvalidJson => 'Запрос имеет неверный формат JSON.';

  @override
  String get errorUnexpectedResponse => 'Сервис вернул неожиданный ответ. Повторите попытку.';

  @override
  String get errorQuotaExhausted =>
      'Квота этого аккаунта исчерпана. Дождитесь сброса лимита или используйте другой аккаунт.';

  @override
  String errorQuotaExhaustedRetry(String retryHint) {
    return 'Квота этого аккаунта исчерпана. Повторите попытку через $retryHint или используйте другой аккаунт.';
  }

  @override
  String get errorInvalidRequestRejected => 'Запрос имеет неверный формат и был отклонён.';

  @override
  String get errorReasoningConfigRejected =>
      'Google отклонил параметры reasoning/thinking для этой модели. Верните Reasoning Effort в Auto или уберите кастомный thinking config.';

  @override
  String get durationFewSeconds => 'несколько секунд';

  @override
  String durationSeconds(int seconds) {
    return '$seconds сек';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes мин';
  }

  @override
  String durationMinutesSeconds(int minutes, int seconds) {
    return '$minutes мин $seconds сек';
  }

  @override
  String durationHours(int hours) {
    return '$hours ч';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours ч $minutes мин';
  }
}
