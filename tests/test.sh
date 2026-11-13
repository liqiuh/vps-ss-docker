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

parse_yaml_password() {
  if python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 -c 'import sys,yaml; print(yaml.safe_load(sys.stdin.read())[0]["password"])'
  elif command -v ruby >/dev/null 2>&1; then
    ruby -ryaml -e 'print YAML.safe_load(STDIN.read).fetch(0).fetch("password")'
  else
    test_fail "PyYAML or Ruby is required for YAML parsing tests"
  fi
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

repo_version="$(<"${ROOT}/VERSION")"
assert_eq "$VERSION" "$repo_version"
assert_eq "$DEFAULT_SS_IMAGE" "ghcr.io/liqiuh/vps-ss-docker:${repo_version}"
grep -Fq "ARG IMAGE_VERSION=${repo_version}" "${ROOT}/Dockerfile" || {
  test_fail "Dockerfile image version is out of sync"
}

valid_ipv4 107.175.213.56 || test_fail "valid IPv4 rejected"
! valid_ipv4 999.1.1.1 || test_fail "invalid IPv4 accepted"
valid_public_ipv4 1.1.1.1 || test_fail "public IPv4 rejected"
for private_ip in 10.0.0.1 100.64.0.1 127.0.0.1 169.254.1.1 172.16.0.1 192.168.1.1 203.0.113.10; do
  ! valid_public_ipv4 "$private_ip" || test_fail "non-public IPv4 accepted: $private_ip"
done
valid_endpoint_host example.com || test_fail "public hostname rejected"
! valid_endpoint_host 10.0.0.1 || test_fail "private IPv4 accepted as a hostname"
! valid_endpoint_host 999.1.1.1 || test_fail "invalid numeric host accepted"
valid_hostname origin.example.com || test_fail "valid hostname rejected"
! valid_hostname bad..example.com || test_fail "invalid hostname accepted"
valid_worker_name worker-name || test_fail "valid Worker name rejected"
! valid_worker_name worker- || test_fail "trailing hyphen accepted"
valid_ws_path /ws-test_1 || test_fail "valid WebSocket path rejected"
valid_origin_token abcdefghijklmnop || test_fail "valid origin token rejected"
valid_ss_password 'custom-pass_123!' || test_fail "valid password rejected"
! valid_ss_password 'short' || test_fail "short password accepted"
! valid_ss_password 'contains space' || test_fail "password with spaces accepted"

curl() { return 1; }
hostname() { [[ "${1:-}" == "-I" ]] && printf '10.0.0.1 1.1.1.1\n'; }
assert_eq "$(detect_public_ipv4)" "1.1.1.1"
unset -f curl hostname

MODE="direct"
DIRECT_PORT="8388"
SS_PASSWORD=""
prompt_install_options <<< $'24443\ncustom-pass_123!\n' >/dev/null
assert_eq "$DIRECT_PORT" "24443"
assert_eq "$SS_PASSWORD" "custom-pass_123!"

MODE="cloudflare"
ORIGIN_PORT="18080"
SS_PASSWORD="existing-password"
prompt_install_options <<< $'\n\n' >/dev/null
assert_eq "$ORIGIN_PORT" "18080"
assert_eq "$SS_PASSWORD" "existing-password"

SS_IMAGE="$DEFAULT_SS_IMAGE"
FALLBACK_SS_IMAGE=""
BUILD_LOCAL="0"
docker() { return 1; }
if (prepare_image >/dev/null 2>&1); then
  test_fail "default image failure unexpectedly succeeded without fallback"
fi
unset -f docker

SS_IMAGE="$DEFAULT_SS_IMAGE"
FALLBACK_SS_IMAGE="docker.io/example/private-vps-ss:${repo_version}"
docker() {
  [[ "$1" == "pull" ]] || return 1
  [[ "$2" == "$FALLBACK_SS_IMAGE" ]]
}
prepare_image >/dev/null
assert_eq "$SS_IMAGE" "$FALLBACK_SS_IMAGE"
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
SS_IMAGE="local/vps-ss:${repo_version}"
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

grep -q 'max-size: "10m"' "$COMPOSE_FILE" || test_fail "log rotation missing"
grep -q 'healthcheck:' "$COMPOSE_FILE" || test_fail "healthcheck missing"

allowed_password_chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~!@%+=,:/-'
for ((index = 0; index < ${#allowed_password_chars}; index++)); do
  password="${allowed_password_chars:index:1}Abcdefg"
  yaml_output="$(
    require_install() { :; }
    load_settings() { :; }
    MODE="direct"
    DIRECT_HOST="example.com"
    DIRECT_PORT="8388"
    CIPHER="chacha20-ietf-poly1305"
    SS_PASSWORD="$password"
    show_clash
  )"
  decoded_password="$(parse_yaml_password <<<"$yaml_output")"
  assert_eq "$decoded_password" "$password"
done

if (
  require_install() { :; }
  load_settings() { MODE="direct"; DIRECT_PORT="9"; }
  docker() { :; }
  compose() { :; }
  container_health_status() { printf 'healthy'; }
  timeout() { return 1; }
  show_status >/dev/null 2>&1
); then
  test_fail "status returned success for a failed direct probe"
fi

if (
  require_install() { :; }
  load_settings() { MODE="direct"; DIRECT_PORT="9"; }
  docker() { :; }
  compose() { :; }
  container_health_status() { printf 'unhealthy'; }
  timeout() { return 0; }
  show_status >/dev/null 2>&1
); then
  test_fail "status returned success for an unhealthy expected container"
fi

if (
  require_install() { :; }
  load_settings() {
    MODE="cloudflare"
    CF_PUBLIC_HOST=""
    ORIGIN_PORT="18080"
    WS_PATH="/test"
    ORIGIN_TOKEN="0123456789abcdef"
  }
  docker() { :; }
  compose() { :; }
  container_health_status() { printf 'healthy'; }
  probe_websocket() { return 0; }
  show_status >/dev/null 2>&1
); then
  test_fail "status returned success without a Cloudflare Worker"
fi

state_dir="${tmp}/state"
mkdir -p "$state_dir"
STATE_FILE="${state_dir}/state.json"
state_init
state_add_rule ufw 18080 tcp
state_rule_managed ufw 18080 tcp || test_fail "managed firewall rule was not recorded"
state_add_rule firewalld 8388 udp
state_rule_managed firewalld 8388 udp || test_fail "second firewall backend was not recorded"
state_remove_rule ufw 18080 tcp
! state_rule_managed ufw 18080 tcp || test_fail "managed firewall rule was not removed"
state_rule_managed firewalld 8388 udp || test_fail "removing one backend removed another backend's rule"

if (
  detect_firewall_backend() { printf 'ufw'; }
  firewall_rule_exists() { return 1; }
  firewall_rule_add() { return 1; }
  state_add_rule() { test_fail "failed firewall rule was recorded"; }
  open_firewall_port 18080 tcp >/dev/null 2>&1
); then
  test_fail "firewall add failure was reported as success"
fi

if (
  ss() { printf 'LISTEN 0 128 0.0.0.0:18080 0.0.0.0:*\n'; }
  docker() { printf '[]\n'; }
  assert_host_port_available 18080 tcp >/dev/null 2>&1
); then
  test_fail "occupied host port was accepted"
fi

if (
  ss() { :; }
  docker() {
    case "$1" in
      ps) printf 'other-service\n' ;;
      inspect)
        printf '[{"NetworkSettings":{"Ports":{"8080/tcp":[{"HostPort":"18080"}]}}}]\n'
        ;;
    esac
  }
  assert_host_port_available 18080 tcp >/dev/null 2>&1
); then
  test_fail "Docker port mapping without an ss listener was accepted"
fi

(
  ss() { printf 'LISTEN 0 128 0.0.0.0:18080 0.0.0.0:*\n'; }
  docker() {
    case "$1" in
      ps) printf '%s\n' "$ORIGIN_CONTAINER_NAME" ;;
      inspect)
        printf '[{"NetworkSettings":{"Ports":{"8080/tcp":[{"HostPort":"18080"}]}}}]\n'
        ;;
    esac
  }
  assert_host_port_available 18080 tcp >/dev/null 2>&1
) || test_fail "current vps-ss Docker port mapping was rejected"


