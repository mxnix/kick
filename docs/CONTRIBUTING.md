# Contributing

Thanks for taking the time to look at KiCk. This guide covers the local setup, day-to-day workflow, and the release pipeline.

## Project layout

KiCk is a Flutter app that ships a local OpenAI-compatible proxy. Source lives in `lib/`:

| Path | What it contains |
| --- | --- |
| `lib/main.dart` | App entry point. |
| `lib/app/` | Bootstrap, routing, and metadata. |
| `lib/proxy/` | Proxy isolate, OpenAI parser/mapper, account pool, Gemini and Kiro clients. |
| `lib/features/` | UI screens (home, accounts, settings, logs, app shell). |
| `lib/data/` | Drift database, repositories, and serializable models. |
| `lib/core/` | Shared logging, networking, security, theming. |
| `lib/l10n/` | ARB source files and generated localizations. |
| `lib/analytics/` and `lib/observability/` | Aptabase and GlitchTip / Sentry integrations. |

Build configs and release tooling live in:

- `android/`, `linux/`, `windows/` - platform projects.
- `installer/` - Inno Setup script, nfpm config, Linux desktop and metainfo, AUR `PKGBUILD`.
- `manifests/` - WinGet manifests.
- `scripts/` - build and publishing scripts referenced by CI.
- `.github/workflows/` - CI, release, version-tag, l10n, and Kiro IDE version sync.

## Local setup

### Prerequisites

