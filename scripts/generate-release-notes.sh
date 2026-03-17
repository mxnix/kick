#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  generate-release-notes.sh \
    --tag <tag> \
    --version <version> \
    --repository <owner/repo> \
    --template <template-path> \
    --output <output-path>
EOF
}

tag=""
version=""
repository=""
template_path=""
output_path=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tag)
      tag="${2:-}"
      shift 2
      ;;
    --version)
      version="${2:-}"
      shift 2
      ;;
    --repository)
      repository="${2:-}"
      shift 2
      ;;
    --template)
      template_path="${2:-}"
      shift 2
      ;;
    --output)
      output_path="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

for required_value in tag version repository template_path output_path; do
  if [ -z "${!required_value}" ]; then
    echo "Missing required argument: ${required_value}" >&2
    usage >&2
    exit 1
  fi
done

if [ ! -f "$template_path" ]; then
  echo "Template file was not found: $template_path" >&2
  exit 1
fi

if ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "Tag was not found in the local repository: $tag" >&2
  exit 1
fi

previous_tag="$(
  git tag --sort=-version:refname |
    awk -v current="$tag" '
      $0 == current { found = 1; next }
      found { print; exit }
    '
)"

range_spec="$tag"
full_changelog_line="This is the first tagged release."
if [ -n "$previous_tag" ]; then
  range_spec="$previous_tag..$tag"
  full_changelog_line="**Full Changelog:** [${previous_tag}...${tag}](https://github.com/${repository}/compare/${previous_tag}...${tag})"
fi

mapfile -t changelog_entries < <(
  git log --no-merges --format='%s' "$range_spec" |
    sed '/^[[:space:]]*$/d' |
    grep -vE '^chore: update version to [0-9]+\.[0-9]+\.[0-9]+$' || true
)

if [ "${#changelog_entries[@]}" -eq 0 ]; then
  mapfile -t changelog_entries < <(
    git log --no-merges --format='%s' "$range_spec" |
      sed '/^[[:space:]]*$/d' || true
  )
fi

if [ "${#changelog_entries[@]}" -eq 0 ]; then
  changelog="No commit subjects were found for this release."
else
  changelog="$(printf -- '- %s\n' "${changelog_entries[@]}")"
  changelog="${changelog%$'\n'}"
fi

template_content="$(cat "$template_path")"
template_content="${template_content//__REPOSITORY__/$repository}"
template_content="${template_content//__TAG__/$tag}"
template_content="${template_content//__VERSION__/$version}"
template_content="${template_content//__CHANGELOG__/$changelog}"
template_content="${template_content//__FULL_CHANGELOG__/$full_changelog_line}"

printf '%s\n' "$template_content" > "$output_path"
