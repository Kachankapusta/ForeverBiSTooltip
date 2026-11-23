#!/usr/bin/env bash
set -euo pipefail

project="$CURSEFORGE_PROJECT_ID"
version_pattern='s/^## Version: +([0-9]+\.[0-9]+\.[0-9]+)\r?$/\1/p'
addon_files=(ForeverBiSTooltip.toc Locale.lua Core.lua Shopping.lua UI.lua ShoppingUI.lua Tooltip.lua)

curseforge_receipt() {
  [[ "$project" =~ ^[1-9][0-9]*$ ]] || return 1
  git show-ref --verify --quiet "refs/tags/curseforge/$project/$1" || return 1
  git for-each-ref --format='%(contents:subject)' "refs/tags/curseforge/$project/$1" |
    sed -nE 's/^CurseForge file ([1-9][0-9]*)$/\1/p' | grep .
}

plan_release() {
  local tag commit url file_id
  tag="$(git describe --first-parent --abbrev=0 --match 'v[0-9]*' HEAD 2>/dev/null || true)"
  if [[ -z "$tag" ]]; then
    if [[ "$project" =~ ^[1-9][0-9]*$ ]]; then
      tag="$(git describe --first-parent --abbrev=0 --match "curseforge/$project/*" HEAD 2>/dev/null || true)"
      if [[ -n "$tag" ]]; then
        echo "backfill_tag=$tag" >> "$GITHUB_OUTPUT"
      fi
    fi
    return
  fi

  commit="$(git rev-parse "$tag^{commit}")"
  url="$(bash tools/github-release.sh check "$tag" || true)"
  file_id="$(curseforge_receipt "$commit" || true)"
  {
    echo "github_url=$url"
    if [[ -n "$url" && ( -z "$project" || -n "$file_id" ) ]]; then
      echo "published_tag=$tag"
    else
      echo "pending_tag=$tag"
    fi
  } >> "$GITHUB_OUTPUT"
}

is_data_update() {
  git log -1 --format=%B "$1" | grep -Ex 'WowTBC-Data-Update: true|CurseForge-Project: [1-9][0-9]*' > /dev/null
}

prepare_notes() {
  local data_commit code_commit previous_version updated_at
  data_commit="$(git log -1 --first-parent --format=%H "$release_commit" -- Data.lua)"
  code_commit="$(git log -1 --first-parent --format=%H "$release_commit" -- CHANGELOG.md)"
  if [[ "$release_commit" != "$code_commit" ]] && ! is_data_update "$data_commit"; then
    echo 'No release has been queued.'
    echo 'status=not_queued' >> "$GITHUB_OUTPUT"
    exit 0
  fi

  version="$(git show "$release_commit:ForeverBiSTooltip.toc" | sed -nE "$version_pattern")"
  if [[ -z "$version" ]]; then
    echo '::error file=ForeverBiSTooltip.toc::Expected a version in X.Y.Z format for the release commit.'
    exit 1
  fi

  : > "$notes"
  if [[ -n "$code_commit" ]] && { [[ -z "$previous_tag" ]] || ! git merge-base --is-ancestor "$code_commit" "$previous_tag"; }; then
    previous_version=''
    if [[ -n "$previous_tag" ]]; then
      previous_version="$(git show "$previous_tag:ForeverBiSTooltip.toc" | sed -nE "$version_pattern")"
    fi
    git show "$release_commit:CHANGELOG.md" | awk -v version="$version" -v previous="$previous_version" '
      { sub(/\r$/, "") }
      $0 == "## " previous { released = 1 }
      $0 == "## " version { include = 1 }
      include && !released { print }
    ' > "$notes"
    if ! grep -q '^- ' "$notes"; then
      echo "::error file=CHANGELOG.md::Add release notes under ## $version and bump the TOC version for code changes."
      exit 1
    fi
  elif [[ -n "$previous_tag" ]] && ! git diff --quiet "$previous_tag" "$release_commit" -- "${addon_files[@]}"; then
    echo '::error file=CHANGELOG.md::Add release notes and bump the TOC version before publishing code changes.'
    exit 1
  fi
  if { [[ -z "$previous_tag" ]] || ! git merge-base --is-ancestor "$data_commit" "$previous_tag"; } && is_data_update "$data_commit"; then
    version="$version.$(git rev-list --count "$release_commit")"
    updated_at="$(TZ=Europe/Warsaw date --date="$(git show -s --format=%cI "$data_commit")" '+%Y-%m-%d %H:%M:%S (Europe/Warsaw, UTC%:z)')"
    if [[ -s "$notes" ]]; then
      printf '\n' >> "$notes"
    fi
    printf '## Data update\n\n- Updated WoW Forever Pre-Raid and Realistic BiS recommendations from WowTBC on %s.\n' "$updated_at" >> "$notes"
  fi
  if [[ ! -s "$notes" ]]; then
    echo '::error::The release has no patch notes.'
    exit 1
  fi
}

build_zip() {
  local package_dir readme
  package_dir="$RUNNER_TEMP/forever-bis-release/ForeverBiSTooltip"
  mkdir -p "$package_dir"
  readme=README.md
  if ! git cat-file -e "$release_commit:README.md" 2>/dev/null; then
    readme=README.txt
  fi
  local package_files=("${addon_files[@]}" Data.lua "$readme")
  if git cat-file -e "$release_commit:LICENSE" 2>/dev/null; then
    package_files+=(LICENSE)
  fi
  git archive "$release_commit" -- "${package_files[@]}" | tar -x -C "$package_dir"
  sed -i -E "s/^## Version: .*/## Version: $version/" "$package_dir/ForeverBiSTooltip.toc"
  touch -r "$package_dir/Data.lua" "$package_dir/ForeverBiSTooltip.toc" "$package_dir"
  (cd "$(dirname "$package_dir")"; TZ=UTC zip -q -X -r "$zip_file" ForeverBiSTooltip)
}