- Flutter SDK matching the version pinned in `.github/workflows/ci.yml` (`FLUTTER_VERSION`).
- Platform tooling for the targets you build:
  - Android: Android Studio with the latest SDK and a working JDK 17.
  - Windows: Visual Studio with the "Desktop development with C++" workload, plus `nuget.exe` on `PATH` (install via `winget install Microsoft.NuGet`). The `flutter_inappwebview_windows` plugin uses NuGet to fetch the WebView2 SDK at build time.
  - Linux: build dependencies listed under [Linux packages](#linux-packages).

### First run

```powershell
flutter pub get
flutter gen-l10n
```

`flutter gen-l10n` generates files into `lib/l10n/generated/`. CI verifies that those files are committed, so always rerun the command after touching any `lib/l10n/*.arb` file or `l10n.yaml`.

Run the app on your platform of choice:

```powershell
flutter run -d windows
```

```bash
flutter run -d linux
```

```powershell
flutter run -d android
```

## Development workflow

Before opening a PR run the same checks CI does:

```powershell
flutter analyze
flutter test --exclude-tags=golden
flutter test --tags=golden
```

Notes:

- Lints come from `analysis_options.yaml`. Highlights: `strict-casts`, `strict-inference`, `require_trailing_commas`, `unawaited_futures`.
- Golden tests live behind the `golden` tag (see `dart_test.yaml`). On Linux the goldens are skipped because they are recorded on Windows; the `goldens-windows` job in CI is the source of truth.
- Use the PR template in `.github/pull_request_template.md` and tick the platforms you actually verified manually.

## Localization

- Source locale is `en` (`lib/l10n/app_en.arb`).
- Add or update keys in `app_en.arb` first, then update `app_<locale>.arb` for every other locale.
- Run `flutter gen-l10n` and commit `lib/l10n/generated/`.
- The `Sync Generated Localizations` workflow regenerates outputs automatically on push, but committing them locally avoids a separate CI commit.
- Full workflow and translation rules: [LOCALIZATION.md](LOCALIZATION.md).

## Release

- The single source of truth is `version:` in `pubspec.yaml`.
- When `version:` changes on `main`, the `Sync Version Tag` workflow creates a `vX.Y.Z` tag.
- Pushing that tag triggers `Release`, which builds and publishes:
  - Windows portable zip and installer
  - Linux `tar.gz`, AppImage, `.deb`, `.rpm`, `.pkg.tar.zst`
  - Android APK and AAB
- After the GitHub release is published, follow-up jobs:
  - Publish APT, RPM, and Pacman repository metadata to GitHub Pages.
  - Update the `kick-bin` AUR package.
  - Submit the WinGet manifest to `microsoft/winget-pkgs`.

### Required secrets

Android signing:

- `KICK_ANDROID_KEYSTORE_BASE64`
- `KICK_ANDROID_KEYSTORE_PASSWORD`
- `KICK_ANDROID_KEY_ALIAS`
- `KICK_ANDROID_KEY_PASSWORD`

Release signing:

- `KICK_RELEASE_GPG_PRIVATE_KEY`
- `KICK_RELEASE_GPG_PASSPHRASE`
- `KICK_RELEASE_GPG_KEY_ID`

The release workflow signs the SHA-256 checksum file and the Linux repository metadata with this key. Per-package Linux signatures and Windows Authenticode signing are intentionally out of scope.

Publishing:

- `AUR_SSH_PRIVATE_KEY` - SSH key authorized to push to the `kick-bin` AUR repository.
- `WINGET_PAT` - GitHub PAT accepted by `wingetcreate` for opening pull requests in `microsoft/winget-pkgs`.

Optional analytics and diagnostics:

- `KICK_APTABASE_APP_KEY_RELEASE`
- `KICK_APTABASE_HOST_RELEASE`
- `SENTRY_DSN`
- `SENTRY_AUTH_TOKEN`
- `KICK_GLITCHTIP_TRACES_SAMPLE_RATE`

Optional repository variables:

- `AUR_GIT_NAME`
- `AUR_GIT_EMAIL`

## Building installers locally

### Windows installer

Inno Setup 6 is required.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-windows-installer.ps1
```

The script runs `flutter build windows --release` (skip with `-SkipBuild` if you already built it) and produces both the installer and a portable zip in `build\dist`.

### Linux packages

Install Flutter Linux build dependencies plus packaging tooling:

```bash
sudo apt install \
  clang lld cmake ninja-build pkg-config \
  openjdk-17-jdk libgtk-3-dev liblzma-dev \
  libcurl4-openssl-dev libsecret-1-dev libjsoncpp-dev \
  libayatana-appindicator3-dev libnotify-dev
```

Install [`nfpm`](https://nfpm.goreleaser.com/) and [`appimagetool`](https://github.com/AppImage/AppImageKit), then run:

```bash
scripts/build-linux-packages.sh --version "$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')"
```

The script writes artifacts to `build/dist/linux`:

- `kick-linux-x64-VERSION.tar.gz`
- `kick-linux-x64-VERSION.AppImage`
- `kick-linux-x64-VERSION.deb`
- `kick-linux-x64-VERSION.rpm`
- `kick-linux-x64-VERSION.pkg.tar.zst`

To regenerate GitHub Pages repository metadata locally after importing the release GPG key:

```bash
scripts/publish-linux-repos.sh \
  --artifact-dir build/dist/linux \
  --pages-dir build/pages \
  --version VERSION \
  --gpg-key-id KEY_ID
```

To refresh the AUR `PKGBUILD` and `.SRCINFO` from a built release archive:

```bash
git clone ssh://aur@aur.archlinux.org/kick-bin.git build/aur/kick-bin
scripts/update-aur-package.sh \
  --aur-dir build/aur/kick-bin \
  --artifact-dir build/dist/linux \
  --version VERSION \
  --repository mxnix/kick
```

#### Linux runtime notes

- `flutter_secure_storage` uses `libsecret`. End users need a working keyring such as GNOME Keyring or KWallet.
- Tray icons use AppIndicator. GNOME users may need the AppIndicator extension.
- The app downloads and verifies update packages but does not invoke `sudo`, `dpkg`, `rpm`, or `pacman` automatically.

### WinGet manifest

The release workflow generates and submits the WinGet manifest after the GitHub release is published. For a first manual submission or local validation:

```powershell
winget validate --manifest .\manifests\n\nikzmx\KiCk\VERSION --disable-interactivity
wingetcreate submit --prtitle "Add nikzmx.KiCk version VERSION" .\manifests\n\nikzmx\KiCk\VERSION
```
