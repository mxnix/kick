# Localization

KiCk uses Flutter's `gen_l10n` to generate localized strings from ARB files.

## Layout

| Path | Purpose |
| --- | --- |
| `lib/l10n/app_en.arb` | Source locale, English. The single source of truth for keys and metadata. |
| `lib/l10n/app_<locale>.arb` | Translations for every other supported locale. |
| `lib/l10n/generated/` | Generated `AppLocalizations` Dart files. Committed to the repo. |
| `lib/l10n/kick_localizations.dart` | Re-export and helper used across the app. |
| `l10n.yaml` | `gen_l10n` configuration. |

The `l10n.yaml` configuration:

- `template-arb-file: app_en.arb` - the canonical source ARB.
- `output-class: AppLocalizations` - generated localization class.
- `preferred-supported-locales: [en, ru]` - declared supported locales.
- `nullable-getter: false` - `AppLocalizations.of(context)` is non-nullable, so callers must be inside a localized subtree.

## Workflow

### Update existing strings

1. Edit `lib/l10n/app_en.arb` (English source).
2. Mirror the change in every other ARB file, for example `lib/l10n/app_ru.arb`.
3. Regenerate:

   ```powershell
   flutter gen-l10n
   ```

4. Commit the ARB files together with the regenerated `lib/l10n/generated/`.

### Add a new key

1. Add the key, value, and metadata block to `app_en.arb`. Example:

   ```json
   "homeStartButton": "Start proxy",
   "@homeStartButton": {
     "description": "Label of the start button on the home page."
   }
   ```

2. For strings with placeholders, declare them in the metadata:

   ```json
   "logsCountLabel": "{count, plural, =0{No entries} =1{1 entry} other{{count} entries}}",
   "@logsCountLabel": {
     "description": "Plural label shown on the logs page header.",
     "placeholders": {
       "count": { "type": "int" }
     }
   }
   ```

3. Add the same key to every translation file. ICU `plural`/`select` patterns must be repeated in each locale.
4. Run `flutter gen-l10n` and commit the result.

### Add a new locale

1. Create `lib/l10n/app_<locale>.arb` with the same keys as `app_en.arb`.
2. Add the locale code to `preferred-supported-locales` in `l10n.yaml`.
3. Run `flutter gen-l10n`.
4. Update any in-app locale picker, fallback list, or tests that enumerate supported locales.
5. Add the same locale to release-facing files where applicable, for example WinGet manifests in `manifests/n/nikzmx/KiCk/<version>/`.

## Translation rules

- Match the source's tone: short, concrete, no exclamation marks, no superlatives.
- Keep placeholders (`{count}`, `{name}`) exactly as in the source. Do not translate the names.
- Preserve ICU plural and select branches (`=0`, `=1`, `other`, `male`, `female`, etc.).
- Keep punctuation consistent with the locale conventions, but do not introduce em dashes or fancy quotes that are absent in the source.
- Reuse existing terms across the app instead of inventing synonyms. Search the ARB before adding a new variant.

## CI automation

- `Sync Generated Localizations` (`.github/workflows/sync-generated-localizations.yml`): when any `lib/l10n/*.arb` or `l10n.yaml` changes on a branch, the workflow runs `flutter gen-l10n` and commits the refreshed generated files back to that branch.
- `CI` (`.github/workflows/ci.yml`): runs `flutter gen-l10n` and fails if `lib/l10n/generated/` differs from what is committed. This catches missing regenerations in PRs.
