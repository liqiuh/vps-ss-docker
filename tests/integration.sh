#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2329
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/vps-ss.sh"
VERSION="$(<"${ROOT}/VERSION")"
IMAGE="${IMAGE:-local/vps-ss:${VERSION}}"
CLIENT_IMAGE="${CLIENT_IMAGE:-local/vps-ss-client:${VERSION}}"
PROJECT_SUFFIX="${RANDOM}-$$"
CF_PROJECT="vps-ss-cf-${PROJECT_SUFFIX}"
DIRECT_PROJECT="vps-ss-direct-${PROJECT_SUFFIX}"
CF_CONTAINER="vps-ss-cf-${PROJECT_SUFFIX}"
ORIGIN_CONTAINER="vps-ss-origin-${PROJECT_SUFFIX}"
CF_WORKER_CONTAINER="vps-ss-worker-${PROJECT_SUFFIX}"
DIRECT_CONTAINER="vps-ss-direct-${PROJECT_SUFFIX}"
CF_CLIENT="vps-ss-cf-client-${PROJECT_SUFFIX}"
DIRECT_CLIENT="vps-ss-direct-client-${PROJECT_SUFFIX}"
FIXTURE_CONTAINER="vps-ss-fixture-${PROJECT_SUFFIX}"
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
  docker rm -f \
    "$CF_CLIENT" "$DIRECT_CLIENT" "$FIXTURE_CONTAINER" \
    "$CF_CONTAINER" "$ORIGIN_CONTAINER" "$CF_WORKER_CONTAINER" \
    "$DIRECT_CONTAINER" >/dev/null 2>&1 || true
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
  docker build --pull --target client -t "$CLIENT_IMAGE" "$ROOT"
fi

render_mode() {
  local mode="$1" dir="$2" host_port="$3" container="$4" origin_container="$5"
  mkdir -p "$dir"
  (
    chown() { :; }
    INSTALL_DIR="$dir"
    SETTINGS_FILE="${dir}/.env"
    STATE_FILE="${dir}/state.json"
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

  docker run --rm --user 0:0 --entrypoint sh -v "${dir}:/data" "$IMAGE" -c '
    chown 65534:65534 /data/config.json
    chmod 0600 /data/config.json
    if [ -f /data/nginx.conf.template ]; then
      chmod 0644 /data/nginx.conf.template
    fi
  '
}

wait_for_http_proxy() {
  local socks_port="$1" label="$2" attempt body
  for attempt in $(seq 1 30); do
    body="$(curl -fsS --max-time 3 --socks5-hostname "127.0.0.1:${socks_port}" \
      "http://${FIXTURE_CONTAINER}:18081/health" 2>/dev/null || true)"
    if [[ "$body" == "vps-ss-integration-ok" ]]; then
      printf '%s HTTP proxy: OK\n' "$label"
      return 0
    fi
    sleep 1
  done
  return 1
}

test_socks5_udp() {
  local socks_port="$1"
  python3 - "$socks_port" "$FIXTURE_CONTAINER" <<'PY'
import socket
import struct
import sys

socks_port = int(sys.argv[1])
target_host = sys.argv[2].encode()
payload = b"vps-ss-udp-ok"

with socket.create_connection(("127.0.0.1", socks_port), timeout=5) as control:
    control.sendall(b"\x05\x01\x00")
    if control.recv(2) != b"\x05\x00":
        raise SystemExit("SOCKS5 authentication negotiation failed")

    control.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
    response = control.recv(32)
    if len(response) < 4 or response[1] != 0:
        raise SystemExit("SOCKS5 UDP associate failed")

    request = (
        b"\x00\x00\x00\x03"
        + bytes([len(target_host)])
        + target_host
        + struct.pack("!H", 19090)
        + payload
    )
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        udp.settimeout(5)
        udp.sendto(request, ("127.0.0.1", socks_port))
        response, _ = udp.recvfrom(65535)
        if not response.endswith(payload):
            raise SystemExit("SOCKS5 UDP payload mismatch")
PY
}

cf_port="$(free_port)"
direct_port="$(free_port)"
cf_socks_port="$(free_port)"
direct_socks_port="$(free_port)"
render_mode cloudflare "${tmp}/cloudflare" "$cf_port" "$CF_CONTAINER" "$ORIGIN_CONTAINER"
render_mode direct "${tmp}/direct" "$direct_port" "$DIRECT_CONTAINER" "unused-${PROJECT_SUFFIX}"

docker compose -p "$CF_PROJECT" -f "${tmp}/cloudflare/compose.yaml" config >/dev/null
docker compose -p "$DIRECT_PROJECT" -f "${tmp}/direct/compose.yaml" config >/dev/null
docker compose -p "$CF_PROJECT" -f "${tmp}/cloudflare/compose.yaml" up -d --wait --wait-timeout 60
docker compose -p "$DIRECT_PROJECT" -f "${tmp}/direct/compose.yaml" up -d --wait --wait-timeout 60

cat > "${tmp}/fixture-nginx.conf" <<'EOF'
worker_processes 1;
error_log /dev/stderr warn;
pid /tmp/nginx.pid;
events { worker_connections 128; }
http {
  access_log off;
  proxy_temp_path /tmp/proxy_temp;
  client_body_temp_path /tmp/client_temp;
  fastcgi_temp_path /tmp/fastcgi_temp;
  uwsgi_temp_path /tmp/uwsgi_temp;
  scgi_temp_path /tmp/scgi_temp;
  server {
    listen 18081;
    location = /health {
      default_type text/plain;
      return 200 "vps-ss-integration-ok";
    }
  }
}
EOF

cat > "${tmp}/worker-nginx.conf" <<EOF
worker_processes 1;
error_log /dev/stderr warn;
pid /tmp/nginx.pid;
events { worker_connections 128; }
http {
  access_log /dev/stdout;
  proxy_temp_path /tmp/proxy_temp;
  client_body_temp_path /tmp/client_temp;
  fastcgi_temp_path /tmp/fastcgi_temp;
  uwsgi_temp_path /tmp/uwsgi_temp;
  scgi_temp_path /tmp/scgi_temp;
  map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
  }
  server {
    listen 18082;
    location = /integration-ws {
      proxy_pass http://${ORIGIN_CONTAINER}:8080;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$connection_upgrade;
      proxy_set_header Host \$host;
      proxy_set_header X-Origin-Token 0123456789abcdef0123456789abcdef;
      proxy_buffering off;
    }
  }
}
EOF

