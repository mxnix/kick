# Contributing

## Local setup

1. Install Flutter and the required Android tooling.
2. Run `flutter pub get`.

## Release

- The version is taken from `pubspec.yaml`.
- When `version:` changes on `main`, the `Sync Version Tag` workflow creates or updates a tag in the `vX.Y.Z` format.
- Pushing that tag triggers the release workflow, which builds:
  - Windows portable zip
  - Windows installer
  - APK/AAB

## Signing

The following secrets must be configured:

- `KICK_ANDROID_KEYSTORE_BASE64`
- `KICK_ANDROID_KEYSTORE_PASSWORD`
- `KICK_ANDROID_KEY_ALIAS`
- `KICK_ANDROID_KEY_PASSWORD`

Optional analytics and diagnostics secrets:

- `KICK_APTABASE_APP_KEY_RELEASE`
- `KICK_APTABASE_HOST_RELEASE`
- `SENTRY_DSN`
- `SENTRY_AUTH_TOKEN`
- `KICK_GLITCHTIP_TRACES_SAMPLE_RATE`

## Windows installer

Inno Setup 6 is required to build the installer locally.

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-windows-installer.ps1
```

## Generated files

- After changing any `lib/l10n/app_*.arb` file, regenerate localizations with `flutter gen-l10n`.
- The canonical source locale is `lib/l10n/app_en.arb`.
- Localization workflow and translation rules are documented in `docs/localization.md`.
