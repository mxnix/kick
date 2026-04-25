#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_dir=""
pages_dir=""
app_version=""
gpg_key_id="${KICK_RELEASE_GPG_KEY_ID:-}"
repo_name="${KICK_LINUX_REPO_NAME:-kick}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-dir)
      artifact_dir="${2:?Missing value for --artifact-dir}"
      shift 2
      ;;
    --pages-dir)
      pages_dir="${2:?Missing value for --pages-dir}"
      shift 2
      ;;
    --version)
      app_version="${2:?Missing value for --version}"
      shift 2
      ;;
    --gpg-key-id)
      gpg_key_id="${2:?Missing value for --gpg-key-id}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

cd "$repo_root"

if [[ -z "$artifact_dir" || -z "$pages_dir" || -z "$app_version" ]]; then
  echo "--artifact-dir, --pages-dir, and --version are required." >&2
  exit 2
fi
if [[ -z "$gpg_key_id" ]]; then
  echo "A GPG key id is required via --gpg-key-id or KICK_RELEASE_GPG_KEY_ID." >&2
  exit 1
fi
gpg_sign_args=(--batch --yes --pinentry-mode loopback --local-user "$gpg_key_id")
if [[ -n "${KICK_RELEASE_GPG_PASSPHRASE:-}" ]]; then
  gpg_sign_args+=(--passphrase "$KICK_RELEASE_GPG_PASSPHRASE")
fi

artifact_dir="$(cd "$artifact_dir" && pwd)"
mkdir -p "$pages_dir/linux"
pages_dir="$(cd "$pages_dir" && pwd)"

deb="$artifact_dir/kick-linux-x64-$app_version.deb"
rpm="$artifact_dir/kick-linux-x64-$app_version.rpm"
pacman_pkg="$artifact_dir/kick-linux-x64-$app_version.pkg.tar.zst"
for file in "$deb" "$rpm" "$pacman_pkg"; do
  if [[ ! -f "$file" ]]; then
    echo "Required Linux package was not found: $file" >&2
    exit 1
  fi
done

gpg --armor --export "$gpg_key_id" > "$pages_dir/linux/kick.asc"
gpg --export "$gpg_key_id" > "$pages_dir/linux/kick.gpg"

apt_root="$pages_dir/linux/apt"
rm -rf "$apt_root"
mkdir -p "$apt_root/pool/main/k/kick" "$apt_root/dists/stable/main/binary-amd64"
cp "$deb" "$apt_root/pool/main/k/kick/"
(
  cd "$apt_root"
  dpkg-scanpackages --arch amd64 pool > dists/stable/main/binary-amd64/Packages
  gzip -9kf dists/stable/main/binary-amd64/Packages
  apt-ftparchive release dists/stable > dists/stable/Release
  gpg "${gpg_sign_args[@]}" \
    --clearsign --digest-algo SHA256 -o dists/stable/InRelease dists/stable/Release
  gpg "${gpg_sign_args[@]}" \
    --detach-sign --armor -o dists/stable/Release.gpg dists/stable/Release
)

rpm_root="$pages_dir/linux/rpm/x86_64"
rm -rf "$rpm_root"
mkdir -p "$rpm_root/Packages"
cp "$rpm" "$rpm_root/Packages/"
createrepo_c "$rpm_root"
gpg "${gpg_sign_args[@]}" \
  --detach-sign --armor -o "$rpm_root/repodata/repomd.xml.asc" "$rpm_root/repodata/repomd.xml"

pacman_root="$pages_dir/linux/pacman/x86_64"
rm -rf "$pacman_root"
mkdir -p "$pacman_root"
cp "$pacman_pkg" "$pacman_root/"
(
  cd "$pacman_root"
  repo-add "$repo_name.db.tar.gz" "$(basename "$pacman_pkg")"
  cp "$repo_name.db.tar.gz" "$repo_name.db"
  cp "$repo_name.files.tar.gz" "$repo_name.files"
  gpg "${gpg_sign_args[@]}" \
    --detach-sign --armor -o "$repo_name.db.tar.gz.sig" "$repo_name.db.tar.gz"
  cp "$repo_name.db.tar.gz.sig" "$repo_name.db.sig"
)

cat > "$pages_dir/linux/index.html" <<HTML
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<title>KiCk Linux packages</title>
<h1>KiCk Linux packages</h1>
<p>Repository metadata is generated for apt, rpm, and pacman clients.</p>
<p>Public signing key: <a href="./kick.asc">kick.asc</a> or <a href="./kick.gpg">kick.gpg</a>.</p>
</html>
HTML

echo "Linux repositories published under $pages_dir/linux"
