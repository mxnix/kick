<div align="center">

<img src="static/logo.png" alt="Логотип KiCk" style="width: 128px; height: 128px; margin-bottom: 3px;">

# KiCk

<p align="center">
  <a href="https://github.com/mxnix/kick/releases/latest">
    <img src="https://img.shields.io/github/v/release/mxnix/kick?style=flat-square&color=blue" alt="Последний выпуск">
  </a>
  <a href="https://github.com/mxnix/kick/actions">
    <img src="https://img.shields.io/github/actions/workflow/status/mxnix/kick/ci.yml?style=flat-square" alt="Состояние сборки">
  </a>
  <a href="https://flutter.dev/">
    <img src="https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Сделано на Flutter">
  </a>
  <a href="https://github.com/mxnix/kick/blob/main/LICENSE.md">
    <img src="https://img.shields.io/github/license/mxnix/kick?style=flat-square" alt="Лицензия">
  </a>
</p>

**Локальный OpenAI-совместимый прокси для Gemini CLI в нативном Flutter-приложении**

**Поддерживаемые платформы**

<a href="https://github.com/mxnix/kick/releases/latest">
  <img src="static/windows.png" alt="Скачать для Windows" style="width: 128px; height: 128px; margin-bottom: 6px; margin-right: 24px;">
</a>
<a href="https://github.com/mxnix/kick/releases/latest">
  <img src="static/android.png" alt="Скачать для Android" style="width: auto; height: 128px; margin-bottom: 6px;">
</a>

</div>

<details>
<summary><strong>Что это</strong></summary>

KiCk поднимает у вас на устройстве локальный адрес в формате OpenAI и пересылает запросы в Gemini через подключенные Google-аккаунты. Приложение нужно для тех, кто хочет работать с Gemini CLI без терминала, ручной настройки входа и отдельного локального сервера.

</details>

<details>
<summary><strong>Что умеет</strong></summary>

- Запускает локальный адрес `http://127.0.0.1:3000/v1` по умолчанию.
- Принимает запросы в формате OpenAI.
- Работает с несколькими Google-аккаунтами, умеет выставлять приоритеты и временно убирать проблемный аккаунт из очереди.
- Подключает аккаунты через вход в браузере.
- Позволяет менять адрес, порт, ключ доступа, число повторов и список моделей.
- Показывает состояние прокси, аккаунтов и журнал работы.
- Работает в фоне на Android.
- Может запускаться вместе с Windows.

</details>

<details>
<summary><strong>Как начать</strong></summary>

1. Скачайте последнюю версию из [раздела выпусков](https://github.com/mxnix/kick/releases/latest).
2. Откройте экран аккаунтов и подключите Google-аккаунт.
3. Укажите идентификатор проекта в `Google Cloud` для этого аккаунта.
4. Вернитесь на главный экран и запустите прокси.
5. Скопируйте локальный адрес и ключ доступа (если требуется)
6. Подставьте их в свою программу или в Gemini CLI.

По умолчанию используется адрес `http://127.0.0.1:3000/v1`. Его можно поменять в настройках.

</details>

<details>
<summary><strong>Какие адреса поддерживаются</strong></summary>

- `GET /health`
- `GET /v1/models`
- `POST /v1/chat/completions`
- `POST /v1/responses`

</details>

<details>
<summary><strong>Пример запроса</strong></summary>

```bash
curl http://127.0.0.1:3000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ВАШ_КЛЮЧ" \
  -d '{
    "model": "gemini-2.5-pro",
    "messages": [
      {"role": "user", "content": "Напиши короткое приветствие"}
    ]
  }'
```

Если вы отключили проверку ключа доступа, строку с `Authorization` можно убрать.

</details>

<details>
<summary><strong>Что можно настроить</strong></summary>

- Сетевые параметры: адрес, порт, доступ из локальной сети.
- Доступ: требование ключа, просмотр и перевыпуск ключа.
- Надежность: число повторов, задержка после ошибки `429`, временный вывод аккаунта из очереди.
- Модели: список дополнительных моделей и список недоступных моделей для конкретного аккаунта.
- Google: веб-поиск по умолчанию и показ источников в ответе.
- Приложение: тема, подробность журнала, работа в фоне на Android, запуск вместе с Windows.

</details>

<details>
<summary><strong>Где хранятся данные</strong></summary>

- Токены входа и локальный ключ доступа хранятся в защищенном хранилище устройства.
- Настройки, список аккаунтов и журнал работы хранятся локально.
- Запись полных сырых данных по умолчанию отключена.
- При сохранении и выгрузке журнала чувствительные данные маскируются.
- Анонимная аналитика отключена по умолчанию.

Подробности: [Политика конфиденциальности](PRIVACY.md).

</details>

<details>
<summary><strong>Если что-то не работает</strong></summary>

- Порт занят: выберите другой порт в настройках.
- Нет активных аккаунтов: подключите аккаунт или включите уже добавленный.
- Истек вход в Google: переподключите аккаунт.
- Google просит подтвердить аккаунт: откройте страницу подтверждения и войдите тем же аккаунтом.
- Неверно указан идентификатор проекта в `Google Cloud` или отключен нужный доступ: проверьте проект и его настройки.
- Ошибка `429`: подождите сброса ограничения или включите временный вывод проблемного аккаунта из очереди.

</details>

<details>
<summary><strong>Сборка из исходников</strong></summary>

1. Установите Flutter и нужные инструменты для Android.
2. Выполните:

```powershell
flutter pub get
flutter test
```

3. Для запуска во время разработки используйте:

```powershell
flutter run -d windows
```

или

```powershell
flutter run -d android
```

4. Для локальной сборки установщика Windows нужен Inno Setup 6:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-windows-installer.ps1
```

Подробности по сборке и выпуску: [CONTRIBUTING.md](CONTRIBUTING.md).

</details>

[Лицензия](LICENSE.md) | [Политика конфиденциальности](PRIVACY.md) | [Как вносить изменения](CONTRIBUTING.md)
