#!/usr/bin/env bash

set -euo pipefail

: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN is required}"

SENTRY_URL="${SENTRY_URL:-https://app.glitchtip.com/}"
SENTRY_ORG="${SENTRY_ORG:-kick}"
SENTRY_PROJECT="${SENTRY_PROJECT:-kick}"

debug_files_dir="${1:-build/app/intermediates/merged_native_libs/release/mergeReleaseNativeLibs/out/lib}"
native_symbols_zip="${2:-build/app/outputs/native-debug-symbols/release/native-debug-symbols.zip}"

if ! command -v sentry-cli >/dev/null 2>&1; then
  echo "sentry-cli is required to upload Android debug files." >&2
  exit 1
fi

if [[ ! -d "$debug_files_dir" && ! -f "$native_symbols_zip" ]]; then
  echo "No Android debug files were found to upload." >&2
  exit 1
fi

temp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$temp_dir"
}
trap cleanup EXIT

if [[ -d "$debug_files_dir" ]]; then
  cp -R "$debug_files_dir"/. "$temp_dir"/
fi

if [[ -f "$native_symbols_zip" ]]; then
  unzip -q "$native_symbols_zip" -d "$temp_dir/native-symbols"
fi

if ! find "$temp_dir" -type f | grep -q .; then
  echo "Resolved Android debug files directory is empty." >&2
  exit 1
fi

sentry-cli \
  --url "$SENTRY_URL" \
  --auth-token "$SENTRY_AUTH_TOKEN" \
  debug-files upload \
  --wait \
  -o "$SENTRY_ORG" \
  -p "$SENTRY_PROJECT" \
  "$temp_dir"
