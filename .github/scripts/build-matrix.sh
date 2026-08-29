#!/usr/bin/env bash
set -euo pipefail

readonly build_config="${1:?Usage: build-matrix.sh <build.yaml>}"

if [[ ! -f "${build_config}" ]]; then
  echo "Build configuration not found: ${build_config}" >&2
  exit 1
fi

declare -A seen_architectures=()
declare -a matrix_entries=()
declare arch
declare image
declare platform
declare line
declare inside_build_from=false

while IFS= read -r line; do
  if [[ "${line}" == "build_from:" ]]; then
    inside_build_from=true
    continue
  fi

  if [[ "${inside_build_from}" != true ]]; then
    continue
  fi

  if [[ "${line}" =~ ^[^[:space:]] ]]; then
    break
  fi

  if [[ -z "${line//[[:space:]]/}" || "${line}" =~ ^[[:space:]]*# ]]; then
    continue
  fi

  if [[ ! "${line}" =~ ^[[:space:]]{2}([a-z0-9_]+):[[:space:]]+([^[:space:]]+)[[:space:]]*$ ]]; then
    echo "Unsupported build_from entry: ${line}" >&2
    exit 1
  fi

  arch="${BASH_REMATCH[1]}"
  image="${BASH_REMATCH[2]}"

  case "${arch}" in
    aarch64) platform="linux/arm64" ;;
    amd64) platform="linux/amd64" ;;
    *)
      echo "Unsupported build architecture: ${arch}" >&2
      exit 1
      ;;
  esac

  if [[ -n "${seen_architectures[${arch}]+set}" ]]; then
    echo "Duplicate build architecture: ${arch}" >&2
    exit 1
  fi
  seen_architectures["${arch}"]=true

  matrix_entries+=("$(
    jq --compact-output --null-input \
      --arg arch "${arch}" \
      --arg platform "${platform}" \
      --arg build_from "${image}" \
      '{arch: $arch, platform: $platform, build_from: $build_from}'
  )")
done < "${build_config}"

if (( ${#matrix_entries[@]} == 0 )); then
  echo "No build_from entries found in ${build_config}" >&2
  exit 1
fi

printf '%s\n' "${matrix_entries[@]}" \
  | jq --compact-output --slurp '{include: .}'
