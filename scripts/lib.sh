#!/usr/bin/env bash
set -euo pipefail

image_name() {
  echo "ghcr.io/${GITHUB_REPOSITORY,,}"
}

resolve_digest() {
  local ref="$1"
  docker buildx imagetools inspect --format '{{json .Manifest}}' "$ref" | jq -r '.digest'
}

promote_image() {
  local image="$1" source_tag="$2" target_tag="$3"
  local source_digest target_digest
  source_digest="$(resolve_digest "${image}:${source_tag}")"
  docker buildx imagetools create --prefer-index=false --tag "${image}:${target_tag}" "${image}@${source_digest}"
  target_digest="$(resolve_digest "${image}:${target_tag}")"
  [[ "$source_digest" == "$target_digest" ]] || { echo "Digest changed during promotion" >&2; exit 1; }
  echo "$target_digest"
}

ensure_image() {
  local image="$1" sha="$2" tag="git-${2}"
  if ! docker buildx imagetools inspect "${image}:${tag}" >/dev/null 2>&1; then
    docker buildx build --platform linux/amd64 --push \
      --tag "${image}:${tag}" \
      --build-arg "GIT_SHA=${sha}" \
      --build-arg "SOURCE_REPO=https://github.com/${GITHUB_REPOSITORY}" .
  fi
  resolve_digest "${image}:${tag}"
}
