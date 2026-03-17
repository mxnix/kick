# Contributing

## Локальная установка

1. Установите Flutter и нужные Android инструменты.
2. Выполните `flutter pub get`.

## Релиз

- Версия берется из `pubspec.yaml`.
- При изменении `version:` в `main` workflow `Sync Version Tag` создает или обновляет tag формата `vX.Y.Z`.
- Пуш такого тега запускает release workflow, который собирает:
  - Windows-переносной zip
  - Windows-установщик
  - APK/AAB

## Подпись

Должны быть настроены секреты:

- `KICK_ANDROID_KEYSTORE_BASE64`
- `KICK_ANDROID_KEYSTORE_PASSWORD`
- `KICK_ANDROID_KEY_ALIAS`
- `KICK_ANDROID_KEY_PASSWORD`

Опционально для аналитики:

- `KICK_APTABASE_APP_KEY_RELEASE`
- `KICK_APTABASE_HOST_RELEASE`
- `SENTRY_DSN`
- `KICK_GLITCHTIP_TRACES_SAMPLE_RATE`

## Windows установщик

Для локальной сборки installer нужен Inno Setup 6.

Команда:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-windows-installer.ps1
```

## Generated files

- После изменений в `lib/l10n/app_ru.arb` обновляйте локализации через `flutter gen-l10n`