docker run -d --name "$FIXTURE_CONTAINER" \
  --network "${CF_PROJECT}_default" \
  -v "${tmp}/fixture-nginx.conf:/etc/nginx-fixture.conf:ro" \
  --entrypoint sh "$IMAGE" -ec '
    nginx -c /etc/nginx-fixture.conf
    exec nc -u -lk -p 19090 -e /bin/cat
  ' >/dev/null
docker network connect "${DIRECT_PROJECT}_default" "$FIXTURE_CONTAINER"

docker run -d --name "$CF_WORKER_CONTAINER" \
  --network "${CF_PROJECT}_default" \
  -v "${tmp}/worker-nginx.conf:/etc/nginx-worker.conf:ro" \
  --entrypoint nginx "$IMAGE" -c /etc/nginx-worker.conf -g 'daemon off;' >/dev/null

docker run -d --name "$DIRECT_CLIENT" \
  --network "${DIRECT_PROJECT}_default" \
  -p "127.0.0.1:${direct_socks_port}:1080/tcp" \
  -p "127.0.0.1:${direct_socks_port}:1080/udp" \
  "$CLIENT_IMAGE" \
  sslocal --log-without-time -U -b 0.0.0.0:1080 \
  -s "${DIRECT_CONTAINER}:8388" -k integration-password -m chacha20-ietf-poly1305 >/dev/null

docker run -d --name "$CF_CLIENT" \
  --network "${CF_PROJECT}_default" \
  -p "127.0.0.1:${cf_socks_port}:1080/tcp" \
  "$CLIENT_IMAGE" \
  sslocal --log-without-time -b 0.0.0.0:1080 \
  -s "${CF_WORKER_CONTAINER}:18082" -k integration-password -m chacha20-ietf-poly1305 \
  --plugin /usr/local/bin/v2ray-plugin \
  --plugin-opts "host=${CF_WORKER_CONTAINER};path=/integration-ws" >/dev/null

if ! wait_for_http_proxy "$direct_socks_port" "Direct"; then
  docker logs "$DIRECT_CLIENT" >&2 || true
  docker compose -p "$DIRECT_PROJECT" -f "${tmp}/direct/compose.yaml" logs >&2
  printf 'Direct Shadowsocks HTTP integration test failed.\n' >&2
  exit 1
fi

if ! wait_for_http_proxy "$cf_socks_port" "Cloudflare-origin"; then
  docker logs "$CF_CLIENT" >&2 || true
  docker compose -p "$CF_PROJECT" -f "${tmp}/cloudflare/compose.yaml" logs >&2
  printf 'Cloudflare-origin Shadowsocks HTTP integration test failed.\n' >&2
  exit 1
fi

test_socks5_udp "$direct_socks_port"
printf 'Direct UDP proxy: OK\n'
printf 'End-to-end Cloudflare-origin and direct-mode integration tests passed.\n'
