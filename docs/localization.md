# Localization

## Overview

- Source locale: `en`
- Source ARB file: `lib/l10n/app_en.arb`
- Translation files: `lib/l10n/app_<locale>.arb`
- Generated Flutter localizations: `lib/l10n/generated/`

English is the canonical source locale for Flutter `gen_l10n`.

## Local workflow

1. Add or update strings in `lib/l10n/app_en.arb`.
2. Update existing translations, for example `lib/l10n/app_ru.arb`.
3. Run:

```powershell
flutter gen-l10n
```

4. Commit the updated ARB files together with `lib/l10n/generated/`.

## GitHub automation

This repository includes `.github/workflows/sync-generated-localizations.yml`.

When any `lib/l10n/*.arb` file or `l10n.yaml` changes in a branch, this workflow runs `flutter gen-l10n` and commits the refreshed generated files back to the same branch.

`CI` also checks that generated localization files are up to date.
