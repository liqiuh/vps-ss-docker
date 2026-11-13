#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2329
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/vps-ss.sh"

test_fail() {
  printf 'TEST FAILED: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  [[ "$1" == "$2" ]] || test_fail "expected '$2', got '$1'"
}

file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

bash -n "$SCRIPT"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$SCRIPT"
fi

export VPS_SS_NO_MAIN=1
# shellcheck source=../vps-ss.sh
source "$SCRIPT"

valid_ipv4 107.175.213.56 || test_fail "valid IPv4 rejected"
! valid_ipv4 999.1.1.1 || test_fail "invalid IPv4 accepted"
valid_hostname origin.example.com || test_fail "valid hostname rejected"
! valid_hostname bad..example.com || test_fail "invalid hostname accepted"
valid_worker_name worker-name || test_fail "valid Worker name rejected"
! valid_worker_name worker- || test_fail "trailing hyphen accepted"
valid_ws_path /ws-test_1 || test_fail "valid WebSocket path rejected"
valid_origin_token abcdefghijklmnop || test_fail "valid origin token rejected"
valid_ss_password 'custom-pass_123!' || test_fail "valid password rejected"
! valid_ss_password 'short' || test_fail "short password accepted"
! valid_ss_password 'contains space' || test_fail "password with spaces accepted"

MODE="direct"
DIRECT_PORT="8388"
SS_PASSWORD=""
prompt_install_options <<< $'24443\ncustom-pass_123!\n' >/dev/null
assert_eq "$DIRECT_PORT" "24443"
assert_eq "$SS_PASSWORD" "custom-pass_123!"

MODE="cloudflare"
ORIGIN_PORT="8080"
SS_PASSWORD="existing-password"
prompt_install_options <<< $'\n\n' >/dev/null
assert_eq "$ORIGIN_PORT" "8080"
assert_eq "$SS_PASSWORD" "existing-password"

SS_IMAGE="$DEFAULT_SS_IMAGE"
FALLBACK_SS_IMAGE="$DEFAULT_FALLBACK_SS_IMAGE"
BUILD_LOCAL="0"
docker() {
  [[ "$1" == "pull" ]] || return 1
  [[ "$2" == "$FALLBACK_SS_IMAGE" ]]
}
prepare_image >/dev/null
assert_eq "$SS_IMAGE" "$DEFAULT_FALLBACK_SS_IMAGE"
unset -f docker

prep="${tmp}/cloudflare-vps-prep.json"
jq -n '{
  schema: "vps-ss-cloudflare-prep/v1",
  cloudflare: {
    account_id: "0123456789abcdef0123456789abcdef",
    workers_subdomain: "test-workers",
    api_token: "dummy-token-0123456789abcdefghijklmnop"
  },
  metadata: {created_at: "2026-11-13T00:00:00Z", created_by: "test"}
}' > "$prep"
chmod 0600 "$prep"

CF_PREP_FILE=""
CF_ACCOUNT_ID=""
CF_WORKERS_SUBDOMAIN=""
CF_API_TOKEN=""
load_cloudflare_prep "$prep" >/dev/null
assert_eq "$CF_ACCOUNT_ID" "0123456789abcdef0123456789abcdef"
assert_eq "$CF_WORKERS_SUBDOMAIN" "test-workers"
assert_eq "$(mask_secret "$CF_API_TOKEN")" "dumm...mnop"
assert_eq "$(file_mode "$prep")" "600"

INSTALL_DIR="${tmp}/install"
SETTINGS_FILE="${INSTALL_DIR}/.env"
COMPOSE_FILE="${INSTALL_DIR}/compose.yaml"
CONFIG_FILE="${INSTALL_DIR}/config.json"
NGINX_FILE="${INSTALL_DIR}/nginx.conf.template"
WORKER_FILE="${INSTALL_DIR}/worker.js"
MODE="cloudflare"
SS_IMAGE="local/vps-ss:1.2.0"
BUILD_LOCAL="1"
SS_PASSWORD="Aa1._~!@%+=,:/-"
CIPHER="chacha20-ietf-poly1305"
WS_PATH="/test-path"
ORIGIN_TOKEN="0123456789abcdef0123456789abcdef"
PUBLIC_IP="203.0.113.10"
DIRECT_HOST="$PUBLIC_IP"
DIRECT_PORT="18388"
ORIGIN_HOST="203-0-113-10.sslip.io"
ORIGIN_PORT="18080"
CF_SCRIPT_NAME="vps-ss-test"
CF_PUBLIC_HOST="vps-ss-test.test-workers.workers.dev"
mkdir -p "$INSTALL_DIR"

