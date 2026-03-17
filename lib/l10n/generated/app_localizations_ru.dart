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
  String get shellSubtitle => 'Локальный прокси для Gemini CLI';

  @override
  String get connectGoogleAccountTitle => 'Подключить Google-аккаунт';

  @override
  String get homeTitle => 'Главная';

  @override
  String get proxyRunningStatus => 'Запущен';

  @override
  String get proxyStoppedStatus => 'Остановлен';

  @override
  String get embeddedProxyTitle => 'Прокси-сервер';

  @override
  String proxyAddress(String host, int port) {
    return 'Адрес: $host:$port';
  }

  @override
  String get proxyEndpointTitle => 'Адрес прокси';

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
  String get uptimeNotStarted => 'Еще не запущен';

  @override
  String uptimeValue(int hours, int minutes, int seconds) {
    return '$hours ч $minutes мин $seconds сек';
  }

  @override
  String get versionTitle => 'Версия';

  @override
  String get apiKeyTitle => 'API-ключ';

  @override
  String get apiKeyDisabledValue => 'Не требуется';

  @override
  String get changeApiKeyLinkLabel => 'Изменить API-ключ';

  @override
  String get loadingValue => 'Загрузка...';

  @override
  String get lastErrorTitle => 'Последняя ошибка';

  @override
  String get openLogsButton => 'Открыть логи';

  @override
  String get accountsTitle => 'Аккаунты';

  @override
  String get accountsSubtitle => 'Подключайте Google-аккаунты и управляйте ими';

  @override
  String get addButton => 'Добавить';

  @override
  String get accountsEmptyTitle => 'Аккаунтов пока нет';

  @override
  String get accountsEmptyMessage => 'Подключите хотя бы один Google-аккаунт';

  @override
  String get connectAccountButton => 'Подключить Google-аккаунт';

  @override
  String get accountsLoadErrorTitle => 'Не удалось загрузить аккаунты';

  @override
  String projectIdChip(String projectId) {
    return 'PROJECT_ID: $projectId';
  }

  @override
  String priorityChip(String priorityLabel) {
    return 'Приоритет: $priorityLabel';
  }

  @override
  String get accountCoolingDownStatus => 'На паузе';

  @override
  String get accountReadyStatus => 'Готов к работе';

  @override
  String get accountDisabledStatus => 'Выключен';

  @override
  String unsupportedModelsList(String models) {
    return 'Не использовать для моделей: $models';
  }

  @override
  String get editAccountTitle => 'Редактирование аккаунта';

  @override
  String get editButton => 'Редактировать';

  @override
  String get reauthorizeAccountTitle => 'Переподключить аккаунт';

  @override
  String get reauthorizeButton => 'Переподключить';

  @override
  String get accountProjectCheckButton => 'Проверить доступ к проекту';

  @override
  String get accountProjectCheckInProgressMessage => 'Проверка...';

  @override
  String get accountProjectCheckSuccessTitle => 'Доступ к проекту подтвержден';

  @override
  String get accountProjectCheckSuccessMessage =>
      'KiCk смог выполнить тестовый запрос к Google для этого аккаунта и проекта';

  @override
  String get accountProjectCheckFailureTitle => 'Не удалось проверить';

  @override
  String get resetCooldownTooltip => 'Сбросить состояние';

  @override
  String get clearCooldownAction => 'Снять паузу';

  @override
  String get deleteTooltip => 'Удалить';

  @override
  String get accountUsageOpenTooltip => 'Лимиты';

  @override
  String get accountUsageTitle => 'Лимиты аккаунта';

  @override
  String get accountUsageProviderLabel => 'Авторизация Gemini CLI (OAuth)';

  @override
  String get accountUsageRefreshTooltip => 'Обновить';

  @override
  String get accountUsageStatusHealthy => 'Доступен';

  @override
  String get accountUsageStatusCoolingDown => 'Ограничен';

  @override
  String get accountUsageStatusDisabled => 'Выключен';

  @override
  String get accountQuotaWarningStatus => 'Лимит заканчивается';

  @override
  String get accountUsageLoadErrorTitle => 'Не удалось загрузить данные по лимитам';

  @override
  String get accountUsageRetryButton => 'Повторить';

  @override
  String get accountUsageVerifyAccountButton => 'Подтвердить в Google';

  @override
  String get openGoogleCloudButton => 'Открыть Google Cloud';

  @override
  String get accountUsageVerificationOpenFailedMessage =>
      'Не удалось открыть страницу подтверждения в Google';

  @override
  String get accountErrorActionOpenFailedMessage => 'Не удалось открыть страницу Google';

  @override
  String get accountUsageEmptyTitle => 'Данные по лимитам недоступны';

  @override
  String get accountUsageEmptyMessage => 'Google не прислал данные по лимитам для этого аккаунта';

  @override
  String get accountUsageMissingTitle => 'Аккаунт не найден';

  @override
  String get accountUsageMissingSubtitle => 'Информация по лимитам';

  @override
  String get accountUsageMissingMessage =>
      'Возможно, аккаунт уже удален или список еще не успел обновиться';

  @override
  String accountUsageResetsAt(String time) {
    return 'Сбросится $time';
  }

  @override
  String get accountUsageResetUnknown => 'Время следующего сброса неизвестно';

  @override
  String accountUsageLastUpdated(String time) {
    return 'Данные обновлены: $time';
  }

  @override
  String accountUsageModelCount(int count) {
    return 'Моделей: $count';
  }

  @override
  String accountUsageAttentionCount(int count) {
    return 'Низкий остаток: $count';
  }

  @override
  String accountUsageCriticalCount(int count) {
    return 'Почти исчерпано: $count';
  }

  @override
  String accountUsageHealthyCount(int count) {
    return 'В норме: $count';
  }

  @override
  String accountUsageTokenType(String value) {
    return 'Тип лимита: $value';
  }

  @override
  String accountUsageRemainingPercent(String value) {
    return 'Осталось $value%';
  }

  @override
  String accountUsageUsedPercent(String value) {
    return 'Израсходовано $value%';
  }

  @override
  String get accountUsageBucketHealthy => 'Достаточно';

  @override
  String get accountUsageBucketLow => 'Заканчивается';

  @override
  String get accountUsageBucketCritical => 'Почти исчерпано';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsSubtitle => 'Сеть, оформление, API-ключ и работа прокси';

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
  String get dynamicThemeSubtitle => 'Использовать динамические цвета системы';

  @override
  String get settingsAppearanceSectionTitle => 'Оформление и поведение';

  @override
  String get settingsAppearanceSectionSummary => 'Тема, логи и работа приложения';

  @override
  String get settingsNetworkSectionTitle => 'Сеть';

  @override
  String get settingsNetworkSectionSummary => 'Хост, порт и доступ из локальной сети';

  @override
  String get settingsReliabilitySectionTitle => 'Повторы и лимиты';

  @override
  String get settingsReliabilitySectionSummary => 'Автоповторы и реакция на ограничения API';

  @override
  String get settingsAccessSectionTitle => 'Доступ и запуск';

  @override
  String get settingsAccessSectionSummary => 'API-ключ и запуск приложения';

  @override
  String get apiKeyRequiredTitle => 'Требовать API-ключ';

  @override
  String get apiKeyRequiredSubtitle =>
      'Если выключить, запросы будут приниматься без Bearer-токена';

  @override
  String get windowsTrayTitle => 'Сворачивать в трей';

  @override
  String get windowsTraySubtitle =>
      'При закрытии окно не завершает работу, а скрывает KiCk в системный трей';

  @override
  String get windowsLaunchAtStartupTitle => 'Запускать вместе с Windows';

  @override
  String get windowsLaunchAtStartupSubtitle =>
      'KiCk будет автоматически запускаться при входе в систему';

  @override
  String get windowsTrayNotificationTitle => 'KiCk продолжает работать';

  @override
  String get windowsTrayNotificationBody => 'Приложение свернуто в системный трей';

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
  String get allowLanTitle => 'Доступ из локальной сети и Docker';

  @override
  String get allowLanSubtitle =>
      'Прокси будет слушать 0.0.0.0 и станет доступен из локальной сети и контейнеров';

  @override
  String get androidBackgroundRuntimeTitle => 'Работа в фоне на Android';

  @override
  String get androidBackgroundRuntimeSubtitle =>
      'Нужно, чтобы прокси не останавливался при сворачивании приложения';

  @override
  String get requestRetriesLabel => 'Количество повторов запросов к Google';

  @override
  String get requestRetriesHelperText => 'Сколько раз KiCk повторит запрос после временной ошибки';

  @override
  String get mark429AsUnhealthyTitle => 'Временно выводить аккаунт из ротации при ошибке 429';

  @override
  String get mark429AsUnhealthySubtitle =>
      'После ошибки 429 KiCk пометит аккаунт как временно недоступный и переключится на другой';

  @override
  String get loggingLabel => 'Логирование';

  @override
  String get loggingQuiet => 'Минимальное';

  @override
  String get loggingNormal => 'Стандартное';

  @override
  String get loggingVerbose => 'Подробное';

  @override
  String get unsafeRawLoggingTitle => 'Сырые логи отладки';

  @override
  String get unsafeRawLoggingSubtitle =>
      'Сохраняет содержимое запросов и ответов. Включайте только для отладки!';

  @override
  String get customModelsLabel => 'Пользовательские ID моделей';

  @override
  String get customModelsHelperText => 'Указывайте точный ID модели, по одному на строке';

  @override
  String get settingsLoadErrorTitle => 'Не удалось загрузить настройки';

  @override
  String get aboutTitle => 'О программе';

  @override
  String get aboutMenuSubtitle => 'Версия, обновления и аналитика';

  @override
  String get aboutDescription =>
      'Локальный OpenAI-совместимый прокси для Gemini CLI в нативном Flutter-приложении';

  @override
  String get aboutUpdatesTitle => 'Обновления';

  @override
  String get aboutUpdatesChecking => 'Проверяем обновления на GitHub...';

  @override
  String get aboutUpdateAvailableTitle => 'Доступно обновление';

  @override
  String aboutUpdateAvailableMessage(String latestVersion, String currentVersion) {
    return 'Доступна версия $latestVersion. Сейчас у вас установлена $currentVersion.';
  }

  @override
  String get aboutUpToDateTitle => 'Обновлений нет';

  @override
  String aboutUpToDateMessage(String currentVersion) {
    return 'У вас установлена актуальная версия: $currentVersion.';
  }

  @override
  String get aboutUpdateCheckFailedTitle => 'Не удалось проверить обновления';

  @override
  String get aboutUpdateCheckFailedMessage => 'Не удалось получить информацию о релизах с GitHub.';

  @override
  String get aboutOpenReleaseButton => 'Открыть релиз';

  @override
  String get aboutRetryUpdateCheckButton => 'Проверить еще раз';

  @override
  String get aboutAnalyticsTitle => 'Аналитика';

  @override
  String get aboutAnalyticsSubtitle => 'Анонимная статистика использования помогает улучшать KiCk.';

  @override
  String get copyProxyEndpointTooltip => 'Скопировать адрес прокси';

  @override
  String get proxyEndpointCopiedMessage => 'Адрес прокси скопирован';

  @override
  String get copyApiKeyTooltip => 'Скопировать API-ключ';

  @override
  String get apiKeyCopiedMessage => 'API-ключ скопирован';

  @override
  String get apiKeyRegeneratedMessage => 'Новый API-ключ сохранен';

  @override
  String get regenerateApiKeyAction => 'Создать новый API-ключ';

  @override
  String get regenerateApiKeyDialogTitle => 'Создать новый API-ключ?';

  @override
  String get regenerateApiKeyDialogMessage =>
      'Старый ключ будет сразу отозван. Всем подключенным клиентам понадобится новый ключ для работы.';

  @override
  String get regenerateApiKeyConfirmButton => 'Сгенерировать';

  @override
  String get trayOpenWindowAction => 'Открыть окно';

  @override
  String get trayHideToTrayAction => 'Свернуть в трей';

  @override
  String get trayExitAction => 'Выйти';

  @override
  String get noActiveAccountsWarning =>
      'Нет активных аккаунтов. Прокси запустится, но не сможет обрабатывать запросы, пока вы не добавите или не включите хотя бы один аккаунт.';

  @override
  String get pinWindowTooltip => 'Закрепить окно поверх остальных';

  @override
  String get unpinWindowTooltip => 'Убрать закрепление окна';

  @override
  String get disclaimerTitle => 'Отказ от ответственности';

  @override
  String get disclaimerBodyLineOne => 'Программа предоставляется \"как есть\".';

  @override
  String get disclaimerBodyLineTwo =>
      'Только для некоммерческого использования в образовательных и исследовательских целях.';

  @override
  String get disclaimerLinkPrefix => 'Подробнее:';

  @override
  String get disclaimerAnalyticsConsentLabel => 'Отправлять анонимную аналитику';

  @override
  String get logsTitle => 'Логи';

  @override
  String get logsSubtitle => 'История запросов и ошибок';

  @override
  String get logsSearchHint => 'Поиск по маршруту или сообщению';

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
  String get logsExportTooltip => 'Сохранить логи в файл';

  @override
  String get logsShareTooltip => 'Поделиться логами';

  @override
  String get logsNothingToExportMessage => 'Нет логов для сохранения';

  @override
  String logsExportedMessage(String fileName) {
    return 'Логи сохранены в файл $fileName';
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
  String get accountDialogTitle => 'Google-аккаунт';

  @override
  String get projectIdLabel => 'PROJECT_ID';

  @override
  String get projectIdHint => 'my-google-cloud-project';

  @override
  String get projectIdConsoleLinkLabel => 'Где посмотреть ID проекта';

  @override
  String get projectIdRequiredError => 'Укажите ID проекта';

  @override
  String get projectIdLookupFailedMessage => 'Не удалось открыть Google Cloud Console.';

  @override
  String get accountNameLabel => 'Название аккаунта';

  @override
  String get accountNameHint => 'Например, основной аккаунт';

  @override
  String get priorityLabel => 'Приоритет';

  @override
  String get priorityHelperText =>
      'Сначала используются основные аккаунты. Аккаунты с одинаковым приоритетом чередуются.';

  @override
  String get priorityLevelPrimary => 'Основной';

  @override
  String get priorityLevelNormal => 'Обычный';

  @override
  String get priorityLevelReserve => 'Резервный';

  @override
  String get blockedModelsLabel => 'Недоступные модели';

  @override
  String get blockedModelsHelperText => 'Укажите по одному ID модели на строке';

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
  String get runtimeChannelName => 'Прокси KiCk в фоне';

  @override
  String get runtimeChannelDescription => 'Поддерживает работу прокси в фоновом режиме';

  @override
  String get runtimeNotificationTitle => 'Прокси KiCk запущен';

  @override
  String get runtimeNotificationReturn => 'Нажмите, чтобы вернуться в приложение';

  @override
  String get runtimeNotificationManage => 'Нажмите, чтобы открыть аккаунты и настройки';

  @override
  String get runtimeNotificationActive => 'Прокси активен';

  @override
  String get errorNetworkUnavailable =>
      'Не удалось связаться с серверами Google. Проверьте интернет и попробуйте снова.';

  @override
  String get errorGoogleServiceUnavailable =>
      'Сервис Google временно недоступен. Повторите попытку позже.';

  @override
  String get errorInvalidServiceResponse => 'Сервер вернул непонятный ответ. Попробуйте еще раз.';

  @override
  String get errorGoogleAuthTimedOut =>
      'Авторизация Google не завершилась вовремя. Вернитесь в приложение и попробуйте снова. Если это повторяется на Android, отключите для KiCk ограничения батареи.';

  @override
  String get errorUnknown => 'Произошла неизвестная ошибка. Попробуйте снова.';

  @override
  String get errorOauthTokensMissing =>
      'Для этого аккаунта не найдены токены авторизации. Переподключите аккаунт.';

  @override
  String get errorAccountNotFound => 'Аккаунт не найден. Возможно, он уже был удалён.';

  @override
  String get errorPortAlreadyInUse =>
      'Этот порт уже занят другим приложением. Выберите другой порт в настройках.';

  @override
  String get errorPermissionDenied =>
      'Не хватило системных разрешений для запуска. Проверьте настройки приложения и повторите попытку.';

  @override
  String errorGoogleRateLimitedRetry(String retryHint) {
    return 'Google временно ограничил запросы для этого аккаунта. Попробуйте снова через $retryHint.';
  }

  @override
  String get errorGoogleRateLimitedLater =>
      'Google временно ограничил запросы для этого аккаунта. Попробуйте снова позже.';

  @override
  String get errorGoogleAccountVerificationRequired =>
      'Google просит подтвердить этот аккаунт. Откройте страницу подтверждения и войдите под тем же Google-аккаунтом.';

  @override
  String get errorGoogleProjectIdMissing =>
      'Google не смог определить корректный ID проекта для этого аккаунта или запроса. Проверьте ID проекта в настройках аккаунта и при необходимости переподключите его.';

  @override
  String get errorGoogleProjectApiDisabled =>
      'Gemini for Google Cloud API отключен для этого проекта. Откройте Google Cloud, включите API для нужного ID проекта и повторите проверку.';

  @override
  String get errorGoogleProjectInvalid =>
      'Google отклонил этот ID проекта. Проверьте, что указали существующий проект и что у аккаунта есть доступ именно к нему.';

  @override
  String get errorGoogleProjectAccessDenied =>
      'Google отклонил запрос для этого проекта или аккаунта. Проверьте ID проекта, выбранный аккаунт и убедитесь, что Gemini Code Assist включен именно для этого проекта.';

  @override
  String get errorAuthExpired =>
      'Срок действия авторизации истек или она стала недействительной. Переподключите аккаунт и попробуйте снова.';

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
      'Лимит этого аккаунта исчерпан. Дождитесь сброса или используйте другой аккаунт.';

  @override
  String errorQuotaExhaustedRetry(String retryHint) {
    return 'Лимит этого аккаунта исчерпан. Попробуйте снова через $retryHint или используйте другой аккаунт.';
  }

  @override
  String get errorInvalidRequestRejected => 'Запрос имеет неверный формат и был отклонён.';

  @override
  String get errorReasoningConfigRejected =>
      'Google отклонил параметры reasoning/thinking для этой модели. Включите автоматический режим размышлений (reasoning).';

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