existing_dir="${tmp}/existing"
mkdir -p "$existing_dir"
cat > "${existing_dir}/.env" <<'EOF'
MODE=cloudflare
SS_IMAGE=local/vps-ss:1.2.1
BUILD_LOCAL=1
SS_PASSWORD=existing-password
CIPHER=chacha20-ietf-poly1305
WS_PATH=/existing
ORIGIN_TOKEN=0123456789abcdef0123456789abcdef
PUBLIC_IP=1.1.1.1
DIRECT_HOST=1.1.1.1
DIRECT_PORT=8388
ORIGIN_HOST=1-1-1-1.sslip.io
ORIGIN_PORT=8080
CF_ACCOUNT_ID=
CF_SCRIPT_NAME=
CF_WORKERS_SUBDOMAIN=
CF_PUBLIC_HOST=
CF_PREP_FILE=
EOF
: > "${existing_dir}/compose.yaml"
printf 'unchanged\n' > "${existing_dir}/marker"
(
  INSTALL_DIR="$existing_dir"
  SETTINGS_FILE="${existing_dir}/.env"
  STATE_FILE="${existing_dir}/state.json"
  COMPOSE_FILE="${existing_dir}/compose.yaml"
  CONFIG_FILE="${existing_dir}/config.json"
  NGINX_FILE="${existing_dir}/nginx.conf.template"
  WORKER_FILE="${existing_dir}/worker.js"
  ORIGIN_PORT="18080"
  load_settings
  assert_eq "$ORIGIN_PORT" "8080"
  require_root() { :; }
  ensure_packages() { :; }
  load_cloudflare_prep() { return 1; }
  ss() { printf 'LISTEN 0 128 0.0.0.0:8080 0.0.0.0:*\n'; }
  docker() { printf '[]\n'; }
  install_mode cloudflare >/dev/null 2>&1
) && test_fail "install continued despite a conflicting existing port"
assert_eq "$(<"${existing_dir}/marker")" "unchanged"
[[ ! -e "${existing_dir}/config.json" ]] || test_fail "port conflict modified the existing deployment"