save_settings
! grep -q 'dummy-token-0123456789abcdefghijklmnop' "$SETTINGS_FILE" || {
  test_fail "Cloudflare API token leaked into settings"
}
assert_eq "$(file_mode "$SETTINGS_FILE")" "600"

write_dockerfile
cmp "$ROOT/Dockerfile" "$INSTALL_DIR/Dockerfile"

chown() { :; }
write_server_config
write_nginx_config
write_worker
write_compose
unset -f chown

assert_eq "$(jq -r '.password' "$CONFIG_FILE")" "$SS_PASSWORD"

if command -v node >/dev/null 2>&1; then
  node --input-type=module --check < "$WORKER_FILE"
fi

assert_eq "$(file_mode "$CONFIG_FILE")" "600"
assert_eq "$(file_mode "$NGINX_FILE")" "644"
! grep -q "$ORIGIN_TOKEN" "$NGINX_FILE" || test_fail "origin token leaked into Nginx template"
grep -Fq "\${ORIGIN_TOKEN}" "$NGINX_FILE" || test_fail "Nginx template token placeholder missing"
grep -q 'user: "101:101"' "$COMPOSE_FILE" || test_fail "Nginx user not pinned"
[[ "$(grep -c "image: ${SS_IMAGE}" "$COMPOSE_FILE")" -eq 2 ]] || {
  test_fail "Cloudflare services are not using the same release image"
}
grep -Fq "\$\${ORIGIN_TOKEN}" "$COMPOSE_FILE" || {
  test_fail "Nginx token substitution command missing"
}
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  docker compose -f "$COMPOSE_FILE" config >/dev/null
fi

deploy_dir="${tmp}/deploy-failure"
mkdir -p "$deploy_dir"
WORKER_FILE="${deploy_dir}/worker.js"
printf 'export default {};\n' > "$WORKER_FILE"
MODE="cloudflare"
CF_ACCOUNT_ID="0123456789abcdef0123456789abcdef"
CF_SCRIPT_NAME="vps-ss-test"
CF_WORKERS_SUBDOMAIN="test-workers"
PUBLIC_IP="203.0.113.10"
ORIGIN_HOST="203-0-113-10.sslip.io"
ORIGIN_PORT="18080"
WS_PATH="/test-path"
ORIGIN_TOKEN="0123456789abcdef0123456789abcdef"

require_root() { :; }
require_install() { :; }
load_settings() { :; }
load_cloudflare_prep() { return 1; }
api_token_value() { printf 'dummy-token-0123456789abcdefghijklmnop'; }
save_settings() { :; }
cf_request() {
  case "$3" in
    /user/tokens/verify) printf '{"success":true,"result":{"status":"active"}}' ;;
    */workers/subdomain) printf '{"success":true,"result":{"subdomain":"test-workers"}}' ;;
    *) printf '{"success":true,"result":{}}' ;;
  esac
}
curl() { printf '{"success":false,"errors":[{"message":"test failure"}]}'; }
mktemp() {
  local target
  if [[ ! -e "${deploy_dir}/metadata.tmp" ]]; then
    target="${deploy_dir}/metadata.tmp"
  else
    target="${deploy_dir}/response.tmp"
  fi
  : > "$target"
  chmod 0600 "$target"
  printf '%s' "$target"
}

if (deploy_cloudflare_worker >/dev/null 2>&1); then
  test_fail "mocked Cloudflare upload unexpectedly succeeded"
fi
[[ ! -e "${deploy_dir}/metadata.tmp" && ! -e "${deploy_dir}/response.tmp" ]] || {
  test_fail "Cloudflare temporary files were not cleaned after failure"
}

printf 'All unit tests passed.\n'
