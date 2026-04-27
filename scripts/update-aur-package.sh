#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
aur_dir=""
app_version=""
artifact_dir=""
repository="${GITHUB_REPOSITORY:-mxnix/kick}"
template_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --aur-dir)
      aur_dir="${2:?Missing value for --aur-dir}"
      shift 2
      ;;
    --version)
      app_version="${2:?Missing value for --version}"
      shift 2
      ;;
    --artifact-dir)
      artifact_dir="${2:?Missing value for --artifact-dir}"
      shift 2
      ;;
    --repository)
      repository="${2:?Missing value for --repository}"
      shift 2
      ;;
    --template)
      template_path="${2:?Missing value for --template}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

cd "$repo_root"

if [[ -z "$aur_dir" || -z "$app_version" ]]; then
  echo "--aur-dir and --version are required." >&2
  exit 2
fi

if [[ -z "$artifact_dir" ]]; then
  artifact_dir="build/dist/linux"
fi
if [[ -z "$template_path" ]]; then
  template_path="installer/aur/PKGBUILD"
fi

if [[ ! -d "$aur_dir" ]]; then
  echo "AUR checkout was not found at '$aur_dir'." >&2
  exit 1
fi
if [[ ! -f "$template_path" ]]; then
  echo "AUR PKGBUILD template was not found at '$template_path'." >&2
  exit 1
fi
if ! command -v makepkg >/dev/null 2>&1; then
  echo "makepkg is required to generate .SRCINFO." >&2
  exit 1
fi

sha256_file() {
  sha256sum "$1" | awk '{ print $1 }'
}

artifact_dir="$(cd "$artifact_dir" && pwd)"
aur_dir="$(cd "$aur_dir" && pwd)"
template_path="$(cd "$(dirname "$template_path")" && pwd)/$(basename "$template_path")"

archive_path="$artifact_dir/kick-linux-x64-$app_version.tar.gz"
desktop_path="installer/linux/com.nikzmx.kick.desktop"
metainfo_path="installer/linux/com.nikzmx.kick.metainfo.xml"
icon_path="static/github/logo/logo.png"
license_path="LICENSE.md"

for file in "$archive_path" "$desktop_path" "$metainfo_path" "$icon_path" "$license_path"; do
  if [[ ! -f "$file" ]]; then
    echo "Required file was not found: $file" >&2
    exit 1
  fi
done

archive_sha256="$(sha256_file "$archive_path")"
desktop_sha256="$(sha256_file "$desktop_path")"
metainfo_sha256="$(sha256_file "$metainfo_path")"
icon_sha256="$(sha256_file "$icon_path")"
license_sha256="$(sha256_file "$license_path")"

rendered_pkgbuild="$aur_dir/PKGBUILD"
sed \
  -e "s|__VERSION__|$app_version|g" \
  -e "s|__REPOSITORY__|$repository|g" \
  -e "s|__ARCHIVE_SHA256__|$archive_sha256|g" \
  -e "s|__DESKTOP_SHA256__|$desktop_sha256|g" \
  -e "s|__METAINFO_SHA256__|$metainfo_sha256|g" \
  -e "s|__ICON_SHA256__|$icon_sha256|g" \
  -e "s|__LICENSE_SHA256__|$license_sha256|g" \
  "$template_path" > "$rendered_pkgbuild"

(
  cd "$aur_dir"
  makepkg --printsrcinfo > .SRCINFO
)

echo "Updated AUR package metadata for kick-bin $app_version."