rollback_root="${tmp}/rollback"
INSTALL_DIR="${rollback_root}/install"
SETTINGS_FILE="${INSTALL_DIR}/.env"
STATE_FILE="${INSTALL_DIR}/state.json"
COMPOSE_FILE="${INSTALL_DIR}/compose.yaml"
backup_dir="${rollback_root}/backup"
MANAGER_PATH="${rollback_root}/vps-ss-manager"
mkdir -p "$INSTALL_DIR" "${backup_dir}/install"
printf 'new\n' > "${INSTALL_DIR}/marker"
printf 'old\n' > "${backup_dir}/install/marker"
printf 'new-manager\n' > "$MANAGER_PATH"
printf 'old-manager\n' > "${backup_dir}/manager"
printf 'present\n' > "${backup_dir}/manager-state"
(
  compose() { :; }
  rollback_new_firewall_rules() { :; }
  rollback_install_tree "$backup_dir" 1 >/dev/null 2>&1
)
assert_eq "$(<"${INSTALL_DIR}/marker")" "old"
assert_eq "$(<"$MANAGER_PATH")" "old-manager"

(
  require_root() { :; }
  require_install() { :; }
  load_settings() { :; }
  load_cloudflare_prep() { return 1; }
  api_token_value() { printf 'dummy-token-0123456789abcdefghijklmnop'; }
  save_settings() { :; }
  cf_request() {
    case "$3" in
      /user/tokens/verify) printf '{"success":true,"result":{"status":"active"}}' ;;
      *) printf '{"success":true,"result":{}}' ;;
    esac
  }
  CF_ACCOUNT_ID="0123456789abcdef0123456789abcdef"
  CF_SCRIPT_NAME="vps-ss-test"
  CF_PUBLIC_HOST="vps-ss-test.example.workers.dev"
  delete_cloudflare_worker >/dev/null
  [[ -z "$CF_SCRIPT_NAME" && -z "$CF_PUBLIC_HOST" ]]
) || test_fail "Cloudflare Worker deletion did not clear saved identity"

uninstall_dir="${tmp}/uninstall"
mkdir -p "$uninstall_dir"
printf 'MODE=direct\nCF_SCRIPT_NAME=\n' > "${uninstall_dir}/.env"
: > "${uninstall_dir}/compose.yaml"
manager_path="${tmp}/vps-ss-manager"
: > "$manager_path"
(
  INSTALL_DIR="$uninstall_dir"
  SETTINGS_FILE="${uninstall_dir}/.env"
  STATE_FILE="${uninstall_dir}/state.json"
  COMPOSE_FILE="${uninstall_dir}/compose.yaml"
  MANAGER_PATH="$manager_path"
  require_root() { :; }
  compose() { :; }
  remove_all_managed_firewall_rules() { :; }
  uninstall_service --yes >/dev/null
)
[[ ! -e "$uninstall_dir" && ! -e "$manager_path" ]] || test_fail "uninstall left local files behind"

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
