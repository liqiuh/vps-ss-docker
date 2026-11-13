#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(<"${ROOT}/VERSION")"

require_text() {
  local file="$1" text="$2"
  grep -Fq -- "$text" "${ROOT}/${file}" || {
    printf 'Version check failed: %s does not contain %s\n' "$file" "$text" >&2
    exit 1
  }
}

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  printf 'Invalid VERSION value: %s\n' "$VERSION" >&2
  exit 1
}

require_text vps-ss.sh "VERSION=\"${VERSION}\""
require_text vps-ss.sh "DEFAULT_SS_IMAGE=\"ghcr.io/liqiuh/vps-ss-docker:${VERSION}\""
require_text Dockerfile "ARG IMAGE_VERSION=${VERSION}"
# shellcheck disable=SC2016 # The Make expression must remain literal.
require_text Makefile 'VERSION := $(shell cat VERSION)'
require_text README.md "ghcr.io/liqiuh/vps-ss-docker:${VERSION}"
require_text README.md "--build-arg IMAGE_VERSION=${VERSION}"
require_text RELEASING.md "git tag -a v${VERSION}"
require_text CHANGELOG.md "## ${VERSION} -"
# shellcheck disable=SC2016 # These test expressions must remain literal.
require_text tests/test.sh 'repo_version="$(<"${ROOT}/VERSION")"'
# shellcheck disable=SC2016 # These test expressions must remain literal.
require_text tests/integration.sh 'VERSION="$(<"${ROOT}/VERSION")"'

printf 'Version references are consistent: %s\n' "$VERSION"
