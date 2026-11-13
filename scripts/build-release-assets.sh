#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-$(<"${ROOT}/VERSION")}"
IMAGE_DIGEST="${2:-}"
OUTPUT_DIR="${3:-${ROOT}/dist}"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  printf 'Invalid version: %s\n' "$VERSION" >&2
  exit 1
}
[[ "$IMAGE_DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]] || {
  printf 'Expected a sha256 image digest.\n' >&2
  exit 1
}

install -d "$OUTPUT_DIR"
sed \
  "s|DEFAULT_SS_IMAGE=\"ghcr.io/liqiuh/vps-ss-docker:${VERSION}\"|DEFAULT_SS_IMAGE=\"ghcr.io/liqiuh/vps-ss-docker:${VERSION}@${IMAGE_DIGEST}\"|" \
  "${ROOT}/vps-ss.sh" > "${OUTPUT_DIR}/vps-ss.sh"
chmod 0755 "${OUTPUT_DIR}/vps-ss.sh"

grep -Fq "DEFAULT_SS_IMAGE=\"ghcr.io/liqiuh/vps-ss-docker:${VERSION}@${IMAGE_DIGEST}\"" \
  "${OUTPUT_DIR}/vps-ss.sh" || {
    printf 'Failed to inject the immutable image digest.\n' >&2
    exit 1
  }

tar -C "${ROOT}/skills" -czf "${OUTPUT_DIR}/cloudflare-vps-prep-skill.tar.gz" cloudflare-vps-prep

(
  cd "$OUTPUT_DIR"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum vps-ss.sh cloudflare-vps-prep-skill.tar.gz > SHA256SUMS
  else
    shasum -a 256 vps-ss.sh cloudflare-vps-prep-skill.tar.gz > SHA256SUMS
  fi
)

printf 'Release assets created in %s\n' "$OUTPUT_DIR"
