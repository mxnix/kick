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
  String get shellSubtitle => 'Локальный прокси для Gemini CLI и Kiro';

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
  String get openAccountsButton => 'Открыть окно с аккаунтами';

  @override
  String get connectAccountShortButton => 'Подключить аккаунт';

  @override
  String get uptimeTitle => 'Время работы';

  @override
  String get uptimeNotStarted => 'Ещё не запускался';

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
  String get accountsSubtitle => 'Подключайте аккаунты Gemini CLI и Kiro и управляйте ими';

  @override
  String get accountsSearchHint => 'Поиск по имени, почте или ID проекта';

  @override
  String get accountsSortLabel => 'Сортировка';

  @override
  String get accountsSortAttention => 'По предупреждениям';

  @override
  String get accountsSortPriority => 'По приоритету';

  @override
  String get accountsSortAlphabetical => 'По имени';

  @override
  String get accountsSortRecentActivity => 'По последней активности';

  @override
  String get addButton => 'Добавить';

  @override
  String get accountsEmptyTitle => 'Аккаунтов пока нет';

  @override
  String get accountsEmptyMessage => 'Подключите хотя бы один аккаунт Gemini CLI или Kiro.';

  @override
  String get connectAccountButton => 'Подключить аккаунт';

  @override
  String get connectAccountDialogTitle => 'Подключить аккаунт';

  @override
  String get connectAccountProviderPickerTitle => 'Выберите провайдера';

  @override
  String get accountsLoadErrorTitle => 'Не удалось загрузить аккаунты';

  @override
  String accountsTotalCount(int count) {
    return 'Всего: $count';
  }

  @override
  String accountsFilteredCount(int count) {
    return 'Показано: $count';
  }

  @override
  String get accountsFilteredEmptyTitle => 'По запросу ничего не найдено';

  @override
  String get accountsFilteredEmptyMessage => 'Попробуйте другое имя, почту или ID проекта.';

  @override
  String get accountAvatarOpenTooltip => 'Открыть аватарку';

  @override
  String get accountAvatarDialogTitle => 'Аватарка аккаунта';

  @override
  String get accountAvatarDiceBearTitle => 'DiceBear Identicon';

  @override
  String get accountAvatarStandardAvatarsTitle => 'Стандартные аватарки';

  @override
  String get accountAvatarApplyButton => 'Применить';

  @override
  String get accountAvatarDiceBearLicense => 'DiceBear Identicon CC0 1.0.';

  @override
  String get accountAvatarChooseFileButton => 'Свой файл';

  @override
  String get accountAvatarResetButton => 'Сбросить';

  @override
  String get accountAvatarResetToDiceBearButton => 'Вернуть DiceBear';

  @override
  String get accountProviderLabel => 'Тип аккаунта';

  @override
  String get accountProviderGemini => 'Gemini CLI';

  @override
  String get accountProviderGeminiCli => 'Gemini CLI';

  @override
  String get accountProviderKiro => 'Kiro';

  @override
  String get kiroBuilderIdStartUrlLabel => 'Ссылка Builder ID';

  @override
  String get kiroBuilderIdStartUrlHelperText => 'Обычно менять не нужно';

  @override
  String get kiroRegionLabel => 'Регион AWS';

  @override
  String get kiroRegionHelperText => 'Обычно us-east-1';

  @override
  String kiroCredentialSourceChip(String value) {
    return 'Источник: $value';
  }

  @override
  String projectIdChip(String projectId) {
    return 'ID проекта: $projectId';
  }

  @override
  String get projectIdAutoChip => 'ID проекта: auto';

  @override
  String priorityChip(String priorityLabel) {
    return 'Приоритет: $priorityLabel';
  }

  @override
  String get accountCoolingDownStatus => 'На паузе';

  @override
  String get accountReadyStatus => 'Готов';

  @override
  String get accountDisabledStatus => 'Выключен';

  @override
  String unsupportedModelsList(String models) {
    return 'Не использовать для моделей: $models';
  }

  @override
  String get editAccountTitle => 'Изменить аккаунт';

  @override
  String get editButton => 'Изменить';

  @override
  String get reauthorizeAccountTitle => 'Переподключить аккаунт';

  @override
  String get reauthorizeButton => 'Переподключить';

  @override
  String get accountProjectCheckButton => 'Проверить доступ к проекту';

  @override
  String get accountProjectCheckInProgressMessage => 'Проверяем...';

  @override
  String get accountProjectCheckSuccessTitle => 'Доступ к проекту подтвержден';

  @override
  String get accountProjectCheckSuccessMessage =>
      'KiCk успешно выполнил тестовый запрос к Google для этого аккаунта и проекта.';

  @override
  String accountProjectCheckModelValue(String model) {
    return 'Модель: $model';
  }

  @override
  String accountProjectCheckTraceIdValue(String traceId) {
    return 'ID трассировки: $traceId';
  }

  @override
  String get accountProjectCheckFailureTitle => 'Проверка не удалась';

  @override
  String get resetCooldownTooltip => 'Сбросить состояние';

  @override
  String get clearCooldownAction => 'Снять паузу';

  @override
  String get deleteTooltip => 'Удалить';

  @override
  String get accountUsageOpenTooltip => 'Лимиты';

  @override
  String get moreButton => 'Ещё';

  @override
  String get deleteAccountDialogTitle => 'Удалить аккаунт?';

  @override
  String deleteAccountDialogMessage(String label) {
    return 'Аккаунт $label будет удалён из KiCk. При необходимости его можно подключить снова позже.';
  }

  @override
  String get deleteAccountConfirmButton => 'Удалить аккаунт';

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
  String get accountUsageStatusLowQuota => 'Лимит заканчивается';

  @override
  String get accountUsageStatusDisabled => 'Выключен';

  @override
  String get accountQuotaWarningStatus => 'Лимит заканчивается';

  @override
  String get accountBanCheckPendingStatus => 'Проверяем блокировку';

  @override
  String get accountBanCheckPendingMessage =>
      'Google вернул RESOURCE_EXHAUSTED без времени сброса.';

  @override
  String get accountTermsOfServiceStatus => 'Блокировка подтверждена';

  @override
  String get accountTermsOfServiceMessage =>
      'Google подтвердил блокировку этого аккаунта за нарушение условий использования. Аккаунт выведен из ротации.';

  @override
  String get accountUsageLoadErrorTitle => 'Не удалось загрузить данные по лимитам';

  @override
  String get accountUsageRetryButton => 'Повторить';

  @override
  String get accountUsageVerifyAccountButton => 'Подтвердить в Google';

  @override
  String get accountSubmitAppealButton => 'Подать апелляцию';

  @override
  String get openGoogleCloudButton => 'Открыть Google Cloud';

  @override
  String get accountUsageVerificationOpenFailedMessage =>
      'Не удалось открыть страницу подтверждения в Google.';

  @override
  String get accountErrorActionOpenFailedMessage => 'Не удалось открыть страницу Google.';

  @override
  String get accountUsageEmptyTitle => 'Данные по лимитам недоступны';

  @override
  String get accountUsageEmptyMessage =>
      'Провайдер не вернул данные по лимитам для этого аккаунта.';

  @override
  String get accountUsageUnavailableTitle => 'Лимиты для этого аккаунта недоступны';

  @override
  String get accountUsageUnavailableMessage =>
      'Страница лимитов работает только для аккаунтов Gemini CLI и Kiro.';

  @override
  String get accountUsageMissingTitle => 'Аккаунт не найден';

  @override
  String get accountUsageMissingSubtitle => 'Информация по лимитам';

  @override
  String get accountUsageMissingMessage =>
      'Возможно, аккаунт уже удалён или список ещё не успел обновиться.';

  @override
  String accountUsageResetsAt(String time) {
    return 'Сбросится $time';
  }

  @override
  String get accountUsageResetUnknown => 'Время следующего сброса неизвестно.';

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
    return 'Почти закончилось: $count';
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
  String accountUsageUsedPercent(String value) {
    return 'Использовано $value%';
  }

  @override
  String accountUsageUsedOfLimit(String used, String limit) {
    return 'Использовано $used из $limit';
  }

  @override
  String get accountUsageBucketHealthy => 'Достаточно';

  @override
  String get accountUsageBucketLow => 'Заканчивается';

  @override
  String get accountUsageBucketCritical => 'Почти закончилось';

  @override
  String get accountUsageKiroAllModelsLimit => 'Лимит на все модели';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsSubtitle => 'Сеть, оформление, API-ключ и работа прокси';

  @override
  String get languageLabel => 'Язык';

  @override
  String get languageHelperText => '«Системный» использует язык устройства';

  @override
  String get languageOptionSystem => 'Системный';

  @override
  String get languageOptionEnglish => 'English';

  @override
  String get languageOptionRussian => 'Русский';

  @override
  String get languageOptionUkrainian => 'Украинский';

  @override
  String get themeLabel => 'Тема';

  @override
  String get themeModeSystem => 'Системная';

  @override
  String get themeModeSystemShort => 'Авто';

  @override
  String get themeModeLight => 'Светлая';

  @override
  String get themeModeDark => 'Тёмная';

  @override
  String get fontLabel => 'Шрифт';

  @override
  String get fontOptionGoogleSans => 'Google Sans';

  @override
  String get fontOptionSystem => 'Системный';

  @override
  String get dynamicThemeTitle => 'Динамическая тема';

  @override
  String get dynamicThemeSubtitle => 'Использовать динамические цвета системы';

  @override
  String get settingsAppearanceSectionTitle => 'Оформление и поведение';

  @override
  String get settingsAppearanceSectionSummary => 'Язык, тема, логи и поведение приложения';

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
  String get windowsTraySubtitle => 'При закрытии окна KiCk продолжит работать в системном трее';

  @override
  String get windowsLaunchAtStartupTitle => 'Запускать при входе в систему';

  @override
  String get windowsLaunchAtStartupSubtitle =>
      'KiCk будет автоматически запускаться при входе в систему';

  @override
  String get windowsTrayNotificationTitle => 'KiCk продолжает работать';

  @override
  String get windowsTrayNotificationBody => 'Приложение свёрнуто в системный трей';

  @override
  String get settingsModelsSectionTitle => 'Модели';

  @override
  String get settingsModelsSectionSummary => 'Пользовательские ID моделей';

  @override
  String get settingsGoogleSectionTitle => 'Возможности провайдеров';

  @override
  String get settingsGoogleSectionSummary => 'Веб-поиск и параметры конкретных провайдеров';

  @override
  String get settingsBackupSectionTitle => 'Резервная копия и восстановление';

  @override
  String get settingsBackupSectionSummary => 'Перенос настроек и аккаунтов между устройствами';

  @override
  String get settingsBackupInfoTitle =>
      'В резервную копию попадут настройки, API-ключ и OAuth-токены';

  @override
  String get settingsBackupInfoSubtitle =>
      'Храните файл в безопасном месте. После восстановления текущие настройки и список аккаунтов будут полностью заменены.';

  @override
  String get hostLabel => 'Хост';

  @override
  String get hostHelperText => 'Обычно localhost';

  @override
  String get hostRequiredError => 'Укажите адрес хоста';

  @override
  String get hostInvalidError => 'Адрес не должен содержать пробелы';

  @override
  String get hostLanDisabledError =>
      'Чтобы использовать 0.0.0.0, включите доступ из локальной сети';

  @override
  String get portLabel => 'Порт';

  @override
  String get portHelperText => 'По умолчанию 3000';

  @override
  String get portInvalidError => 'Укажите порт от 1 до 65535';

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
  String get requestRetriesInvalidError => 'Укажите число от 0 до 20';

  @override
  String get retry429DelayLabel => 'Интервал повтора при 429';

  @override
  String get retry429DelayHelperText =>
      'Интервал, с которым прокси повторяет запрос после ошибки 429';

  @override
  String get retry429DelayInvalidError => 'Укажите число от 1 до 3600';

  @override
  String get mark429AsUnhealthyTitle => 'Выводить аккаунт из ротации при ошибке 429';

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
  String get logRetentionLabel => 'Лимит записей лога';

  @override
  String get logRetentionHelperText =>
      'При достижении лимита самые старые записи автоматически удаляются';

  @override
  String logRetentionInvalidError(int min, int max) {
    return 'Укажите число от $min до $max';
  }

  @override
  String get unsafeRawLoggingTitle => 'Сырые логи отладки';

  @override
  String get unsafeRawLoggingSubtitle =>
      'Сохраняет содержимое запросов и ответов. Включайте только для отладки.';

  @override
  String get defaultGoogleWebSearchTitle => 'Включать веб-поиск по умолчанию';

  @override
  String get defaultGoogleWebSearchSubtitle =>
      'KiCk будет автоматически использовать Google Поиск, если клиент не задал свои параметры и в запросе нет вызовов функций';

  @override
  String get defaultGoogleVisibleReasoningTitle =>
      'Запрашивать видимые рассуждения Gemini по умолчанию';

  @override
  String get defaultGoogleVisibleReasoningSubtitle =>
      'Добавляет include_reasoning для запросов Gemini CLI, если клиент не задал рассуждения сам. Помогает клиентам показывать блок рассуждений.';

  @override
  String get renderGoogleGroundingInMessageTitle => 'Показывать цитаты и источники в ответе';

  @override
  String get renderGoogleGroundingInMessageSubtitle =>
      'Если выключить, ссылки на источники останутся в метаданных и не будут добавляться в текст ответа';

  @override
  String get settingsGeminiSubsectionTitle => 'Gemini CLI';

  @override
  String get settingsKiroSubsectionTitle => 'Kiro';

  @override
  String get defaultKiroServerToolsTitle => 'Включать серверные инструменты Kiro по умолчанию';

  @override
  String get defaultKiroServerToolsSubtitle =>
      'Добавляет инструмент веб-поиска Kiro к запросам, если клиент не задал свои инструменты. Каждый вызов расходует дополнительные кредиты Kiro.';

  @override
  String get customModelsLabel => 'Пользовательские ID моделей';

  @override
  String get customModelsHelperText => 'По одному ID на строку, например google/... или kiro/...';

  @override
  String get settingsSavingStatus => 'Сохраняем изменения...';

  @override
  String get settingsSavedStatus => 'Изменения сохранены';

  @override
  String get settingsValidationStatus => 'Проверьте поля с ошибками';

  @override
  String get settingsSaveFailedStatus => 'Не удалось сохранить изменения';

  @override
  String get settingsBackupExportButton => 'Сохранить резервную копию';

  @override
  String get settingsBackupImportButton => 'Восстановить резервную копию';

  @override
  String get settingsBackupExportOptionsDialogTitle => 'Экспорт резервной копии';

  @override
  String get settingsBackupExportDialogTitle => 'Куда сохранить резервную копию?';

  @override
  String get settingsBackupImportDialogTitle => 'Выберите файл резервной копии';

  @override
  String get settingsBackupExportConfirmButton => 'Продолжить';

  @override
  String get settingsBackupProtectWithPasswordLabel => 'Защитить файл паролем (рекомендуется)';

  @override
  String get settingsBackupProtectWithPasswordSubtitle =>
      'Шифрует резервную копию, чтобы токены и ключи нельзя было прочитать без пароля';

  @override
  String get settingsBackupPasswordLabel => 'Пароль';

  @override
  String get settingsBackupPasswordConfirmLabel => 'Подтвердите пароль';

  @override
  String get settingsBackupPasswordHelperText =>
      'Запомните этот пароль: без него зашифрованную копию не получится восстановить.';

  @override
  String get settingsBackupPasswordsDoNotMatch => 'Пароли не совпадают';

  @override
  String get settingsBackupUnprotectedWarning =>
      'Ваши токены и ключи будут сохранены в открытом виде. Любой, у кого окажется этот файл, получит доступ к вашим данным.';

  @override
  String get settingsBackupRestoreDialogTitle => 'Восстановить конфигурацию?';

  @override
  String get settingsBackupRestoreDialogMessage =>
      'Текущие настройки, API-ключ и список аккаунтов будут заменены данными из этой резервной копии. Это действие нельзя отменить.';

  @override
  String get settingsBackupRestoreConfirmButton => 'Восстановить';

  @override
  String get settingsBackupPasswordDialogTitle => 'Введите пароль резервной копии';

  @override
  String settingsBackupPasswordDialogMessage(String fileName) {
    return 'Файл $fileName защищён паролем. Введите пароль, чтобы продолжить восстановление.';
  }

  @override
  String settingsBackupPasswordDialogInvalidMessage(String fileName) {
    return 'Не удалось расшифровать файл $fileName. Проверьте пароль и попробуйте снова.';
  }

  @override
  String get settingsBackupPasswordConfirmButton => 'Расшифровать';

  @override
  String settingsBackupExportedMessage(String fileName) {
    return 'Резервная копия сохранена в файл $fileName';
  }

  @override
  String settingsBackupRestoredMessage(int accountCount) {
    return 'Конфигурация восстановлена. Аккаунтов: $accountCount';
  }

  @override
  String settingsBackupRestoredMissingTokensMessage(int accountCount, int missingCount) {
    return 'Конфигурация восстановлена. Аккаунтов: $accountCount, без токенов: $missingCount';
  }

  @override
  String settingsBackupExportFailedMessage(String error) {
    return 'Не удалось сохранить резервную копию: $error';
  }

  @override
  String settingsBackupRestoreFailedMessage(String error) {
    return 'Не удалось восстановить резервную копию: $error';
  }

  @override
  String get settingsBackupInvalidMessage =>
      'Файл резервной копии повреждён или имеет неподдерживаемый формат';

  @override
  String get settingsBackupUnsupportedVersionMessage =>
      'Эта резервная копия создана в более новой версии KiCk и пока не поддерживается';

  @override
  String get settingsBackupReadFailedMessage => 'Не удалось прочитать выбранную резервную копию';

  @override
  String get settingsBackupPasswordRequiredMessage => 'Для этой резервной копии нужен пароль';

  @override
  String get settingsLoadErrorTitle => 'Не удалось загрузить настройки';

  @override
  String get aboutTitle => 'О программе';

  @override
  String get aboutMenuSubtitle => 'Версия, обновления и аналитика';

  @override
  String get aboutDescription =>
      'Локальный OpenAI-совместимый прокси для Gemini CLI и Kiro в нативном приложении Flutter';

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
  String get aboutDownloadUpdateButton => 'Скачать обновление';

  @override
  String get aboutDownloadAndInstallButton => 'Скачать и установить';

  @override
  String get aboutInstallOnRestartButton => 'Установить при перезапуске';

  @override
  String get aboutInstallUpdateButton => 'Установить обновление';

  @override
  String get aboutAllowUnknownSourcesButton => 'Разрешить этот источник';

  @override
  String get aboutPreparingUpdateButton => 'Готовим обновление...';

  @override
  String aboutUpdateDownloadingProgress(String progress) {
    return 'Скачиваем обновление в фоне: $progress';
  }

  @override
  String get aboutUpdateDownloadingIndeterminate => 'Скачиваем обновление в фоне...';

  @override
  String get aboutUpdateVerifyingMessage => 'Проверяем скачанный файл по SHA-256...';

  @override
  String get aboutUpdateReadyVerifiedMessage =>
      'Обновление скачано, проверено и готово к установке.';

  @override
  String get aboutUpdateReadyUnverifiedMessage =>
      'Обновление скачано и готово к установке. Для этого релиза не была предоставлена контрольная сумма.';

  @override
  String get aboutUpdateUnknownSourcesMessage =>
      'Разрешите установку из этого источника в настройках Android, затем вернитесь и снова нажмите «Установить обновление».';

  @override
  String aboutUpdateOperationFailedMessage(String error) {
    return 'Не удалось подготовить обновление: $error';
  }

  @override
  String get aboutOpenReleaseButton => 'Открыть релиз';

  @override
  String get aboutRetryUpdateCheckButton => 'Проверить ещё раз';

  @override
  String get aboutAnalyticsTitle => 'Аналитика';

  @override
  String get aboutAnalyticsSubtitle => 'Анонимная статистика использования помогает улучшать KiCk.';

  @override
  String get aboutLicenseTitle => 'Лицензия';

  @override
  String get aboutLicenseMessage => 'KiCk распространяется как проект с открытым исходным кодом.';

  @override
  String get aboutOpenLicenseButton => 'Открыть лицензию';

  @override
  String get aboutPrivacyTitle => 'Приватность';

  @override
  String get aboutPrivacyMessage => 'KiCk хранит аккаунты, токены и настройки локально.';

  @override
  String get aboutOpenPrivacyButton => 'Открыть заметку о приватности';

  @override
  String get aboutDisclaimerTitle => 'Отказ от ответственности';

  @override
  String get aboutDisclaimerMessage => 'KiCk не связан с Google, AWS, Kiro или SillyTavern.';

  @override
  String get aboutCreditsTitle => 'Благодарности';

  @override
  String get aboutCreditsMessage =>
      'Собрано на Flutter и Material Symbols. DiceBear Identicon CC0 1.0.';

  @override
  String get aboutOpenLinkFailedMessage => 'Не удалось открыть ссылку';

  @override
  String get copyProxyEndpointTooltip => 'Скопировать адрес прокси';

  @override
  String get proxyEndpointCopiedMessage => 'Адрес прокси скопирован';

  @override
  String get copyApiKeyTooltip => 'Скопировать API-ключ';

  @override
  String get apiKeyCopiedMessage => 'API-ключ скопирован';

  @override
  String get pushSillyTavernButton => 'В SillyTavern';

  @override
  String get pushSillyTavernDialogTitle => 'Отправить в запущенный SillyTavern';

  @override
  String get pushSillyTavernDialogMessage =>
      'KiCk добавит профиль и выберет его в менеджере подключений.';

  @override
  String get pushSillyTavernUrlLabel => 'URL SillyTavern';

  @override
  String get pushSillyTavernProfileNameLabel => 'Имя профиля';

  @override
  String get pushSillyTavernModelLabel => 'Модель';

  @override
  String get pushSillyTavernConfirmButton => 'Добавить профиль';

  @override
  String pushSillyTavernSuccessMessage(String profileName) {
    return 'Профиль \"$profileName\" добавлен в SillyTavern.';
  }

  @override
  String pushSillyTavernFailedMessage(String error) {
    return 'Не удалось отправить профиль в SillyTavern: $error';
  }

  @override
  String get pushSillyTavernErrorInvalidUrl =>
      'Укажите полный URL SillyTavern, например http://127.0.0.1:8000.';

  @override
  String get pushSillyTavernErrorMissingCsrf => 'SillyTavern не вернул CSRF-токен.';

  @override
  String pushSillyTavernErrorHttp(int statusCode, String path) {
    return 'SillyTavern вернул HTTP $statusCode для $path.';
  }

  @override
  String get pushSillyTavernErrorInvalidJson => 'SillyTavern вернул некорректный JSON-ответ.';

  @override
  String get homeOnboardingTitle => 'С чего начать';

  @override
  String get homeOnboardingSubtitle => 'Короткая подсказка для первого запуска';

  @override
  String get homeOnboardingAccountsTitle => 'Подключите аккаунт';

  @override
  String get homeOnboardingAccountsMessage =>
      'KiCk не сможет обрабатывать запросы без активного аккаунта Gemini CLI или Kiro.';

  @override
  String get homeOnboardingEndpointTitle => 'Посмотрите адрес прокси';

  @override
  String homeOnboardingEndpointMessage(String endpoint) {
    return 'Когда все будет готово, используйте адрес $endpoint в своем клиенте.';
  }

  @override
  String get homeOnboardingStartTitle => 'Запустите прокси';

  @override
  String get homeOnboardingStartMessage =>
      'После запуска KiCk начнёт принимать запросы на этом устройстве.';

  @override
  String get homeOnboardingFooter =>
      'Если аккаунт уже подключён, просто включите его на экране аккаунтов и вернитесь сюда.';

  @override
  String get apiKeyRegeneratedMessage => 'Новый API-ключ сохранён';

  @override
  String get regenerateApiKeyAction => 'Создать новый API-ключ';

  @override
  String get regenerateApiKeyDialogTitle => 'Создать новый API-ключ?';

  @override
  String get regenerateApiKeyDialogMessage =>
      'Старый ключ будет сразу отозван. Всем подключённым клиентам понадобится новый ключ, чтобы продолжить работу.';

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
  String get welcomeTitle => 'Добро пожаловать в KiCk';

  @override
  String get welcomeSubtitle =>
      'KiCk помогает запустить локальный прокси для Gemini CLI и Kiro без терминала и лишних настроек.';

  @override
  String get welcomeStepAccountsTitle => 'Подключите аккаунт';

  @override
  String get welcomeStepAccountsMessage =>
      'Сделайте это на экране аккаунтов. Можно подключить Gemini CLI или Kiro.';

  @override
  String get welcomeStepHomeTitle => 'Откройте главную';

  @override
  String get welcomeStepHomeMessage =>
      'На главной всегда видны адрес прокси, API-ключ и кнопка запуска.';

  @override
  String get welcomeUsageTitle => 'Важно знать';

  @override
  String get welcomeUsageMessage =>
      'KiCk создан для личного, учебного и исследовательского использования.';

  @override
  String get welcomeAnalyticsTitle => 'Анонимная аналитика';

  @override
  String get welcomeAnalyticsSubtitle =>
      'Помогает понять, где KiCk работает хорошо, а где его можно улучшить.';

  @override
  String get welcomeRepositoryLinkLabel => 'Подробнее о проекте';

  @override
  String get logsTitle => 'Логи';

  @override
  String get logsSubtitle => 'История запросов и ошибок';

  @override
  String get logsSearchHint => 'Поиск по маршруту или сообщению';

  @override
  String get logsRefreshButton => 'Обновить';

  @override
  String get logsClearButton => 'Очистить';

  @override
  String get logsClearDialogTitle => 'Очистить логи?';

  @override
  String get logsClearDialogMessage =>
      'Все записи будут удалены из KiCk. Это действие нельзя отменить.';

  @override
  String get logsClearConfirmButton => 'Очистить';

  @override
  String get logsLevelAll => 'Все уровни';

  @override
  String get logsLevelInfo => 'Инфо';

  @override
  String get logsLevelWarning => 'Предупреждения';

  @override
  String get logsLevelError => 'Ошибки';

  @override
  String get logsCategoryAll => 'Все категории';

  @override
  String get logsCategoryFilterTitle => 'Категории';

  @override
  String get logsPayloadShowButton => 'Показать payload';

  @override
  String get logsPayloadHideButton => 'Скрыть payload';

  @override
  String get logsCopyEntryButton => 'Копировать';

  @override
  String get logsCopiedMessage => 'Запись лога скопирована';

  @override
  String get logsFilteredEmptyTitle => 'По текущим фильтрам ничего не найдено';

  @override
  String get logsFilteredEmptyMessage => 'Попробуйте убрать часть фильтров или изменить поиск.';

  @override
  String get logsEntryLevelInfo => 'Инфо';

  @override
  String get logsEntryLevelWarning => 'Предупреждение';

  @override
  String get logsEntryLevelError => 'Ошибка';

  @override
  String logsTotalCount(int count) {
    return 'Всего: $count';
  }

  @override
  String logsFilteredCount(int count) {
    return 'После фильтра: $count';
  }

  @override
  String logsRequestGroupTitle(String requestLabel) {
    return 'Запрос $requestLabel';
  }

  @override
  String logsRequestStatusCount(int count) {
    return 'Статусов: $count';
  }

  @override
  String logsRequestRetryCount(int count) {
    return 'Повторов: $count';
  }

  @override
  String logsRequestKiroCredits(String credits) {
    return 'Кредитов: $credits';
  }

  @override
  String get logsRequestDetailsShowButton => 'Показать статусы';

  @override
  String get logsRequestDetailsHideButton => 'Скрыть статусы';

  @override
  String logsLoadedCount(int count) {
    return 'Загружено: $count';
  }

  @override
  String get logsEmptyTitle => 'Логи пусты';

  @override
  String get logsLoadErrorTitle => 'Не удалось загрузить логи';

  @override
  String get logsExportTooltip => 'Сохранить все логи по текущим фильтрам';

  @override
  String get logsExportDialogTitle => 'Куда сохранить логи?';

  @override
  String get logsShareTooltip => 'Поделиться всеми логами по текущим фильтрам';

  @override
  String get logsLoadMoreButton => 'Загрузить ещё';

  @override
  String get logsNothingToExportMessage => 'Нет логов для сохранения.';

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
  String get logsExportFileTitle => 'Экспорт логов KiCk';

  @override
  String get logsExportShareSubject => 'Логи KiCk';

  @override
  String get logsExportGeneratedAtLabel => 'Сгенерировано';

  @override
  String logsExportEntriesCount(int count) {
    return 'Записей: $count';
  }

  @override
  String get logsExportSectionEnvironment => 'Окружение';

  @override
  String get logsExportAppLabel => 'Приложение';

  @override
  String get logsExportFiltersLabel => 'Фильтры';

  @override
  String get logsExportScopeLabel => 'Область';

  @override
  String get logsExportRuntimeSettingsLabel => 'Настройки во время работы';

  @override
  String get logsExportNoneValue => 'нет';

  @override
  String get logsExportNoneDetectedValue => 'не обнаружено';

  @override
  String get logsExportSectionDiagnostics => 'Сводка диагностики';

  @override
  String get logsExportTimeRangeLabel => 'Временной диапазон';

  @override
  String get logsExportLevelsLabel => 'Уровни';

  @override
  String get logsExportCategoriesLabel => 'Категории';

  @override
  String get logsExportRoutesLabel => 'Маршруты';

  @override
  String get logsExportModelsLabel => 'Модели';

  @override
  String get logsExportStatusCodesLabel => 'Коды статуса';

  @override
  String get logsExportErrorDetailsLabel => 'Подробности ошибок';

  @override
  String get logsExportUpstreamReasonsLabel => 'Причины от провайдера';

  @override
  String get logsExportRetriedRequestsLabel => 'Повторов запросов';

  @override
  String get logsExportTokensLabel => 'Токены';

  @override
  String get logsExportKiroCreditsLabel => 'Кредиты Kiro';

  @override
  String get logsExportAndroidBackgroundSessionsLabel => 'Фоновые сессии Android';

  @override
  String get logsExportTimestampLabel => 'Время';

  @override
  String get logsExportLevelLabel => 'Уровень';

  @override
  String get logsExportCategoryLabel => 'Категория';

  @override
  String get logsExportRouteLabel => 'Маршрут';

  @override
  String get logsExportMessageLabel => 'Сообщение';

  @override
  String get logsExportMaskedPayloadLabel => 'Payload (замаскированный)';

  @override
  String get logsExportRawPayloadLabel => 'Payload (без маскировки)';

  @override
  String get logMessageRequestReceived => 'Запрос получен';

  @override
  String get logMessageParsedRequest => 'Запрос разобран';

  @override
  String get logMessageResponseCompleted => 'Ответ завершён';

  @override
  String get logMessageStreamClientAborted => 'Потоковый ответ прерван клиентом';

  @override
  String get logMessageRetryScheduled => 'Запланирован повтор после сбоя запроса';

  @override
  String get logMessageRetryWithAnotherAccount => 'Повторяем запрос с другим аккаунтом после сбоя';

  @override
  String get logMessageRequestSucceededAfterRetries => 'Запрос выполнен после повторных попыток';

  @override
  String get logMessageRequestFailedAfterRetries => 'Запрос не удался после повторных попыток';

  @override
  String get logMessageDispatchingStreamingRequest => 'Отправляем потоковый запрос провайдеру';

  @override
  String get logMessageDispatchingRequest => 'Отправляем запрос провайдеру';

  @override
  String get logMessageUpstreamPayloadReturned => 'Провайдер вернул ответ';

  @override
  String get logMessageMappedChatCompletion =>
      'Ответ провайдера преобразован в формат OpenAI Chat Completion';

  @override
  String logMessageUsingAccountForModel(String account, String model) {
    return 'Используем аккаунт $account для $model';
  }

  @override
  String get logMessageProxySessionSummary => 'Сводка по сессии прокси';

  @override
  String get logMessageAndroidBackgroundSessionStarted => 'Фоновая сессия Android началась';

  @override
  String get logMessageAndroidBackgroundSessionEnded => 'Фоновая сессия Android завершилась';

  @override
  String get logMessageAndroidBackgroundSessionRecovered =>
      'Фоновая сессия Android восстановлена после перезапуска процесса';

  @override
  String get accountDialogTitle => 'Аккаунт';

  @override
  String get accountDialogBasicsTitle => 'Основное';

  @override
  String get accountDialogBasicsSubtitle => 'Поля для подключения выбранного типа аккаунта';

  @override
  String get accountDialogAdvancedTitle => 'Расширенные настройки';

  @override
  String get accountDialogAdvancedSubtitle => 'Приоритет и ограничения по моделям';

  @override
  String get accountDialogAdvancedHint =>
      'Если не хотите настраивать вручную, этот блок можно оставить как есть.';

  @override
  String get projectIdLabel => 'ID проекта';

  @override
  String get projectIdHint => 'my-google-cloud-project';

  @override
  String get projectIdOptionalHelperText =>
      'Необязательно. Если оставить пустым, KiCk попробует определить его автоматически.';

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
  String get accountNameHelperText => 'Если оставить поле пустым, KiCk подставит имя аккаунта.';

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
  String get blockedModelsHelperText => 'По одному ID на строку, например google/... или kiro/...';

  @override
  String get kiroLinkAuthDialogTitle => 'Авторизация Kiro';

  @override
  String get kiroLinkAuthDialogMessage =>
      'Откройте ссылку и войдите в Kiro через GitHub или Google. KiCk сам дождется ответа из браузера.';

  @override
  String get kiroLinkAuthUserCodeLabel => 'Код для сверки';

  @override
  String get kiroLinkAuthVerificationUrlLabel => 'Ссылка для входа';

  @override
  String get kiroLinkAuthWaitingMessage => 'Ждем подтверждения входа в браузере...';

  @override
  String get kiroLinkAuthOpenLinkButton => 'Открыть ссылку';

  @override
  String get kiroLinkAuthOpenLinkAgainButton => 'Открыть снова';

  @override
  String get kiroLinkAuthOpenLinkFailedMessage => 'Не удалось открыть ссылку для входа в Kiro.';

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
  String get oauthPageTitleError => 'Ошибка авторизации';

  @override
  String get oauthPageTitleSuccess => 'Успешная авторизация';

  @override
  String get oauthPageStateMismatchMessage => 'Состояния не совпадают. Можно закрыть эту вкладку.';

  @override
  String get oauthPageGoogleErrorMessage => 'Google вернул ошибку. Можно закрыть эту вкладку.';

  @override
  String get oauthPageCodeMissingMessage => 'Код не получен. Можно закрыть эту вкладку.';

  @override
  String get oauthPageCloseTabMessage => 'Вкладку можно закрыть.';

  @override
  String get accountDisplayNameFallbackGoogle => 'Google-аккаунт';

  @override
  String get errorNetworkUnavailable =>
      'Не удалось связаться с серверами Google. Проверьте интернет и попробуйте снова.';

  @override
  String get errorGoogleServiceUnavailable => 'Google временно недоступен. Попробуйте позже.';

  @override
  String get errorInvalidServiceResponse => 'Сервер вернул неожиданный ответ. Попробуйте еще раз.';

  @override
  String get errorGoogleAuthFailed => 'Не удалось войти в Google. Попробуйте снова.';

  @override
  String get errorGoogleAuthTimedOut =>
      'Вход в Google не завершился вовремя. Вернитесь в приложение и попробуйте снова. Если это повторяется на Android, отключите для KiCk ограничения батареи.';

  @override
  String get errorGoogleAuthBrowserOpenFailed =>
      'Не удалось открыть браузер для входа в Google. Попробуйте снова.';

  @override
  String get errorUnknown => 'Что-то пошло не так. Попробуйте снова.';

  @override
  String get errorOauthTokensMissing =>
      'Токены авторизации для этого аккаунта не найдены. Переподключите аккаунт.';

  @override
  String get errorAccountNotFound => 'Аккаунт не найден. Возможно, он уже удалён.';

  @override
  String get errorPortAlreadyInUse =>
      'Этот порт уже занят другим приложением. Выберите другой порт в настройках.';

  @override
  String get errorPermissionDenied =>
      'Не хватает системных разрешений для запуска. Проверьте настройки приложения и попробуйте снова.';

  @override
  String errorGoogleRateLimitedRetry(String retryHint) {
    return 'Google временно ограничил запросы для этого аккаунта. Попробуйте снова через $retryHint.';
  }

  @override
  String get errorGoogleRateLimitedLater =>
      'Google временно ограничил запросы для этого аккаунта. Попробуйте позже.';

  @override
  String get errorKiroAuthExpired => 'Сессия Kiro истекла. Войдите заново и попробуйте снова.';

  @override
  String get errorKiroAuthStartFailed => 'Не удалось начать вход в Kiro. Попробуйте позже.';

  @override
  String get errorKiroAuthCancelled => 'Вход в Kiro был отменён.';

  @override
  String get errorKiroAuthTimedOut => 'Время ожидания входа в Kiro истекло. Попробуйте снова.';

  @override
  String get errorKiroAuthRejected => 'Kiro отклонил вход. Попробуйте начать заново.';

  @override
  String errorKiroRateLimitedRetry(String retryHint) {
    return 'Kiro временно ограничил запросы. Попробуйте снова через $retryHint.';
  }

  @override
  String get errorKiroRateLimitedLater => 'Kiro временно ограничил запросы. Попробуйте позже.';

  @override
  String get errorKiroServiceUnavailable => 'Kiro временно недоступен. Попробуйте позже.';

  @override
  String get errorGoogleAccountVerificationRequired =>
      'Google просит подтвердить этот аккаунт. Откройте страницу подтверждения и войдите под тем же Google-аккаунтом.';

  @override
  String get errorGoogleProjectIdMissing =>
      'Google не смог определить корректный ID проекта для этого аккаунта или запроса. Проверьте ID проекта в настройках аккаунта и при необходимости переподключите его.';

  @override
  String get errorGoogleProjectApiDisabled =>
      'Gemini for Google Cloud API выключен для этого проекта. Откройте Google Cloud, включите API для нужного ID проекта и повторите проверку.';

  @override
  String get errorGoogleProjectInvalid =>
      'Google отклонил этот ID проекта. Убедитесь, что указан существующий проект и у аккаунта есть к нему доступ.';

  @override
  String get errorGoogleProjectAccessDenied =>
      'Google отклонил запрос для этого проекта или аккаунта. Проверьте ID проекта, выбранный аккаунт и убедитесь, что Gemini Code Assist включён именно для этого проекта.';

  @override
  String get errorAuthExpired =>
      'Срок действия авторизации истёк или она больше недействительна. Переподключите аккаунт и попробуйте снова.';

  @override
  String get errorGoogleCapacity => 'Серверы Google временно перегружены. Попробуйте чуть позже.';

  @override
  String get errorUnsupportedModel => 'Выбранная модель сейчас недоступна для этого аккаунта.';

  @override
  String get errorInvalidJson => 'Запрос содержит некорректный JSON.';

  @override
  String get errorUnexpectedResponse => 'Сервис вернул неожиданный ответ. Попробуйте снова.';

  @override
  String get errorQuotaExhausted =>
      'Лимит этого аккаунта исчерпан. Дождитесь сброса или используйте другой аккаунт.';

  @override
  String errorQuotaExhaustedRetry(String retryHint) {
    return 'Лимит этого аккаунта исчерпан. Попробуйте снова через $retryHint или используйте другой аккаунт.';
  }

  @override
  String get errorQuotaExhaustedNoResetHint =>
      'Google вернул RESOURCE_EXHAUSTED без времени сброса. KiCk отдельно проверит этот аккаунт. Если ошибка повторится, используйте другой аккаунт.';

  @override
  String get errorGoogleTermsOfServiceViolation =>
      'Google отключил этот аккаунт за нарушение условий использования. Подайте апелляцию или используйте другой аккаунт.';

  @override
  String get errorInvalidRequestRejected => 'У запроса неверный формат, поэтому он был отклонён.';

  @override
  String get errorReasoningConfigRejected =>
      'Google отклонил параметры reasoning/thinking для этой модели. Включите автоматический режим рассуждений (reasoning).';

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