download_curseforge_zip() {
  local major="${file_id:0:-3}" minor="$((10#${file_id: -3}))"
  curl --fail --silent --show-error --location --max-time 60 \
    "https://edge.forgecdn.net/files/$major/$minor/ForeverBiSTooltip-$version.zip" --output "$zip_file"
}

prepare_release() {
  local tag="$PENDING_TAG" previous_tag="$PUBLISHED_TAG"
  local release_commit version notes zip_file file_id expected_hash='' release_info zip_hash
  notes="$RUNNER_TEMP/forever-bis-changelog.md"
  release_info="$RUNNER_TEMP/forever-bis-release-info.md"

  if [[ -n "$tag" ]]; then
    release_commit="$(git rev-parse "$tag^{commit}")"
    version="${tag#v}"
    git cat-file tag "$tag" | sed '1,/^$/d' > "$release_info"
    expected_hash="$(sed -nE '1s/^SHA256 ([0-9a-f]{64})$/\1/p' "$release_info")"
    tail -n +3 "$release_info" > "$notes"
    if [[ -z "$expected_hash" || ! -s "$notes" ]]; then
      echo "::error::Missing archive checksum or patch notes on $tag."
      exit 1
    fi
  else
    if [[ -n "$BACKFILL_TAG" ]]; then
      release_commit="$(git rev-parse "$BACKFILL_TAG^{commit}")"
      previous_tag="$(git describe --first-parent --abbrev=0 --match "curseforge/$project/*" \
        --exclude "$BACKFILL_TAG" "$release_commit" 2>/dev/null || true)"
    else
      release_commit="$(git log -1 --first-parent --format=%H -- Data.lua CHANGELOG.md)"
      if [[ -n "$previous_tag" && "$release_commit" == "$(git rev-parse "$previous_tag^{commit}")" ]]; then
        echo 'status=already_published' >> "$GITHUB_OUTPUT"
        echo "github_url=$EXISTING_GITHUB_URL" >> "$GITHUB_OUTPUT"
        echo "curseforge_file_id=$(curseforge_receipt "$release_commit" || true)" >> "$GITHUB_OUTPUT"
        exit 0
      fi
    fi
    prepare_notes
  fi

  file_id="$(curseforge_receipt "$release_commit" || true)"
  zip_file="$RUNNER_TEMP/ForeverBiSTooltip-$version.zip"
  if [[ -n "$BACKFILL_TAG" ]]; then
    [[ -n "$file_id" ]]
    download_curseforge_zip
  elif [[ -n "$file_id" ]] && download_curseforge_zip; then
    echo "Reusing CurseForge file $file_id."
  elif [[ -n "$tag" ]] && bash tools/github-release.sh download "$tag" "$zip_file"; then
    echo "Reusing the GitHub release archive for $tag."
  else
    rm -f -- "$zip_file"
    build_zip
  fi

  unzip -tqq "$zip_file"
  if ! unzip -p "$zip_file" ForeverBiSTooltip/ForeverBiSTooltip.toc | sed 's/\r$//' | grep -Fx "## Version: $version"; then
    echo "::error::The archive TOC does not match version $version."
    exit 1
  fi
  zip_hash="$(sha256sum "$zip_file" | cut -d ' ' -f 1)"
  if [[ -n "$expected_hash" && "$zip_hash" != "$expected_hash" ]]; then
    echo "::error::The archive for $tag does not match the original build checksum."
    exit 1
  fi

  if [[ -z "$tag" ]]; then
    tag="v$version"
    { printf 'SHA256 %s\n\n' "$zip_hash"; cat "$notes"; } > "$release_info"
    git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
      tag -a "$tag" "$release_commit" --cleanup=verbatim -F "$release_info"
    git push origin "refs/tags/$tag"
  fi

  {
    echo 'status=ready'
    echo "zip=$zip_file"
    echo "version=$version"
    echo "tag=$tag"
    echo "changelog=$notes"
    echo "receipt=curseforge/$project/$release_commit"
    echo "release_commit=$release_commit"
    echo "curseforge_file_id=$file_id"
    if [[ -n "$PENDING_TAG" ]]; then
      echo "github_url=$EXISTING_GITHUB_URL"
    fi
  } >> "$GITHUB_OUTPUT"
}

case "$1" in
  plan) plan_release ;;
  package) prepare_release ;;
  *) exit 2 ;;
esac
