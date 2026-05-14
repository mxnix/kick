// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get appTitle => 'KiCk';

  @override
  String get shellSubtitle => 'Локальний проксі для Gemini CLI та Kiro';

  @override
  String get connectGoogleAccountTitle => 'Підключити Google-акаунт';

  @override
  String get homeTitle => 'Головна';

  @override
  String get proxyRunningStatus => 'Запущено';

  @override
  String get proxyStoppedStatus => 'Зупинено';

  @override
  String get embeddedProxyTitle => 'Проксі-сервер';

  @override
  String proxyAddress(String host, int port) {
    return 'Адреса: $host:$port';
  }

  @override
  String get proxyEndpointTitle => 'Адреса проксі';

  @override
  String activeAccounts(int count) {
    return 'Активних акаунтів: $count';
  }

  @override
  String get stopProxyButton => 'Зупинити';

  @override
  String get startProxyButton => 'Запустити';

  @override
  String get openAccountsButton => 'Відкрити вікно з акаунтами';

  @override
  String get connectAccountShortButton => 'Підключити акаунт';

  @override
  String get uptimeTitle => 'Час роботи';

  @override
  String get uptimeNotStarted => 'Ще не запускався';

  @override
  String uptimeValue(int hours, int minutes, int seconds) {
    return '$hours год $minutes хв $seconds с';
  }

  @override
  String get versionTitle => 'Версія';

  @override
  String get apiKeyTitle => 'API-ключ';

  @override
  String get apiKeyDisabledValue => 'Не потрібен';

  @override
  String get changeApiKeyLinkLabel => 'Змінити API-ключ';

  @override
  String get loadingValue => 'Завантаження...';

  @override
  String get lastErrorTitle => 'Остання помилка';

  @override
  String get openLogsButton => 'Відкрити логи';

  @override
  String get accountsTitle => 'Акаунти';

  @override
  String get accountsSubtitle => 'Підключайте акаунти Gemini CLI і Kiro та керуйте ними';

  @override
  String get accountsSearchHint => 'Пошук за іменем, поштою або ID проєкту';

  @override
  String get accountsSortLabel => 'Сортування';

  @override
  String get accountsSortAttention => 'За попередженнями';

  @override
  String get accountsSortPriority => 'За пріоритетом';

  @override
  String get accountsSortAlphabetical => 'За іменем';

  @override
  String get accountsSortRecentActivity => 'За останньою активністю';

  @override
  String get addButton => 'Додати';

  @override
  String get accountsEmptyTitle => 'Акаунтів поки немає';

  @override
  String get accountsEmptyMessage => 'Підключіть хоча б один акаунт Gemini CLI або Kiro.';

  @override
  String get connectAccountButton => 'Підключити акаунт';

  @override
  String get connectAccountDialogTitle => 'Підключити акаунт';

  @override
  String get connectAccountProviderPickerTitle => 'Виберіть провайдера';

  @override
  String get accountsLoadErrorTitle => 'Не вдалося завантажити акаунти';

  @override
  String accountsTotalCount(int count) {
    return 'Усього: $count';
  }

  @override
  String accountsFilteredCount(int count) {
    return 'Показано: $count';
  }

  @override
  String get accountsFilteredEmptyTitle => 'За запитом нічого не знайдено';

  @override
  String get accountsFilteredEmptyMessage => 'Спробуйте інше ім\'я, пошту або ID проєкту.';

  @override
  String get accountAvatarOpenTooltip => 'Відкрити аватар';

  @override
  String get accountAvatarDialogTitle => 'Аватар акаунта';

  @override
  String get accountAvatarDiceBearTitle => 'DiceBear Identicon';

  @override
  String get accountAvatarStandardAvatarsTitle => 'Стандартні аватари';

  @override
  String get accountAvatarApplyButton => 'Застосувати';

  @override
  String get accountAvatarDiceBearLicense => 'DiceBear Identicon CC0 1.0.';

  @override
  String get accountAvatarChooseFileButton => 'Свій файл';

  @override
  String get accountAvatarResetButton => 'Скинути';

  @override
  String get accountAvatarResetToDiceBearButton => 'Повернути DiceBear';

  @override
  String get accountProviderLabel => 'Тип акаунта';

  @override
  String get accountProviderGemini => 'Gemini CLI';

  @override
  String get accountProviderGeminiCli => 'Gemini CLI';

  @override
  String get accountProviderKiro => 'Kiro';

  @override
  String get kiroBuilderIdStartUrlLabel => 'Посилання Builder ID';

  @override
  String get kiroBuilderIdStartUrlHelperText => 'Зазвичай змінювати не потрібно';

  @override
  String get kiroRegionLabel => 'Регіон AWS';

  @override
  String get kiroRegionHelperText => 'Зазвичай us-east-1';

  @override
  String kiroCredentialSourceChip(String value) {
    return 'Джерело: $value';
  }

  @override
  String projectIdChip(String projectId) {
    return 'ID проєкту: $projectId';
  }

  @override
  String get projectIdAutoChip => 'ID проєкту: auto';

  @override
  String priorityChip(String priorityLabel) {
    return 'Пріоритет: $priorityLabel';
  }

  @override
  String get accountCoolingDownStatus => 'На паузі';

  @override
  String get accountReadyStatus => 'Готовий';

  @override
  String get accountDisabledStatus => 'Вимкнений';

  @override
  String unsupportedModelsList(String models) {
    return 'Не використовувати для моделей: $models';
  }

  @override
  String get editAccountTitle => 'Змінити акаунт';

  @override
  String get editButton => 'Змінити';

  @override
  String get reauthorizeAccountTitle => 'Перепідключити акаунт';

  @override
  String get reauthorizeButton => 'Перепідключити';

  @override
  String get accountProjectCheckButton => 'Перевірити доступ до проєкту';

  @override
  String get accountProjectCheckInProgressMessage => 'Перевіряємо...';

  @override
  String get accountProjectCheckSuccessTitle => 'Доступ до проєкту підтверджено';

  @override
  String get accountProjectCheckSuccessMessage =>
      'KiCk успішно виконав тестовий запит до Google для цього акаунта і проєкту.';

  @override
  String accountProjectCheckModelValue(String model) {
    return 'Модель: $model';
  }

  @override
  String accountProjectCheckTraceIdValue(String traceId) {
    return 'ID трасування: $traceId';
  }

  @override
  String get accountProjectCheckFailureTitle => 'Перевірка не вдалася';

  @override
  String get resetCooldownTooltip => 'Скинути стан';

  @override
  String get clearCooldownAction => 'Зняти паузу';

  @override
  String get deleteTooltip => 'Видалити';

  @override
  String get accountUsageOpenTooltip => 'Ліміти';

  @override
  String get moreButton => 'Ще';

  @override
  String get deleteAccountDialogTitle => 'Видалити акаунт?';

  @override
  String deleteAccountDialogMessage(String label) {
    return 'Акаунт $label буде видалено з KiCk. За потреби його можна підключити знову пізніше.';
  }

  @override
  String get deleteAccountConfirmButton => 'Видалити акаунт';

  @override
  String get accountUsageTitle => 'Ліміти акаунта';

  @override
  String get accountUsageProviderLabel => 'Авторизація Gemini CLI (OAuth)';

  @override
  String get accountUsageRefreshTooltip => 'Оновити';

  @override
  String get accountUsageStatusHealthy => 'Доступний';

  @override
  String get accountUsageStatusCoolingDown => 'Обмежений';

  @override
  String get accountUsageStatusLowQuota => 'Ліміт закінчується';

  @override
  String get accountUsageStatusDisabled => 'Вимкнений';

  @override
  String get accountQuotaWarningStatus => 'Ліміт закінчується';

  @override
  String get accountBanCheckPendingStatus => 'Перевіряємо блокування';

  @override
  String get accountBanCheckPendingMessage =>
      'Google повернув RESOURCE_EXHAUSTED без часу скидання.';

  @override
  String get accountTermsOfServiceStatus => 'Блокування підтверджено';

  @override
  String get accountTermsOfServiceMessage =>
      'Google підтвердив блокування цього акаунта за порушення умов використання. Акаунт виведено з ротації.';

  @override
  String get accountUsageLoadErrorTitle => 'Не вдалося завантажити дані щодо лімітів';

  @override
  String get accountUsageRetryButton => 'Повторити';

  @override
  String get accountUsageVerifyAccountButton => 'Підтвердити в Google';

  @override
  String get accountSubmitAppealButton => 'Подати апеляцію';

  @override
  String get openGoogleCloudButton => 'Відкрити Google Cloud';

  @override
  String get accountUsageVerificationOpenFailedMessage =>
      'Не вдалося відкрити сторінку підтвердження в Google.';

  @override
  String get accountErrorActionOpenFailedMessage => 'Не вдалося відкрити сторінку Google.';

  @override
  String get accountUsageEmptyTitle => 'Дані щодо лімітів недоступні';

  @override
  String get accountUsageEmptyMessage =>
      'Провайдер не повернув дані щодо лімітів для цього акаунта.';

  @override
  String get accountUsageUnavailableTitle => 'Ліміти для цього акаунта недоступні';

  @override
  String get accountUsageUnavailableMessage =>
      'Сторінка лімітів працює лише для акаунтів Gemini CLI і Kiro.';

  @override
  String get accountUsageMissingTitle => 'Акаунт не знайдено';

  @override
  String get accountUsageMissingSubtitle => 'Інформація щодо лімітів';

  @override
  String get accountUsageMissingMessage =>
      'Можливо, акаунт уже видалено або список ще не встиг оновитися.';

  @override
  String accountUsageResetsAt(String time) {
    return 'Скинеться $time';
  }

  @override
  String get accountUsageResetUnknown => 'Час наступного скидання невідомий.';

  @override
  String accountUsageLastUpdated(String time) {
    return 'Дані оновлено: $time';
  }

  @override
  String accountUsageModelCount(int count) {
    return 'Моделей: $count';
  }

  @override
  String accountUsageAttentionCount(int count) {
    return 'Низький залишок: $count';
  }

  @override
  String accountUsageCriticalCount(int count) {
    return 'Майже закінчилось: $count';
  }

  @override
  String accountUsageHealthyCount(int count) {
    return 'У нормі: $count';
  }

  @override
  String accountUsageTokenType(String value) {
    return 'Тип ліміту: $value';
  }

  @override
  String accountUsageUsedPercent(String value) {
    return 'Використано $value%';
  }

  @override
  String accountUsageUsedOfLimit(String used, String limit) {
    return 'Використано $used з $limit';
  }

  @override
  String get accountUsageBucketHealthy => 'Достатньо';

  @override
  String get accountUsageBucketLow => 'Закінчується';

  @override
  String get accountUsageBucketCritical => 'Майже закінчилось';

  @override
  String get accountUsageKiroAllModelsLimit => 'Ліміт на всі моделі';

  @override
  String get settingsTitle => 'Налаштування';

  @override
  String get settingsSubtitle => 'Мережа, оформлення, API-ключ і робота проксі';

  @override
  String get languageLabel => 'Мова';

  @override
  String get languageHelperText => '«Системна» використовує мову пристрою';

  @override
  String get languageOptionSystem => 'Системна';

  @override
  String get languageOptionEnglish => 'English';

  @override
  String get languageOptionRussian => 'Русский';

  @override
  String get languageOptionUkrainian => 'Українська';

  @override
  String get themeLabel => 'Тема';

  @override
  String get themeModeSystem => 'Системна';

  @override
  String get themeModeSystemShort => 'Авто';

  @override
  String get themeModeLight => 'Світла';

  @override
  String get themeModeDark => 'Темна';

  @override
  String get fontLabel => 'Шрифт';

  @override
  String get fontOptionGoogleSans => 'Google Sans';

  @override
  String get fontOptionSystem => 'Системний';

  @override
  String get dynamicThemeTitle => 'Динамічна тема';

  @override
  String get dynamicThemeSubtitle => 'Використовувати динамічні кольори системи';

  @override
  String get settingsAppearanceSectionTitle => 'Оформлення та поведінка';

  @override
  String get settingsAppearanceSectionSummary => 'Мова, тема, логи та поведінка застосунку';

  @override
  String get settingsNetworkSectionTitle => 'Мережа';

  @override
  String get settingsNetworkSectionSummary => 'Хост, порт і доступ із локальної мережі';

  @override
  String get settingsReliabilitySectionTitle => 'Повтори та ліміти';

  @override
  String get settingsReliabilitySectionSummary => 'Автоповтори та реакція на обмеження API';

  @override
  String get settingsAccessSectionTitle => 'Доступ і запуск';

  @override
  String get settingsAccessSectionSummary => 'API-ключ і запуск застосунку';

  @override
  String get apiKeyRequiredTitle => 'Вимагати API-ключ';

  @override
  String get apiKeyRequiredSubtitle => 'Якщо вимкнути, запити прийматимуться без Bearer-токена';

  @override
  String get windowsTrayTitle => 'Згортати в трей';

  @override
  String get windowsTraySubtitle =>
      'При закритті вікна KiCk продовжить працювати в системному треї';

  @override
  String get windowsLaunchAtStartupTitle => 'Запускати при вході в систему';

  @override
  String get windowsLaunchAtStartupSubtitle =>
      'KiCk автоматично запускатиметься при вході в систему';

  @override
  String get windowsTrayNotificationTitle => 'KiCk продовжує працювати';

  @override
  String get windowsTrayNotificationBody => 'Застосунок згорнуто в системний трей';

  @override
  String get settingsModelsSectionTitle => 'Моделі';

  @override
  String get settingsModelsSectionSummary => 'Користувацькі ID моделей';

  @override
  String get settingsGoogleSectionTitle => 'Можливості провайдерів';

  @override
  String get settingsGoogleSectionSummary => 'Веб-пошук і параметри конкретних провайдерів';

  @override
  String get settingsBackupSectionTitle => 'Резервна копія та відновлення';

  @override
  String get settingsBackupSectionSummary => 'Перенос налаштувань і акаунтів між пристроями';

  @override
  String get settingsBackupInfoTitle =>
      'У резервну копію потраплять налаштування, API-ключ і OAuth-токени';

  @override
  String get settingsBackupInfoSubtitle =>
      'Зберігайте файл у безпечному місці. Після відновлення поточні налаштування та список акаунтів буде повністю замінено.';

  @override
  String get hostLabel => 'Хост';

  @override
  String get hostHelperText => 'Зазвичай localhost';

  @override
  String get hostRequiredError => 'Вкажіть адресу хоста';

  @override
  String get hostInvalidError => 'Адреса не повинна містити пробілів';

  @override
  String get hostLanDisabledError =>
      'Щоб використати 0.0.0.0, увімкніть доступ із локальної мережі';

  @override
  String get portLabel => 'Порт';

  @override
  String get portHelperText => 'За замовчуванням 3000';

  @override
  String get portInvalidError => 'Вкажіть порт від 1 до 65535';

  @override
  String get allowLanTitle => 'Доступ із локальної мережі та Docker';

  @override
  String get allowLanSubtitle =>
      'Проксі слухатиме 0.0.0.0 і стане доступним із локальної мережі та контейнерів';

  @override
  String get androidBackgroundRuntimeTitle => 'Робота у фоні на Android';

  @override
  String get androidBackgroundRuntimeSubtitle =>
      'Потрібно, щоб проксі не зупинявся при згортанні застосунку';

  @override
  String get requestRetriesLabel => 'Кількість повторів запитів до Google';

  @override
  String get requestRetriesHelperText =>
      'Скільки разів KiCk повторить запит після тимчасової помилки';

  @override
  String get requestRetriesInvalidError => 'Вкажіть число від 0 до 20';

  @override
  String get retry429DelayLabel => 'Інтервал повтору при 429';

  @override
  String get retry429DelayHelperText => 'Інтервал, з яким проксі повторює запит після помилки 429';

  @override
  String get retry429DelayInvalidError => 'Вкажіть число від 1 до 3600';

  @override
  String get mark429AsUnhealthyTitle => 'Виводити акаунт із ротації при помилці 429';

  @override
  String get mark429AsUnhealthySubtitle =>
      'Після помилки 429 KiCk позначить акаунт як тимчасово недоступний і переключиться на інший';

  @override
  String get loggingLabel => 'Логування';

  @override
  String get loggingQuiet => 'Мінімальне';

  @override
  String get loggingNormal => 'Стандартне';

  @override
  String get loggingVerbose => 'Докладне';

  @override
  String get logRetentionLabel => 'Ліміт записів логу';

  @override
  String get logRetentionHelperText =>
      'При досягненні ліміту найстаріші записи автоматично видаляються';

  @override
  String logRetentionInvalidError(int min, int max) {
    return 'Вкажіть число від $min до $max';
  }

  @override
  String get unsafeRawLoggingTitle => 'Сирі логи зневадження';

  @override
  String get unsafeRawLoggingSubtitle =>
      'Зберігає вміст запитів і відповідей. Вмикайте лише для зневадження.';

  @override
  String get defaultGoogleWebSearchTitle => 'Вмикати веб-пошук за замовчуванням';

  @override
  String get defaultGoogleWebSearchSubtitle =>
      'KiCk автоматично використовуватиме Google Пошук, якщо клієнт не задав свої параметри і в запиті немає викликів функцій';

  @override
  String get defaultGoogleVisibleReasoningTitle =>
      'Запитувати видимі міркування Gemini за замовчуванням';

  @override
  String get defaultGoogleVisibleReasoningSubtitle =>
      'Додає include_reasoning для запитів Gemini CLI, якщо клієнт сам не задав міркування. Допомагає клієнтам показувати блок міркувань.';

  @override
  String get renderGoogleGroundingInMessageTitle => 'Показувати цитати та джерела у відповіді';

  @override
  String get renderGoogleGroundingInMessageSubtitle =>
      'Якщо вимкнути, посилання на джерела залишаться в метаданих і не додаватимуться до тексту відповіді';

  @override
  String get settingsGeminiSubsectionTitle => 'Gemini CLI';

  @override
  String get settingsKiroSubsectionTitle => 'Kiro';

  @override
  String get defaultKiroServerToolsTitle => 'Вмикати серверні інструменти Kiro за замовчуванням';

  @override
  String get defaultKiroServerToolsSubtitle =>
      'Додає інструмент веб-пошуку Kiro до запитів, якщо клієнт не задав свої інструменти. Кожен виклик витрачає додаткові кредити Kiro.';

  @override
  String get customModelsLabel => 'Користувацькі ID моделей';

  @override
  String get customModelsHelperText => 'По одному ID на рядок, наприклад google/... або kiro/...';

  @override
  String get settingsSavingStatus => 'Зберігаємо зміни...';

  @override
  String get settingsSavedStatus => 'Зміни збережено';

  @override
  String get settingsValidationStatus => 'Перевірте поля з помилками';

  @override
  String get settingsSaveFailedStatus => 'Не вдалося зберегти зміни';

  @override
  String get settingsBackupExportButton => 'Зберегти резервну копію';

  @override
  String get settingsBackupImportButton => 'Відновити з резервної копії';

  @override
  String get settingsBackupExportOptionsDialogTitle => 'Експорт резервної копії';

  @override
  String get settingsBackupExportDialogTitle => 'Куди зберегти резервну копію?';

  @override
  String get settingsBackupImportDialogTitle => 'Виберіть файл резервної копії';

  @override
  String get settingsBackupExportConfirmButton => 'Продовжити';

  @override
  String get settingsBackupProtectWithPasswordLabel => 'Захистити файл паролем (рекомендовано)';

  @override
  String get settingsBackupProtectWithPasswordSubtitle =>
      'Шифрує резервну копію, щоб токени та ключі не можна було прочитати без пароля';

  @override
  String get settingsBackupPasswordLabel => 'Пароль';

  @override
  String get settingsBackupPasswordConfirmLabel => 'Підтвердьте пароль';

  @override
  String get settingsBackupPasswordHelperText =>
      'Запам\'ятайте цей пароль: без нього зашифровану копію не вдасться відновити.';

  @override
  String get settingsBackupPasswordsDoNotMatch => 'Паролі не збігаються';

  @override
  String get settingsBackupUnprotectedWarning =>
      'Ваші токени та ключі буде збережено у відкритому вигляді. Будь-хто, у кого опиниться цей файл, отримає доступ до ваших даних.';

  @override
  String get settingsBackupRestoreDialogTitle => 'Відновити конфігурацію?';

  @override
  String get settingsBackupRestoreDialogMessage =>
      'Поточні налаштування, API-ключ і список акаунтів буде замінено даними з цієї резервної копії. Цю дію неможливо скасувати.';

  @override
  String get settingsBackupRestoreConfirmButton => 'Відновити';

  @override
  String get settingsBackupPasswordDialogTitle => 'Введіть пароль резервної копії';

  @override
  String settingsBackupPasswordDialogMessage(String fileName) {
    return 'Файл $fileName захищений паролем. Введіть пароль, щоб продовжити відновлення.';
  }

  @override
  String settingsBackupPasswordDialogInvalidMessage(String fileName) {
    return 'Не вдалося розшифрувати файл $fileName. Перевірте пароль і спробуйте ще раз.';
  }

  @override
  String get settingsBackupPasswordConfirmButton => 'Розшифрувати';

  @override
  String settingsBackupExportedMessage(String fileName) {
    return 'Резервну копію збережено у файл $fileName';
  }

  @override
  String settingsBackupRestoredMessage(int accountCount) {
    return 'Конфігурацію відновлено. Акаунтів: $accountCount';
  }

  @override
  String settingsBackupRestoredMissingTokensMessage(int accountCount, int missingCount) {
    return 'Конфігурацію відновлено. Акаунтів: $accountCount, без токенів: $missingCount';
  }

  @override
  String settingsBackupExportFailedMessage(String error) {
    return 'Не вдалося зберегти резервну копію: $error';
  }

  @override
  String settingsBackupRestoreFailedMessage(String error) {
    return 'Не вдалося відновити з резервної копії: $error';
  }

  @override
  String get settingsBackupInvalidMessage =>
      'Файл резервної копії пошкоджений або має непідтримуваний формат';

  @override
  String get settingsBackupUnsupportedVersionMessage =>
      'Цю резервну копію створено в новішій версії KiCk і поки що не підтримується';

  @override
  String get settingsBackupReadFailedMessage => 'Не вдалося прочитати вибрану резервну копію';

  @override
  String get settingsBackupPasswordRequiredMessage => 'Для цієї резервної копії потрібен пароль';

  @override
  String get settingsLoadErrorTitle => 'Не вдалося завантажити налаштування';

  @override
  String get aboutTitle => 'Про програму';

  @override
  String get aboutMenuSubtitle => 'Версія, оновлення та аналітика';

  @override
  String get aboutDescription =>
      'Локальний OpenAI-сумісний проксі для Gemini CLI та Kiro у нативному застосунку Flutter';

  @override
  String get aboutUpdatesTitle => 'Оновлення';

  @override
  String get aboutUpdatesChecking => 'Перевіряємо оновлення на GitHub...';

  @override
  String get aboutUpdateAvailableTitle => 'Доступне оновлення';

  @override
  String aboutUpdateAvailableMessage(String latestVersion, String currentVersion) {
    return 'Доступна версія $latestVersion. Зараз у вас встановлено $currentVersion.';
  }

  @override
  String get aboutUpToDateTitle => 'Оновлень немає';

  @override
  String aboutUpToDateMessage(String currentVersion) {
    return 'У вас встановлено актуальну версію: $currentVersion.';
  }

  @override
  String get aboutUpdateCheckFailedTitle => 'Не вдалося перевірити оновлення';

  @override
  String get aboutUpdateCheckFailedMessage => 'Не вдалося отримати інформацію про релізи з GitHub.';

  @override
  String get aboutDownloadUpdateButton => 'Завантажити оновлення';

  @override
  String get aboutDownloadAndInstallButton => 'Завантажити та встановити';

  @override
  String get aboutInstallOnRestartButton => 'Встановити при перезапуску';

  @override
  String get aboutInstallUpdateButton => 'Встановити оновлення';

  @override
  String get aboutAllowUnknownSourcesButton => 'Дозволити це джерело';

  @override
  String get aboutPreparingUpdateButton => 'Готуємо оновлення...';

  @override
  String aboutUpdateDownloadingProgress(String progress) {
    return 'Завантажуємо оновлення у фоні: $progress';
  }

  @override
  String get aboutUpdateDownloadingIndeterminate => 'Завантажуємо оновлення у фоні...';

  @override
  String get aboutUpdateVerifyingMessage => 'Перевіряємо завантажений файл за SHA-256...';

  @override
  String get aboutUpdateReadyVerifiedMessage =>
      'Оновлення завантажено, перевірено й готове до встановлення.';

  @override
  String get aboutUpdateReadyUnverifiedMessage =>
      'Оновлення завантажено й готове до встановлення. Для цього релізу не було надано контрольну суму.';

  @override
  String get aboutUpdateUnknownSourcesMessage =>
      'Дозвольте встановлення з цього джерела в налаштуваннях Android, потім поверніться і знову натисніть «Встановити оновлення».';

  @override
  String aboutUpdateOperationFailedMessage(String error) {
    return 'Не вдалося підготувати оновлення: $error';
  }

  @override
  String get aboutOpenReleaseButton => 'Відкрити реліз';

  @override
  String get aboutRetryUpdateCheckButton => 'Перевірити ще раз';

  @override
  String get aboutAnalyticsTitle => 'Аналітика';

  @override
  String get aboutAnalyticsSubtitle =>
      'Анонімна статистика використання допомагає покращувати KiCk.';

  @override
  String get aboutLicenseTitle => 'Ліцензія';

  @override
  String get aboutLicenseMessage => 'KiCk поширюється як проєкт із відкритим вихідним кодом.';

  @override
  String get aboutOpenLicenseButton => 'Відкрити ліцензію';

  @override
  String get aboutPrivacyTitle => 'Приватність';

  @override
  String get aboutPrivacyMessage => 'KiCk зберігає акаунти, токени та налаштування локально.';

  @override
  String get aboutOpenPrivacyButton => 'Відкрити нотатку про приватність';

  @override
  String get aboutDisclaimerTitle => 'Відмова від відповідальності';

  @override
  String get aboutDisclaimerMessage => 'KiCk не пов\'язаний з Google, AWS, Kiro або SillyTavern.';

  @override
  String get aboutCreditsTitle => 'Подяки';

  @override
  String get aboutCreditsMessage =>
      'Зібрано на Flutter і Material Symbols. DiceBear Identicon CC0 1.0.';

  @override
  String get aboutOpenLinkFailedMessage => 'Не вдалося відкрити посилання';

  @override
  String get copyProxyEndpointTooltip => 'Скопіювати адресу проксі';

  @override
  String get proxyEndpointCopiedMessage => 'Адресу проксі скопійовано';

  @override
  String get copyApiKeyTooltip => 'Скопіювати API-ключ';

  @override
  String get apiKeyCopiedMessage => 'API-ключ скопійовано';

  @override
  String get pushSillyTavernButton => 'У SillyTavern';

  @override
  String get pushSillyTavernDialogTitle => 'Надіслати в запущений SillyTavern';

  @override
  String get pushSillyTavernDialogMessage =>
      'KiCk додасть профіль і вибере його в менеджері з\'єднань.';

  @override
  String get pushSillyTavernUrlLabel => 'URL SillyTavern';

  @override
  String get pushSillyTavernProfileNameLabel => 'Ім\'я профілю';

  @override
  String get pushSillyTavernModelLabel => 'Модель';

  @override
  String get pushSillyTavernConfirmButton => 'Додати профіль';

  @override
  String pushSillyTavernSuccessMessage(String profileName) {
    return 'Профіль \"$profileName\" додано в SillyTavern.';
  }

  @override
  String pushSillyTavernFailedMessage(String error) {
    return 'Не вдалося надіслати профіль у SillyTavern: $error';
  }

  @override
  String get pushSillyTavernErrorInvalidUrl =>
      'Вкажіть повний URL SillyTavern, наприклад http://127.0.0.1:8000.';

  @override
  String get pushSillyTavernErrorMissingCsrf => 'SillyTavern не повернув CSRF-токен.';

  @override
  String pushSillyTavernErrorHttp(int statusCode, String path) {
    return 'SillyTavern повернув HTTP $statusCode для $path.';
  }

  @override
  String get pushSillyTavernErrorInvalidJson => 'SillyTavern повернув некоректну JSON-відповідь.';

  @override
  String get homeOnboardingTitle => 'З чого почати';

  @override
  String get homeOnboardingSubtitle => 'Коротка підказка для першого запуску';

  @override
  String get homeOnboardingAccountsTitle => 'Підключіть акаунт';

  @override
  String get homeOnboardingAccountsMessage =>
      'KiCk не зможе обробляти запити без активного акаунта Gemini CLI або Kiro.';

  @override
  String get homeOnboardingEndpointTitle => 'Перевірте адресу проксі';

  @override
  String homeOnboardingEndpointMessage(String endpoint) {
    return 'Коли все буде готово, використовуйте адресу $endpoint у своєму клієнті.';
  }

  @override
  String get homeOnboardingStartTitle => 'Запустіть проксі';

  @override
  String get homeOnboardingStartMessage =>
      'Після запуску KiCk почне приймати запити на цьому пристрої.';

  @override
  String get homeOnboardingFooter =>
      'Якщо акаунт уже підключено, просто увімкніть його на екрані акаунтів і поверніться сюди.';

  @override
  String get apiKeyRegeneratedMessage => 'Новий API-ключ збережено';

  @override
  String get regenerateApiKeyAction => 'Створити новий API-ключ';

  @override
  String get regenerateApiKeyDialogTitle => 'Створити новий API-ключ?';

  @override
  String get regenerateApiKeyDialogMessage =>
      'Старий ключ буде одразу відкликано. Усім підключеним клієнтам знадобиться новий ключ, щоб продовжити роботу.';

  @override
  String get regenerateApiKeyConfirmButton => 'Згенерувати';

  @override
  String get trayOpenWindowAction => 'Відкрити вікно';

  @override
  String get trayHideToTrayAction => 'Згорнути в трей';

  @override
  String get trayExitAction => 'Вийти';

  @override
  String get noActiveAccountsWarning =>
      'Немає активних акаунтів. Проксі запуститься, але не зможе обробляти запити, поки ви не додасте чи не увімкнете хоча б один акаунт.';

  @override
  String get pinWindowTooltip => 'Закріпити вікно поверх інших';

  @override
  String get unpinWindowTooltip => 'Зняти закріплення вікна';

  @override
  String get welcomeTitle => 'Ласкаво просимо в KiCk';

  @override
  String get welcomeSubtitle =>
      'KiCk допомагає запустити локальний проксі для Gemini CLI та Kiro без терміналу й зайвих налаштувань.';

  @override
  String get welcomeStepAccountsTitle => 'Підключіть акаунт';

  @override
  String get welcomeStepAccountsMessage =>
      'Зробіть це на екрані акаунтів. Можна підключити Gemini CLI або Kiro.';

  @override
  String get welcomeStepHomeTitle => 'Відкрийте головну';

  @override
  String get welcomeStepHomeMessage =>
      'На головній завжди видно адресу проксі, API-ключ і кнопку запуску.';

  @override
  String get welcomeUsageTitle => 'Важливо знати';

  @override
  String get welcomeUsageMessage =>
      'KiCk створено для особистого, навчального та дослідницького використання.';

  @override
  String get welcomeAnalyticsTitle => 'Анонімна аналітика';

  @override
  String get welcomeAnalyticsSubtitle =>
      'Допомагає зрозуміти, де KiCk працює добре, а де його можна покращити.';

  @override
  String get welcomeRepositoryLinkLabel => 'Детальніше про проєкт';

  @override
  String get logsTitle => 'Логи';

  @override
  String get logsSubtitle => 'Історія запитів і помилок';

  @override
  String get logsSearchHint => 'Пошук за маршрутом або повідомленням';

  @override
  String get logsRefreshButton => 'Оновити';

  @override
  String get logsClearButton => 'Очистити';

  @override
  String get logsClearDialogTitle => 'Очистити логи?';

  @override
  String get logsClearDialogMessage =>
      'Усі записи буде видалено з KiCk. Цю дію неможливо скасувати.';

  @override
  String get logsClearConfirmButton => 'Очистити';

  @override
  String get logsLevelAll => 'Усі рівні';

  @override
  String get logsLevelInfo => 'Інфо';

  @override
  String get logsLevelWarning => 'Попередження';

  @override
  String get logsLevelError => 'Помилки';

  @override
  String get logsCategoryAll => 'Усі категорії';

  @override
  String get logsCategoryFilterTitle => 'Категорії';

  @override
  String get logsPayloadShowButton => 'Показати payload';

  @override
  String get logsPayloadHideButton => 'Сховати payload';

  @override
  String get logsCopyEntryButton => 'Копіювати';

  @override
  String get logsCopiedMessage => 'Запис логу скопійовано';

  @override
  String get logsFilteredEmptyTitle => 'За поточними фільтрами нічого не знайдено';

  @override
  String get logsFilteredEmptyMessage => 'Спробуйте прибрати частину фільтрів або змінити пошук.';

  @override
  String get logsEntryLevelInfo => 'Інфо';

  @override
  String get logsEntryLevelWarning => 'Попередження';

  @override
  String get logsEntryLevelError => 'Помилка';

  @override
  String logsTotalCount(int count) {
    return 'Усього: $count';
  }

  @override
  String logsFilteredCount(int count) {
    return 'Після фільтра: $count';
  }

  @override
  String logsRequestGroupTitle(String requestLabel) {
    return 'Запит $requestLabel';
  }

  @override
  String logsRequestStatusCount(int count) {
    return 'Статусів: $count';
  }

  @override
  String logsRequestRetryCount(int count) {
    return 'Повторів: $count';
  }

  @override
  String logsRequestKiroCredits(String credits) {
    return 'Кредитів: $credits';
  }

  @override
  String get logsRequestDetailsShowButton => 'Показати статуси';

  @override
  String get logsRequestDetailsHideButton => 'Сховати статуси';

  @override
  String logsLoadedCount(int count) {
    return 'Завантажено: $count';
  }

  @override
  String get logsEmptyTitle => 'Логи порожні';

  @override
  String get logsLoadErrorTitle => 'Не вдалося завантажити логи';

  @override
  String get logsExportTooltip => 'Зберегти всі логи за поточними фільтрами';

  @override
  String get logsExportDialogTitle => 'Куди зберегти логи?';

  @override
  String get logsShareTooltip => 'Поділитися всіма логами за поточними фільтрами';

  @override
  String get logsLoadMoreButton => 'Завантажити ще';

  @override
  String get logsNothingToExportMessage => 'Немає логів для збереження.';

  @override
  String logsExportedMessage(String fileName) {
    return 'Логи збережено у файл $fileName';
  }

  @override
  String logsExportFailedMessage(String error) {
    return 'Не вдалося зберегти логи: $error';
  }

  @override
  String logsShareFailedMessage(String error) {
    return 'Не вдалося поділитися логами: $error';
  }

  @override
  String get logsExportFileTitle => 'Експорт логів KiCk';

  @override
  String get logsExportShareSubject => 'Логи KiCk';

  @override
  String get logsExportGeneratedAtLabel => 'Згенеровано';

  @override
  String logsExportEntriesCount(int count) {
    return 'Записів: $count';
  }

  @override
  String get logsExportSectionEnvironment => 'Середовище';

  @override
  String get logsExportAppLabel => 'Застосунок';

  @override
  String get logsExportFiltersLabel => 'Фільтри';

  @override
  String get logsExportScopeLabel => 'Область';

  @override
  String get logsExportRuntimeSettingsLabel => 'Налаштування під час роботи';

  @override
  String get logsExportNoneValue => 'немає';

  @override
  String get logsExportNoneDetectedValue => 'не виявлено';

  @override
  String get logsExportSectionDiagnostics => 'Зведення діагностики';

  @override
  String get logsExportTimeRangeLabel => 'Часовий діапазон';

  @override
  String get logsExportLevelsLabel => 'Рівні';

  @override
  String get logsExportCategoriesLabel => 'Категорії';

  @override
  String get logsExportRoutesLabel => 'Маршрути';

  @override
  String get logsExportModelsLabel => 'Моделі';

  @override
  String get logsExportStatusCodesLabel => 'Коди статусу';

  @override
  String get logsExportErrorDetailsLabel => 'Подробиці помилок';

  @override
  String get logsExportUpstreamReasonsLabel => 'Причини від провайдера';

  @override
  String get logsExportRetriedRequestsLabel => 'Повторів запитів';

  @override
  String get logsExportTokensLabel => 'Токени';

  @override
  String get logsExportKiroCreditsLabel => 'Кредити Kiro';

  @override
  String get logsExportAndroidBackgroundSessionsLabel => 'Фонові сесії Android';

  @override
  String get logsExportTimestampLabel => 'Час';

  @override
  String get logsExportLevelLabel => 'Рівень';

  @override
  String get logsExportCategoryLabel => 'Категорія';

  @override
  String get logsExportRouteLabel => 'Маршрут';

  @override
  String get logsExportMessageLabel => 'Повідомлення';

  @override
  String get logsExportMaskedPayloadLabel => 'Payload (замаскований)';

  @override
  String get logsExportRawPayloadLabel => 'Payload (без маскування)';

  @override
  String get logMessageRequestReceived => 'Запит отримано';

  @override
  String get logMessageParsedRequest => 'Запит розібрано';

  @override
  String get logMessageResponseCompleted => 'Відповідь завершено';

  @override
  String get logMessageStreamClientAborted => 'Потокову відповідь перервано клієнтом';

  @override
  String get logMessageRetryScheduled => 'Заплановано повтор після збою запиту';

  @override
  String get logMessageRetryWithAnotherAccount => 'Повторюємо запит з іншим акаунтом після збою';

  @override
  String get logMessageRequestSucceededAfterRetries => 'Запит виконано після повторних спроб';

  @override
  String get logMessageRequestFailedAfterRetries => 'Запит не вдався після повторних спроб';

  @override
  String get logMessageDispatchingStreamingRequest => 'Надсилаємо потоковий запит провайдеру';

  @override
  String get logMessageDispatchingRequest => 'Надсилаємо запит провайдеру';

  @override
  String get logMessageUpstreamPayloadReturned => 'Провайдер повернув відповідь';

  @override
  String get logMessageMappedChatCompletion =>
      'Відповідь провайдера перетворено у формат OpenAI Chat Completion';

  @override
  String logMessageUsingAccountForModel(String account, String model) {
    return 'Використовуємо акаунт $account для $model';
  }

  @override
  String get logMessageProxySessionSummary => 'Зведення по сесії проксі';

  @override
  String get logMessageAndroidBackgroundSessionStarted => 'Фонова сесія Android розпочалась';

  @override
  String get logMessageAndroidBackgroundSessionEnded => 'Фонова сесія Android завершилась';

  @override
  String get logMessageAndroidBackgroundSessionRecovered =>
      'Фонову сесію Android відновлено після перезапуску процесу';

  @override
  String get accountDialogTitle => 'Акаунт';

  @override
  String get accountDialogBasicsTitle => 'Основне';

  @override
  String get accountDialogBasicsSubtitle => 'Поля для підключення вибраного типу акаунта';

  @override
  String get accountDialogAdvancedTitle => 'Розширені налаштування';

  @override
  String get accountDialogAdvancedSubtitle => 'Пріоритет та обмеження по моделях';

  @override
  String get accountDialogAdvancedHint =>
      'Якщо не хочете налаштовувати вручну, цей блок можна залишити як є.';

  @override
  String get projectIdLabel => 'ID проєкту';

  @override
  String get projectIdHint => 'my-google-cloud-project';

  @override
  String get projectIdOptionalHelperText =>
      'Необов\'язково. Якщо залишити порожнім, KiCk спробує визначити його автоматично.';

  @override
  String get projectIdConsoleLinkLabel => 'Де подивитися ID проєкту';

  @override
  String get projectIdRequiredError => 'Вкажіть ID проєкту';

  @override
  String get projectIdLookupFailedMessage => 'Не вдалося відкрити Google Cloud Console.';

  @override
  String get accountNameLabel => 'Назва акаунта';

  @override
  String get accountNameHint => 'Наприклад, основний акаунт';

  @override
  String get accountNameHelperText => 'Якщо залишити поле порожнім, KiCk підставить ім\'я акаунта.';

  @override
  String get priorityLabel => 'Пріоритет';

  @override
  String get priorityHelperText =>
      'Спочатку використовуються основні акаунти. Акаунти з однаковим пріоритетом чергуються.';

  @override
  String get priorityLevelPrimary => 'Основний';

  @override
  String get priorityLevelNormal => 'Звичайний';

  @override
  String get priorityLevelReserve => 'Резервний';

  @override
  String get blockedModelsLabel => 'Недоступні моделі';

  @override
  String get blockedModelsHelperText => 'По одному ID на рядок, наприклад google/... або kiro/...';

  @override
  String get kiroLinkAuthDialogTitle => 'Авторизація Kiro';

  @override
  String get kiroLinkAuthDialogMessage =>
      'Відкрийте посилання та увійдіть у Kiro через GitHub або Google. KiCk сам дочекається відповіді з браузера.';

  @override
  String get kiroLinkAuthUserCodeLabel => 'Код для звірки';

  @override
  String get kiroLinkAuthVerificationUrlLabel => 'Посилання для входу';

  @override
  String get kiroLinkAuthWaitingMessage => 'Чекаємо підтвердження входу в браузері...';

  @override
  String get kiroLinkAuthOpenLinkButton => 'Відкрити посилання';

  @override
  String get kiroLinkAuthOpenLinkAgainButton => 'Відкрити знову';

  @override
  String get kiroLinkAuthOpenLinkFailedMessage => 'Не вдалося відкрити посилання для входу в Kiro.';

  @override
  String get cancelButton => 'Скасувати';

  @override
  String get continueButton => 'Продовжити';

  @override
  String get navHome => 'Головна';

  @override
  String get navAccounts => 'Акаунти';

  @override
  String get navSettings => 'Налаштування';

  @override
  String get navLogs => 'Логи';

  @override
  String get runtimeChannelName => 'Проксі KiCk у фоні';

  @override
  String get runtimeChannelDescription => 'Підтримує роботу проксі у фоновому режимі';

  @override
  String get runtimeNotificationTitle => 'Проксі KiCk запущено';

  @override
  String get runtimeNotificationReturn => 'Натисніть, щоб повернутися в застосунок';

  @override
  String get runtimeNotificationManage => 'Натисніть, щоб відкрити акаунти та налаштування';

  @override
  String get runtimeNotificationActive => 'Проксі активне';

  @override
  String get oauthPageTitleError => 'Помилка авторизації';

  @override
  String get oauthPageTitleSuccess => 'Успішна авторизація';

  @override
  String get oauthPageStateMismatchMessage => 'Стани не збігаються. Можна закрити цю вкладку.';

  @override
  String get oauthPageGoogleErrorMessage => 'Google повернув помилку. Можна закрити цю вкладку.';

  @override
  String get oauthPageCodeMissingMessage => 'Код не отримано. Можна закрити цю вкладку.';

  @override
  String get oauthPageCloseTabMessage => 'Вкладку можна закрити.';

  @override
  String get accountDisplayNameFallbackGoogle => 'Google-акаунт';

  @override
  String get errorNetworkUnavailable =>
      'Не вдалося зв\'язатися із серверами Google. Перевірте інтернет і спробуйте ще раз.';

  @override
  String get errorGoogleServiceUnavailable => 'Google тимчасово недоступний. Спробуйте пізніше.';

  @override
  String get errorInvalidServiceResponse =>
      'Сервер повернув несподівану відповідь. Спробуйте ще раз.';

  @override
  String get errorGoogleAuthFailed => 'Не вдалося увійти в Google. Спробуйте ще раз.';

  @override
  String get errorGoogleAuthTimedOut =>
      'Вхід у Google не завершився вчасно. Поверніться в застосунок і спробуйте ще раз. Якщо це повторюється на Android, вимкніть для KiCk обмеження батареї.';

  @override
  String get errorGoogleAuthBrowserOpenFailed =>
      'Не вдалося відкрити браузер для входу в Google. Спробуйте ще раз.';

  @override
  String get errorUnknown => 'Щось пішло не так. Спробуйте ще раз.';

  @override
  String get errorOauthTokensMissing =>
      'Токени авторизації для цього акаунта не знайдено. Перепідключіть акаунт.';

  @override
  String get errorAccountNotFound => 'Акаунт не знайдено. Можливо, його вже видалено.';

  @override
  String get errorPortAlreadyInUse =>
      'Цей порт уже зайнятий іншим застосунком. Виберіть інший порт у налаштуваннях.';

  @override
  String get errorPermissionDenied =>
      'Не вистачає системних дозволів для запуску. Перевірте налаштування застосунку та спробуйте ще раз.';

  @override
  String errorGoogleRateLimitedRetry(String retryHint) {
    return 'Google тимчасово обмежив запити для цього акаунта. Спробуйте знову через $retryHint.';
  }

  @override
  String get errorGoogleRateLimitedLater =>
      'Google тимчасово обмежив запити для цього акаунта. Спробуйте пізніше.';

  @override
  String get errorKiroAuthExpired => 'Сесія Kiro минула. Увійдіть знову та спробуйте ще раз.';

  @override
  String get errorKiroAuthStartFailed => 'Не вдалося розпочати вхід у Kiro. Спробуйте пізніше.';

  @override
  String get errorKiroAuthCancelled => 'Вхід у Kiro було скасовано.';

  @override
  String get errorKiroAuthTimedOut => 'Час очікування входу в Kiro минув. Спробуйте ще раз.';

  @override
  String get errorKiroAuthRejected => 'Kiro відхилив вхід. Спробуйте розпочати знову.';

  @override
  String errorKiroRateLimitedRetry(String retryHint) {
    return 'Kiro тимчасово обмежив запити. Спробуйте знову через $retryHint.';
  }

  @override
  String get errorKiroRateLimitedLater => 'Kiro тимчасово обмежив запити. Спробуйте пізніше.';

  @override
  String get errorKiroServiceUnavailable => 'Kiro тимчасово недоступний. Спробуйте пізніше.';

  @override
  String get errorGoogleAccountVerificationRequired =>
      'Google просить підтвердити цей акаунт. Відкрийте сторінку підтвердження та увійдіть під тим самим Google-акаунтом.';

  @override
  String get errorGoogleProjectIdMissing =>
      'Google не зміг визначити коректний ID проєкту для цього акаунта або запиту. Перевірте ID проєкту в налаштуваннях акаунта і за потреби перепідключіть його.';

  @override
  String get errorGoogleProjectApiDisabled =>
      'Gemini for Google Cloud API вимкнено для цього проєкту. Відкрийте Google Cloud, увімкніть API для потрібного ID проєкту та повторіть перевірку.';

  @override
  String get errorGoogleProjectInvalid =>
      'Google відхилив цей ID проєкту. Переконайтеся, що вказано існуючий проєкт і в акаунта є до нього доступ.';

  @override
  String get errorGoogleProjectAccessDenied =>
      'Google відхилив запит для цього проєкту або акаунта. Перевірте ID проєкту, обраний акаунт і переконайтеся, що Gemini Code Assist увімкнено саме для цього проєкту.';

  @override
  String get errorAuthExpired =>
      'Термін дії авторизації минув або вона більше не дійсна. Перепідключіть акаунт і спробуйте ще раз.';

  @override
  String get errorGoogleCapacity =>
      'Сервери Google тимчасово перевантажені. Спробуйте трохи пізніше.';

  @override
  String get errorUnsupportedModel => 'Вибрана модель зараз недоступна для цього акаунта.';

  @override
  String get errorInvalidJson => 'Запит містить некоректний JSON.';

  @override
  String get errorUnexpectedResponse => 'Сервіс повернув несподівану відповідь. Спробуйте ще раз.';

  @override
  String get errorQuotaExhausted =>
      'Ліміт цього акаунта вичерпано. Дочекайтеся скидання або використайте інший акаунт.';

  @override
  String errorQuotaExhaustedRetry(String retryHint) {
    return 'Ліміт цього акаунта вичерпано. Спробуйте знову через $retryHint або використайте інший акаунт.';
  }

  @override
  String get errorQuotaExhaustedNoResetHint =>
      'Google повернув RESOURCE_EXHAUSTED без часу скидання. KiCk окремо перевірить цей акаунт. Якщо помилка повториться, використайте інший акаунт.';

  @override
  String get errorGoogleTermsOfServiceViolation =>
      'Google вимкнув цей акаунт за порушення умов використання. Подайте апеляцію або використайте інший акаунт.';

  @override
  String get errorInvalidRequestRejected =>
      'У запиту неправильний формат, тому його було відхилено.';

  @override
  String get errorReasoningConfigRejected =>
      'Google відхилив параметри reasoning/thinking для цієї моделі. Увімкніть автоматичний режим міркувань (reasoning).';

  @override
  String get durationFewSeconds => 'кілька секунд';

  @override
  String durationSeconds(int seconds) {
    return '$seconds с';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes хв';
  }

  @override
  String durationMinutesSeconds(int minutes, int seconds) {
    return '$minutes хв $seconds с';
  }

  @override
  String durationHours(int hours) {
    return '$hours год';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours год $minutes хв';
  }
}
