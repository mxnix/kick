# Privacy Policy

*Updated: May 14, 2026*

KiCk runs locally on your device. The project does not operate any server that processes your prompts or responses.

## What is stored locally

All data stays on your device:

- **Settings.** Theme, host, port, retry policy, custom model IDs, analytics consent, and similar preferences.
- **Account data.** Email, Gemini `PROJECT_ID`, Kiro session parameters, per-account counters, and limit statuses.
- **Authentication.** Google OAuth tokens, Kiro session data (Builder ID or social sign-in via GitHub or Google), and the local KiCk API key. Tokens and the API key are stored in the device's secure storage (Keychain on macOS/iOS, Credential Vault on Windows, libsecret on Linux, EncryptedSharedPreferences on Android).
- **Logs.** Stored locally for debugging. Full raw prompt logging is **disabled** by default. Sensitive values are masked when logs are saved or exported.

## Network connections

KiCk connects only to:

- Google services, for OAuth sign-in and Gemini CLI requests.
- AWS and Kiro services, for Kiro sign-in (Builder ID or social via GitHub or Google), Kiro session refresh, and Kiro requests.
- The local loopback address, by default `127.0.0.1`.
- Aptabase, **only** if you explicitly opt in to anonymous analytics.
- A GlitchTip or Sentry-compatible endpoint, **only** if that diagnostics option is enabled in a specific build.

The app also downloads update artifacts from GitHub Releases when you check for updates from inside the app.

## Analytics (strictly optional)

Anonymous analytics is **disabled** by default. If you opt in, KiCk sends only basic events such as app launches, proxy errors, and account connection results. The data does not include:

- prompt or response text,
- API keys or tokens,
- email addresses,
- `PROJECT_ID`,
- raw logs.

You can disable analytics again at any time from settings. When you do, KiCk emits a single `analytics_consent_revoked` marker and purges the local outgoing queue. The full list of events and properties is published in [`docs/ANALYTICS.md`](ANALYTICS.md).

## Access modes

By default the proxy listens only on `127.0.0.1` and requires the local API key. Two settings widen access; both are off by default and your responsibility once enabled:

- **Allow LAN.** Binds to `0.0.0.0` so other devices on your network can reach the proxy.
- **Disable API key.** Removes the `Authorization` header check.

If you enable either, anyone who can reach the proxy port can use your connected accounts. Treat this the same way you would a forwarded service on your machine.

## Contact

For privacy questions, open an issue in the repository.
