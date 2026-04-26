<div align="center">

<img src="static/github/logo/logo.png" alt="Логотип KiCk" width="128" height="128">

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
  <a href="https://aur.archlinux.org/packages/kick-bin">
    <img src="https://img.shields.io/aur/version/kick-bin?style=flat-square&color=1793D1&logo=arch-linux&logoColor=white" alt="AUR Package">
  </a>
</p>

**Локальный OpenAI-совместимый прокси для Gemini CLI и Kiro в нативном Flutter-приложении**

**Поддерживаемые платформы**

<p align="center">
  <a href="https://github.com/mxnix/kick/releases/latest">
    <img src="static/github/logo/windows.png" alt="Скачать для Windows" width="112" height="112">
  </a>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <a href="https://github.com/mxnix/kick/releases/latest">
    <img src="static/github/logo/linux.png" alt="Скачать для Linux" width="112" height="112">
  </a>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <a href="https://github.com/mxnix/kick/releases/latest">
    <img src="static/github/logo/android.png" alt="Скачать для Android" width="112" height="112">
  </a>
</p>

</div>

<details>
<summary><strong>Интерфейс</strong></summary>

<p align="center">
  <img src="static/github/screenshots/desktop_ru.png" alt="KiCk на Windows: экран управления аккаунтами" width="100%">
</p>

<p align="center">
  <img src="static/github/screenshots/mobile_ru.png" alt="KiCk на Android: быстрый запуск локального прокси" width="100%">
</p>

</details>

<details>
<summary><strong>Что это</strong></summary>

KiCk поднимает у вас на устройстве локальный адрес в формате OpenAI и пересылает запросы в Gemini CLI через подключенные Google-аккаунты, а в Kiro через сессию AWS Builder ID. Приложение нужно для тех, кто хочет работать с Gemini CLI или Kiro без терминала, ручной настройки входа и отдельного локального сервера.

</details>

<details>
<summary><strong>Что умеет</strong></summary>

- Запускает локальный адрес `http://127.0.0.1:3000/v1` по умолчанию.
- Принимает запросы в формате OpenAI.
- Работает с несколькими аккаунтами Gemini CLI и Kiro, умеет выставлять приоритеты и временно убирать проблемный аккаунт из очереди.
- Подключает Gemini CLI через вход Google в браузере, а Kiro через AWS Builder ID.
- Позволяет менять адрес, порт, ключ доступа, число повторов и список моделей.
- Показывает состояние прокси, аккаунтов и журнал работы.
- Работает в фоне на Android.
- Может запускаться при входе и сворачиваться в трей.

</details>

<details>
<summary><strong>Как начать</strong></summary>

1. Скачайте последнюю версию из [раздела выпусков](https://github.com/mxnix/kick/releases/latest) или подключите Linux-репозиторий ниже.
2. Откройте экран аккаунтов и подключите аккаунт Gemini CLI или Kiro.
3. Если выбрали Gemini CLI, укажите идентификатор проекта в `Google Cloud`. Для Kiro достаточно завершить авторизацию через AWS Builder ID.
4. Вернитесь на главный экран и запустите прокси.
5. Скопируйте локальный адрес и ключ доступа (если требуется)
6. Подставьте их в свою программу, Gemini CLI или другой OpenAI-совместимый клиент.

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
- Приложение: тема, подробность журнала, работа в фоне на Android, автозапуск на desktop.

</details>

<details>
<summary><strong>Установка на Linux</strong></summary>

Debian, Ubuntu и Linux Mint:

```bash
curl -fsSL https://mxnix.github.io/kick/linux/kick.asc | sudo gpg --dearmor -o /usr/share/keyrings/kick.gpg
echo "deb [signed-by=/usr/share/keyrings/kick.gpg] https://mxnix.github.io/kick/linux/apt stable main" | sudo tee /etc/apt/sources.list.d/kick.list
sudo apt update
sudo apt install kick
```

Fedora/RHEL/openSUSE-подобные системы:

```bash
sudo rpm --import https://mxnix.github.io/kick/linux/kick.asc
sudo tee /etc/yum.repos.d/kick.repo >/dev/null <<'EOF'
[kick]
name=KiCk
baseurl=https://mxnix.github.io/kick/linux/rpm/x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=1
gpgkey=https://mxnix.github.io/kick/linux/kick.asc
EOF
sudo dnf install kick
```

Arch Linux-подобные системы:

```bash
curl -fsSL https://mxnix.github.io/kick/linux/kick.asc | sudo pacman-key --add -
sudo pacman-key --lsign-key "$(curl -fsSL https://mxnix.github.io/kick/linux/kick.asc | gpg --show-keys --with-colons | awk -F: '/^pub:/ { print $5; exit }')"
sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'
[kick]
Server = https://mxnix.github.io/kick/linux/pacman/x86_64
SigLevel = DatabaseRequired PackageOptional
EOF
sudo pacman -Sy kick
```

Или установите из [AUR](https://aur.archlinux.org/packages/kick-bin) с помощью yay или paru:

```bash
yay -S kick-bin
```

```bash
paru -S kick-bin
```

Также можно скачать AppImage, `.deb`, `.rpm`, `.pkg.tar.zst` или `.tar.gz` из раздела выпусков. В GNOME для трея может понадобиться расширение AppIndicator.

</details>

<details>
<summary><strong>Где хранятся данные</strong></summary>

- Токены входа и локальный ключ доступа хранятся в защищенном хранилище устройства.
- Настройки, список аккаунтов и журнал работы хранятся локально.
- Запись полных сырых данных по умолчанию отключена.
- При сохранении и выгрузке журнала чувствительные данные маскируются.
- Анонимная аналитика отключена по умолчанию.

Подробности: [Политика конфиденциальности](docs/PRIVACY.md).

</details>

<details>
<summary><strong>Если что-то не работает</strong></summary>

- Порт занят: выберите другой порт в настройках.
- Нет активных аккаунтов: подключите аккаунт Gemini CLI или Kiro либо включите уже добавленный.
- Истек вход в Google: переподключите аккаунт Gemini CLI.
- Истекла сессия Kiro: переподключите аккаунт Kiro.
- Google просит подтвердить аккаунт: откройте страницу подтверждения и войдите тем же аккаунтом.
- Неверно указан идентификатор проекта в `Google Cloud` или отключен нужный доступ: проверьте проект и его настройки.
- Ошибка `429`: подождите сброса ограничения или включите временный вывод проблемного аккаунта из очереди.

</details>

<details>
<summary><strong>Сборка из исходников</strong></summary>

1. Установите Flutter и нужные инструменты для нужной платформы: Android, Windows или Linux.
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

```bash
flutter run -d linux
```

или

```powershell
flutter run -d android
```

4. Для локальной сборки установщика Windows нужен Inno Setup 6:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-windows-installer.ps1
```

5. Для локальной сборки Linux-пакетов установите `nfpm` и `appimagetool`, затем выполните:

```bash
scripts/build-linux-packages.sh
```

Подробности по сборке и выпуску: [CONTRIBUTING.md](docs/CONTRIBUTING.md).

</details>

[Лицензия](LICENSE.md) | [Политика конфиденциальности](docs/PRIVACY.md) | [Локализация](docs/localization.md) | [Как вносить изменения](docs/CONTRIBUTING.md)
