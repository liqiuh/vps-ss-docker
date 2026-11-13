#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2329
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/vps-ss.sh"
IMAGE="${IMAGE:-local/vps-ss:1.2.0-test}"
PROJECT_SUFFIX="${RANDOM}-$$"
CF_PROJECT="vps-ss-cf-${PROJECT_SUFFIX}"
DIRECT_PROJECT="vps-ss-direct-${PROJECT_SUFFIX}"
CF_CONTAINER="vps-ss-cf-${PROJECT_SUFFIX}"
ORIGIN_CONTAINER="vps-ss-origin-${PROJECT_SUFFIX}"
DIRECT_CONTAINER="vps-ss-direct-${PROJECT_SUFFIX}"
tmp="$(mktemp -d)"

free_port() {
  python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

cleanup() {
  docker rm -f "$CF_CONTAINER" "$ORIGIN_CONTAINER" "$DIRECT_CONTAINER" >/dev/null 2>&1 || true
  docker network rm "${CF_PROJECT}_default" "${DIRECT_PROJECT}_default" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

for command in docker curl jq python3; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$command" >&2
    exit 1
  }
done
docker info >/dev/null
docker compose version >/dev/null

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  docker build --pull -t "$IMAGE" "$ROOT"
fi

render_mode() {
  local mode="$1" dir="$2" host_port="$3" container="$4" origin_container="$5"
  mkdir -p "$dir"
  (
    chown() { :; }
    INSTALL_DIR="$dir"
    SETTINGS_FILE="${dir}/.env"
    COMPOSE_FILE="${dir}/compose.yaml"
    CONFIG_FILE="${dir}/config.json"
    NGINX_FILE="${dir}/nginx.conf.template"
    WORKER_FILE="${dir}/worker.js"
    MODE="$mode"
    SS_IMAGE="$IMAGE"
    SS_PASSWORD="integration-password"
    CIPHER="chacha20-ietf-poly1305"
    WS_PATH="/integration-ws"
    ORIGIN_TOKEN="0123456789abcdef0123456789abcdef"
    DIRECT_PORT="$host_port"
    ORIGIN_PORT="$host_port"
    CONTAINER_NAME="$container"
    ORIGIN_CONTAINER_NAME="$origin_container"
    VPS_SS_NO_MAIN=1
    # shellcheck source=../vps-ss.sh
    source "$SCRIPT"
    save_settings
    write_server_config
    if [[ "$mode" == "cloudflare" ]]; then
      write_nginx_config
      write_worker
    fi
    write_compose
  )

  docker run --rm -v "${dir}:/data" alpine:3.22 sh -c '
    chown 65534:65534 /data/config.json
    chmod 0600 /data/config.json
    if [ -f /data/nginx.conf.template ]; then
      chmod 0644 /data/nginx.conf.template
    fi
  '
}

cf_port="$(free_port)"
direct_port="$(free_port)"
render_mode cloudflare "${tmp}/cloudflare" "$cf_port" "$CF_CONTAINER" "$ORIGIN_CONTAINER"
render_mode direct "${tmp}/direct" "$direct_port" "$DIRECT_CONTAINER" "unused-${PROJECT_SUFFIX}"

docker compose -p "$CF_PROJECT" -f "${tmp}/cloudflare/compose.yaml" config >/dev/null
docker compose -p "$DIRECT_PROJECT" -f "${tmp}/direct/compose.yaml" config >/dev/null
docker compose -p "$CF_PROJECT" -f "${tmp}/cloudflare/compose.yaml" up -d
docker compose -p "$DIRECT_PROJECT" -f "${tmp}/direct/compose.yaml" up -d

cf_ok=0
for _ in $(seq 1 30); do
  response="$(curl --http1.1 -isS --max-time 3 \
    -H 'Connection: Upgrade' \
    -H 'Upgrade: websocket' \
    -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
    -H 'X-Origin-Token: 0123456789abcdef0123456789abcdef' \
    "http://127.0.0.1:${cf_port}/integration-ws" 2>/dev/null || true)"
  first_line="$(printf '%s\n' "$response" | sed -n '1{s/\r$//;p;}')"
  if [[ "$first_line" == *" 101 "* ]]; then
    cf_ok=1
    break
  fi
  sleep 1
done

if [[ "$cf_ok" != "1" ]]; then
  docker compose -p "$CF_PROJECT" -f "${tmp}/cloudflare/compose.yaml" logs >&2
  printf 'Cloudflare-origin WebSocket integration test failed.\n' >&2
  exit 1
fi

direct_ok=0
for _ in $(seq 1 30); do
  if python3 - "$direct_port" <<'PY'
import socket
import sys
try:
    with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=1):
        pass
except OSError:
    raise SystemExit(1)
PY
  then
    direct_ok=1
    break
  fi
  sleep 1
done

if [[ "$direct_ok" != "1" ]]; then
  docker compose -p "$DIRECT_PROJECT" -f "${tmp}/direct/compose.yaml" logs >&2
  printf 'Direct TCP integration test failed.\n' >&2
  exit 1
fi

printf 'Cloudflare-origin and direct-mode integration tests passed.\n'
