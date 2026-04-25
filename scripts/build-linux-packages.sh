#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_version=""
skip_build="false"
source_dir=""
output_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      app_version="${2:?Missing value for --version}"
      shift 2
      ;;
    --skip-build)
      skip_build="true"
      shift
      ;;
    --source-dir)
      source_dir="${2:?Missing value for --source-dir}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:?Missing value for --output-dir}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

cd "$repo_root"

if [[ -z "$app_version" ]]; then
  app_version="$(sed -n 's/^version: *//p' pubspec.yaml | head -n1 | cut -d+ -f1)"
fi
if [[ -z "$app_version" ]]; then
  echo "Could not determine app version from pubspec.yaml." >&2
  exit 1
fi

if [[ -z "$source_dir" ]]; then
  source_dir="build/linux/x64/release/bundle"
fi
if [[ -z "$output_dir" ]]; then
  output_dir="build/dist/linux"
fi

if [[ "$skip_build" != "true" ]]; then
  flutter_args=(build linux --release)
  if [[ -n "${KICK_APTABASE_APP_KEY_RELEASE:-}" ]]; then
    flutter_args+=("--dart-define=KICK_APTABASE_APP_KEY_RELEASE=$KICK_APTABASE_APP_KEY_RELEASE")
  fi
  if [[ -n "${KICK_APTABASE_HOST_RELEASE:-}" ]]; then
    flutter_args+=("--dart-define=KICK_APTABASE_HOST_RELEASE=$KICK_APTABASE_HOST_RELEASE")
  fi
  if [[ -n "${SENTRY_DSN:-}" ]]; then
    flutter_args+=("--dart-define=SENTRY_DSN=$SENTRY_DSN")
  fi
  flutter_args+=("--dart-define=SENTRY_ENVIRONMENT=production")
  if [[ -n "${KICK_GLITCHTIP_TRACES_SAMPLE_RATE:-}" ]]; then
    flutter_args+=("--dart-define=KICK_GLITCHTIP_TRACES_SAMPLE_RATE=$KICK_GLITCHTIP_TRACES_SAMPLE_RATE")
  fi
  flutter "${flutter_args[@]}"
fi

if [[ ! -d "$source_dir" ]]; then
  echo "Linux release bundle was not found at '$source_dir'." >&2
  exit 1
fi
source_dir="$(cd "$source_dir" && pwd)"

mkdir -p "$output_dir"

tar_path="$output_dir/kick-linux-x64-$app_version.tar.gz"
rm -f "$tar_path"
tar -C "$source_dir" -czf "$tar_path" .

package_work_dir="build/linux/package"
app_dir="$package_work_dir/AppDir"
rm -rf "$package_work_dir"
mkdir -p "$app_dir/opt" "$app_dir/usr/bin" "$app_dir/usr/share/applications" \
  "$app_dir/usr/share/icons/hicolor/256x256/apps" "$app_dir/usr/share/metainfo"

cp -R "$source_dir" "$app_dir/opt/kick"
install -m 0755 "installer/linux/kick" "$app_dir/usr/bin/kick"
install -m 0644 "installer/linux/com.nikzmx.kick.desktop" \
  "$app_dir/usr/share/applications/com.nikzmx.kick.desktop"
install -m 0644 "static/github/logo/linux.png" \
  "$app_dir/usr/share/icons/hicolor/256x256/apps/com.nikzmx.kick.png"
install -m 0644 "installer/linux/com.nikzmx.kick.metainfo.xml" \
  "$app_dir/usr/share/metainfo/com.nikzmx.kick.metainfo.xml"
install -m 0644 "installer/linux/com.nikzmx.kick.desktop" "$app_dir/com.nikzmx.kick.desktop"
install -m 0644 "static/github/logo/linux.png" "$app_dir/com.nikzmx.kick.png"
cat > "$app_dir/AppRun" <<'APPRUN'
#!/usr/bin/env sh
set -e
here="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$here/opt/kick/kick" "$@"
APPRUN
chmod 0755 "$app_dir/AppRun"

if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$app_dir/com.nikzmx.kick.desktop"
fi
if command -v appstreamcli >/dev/null 2>&1; then
  appstreamcli validate --no-net "$app_dir/usr/share/metainfo/com.nikzmx.kick.metainfo.xml" || true
fi

appimage_path="$output_dir/kick-linux-x64-$app_version.AppImage"
if ! command -v appimagetool >/dev/null 2>&1; then
  echo "appimagetool is required to build $appimage_path." >&2
  exit 1
fi
rm -f "$appimage_path"
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 appimagetool "$app_dir" "$appimage_path"
chmod 0755 "$appimage_path"

if ! command -v nfpm >/dev/null 2>&1; then
  echo "nfpm is required to build Linux package manager artifacts." >&2
  exit 1
fi

generated_nfpm_config="$package_work_dir/nfpm.yaml"
escape_yaml_double_quoted() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

version_replacement="$(escape_sed_replacement "$(escape_yaml_double_quoted "$app_version")")"
source_dir_replacement="$(escape_sed_replacement "$(escape_yaml_double_quoted "$source_dir")")"
sed \
  -e "s|__VERSION__|$version_replacement|g" \
  -e "s|__SOURCE_DIR__|$source_dir_replacement|g" \
  "installer/linux/nfpm.yaml" > "$generated_nfpm_config"

nfpm pkg --packager deb --config "$generated_nfpm_config" \
  --target "$output_dir/kick-linux-x64-$app_version.deb"
nfpm pkg --packager rpm --config "$generated_nfpm_config" \
  --target "$output_dir/kick-linux-x64-$app_version.rpm"
nfpm pkg --packager archlinux --config "$generated_nfpm_config" \
  --target "$output_dir/kick-linux-x64-$app_version.pkg.tar.zst"

echo "Linux release artifacts:"
find "$output_dir" -maxdepth 1 -type f -printf '  %p\n' | sort
