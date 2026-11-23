#!/usr/bin/env bash
set -euo pipefail

asset_name=ForeverBiSTooltip.zip

view_release() {
  gh release view "$tag" --json assets,isDraft,url
}

find_asset() {
  jq -c --arg name "$asset_name" '.assets[] | select(.name == $name)' <<< "$release"
}

check_release() {
  jq -er --arg name "$asset_name" '
    select(.isDraft == false)
    | select(any(.assets[]; .name == $name and .state == "uploaded" and .size > 0))
    | .url
  ' <<< "$release"
}

download_asset() {
  gh release download "$tag" --pattern "$asset_name" --output "$1" --clobber
}

publish_release() {
  local zip_path="$1" notes_file="$2" asset state digest expected
  if [[ ! -s "$zip_path" || ! -s "$notes_file" ]]; then
    echo 'GitHub release requires a ZIP and patch notes.' >&2
    return 1
  fi

  if ! release="$(view_release 2>/dev/null)"; then
    release="$(gh api --paginate 'repos/{owner}/{repo}/releases?per_page=100' \
      --jq ".[] | select(.tag_name == \"$tag\") | {isDraft: .draft, url: .html_url, assets}")"
    if [[ -z "$release" ]]; then
      gh release create "$tag" --draft --verify-tag \
        --title "Forever BiS Tooltip ${tag#v}" --notes-file "$notes_file" >&2
      release="$(view_release)"
    fi
  fi

  temporary_dir="$(mktemp -d)"
  trap 'rm -f -- "$temporary_dir/$asset_name"; rmdir -- "$temporary_dir"' EXIT
  asset="$(find_asset)"
  if [[ -z "$asset" ]]; then
    cp -- "$zip_path" "$temporary_dir/$asset_name"
    gh release upload "$tag" "$temporary_dir/$asset_name" >&2
  else
    state="$(jq -r '.state' <<< "$asset")"
    case "$state" in
      uploaded)
        digest="$(jq -r '.digest // empty' <<< "$asset")"
        if [[ -n "$digest" ]]; then
          expected="sha256:$(sha256sum < "$zip_path" | cut -d ' ' -f 1)"
        else
          download_asset "$temporary_dir/$asset_name"
          digest="$(sha256sum < "$temporary_dir/$asset_name")"
          expected="$(sha256sum < "$zip_path")"
        fi
        if [[ "$digest" != "$expected" ]]; then
          echo "GitHub asset $asset_name for $tag has different contents." >&2
          return 1
        fi
        ;;
      starter)
        cp -- "$zip_path" "$temporary_dir/$asset_name"
        gh release upload "$tag" "$temporary_dir/$asset_name" --clobber >&2
        ;;
      *)
        echo "GitHub asset $asset_name for $tag is in unexpected state $state." >&2
        return 1
        ;;
    esac
  fi

  release="$(view_release)"
  asset="$(find_asset)"
  jq -e '.state == "uploaded" and .size > 0' <<< "$asset" > /dev/null
  if [[ "$(jq -r '.isDraft' <<< "$release")" == 'true' ]]; then
    gh release edit "$tag" --draft=false --latest >&2
    release="$(view_release)"
  fi
  check_release
}

command="${1:-}"
tag="${2:-}"

if [[ ! "$tag" =~ ^v[0-9]+(\.[0-9]+){2,3}$ ]]; then
  echo 'Expected a version tag such as v0.1.2 or v0.1.2.27.' >&2
  exit 1
fi

case "$command:$#" in
  check:2)
    release="$(view_release)"
    check_release
    ;;
  download:3)
    download_asset "$3"
    [[ -s "$3" ]]
    ;;
  publish:4)
    publish_release "$3" "$4"
    ;;
  *)
    echo 'Usage: github-release.sh check <tag> | download <tag> <ZIP> | publish <tag> <ZIP> <notes>' >&2
    exit 1
    ;;
esac
