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
  - Linux x64 tar.gz, AppImage, deb, rpm, and pacman package
  - APK/AAB
- Linux apt/rpm/pacman repository metadata is published to GitHub Pages after the release packages are built.

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

Release signing secrets:

- `KICK_RELEASE_GPG_PRIVATE_KEY`
- `KICK_RELEASE_GPG_PASSPHRASE`
- `KICK_RELEASE_GPG_KEY_ID`

The release workflow signs the SHA-256 checksum file and Linux repository metadata with this key. Individual Linux package signatures and Windows Authenticode signing are intentionally out of scope for the first Linux release.

## Windows installer

Inno Setup 6 is required to build the installer locally.

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-windows-installer.ps1
```

## Linux packages

Install Flutter Linux build dependencies plus package tooling:

```bash
sudo apt install clang lld cmake ninja-build pkg-config openjdk-17-jdk libgtk-3-dev liblzma-dev libcurl4-openssl-dev libsecret-1-dev libjsoncpp-dev libayatana-appindicator3-dev libnotify-dev
```

Install `nfpm` and `appimagetool`, then build all Linux artifacts:

```bash
scripts/build-linux-packages.sh
```

The script writes artifacts to `build/dist/linux`:

- `kick-linux-x64-VERSION.tar.gz`
- `kick-linux-x64-VERSION.AppImage`
- `kick-linux-x64-VERSION.deb`
- `kick-linux-x64-VERSION.rpm`
- `kick-linux-x64-VERSION.pkg.tar.zst`

To generate GitHub Pages repository metadata locally after importing the release GPG key:

```bash
scripts/publish-linux-repos.sh \
  --artifact-dir build/dist/linux \
  --pages-dir build/pages \
  --version VERSION \
  --gpg-key-id KEY_ID
```

Linux runtime notes:

- `flutter_secure_storage` uses `libsecret`; users need a working keyring service such as GNOME Keyring or KWallet.
- Tray icons use AppIndicator; GNOME users may need the AppIndicator extension.
- The app downloads and verifies Linux update packages but does not run `sudo`, `dpkg`, `rpm`, or `pacman` automatically.

## Generated files

- After changing any `lib/l10n/app_*.arb` file, regenerate localizations with `flutter gen-l10n`.
- The canonical source locale is `lib/l10n/app_en.arb`.
- Localization workflow and translation rules are documented in `docs/localization.md`.
