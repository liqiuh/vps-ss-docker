#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.2.0"
INSTALL_DIR="${INSTALL_DIR:-/opt/vps-ss}"
SETTINGS_FILE="${SETTINGS_FILE:-${INSTALL_DIR}/.env}"
COMPOSE_FILE="${COMPOSE_FILE:-${INSTALL_DIR}/compose.yaml}"
CONFIG_FILE="${CONFIG_FILE:-${INSTALL_DIR}/config.json}"
NGINX_FILE="${NGINX_FILE:-${INSTALL_DIR}/nginx.conf.template}"
WORKER_FILE="${WORKER_FILE:-${INSTALL_DIR}/worker.js}"
MANAGER_PATH="${MANAGER_PATH:-/usr/local/sbin/vps-ss}"
CONTAINER_NAME="${CONTAINER_NAME:-vps-ss}"
ORIGIN_CONTAINER_NAME="${ORIGIN_CONTAINER_NAME:-vps-ss-origin}"

OVERRIDE_MODE="${MODE-}"
OVERRIDE_SS_IMAGE="${SS_IMAGE-}"
OVERRIDE_BUILD_LOCAL="${BUILD_LOCAL-}"
OVERRIDE_SS_PASSWORD="${SS_PASSWORD-}"
OVERRIDE_CIPHER="${CIPHER-}"
OVERRIDE_WS_PATH="${WS_PATH-}"
OVERRIDE_ORIGIN_TOKEN="${ORIGIN_TOKEN-}"
OVERRIDE_PUBLIC_IP="${PUBLIC_IP-}"
OVERRIDE_DIRECT_HOST="${DIRECT_HOST-}"
OVERRIDE_DIRECT_PORT="${DIRECT_PORT-}"
OVERRIDE_ORIGIN_HOST="${ORIGIN_HOST-}"
OVERRIDE_ORIGIN_PORT="${ORIGIN_PORT-}"
OVERRIDE_CF_ACCOUNT_ID="${CF_ACCOUNT_ID-}"
OVERRIDE_CF_SCRIPT_NAME="${CF_SCRIPT_NAME-}"
OVERRIDE_CF_WORKERS_SUBDOMAIN="${CF_WORKERS_SUBDOMAIN-}"
OVERRIDE_CF_PUBLIC_HOST="${CF_PUBLIC_HOST-}"
OVERRIDE_CF_PREP_FILE="${CF_PREP_FILE-}"
OVERRIDE_CF_API_TOKEN="${CF_API_TOKEN-}"

MODE="${MODE:-}"
DEFAULT_SS_IMAGE="ghcr.io/liqiuh/vps-ss-docker:1.2.0"
DEFAULT_FALLBACK_SS_IMAGE="docker.io/macro1996/vps-ss:1.2.0"
SS_IMAGE="${SS_IMAGE:-$DEFAULT_SS_IMAGE}"
FALLBACK_SS_IMAGE="${FALLBACK_SS_IMAGE-$DEFAULT_FALLBACK_SS_IMAGE}"
BUILD_LOCAL="${BUILD_LOCAL:-}"
SS_PASSWORD="${SS_PASSWORD:-}"
CIPHER="${CIPHER:-chacha20-ietf-poly1305}"
WS_PATH="${WS_PATH:-}"
ORIGIN_TOKEN="${ORIGIN_TOKEN:-}"
PUBLIC_IP="${PUBLIC_IP:-}"
DIRECT_HOST="${DIRECT_HOST:-}"
DIRECT_PORT="${DIRECT_PORT:-8388}"
ORIGIN_HOST="${ORIGIN_HOST:-}"
ORIGIN_PORT="${ORIGIN_PORT:-8080}"
CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-}"
CF_SCRIPT_NAME="${CF_SCRIPT_NAME:-}"
CF_WORKERS_SUBDOMAIN="${CF_WORKERS_SUBDOMAIN:-}"
CF_PUBLIC_HOST="${CF_PUBLIC_HOST:-}"
CF_PREP_FILE="${CF_PREP_FILE:-}"
CF_API_TOKEN="${CF_API_TOKEN:-}"

if [[ -t 1 ]]; then
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  CYAN=$'\033[36m'
  NC=$'\033[0m'
else
  RED=""
  GREEN=""
  YELLOW=""
  CYAN=""
  NC=""
fi

info() { printf '%s\n' "${CYAN}$*${NC}"; }
ok() { printf '%s\n' "${GREEN}$*${NC}"; }
warn() { printf '%s\n' "${YELLOW}$*${NC}"; }
fail() { printf '%s\n' "${RED}$*${NC}" >&2; }
die() { fail "$*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "请使用 root 运行此命令。"
}

require_install() {
  [[ -f "$SETTINGS_FILE" && -f "$COMPOSE_FILE" ]] || {
    die "尚未安装。请先运行: $0 install cloudflare 或 $0 install direct"
  }
}

setting_get() {
  local key="$1"
  [[ -f "$SETTINGS_FILE" ]] || return 0
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$SETTINGS_FILE"
}

load_settings() {
  [[ -f "$SETTINGS_FILE" ]] || return 0
  local stored

  stored="$(setting_get MODE)"; MODE="${OVERRIDE_MODE:-${stored:-$MODE}}"
  stored="$(setting_get SS_IMAGE)"; SS_IMAGE="${OVERRIDE_SS_IMAGE:-${stored:-$SS_IMAGE}}"
  stored="$(setting_get BUILD_LOCAL)"; BUILD_LOCAL="${OVERRIDE_BUILD_LOCAL:-${stored:-$BUILD_LOCAL}}"
  stored="$(setting_get SS_PASSWORD)"; SS_PASSWORD="${OVERRIDE_SS_PASSWORD:-${stored:-$SS_PASSWORD}}"
  stored="$(setting_get CIPHER)"; CIPHER="${OVERRIDE_CIPHER:-${stored:-$CIPHER}}"
  stored="$(setting_get WS_PATH)"; WS_PATH="${OVERRIDE_WS_PATH:-${stored:-$WS_PATH}}"
  stored="$(setting_get ORIGIN_TOKEN)"; ORIGIN_TOKEN="${OVERRIDE_ORIGIN_TOKEN:-${stored:-$ORIGIN_TOKEN}}"
  stored="$(setting_get PUBLIC_IP)"; PUBLIC_IP="${OVERRIDE_PUBLIC_IP:-${stored:-$PUBLIC_IP}}"
  stored="$(setting_get DIRECT_HOST)"; DIRECT_HOST="${OVERRIDE_DIRECT_HOST:-${stored:-$DIRECT_HOST}}"
  stored="$(setting_get DIRECT_PORT)"; DIRECT_PORT="${OVERRIDE_DIRECT_PORT:-${stored:-$DIRECT_PORT}}"
  stored="$(setting_get ORIGIN_HOST)"; ORIGIN_HOST="${OVERRIDE_ORIGIN_HOST:-${stored:-$ORIGIN_HOST}}"
  stored="$(setting_get ORIGIN_PORT)"; ORIGIN_PORT="${OVERRIDE_ORIGIN_PORT:-${stored:-$ORIGIN_PORT}}"
  stored="$(setting_get CF_ACCOUNT_ID)"; CF_ACCOUNT_ID="${OVERRIDE_CF_ACCOUNT_ID:-${stored:-$CF_ACCOUNT_ID}}"
  stored="$(setting_get CF_SCRIPT_NAME)"; CF_SCRIPT_NAME="${OVERRIDE_CF_SCRIPT_NAME:-${stored:-$CF_SCRIPT_NAME}}"
  stored="$(setting_get CF_WORKERS_SUBDOMAIN)"; CF_WORKERS_SUBDOMAIN="${OVERRIDE_CF_WORKERS_SUBDOMAIN:-${stored:-$CF_WORKERS_SUBDOMAIN}}"
  stored="$(setting_get CF_PUBLIC_HOST)"; CF_PUBLIC_HOST="${OVERRIDE_CF_PUBLIC_HOST:-${stored:-$CF_PUBLIC_HOST}}"
  stored="$(setting_get CF_PREP_FILE)"; CF_PREP_FILE="${OVERRIDE_CF_PREP_FILE:-${stored:-$CF_PREP_FILE}}"
}

save_settings() {
  install -d -m 0750 "$INSTALL_DIR"
  umask 077
  cat > "$SETTINGS_FILE" <<EOF
MODE=${MODE}
SS_IMAGE=${SS_IMAGE}
BUILD_LOCAL=${BUILD_LOCAL}
SS_PASSWORD=${SS_PASSWORD}
CIPHER=${CIPHER}
WS_PATH=${WS_PATH}
ORIGIN_TOKEN=${ORIGIN_TOKEN}
PUBLIC_IP=${PUBLIC_IP}
DIRECT_HOST=${DIRECT_HOST}
DIRECT_PORT=${DIRECT_PORT}
ORIGIN_HOST=${ORIGIN_HOST}
ORIGIN_PORT=${ORIGIN_PORT}
CF_ACCOUNT_ID=${CF_ACCOUNT_ID}
CF_SCRIPT_NAME=${CF_SCRIPT_NAME}
CF_WORKERS_SUBDOMAIN=${CF_WORKERS_SUBDOMAIN}
CF_PUBLIC_HOST=${CF_PUBLIC_HOST}
CF_PREP_FILE=${CF_PREP_FILE}
EOF
  chmod 0600 "$SETTINGS_FILE"
}

random_hex() {
  openssl rand -hex "$1"
}

valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535))
}

valid_ss_password() {
  [[ "$1" =~ ^[A-Za-z0-9._~!@%+=,:/-]{8,128}$ ]]
}

valid_ipv4() {
  local ip="$1" octet
  local -a octets
  IFS='.' read -r -a octets <<<"$ip"
  [[ "${#octets[@]}" -eq 4 ]] || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]{1,3}$ ]] && ((10#$octet <= 255)) || return 1
  done
}

valid_hostname() {
  local hostname="$1" label
  local -a labels
  [[ -n "$hostname" && "${#hostname}" -le 253 && "$hostname" != .* && "$hostname" != *. && "$hostname" != *..* ]] || return 1
  IFS='.' read -r -a labels <<<"$hostname"
  for label in "${labels[@]}"; do
    [[ "${#label}" -le 63 && "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
  done
}

valid_worker_name() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,62}$ && "$1" != *- ]]
}

valid_ws_path() {
  [[ "$1" =~ ^/[A-Za-z0-9._~/-]+$ ]]
}

valid_origin_token() {
  [[ "$1" =~ ^[A-Za-z0-9._~-]{16,128}$ ]]
}

prompt_install_options() {
  local entered=""
  if [[ "$MODE" == "cloudflare" ]]; then
    read -r -p "VPS 源站 TCP 端口 [${ORIGIN_PORT}]: " entered
    ORIGIN_PORT="${entered:-$ORIGIN_PORT}"
    valid_port "$ORIGIN_PORT" || die "ORIGIN_PORT 无效，必须是 1-65535。"
  else
    read -r -p "Shadowsocks 对外 TCP/UDP 端口 [${DIRECT_PORT}]: " entered
    DIRECT_PORT="${entered:-$DIRECT_PORT}"
    valid_port "$DIRECT_PORT" || die "DIRECT_PORT 无效，必须是 1-65535。"
  fi

  entered=""
  if [[ -n "$SS_PASSWORD" ]]; then
    IFS= read -r -s -p "Shadowsocks 密码 [回车保留当前密码]: " entered
  else
    IFS= read -r -s -p "Shadowsocks 密码 [回车自动生成强随机密码]: " entered
  fi
  printf '\n'
  [[ -z "$entered" ]] || SS_PASSWORD="$entered"
  if [[ -n "$SS_PASSWORD" ]]; then
    valid_ss_password "$SS_PASSWORD" || {
      die "密码必须为 8-128 位，只能包含字母、数字和 . _ ~ ! @ % + = , : / -"
    }
  fi
}

select_cloudflare_prep_file() {
  local requested="${1:-}" candidate script_dir script_source
  if [[ -n "$requested" ]]; then
    [[ -f "$requested" && -r "$requested" ]] || die "无法读取 Cloudflare 材料文件: $requested"
    CF_PREP_FILE="$(readlink -f "$requested" 2>/dev/null || realpath "$requested" 2>/dev/null || printf '%s' "$requested")"
    return 0
  fi

  if [[ -n "$CF_PREP_FILE" && -f "$CF_PREP_FILE" && -r "$CF_PREP_FILE" ]]; then
    return 0
  fi

  script_source="${BASH_SOURCE[0]:-$0}"
  script_dir="$(cd "$(dirname "$script_source")" && pwd)"
  for candidate in \
    "${script_dir}/cloudflare-vps-prep.json" \
    "/root/cloudflare-vps-prep.json"; do
    if [[ -f "$candidate" && -r "$candidate" ]]; then
      CF_PREP_FILE="$candidate"
      return 0
    fi
  done
  return 1
}

load_cloudflare_prep() {
  local requested="${1:-}" schema account_id subdomain token
  select_cloudflare_prep_file "$requested" || return 1
  jq -e . "$CF_PREP_FILE" >/dev/null 2>&1 || die "Cloudflare 材料文件不是有效 JSON: $CF_PREP_FILE"

  schema="$(jq -r '.schema // empty' "$CF_PREP_FILE")"
  account_id="$(jq -r '.cloudflare.account_id // empty' "$CF_PREP_FILE")"
  subdomain="$(jq -r '.cloudflare.workers_subdomain // empty' "$CF_PREP_FILE")"
  token="$(jq -r '.cloudflare.api_token // empty' "$CF_PREP_FILE")"
  subdomain="${subdomain%.workers.dev}"
  subdomain="$(printf '%s' "$subdomain" | tr '[:upper:]_' '[:lower:]-')"

  [[ "$schema" == "vps-ss-cloudflare-prep/v1" ]] || die "不支持的材料文件版本: ${schema:-缺失}"
  [[ "$account_id" =~ ^[a-fA-F0-9]{32}$ ]] || die "材料文件中的 Account ID 格式无效。"
  valid_worker_name "$subdomain" || die "材料文件中的 workers.dev 子域名格式无效。"
  [[ "$token" =~ ^[^[:space:]]{20,}$ ]] || die "材料文件中的 API Token 格式无效。"

  chmod 0600 "$CF_PREP_FILE"
  if [[ "$(id -u)" -eq 0 ]]; then chown 0:0 "$CF_PREP_FILE"; fi
  if [[ -z "$OVERRIDE_CF_ACCOUNT_ID" ]]; then CF_ACCOUNT_ID="$account_id"; fi
  if [[ -z "$OVERRIDE_CF_WORKERS_SUBDOMAIN" ]]; then CF_WORKERS_SUBDOMAIN="$subdomain"; fi
  if [[ -z "$OVERRIDE_CF_API_TOKEN" ]]; then CF_API_TOKEN="$token"; fi
  ok "已读取 Cloudflare 材料文件: $CF_PREP_FILE"
}

detect_public_ipv4() {
  local ip=""
  ip="$(curl -4fsS --max-time 8 https://1.1.1.1/cdn-cgi/trace 2>/dev/null \
    | sed -n 's/^ip=//p' | head -n 1 || true)"
  if ! valid_ipv4 "$ip"; then
    ip="$(hostname -I 2>/dev/null | tr ' ' '\n' \
      | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print; exit}')"
  fi
  valid_ipv4 "$ip" || return 1
  printf '%s' "$ip"
}

configure_docker_repository() {
  local distro="$1" codename="$2" arch
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL --connect-timeout 10 --max-time 60 "https://download.docker.com/linux/${distro}/gpg" \
    | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  arch="$(dpkg --print-architecture)"
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/%s %s stable\n' \
    "$arch" "$distro" "$codename" > /etc/apt/sources.list.d/docker.list
  apt-get update -y
}

ensure_packages() {
  require_root
  [[ -f /etc/os-release ]] || die "无法识别系统，仅支持 Ubuntu/Debian。"
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) ;;
    *) die "当前仅支持 Ubuntu/Debian，检测到: ${ID:-unknown}" ;;
  esac

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ca-certificates curl jq openssl qrencode gnupg

  local codename conflict conflicts=()
  codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  [[ -n "$codename" ]] || die "无法识别系统版本代号。"

  if have docker; then
    if dpkg-query -W -f='${Status}' podman-docker 2>/dev/null | grep -q 'install ok installed'; then
      die "检测到 podman-docker。请先移除该兼容包，或手工安装 Docker Engine 与 Compose 插件。"
    fi
    if ! docker compose version >/dev/null 2>&1; then
      info "检测到 Docker，但缺少 Compose 插件，正在补充安装..."
      if ! apt-get install -y docker-compose-v2; then
        configure_docker_repository "$ID" "$codename"
        apt-get install -y docker-compose-plugin || {
          die "无法为现有 Docker 安装 Compose 插件，请先手工处理 Docker 软件包来源。"
        }
      fi
    fi
  else
    for conflict in docker.io docker-compose docker-compose-v2 podman-docker containerd runc; do
      if dpkg-query -W -f='${Status}' "$conflict" 2>/dev/null | grep -q 'install ok installed'; then
        conflicts+=("$conflict")
      fi
    done
    if ((${#conflicts[@]} > 0)); then
      die "检测到可能与 Docker CE 冲突的软件包: ${conflicts[*]}。请先确认并移除后再运行。"
    fi
    info "安装 Docker Engine 和 Compose 插件..."
    configure_docker_repository "$ID" "$codename"
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi

  systemctl enable --now docker >/dev/null
  docker info >/dev/null 2>&1 || die "Docker 未正常运行。"
  docker compose version >/dev/null 2>&1 || die "Docker Compose 插件不可用。"
}

write_dockerfile() {
  cat > "${INSTALL_DIR}/Dockerfile" <<'EOF'
# syntax=docker/dockerfile:1.7

ARG V2RAY_PLUGIN_VERSION=1.5.0
ARG SSSERVER_VERSION=v1.25.0
ARG IMAGE_VERSION=1.2.0

FROM alpine:3.22 AS plugin
ARG TARGETARCH
ARG V2RAY_PLUGIN_VERSION
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
# hadolint ignore=DL3018
RUN apk add --no-cache ca-certificates tar wget \
    && case "${TARGETARCH}" in \
         amd64) \
           archive="v2ray-plugin-linux-amd64-v${V2RAY_PLUGIN_VERSION}.tar.gz"; \
           checksum="f326c48a0f91f8ab536a864c6a2dba6b587ea1df537b2c43af0bfb7922ed05c4" \
           ;; \
         arm64) \
           archive="v2ray-plugin-linux-arm64-v${V2RAY_PLUGIN_VERSION}.tar.gz"; \
           checksum="96870e810a548e4f7e186016b1df76b24b59a60ffd9cd852586ef830479aeff6" \
           ;; \
         *) \
           echo "Unsupported architecture: ${TARGETARCH}" >&2; \
           exit 1 \
           ;; \
       esac \
    && wget -q --timeout=30 --tries=3 -O /tmp/plugin.tgz \
       "https://github.com/shadowsocks/v2ray-plugin/releases/download/v${V2RAY_PLUGIN_VERSION}/${archive}" \
    && echo "${checksum}  /tmp/plugin.tgz" | sha256sum -c - \
    && mkdir -p /tmp/plugin /out \
    && tar -xzf /tmp/plugin.tgz -C /tmp/plugin \
    && cp "$(find /tmp/plugin -type f -name 'v2ray-plugin*' | head -n 1)" /out/v2ray-plugin \
    && chmod 0755 /out/v2ray-plugin

FROM ghcr.io/shadowsocks/ssserver-rust:${SSSERVER_VERSION}
ARG V2RAY_PLUGIN_VERSION
ARG IMAGE_VERSION
# The same image also runs the unprivileged Cloudflare origin proxy. Keeping
# both services in one scanned image avoids an untracked runtime dependency.
# hadolint ignore=DL3017,DL3018
RUN apk upgrade --no-cache \
    && apk add --no-cache gettext-envsubst nginx
LABEL org.opencontainers.image.title="Shadowsocks Rust with v2ray-plugin" \
      org.opencontainers.image.description="Multi-mode Shadowsocks server for direct or Cloudflare WebSocket deployment" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      io.vps-ss.v2ray-plugin.version="${V2RAY_PLUGIN_VERSION}"
COPY --from=plugin /out/v2ray-plugin /usr/local/bin/v2ray-plugin
EOF
}

prepare_image() {
  if [[ -z "$BUILD_LOCAL" ]]; then
    if [[ "$SS_IMAGE" == local/* ]]; then BUILD_LOCAL="1"; else BUILD_LOCAL="0"; fi
  fi
  case "$BUILD_LOCAL" in 0|1) ;; *) die "BUILD_LOCAL 只能是 0 或 1。" ;; esac

  if [[ "$BUILD_LOCAL" == "1" ]]; then
    info "构建镜像: ${SS_IMAGE}"
    docker build --pull -t "$SS_IMAGE" "$INSTALL_DIR"
  else
    info "拉取镜像: ${SS_IMAGE}"
    if ! docker pull "$SS_IMAGE"; then
      if [[ "$SS_IMAGE" != "$DEFAULT_SS_IMAGE" || -z "$FALLBACK_SS_IMAGE" ]]; then
        die "无法拉取镜像: $SS_IMAGE"
      fi
      warn "GHCR 拉取失败，改用 Docker Hub 镜像: ${FALLBACK_SS_IMAGE}"
      SS_IMAGE="$FALLBACK_SS_IMAGE"
      docker pull "$SS_IMAGE" || die "两个公共镜像仓库均拉取失败。"
    fi
  fi
}

write_server_config() {
  if [[ "$MODE" == "cloudflare" ]]; then
    jq -n \
      --arg password "$SS_PASSWORD" \
      --arg method "$CIPHER" \
      --arg path "$WS_PATH" \
      '{
        server: "0.0.0.0",
        server_port: 8388,
        password: $password,
        method: $method,
        mode: "tcp_only",
        plugin: "/usr/local/bin/v2ray-plugin",
        plugin_opts: ("server;path=" + $path)
      }' > "$CONFIG_FILE"
  else
    jq -n \
      --arg password "$SS_PASSWORD" \
      --arg method "$CIPHER" \
      '{
        server: "0.0.0.0",
        server_port: 8388,
        password: $password,
        method: $method,
        mode: "tcp_and_udp"
      }' > "$CONFIG_FILE"
  fi
  chown 65534:65534 "$CONFIG_FILE"
  chmod 0600 "$CONFIG_FILE"
}

write_nginx_config() {
  cat > "$NGINX_FILE" <<EOF
worker_processes auto;
error_log /dev/stderr warn;
pid /tmp/nginx.pid;

events {
  worker_connections 1024;
}

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
    listen 8080 default_server;
    server_name _;

    location / {
      return 404;
    }

    location = ${WS_PATH} {
      if (\$http_x_origin_token != "\${ORIGIN_TOKEN}") {
        return 404;
      }

      proxy_pass http://ss:8388;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$connection_upgrade;
      proxy_set_header Host \$host;
      proxy_buffering off;
      proxy_read_timeout 86400s;
      proxy_send_timeout 86400s;
    }
  }
}
EOF
  chmod 0644 "$NGINX_FILE"
  if [[ "$NGINX_FILE" != "${INSTALL_DIR}/nginx.conf" ]]; then
    rm -f "${INSTALL_DIR}/nginx.conf"
  fi
}

write_worker() {
  cat > "$WORKER_FILE" <<'EOF'
export default {
  async fetch(request, env) {
    const upgrade = request.headers.get("Upgrade");
    const incoming = new URL(request.url);

    if (!upgrade || upgrade.toLowerCase() !== "websocket" || incoming.pathname !== env.WS_PATH) {
      return new Response("Not found", { status: 404 });
    }

    const origin = new URL(env.ORIGIN_URL);
    origin.pathname = incoming.pathname;
    origin.search = incoming.search;

    const upstream = new Request(origin.toString(), request);
    const headers = new Headers(upstream.headers);
    headers.set("X-Origin-Token", env.ORIGIN_TOKEN);

    return fetch(new Request(upstream, { headers }));
  },
};
EOF
  chmod 0600 "$WORKER_FILE"
}

write_compose() {
  if [[ "$MODE" == "cloudflare" ]]; then
    cat > "$COMPOSE_FILE" <<EOF
services:
  ss:
    image: ${SS_IMAGE}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    user: "65534:65534"
    command: ["ssserver", "--log-without-time", "-c", "/etc/shadowsocks-rust/config.json"]
    volumes:
      - ./config.json:/etc/shadowsocks-rust/config.json:ro
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true

  origin:
    image: ${SS_IMAGE}
    container_name: ${ORIGIN_CONTAINER_NAME}
    restart: unless-stopped
    user: "101:101"
    environment:
      ORIGIN_TOKEN: \${ORIGIN_TOKEN}
    command:
      - /bin/sh
      - -ec
      - |
        envsubst '\$\${ORIGIN_TOKEN}' < /etc/nginx/nginx.conf.template > /tmp/nginx.conf
        exec nginx -c /tmp/nginx.conf -g 'daemon off;'
    depends_on:
      - ss
    ports:
      - "${ORIGIN_PORT}:8080/tcp"
    volumes:
      - ./nginx.conf.template:/etc/nginx/nginx.conf.template:ro
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
EOF
  else
    cat > "$COMPOSE_FILE" <<EOF
services:
  ss:
    image: ${SS_IMAGE}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    user: "65534:65534"
    command: ["ssserver", "--log-without-time", "-c", "/etc/shadowsocks-rust/config.json"]
    ports:
      - "${DIRECT_PORT}:8388/tcp"
      - "${DIRECT_PORT}:8388/udp"
    volumes:
      - ./config.json:/etc/shadowsocks-rust/config.json:ro
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
EOF
  fi
  chmod 0644 "$COMPOSE_FILE"
}

compose() {
  (cd "$INSTALL_DIR" && docker compose -f "$COMPOSE_FILE" "$@")
}

open_firewall_port() {
  local port="$1" proto="$2"
  if have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow "${port}/${proto}" >/dev/null
    ok "UFW 已放行 ${port}/${proto}。"
  elif have firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="${port}/${proto}" >/dev/null
    firewall-cmd --reload >/dev/null
    ok "firewalld 已放行 ${port}/${proto}。"
  else
    warn "未修改本机防火墙；请确认云厂商安全组已放行 ${port}/${proto}。"
  fi
}

api_token_value() {
  local token="${CF_API_TOKEN:-}"
  if [[ -z "$token" && -n "${CF_API_TOKEN_FILE:-}" ]]; then
    [[ -r "$CF_API_TOKEN_FILE" ]] || die "无法读取 CF_API_TOKEN_FILE。"
    token="$(tr -d '\r\n' < "$CF_API_TOKEN_FILE")"
  fi
  if [[ -z "$token" && -t 0 ]]; then
    read -r -s -p "Cloudflare API Token（输入时不显示，留空跳过部署）: " token
    printf '\n' >&2
  fi
  printf '%s' "$token"
}

cf_request() {
  local token="$1" method="$2" endpoint="$3"
  shift 3
  curl -sS -X "$method" \
    --connect-timeout 10 \
    --max-time 60 \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4${endpoint}" "$@"
}

deploy_cloudflare_worker() {
  require_root
  require_install
  load_settings
  [[ "$MODE" == "cloudflare" ]] || die "当前不是 Cloudflare 模式。"

  local token verify_response subdomain_response upload_response enable_response metadata_file response_file
  local detected_subdomain=""
  if ! load_cloudflare_prep ""; then
    if [[ -n "$CF_PREP_FILE" ]]; then
      warn "已配置的 Cloudflare 材料文件不可读，将改为交互输入: $CF_PREP_FILE"
    fi
  fi
  token="$(api_token_value)"
  if [[ -z "$token" ]]; then
    warn "已跳过 Cloudflare Worker 部署。稍后运行: vps-ss cf-deploy"
    return 0
  fi

  verify_response="$(cf_request "$token" GET "/user/tokens/verify" || true)"
  if [[ "$(jq -r '.success // false' <<<"$verify_response" 2>/dev/null)" != "true" || \
        "$(jq -r '.result.status // empty' <<<"$verify_response" 2>/dev/null)" != "active" ]]; then
    fail "Cloudflare API Token 无效或已失效："
    jq -r '.errors[]?.message // empty' <<<"$verify_response" >&2 || true
    exit 1
  fi

  if [[ -z "$CF_ACCOUNT_ID" && -t 0 ]]; then
    read -r -p "Cloudflare Account ID: " CF_ACCOUNT_ID
  fi
  [[ "$CF_ACCOUNT_ID" =~ ^[a-fA-F0-9]{32}$ ]] || die "Cloudflare Account ID 格式无效。"

  if [[ -z "$CF_SCRIPT_NAME" ]]; then
    CF_SCRIPT_NAME="vps-ss-$(printf '%s' "$PUBLIC_IP" | tr '.' '-')"
  fi
  CF_SCRIPT_NAME="$(printf '%s' "$CF_SCRIPT_NAME" | tr '[:upper:]_' '[:lower:]-')"
  valid_worker_name "$CF_SCRIPT_NAME" || die "Worker 名称无效: $CF_SCRIPT_NAME"

  subdomain_response="$(cf_request "$token" GET "/accounts/${CF_ACCOUNT_ID}/workers/subdomain" || true)"
  if [[ "$(jq -r '.success // false' <<<"$subdomain_response" 2>/dev/null)" == "true" ]]; then
    detected_subdomain="$(jq -r '.result.subdomain // empty' <<<"$subdomain_response")"
    CF_WORKERS_SUBDOMAIN="${detected_subdomain:-$CF_WORKERS_SUBDOMAIN}"
  fi

  if [[ -z "$CF_WORKERS_SUBDOMAIN" && -t 0 ]]; then
    read -r -p "尚未检测到 workers.dev 子域名，请输入希望使用的账户子域名: " CF_WORKERS_SUBDOMAIN
  fi
  CF_WORKERS_SUBDOMAIN="$(printf '%s' "$CF_WORKERS_SUBDOMAIN" | tr '[:upper:]_' '[:lower:]-')"
  valid_worker_name "$CF_WORKERS_SUBDOMAIN" || {
    die "需要先在 Cloudflare Workers & Pages 中启用 workers.dev 子域名。"
  }

  if [[ -z "$detected_subdomain" ]]; then
    local create_subdomain
    create_subdomain="$(jq -nc --arg value "$CF_WORKERS_SUBDOMAIN" '{subdomain:$value}')"
    subdomain_response="$(cf_request "$token" PUT "/accounts/${CF_ACCOUNT_ID}/workers/subdomain" \
      --data "$create_subdomain" || true)"
    [[ "$(jq -r '.success // false' <<<"$subdomain_response" 2>/dev/null)" == "true" ]] || {
      fail "无法创建 workers.dev 子域名："
      jq -r '.errors[]?.message // empty' <<<"$subdomain_response" >&2 || true
      exit 1
    }
  fi

  metadata_file="$(mktemp)"
  response_file="$(mktemp)"
  trap 'rm -f -- "${metadata_file:-}" "${response_file:-}"' EXIT
  jq -n \
    --arg origin_url "http://${ORIGIN_HOST}:${ORIGIN_PORT}" \
    --arg path "$WS_PATH" \
    --arg token "$ORIGIN_TOKEN" \
    '{
      main_module: "worker.js",
      compatibility_date: "2026-11-13",
      compatibility_flags: ["allow_custom_ports"],
      bindings: [
        {type: "plain_text", name: "ORIGIN_URL", text: $origin_url},
        {type: "plain_text", name: "WS_PATH", text: $path},
        {type: "secret_text", name: "ORIGIN_TOKEN", text: $token}
      ]
    }' > "$metadata_file"

  info "部署 Cloudflare Worker: ${CF_SCRIPT_NAME}"
  upload_response="$(curl -sS -X PUT \
    --connect-timeout 10 \
    --max-time 60 \
    -H "Authorization: Bearer ${token}" \
    -F "metadata=@${metadata_file};type=application/json" \
    -F "worker.js=@${WORKER_FILE};type=application/javascript+module" \
    "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/workers/scripts/${CF_SCRIPT_NAME}" || true)"
  printf '%s' "$upload_response" > "$response_file"
  if [[ "$(jq -r '.success // false' "$response_file" 2>/dev/null)" != "true" ]]; then
    fail "Worker 上传失败："
    jq -r '.errors[]?.message // empty' "$response_file" >&2 || true
    exit 1
  fi

  enable_response="$(cf_request "$token" POST \
    "/accounts/${CF_ACCOUNT_ID}/workers/scripts/${CF_SCRIPT_NAME}/subdomain" \
    --data '{"enabled":true,"previews_enabled":false}' || true)"
  if [[ "$(jq -r '.success // false' <<<"$enable_response" 2>/dev/null)" != "true" ]]; then
    fail "Worker 已上传，但启用 workers.dev 地址失败："
    jq -r '.errors[]?.message // empty' <<<"$enable_response" >&2 || true
    exit 1
  fi

  CF_PUBLIC_HOST="${CF_SCRIPT_NAME}.${CF_WORKERS_SUBDOMAIN}.workers.dev"
  save_settings
  rm -f "$metadata_file" "$response_file"
  trap - EXIT
  unset token CF_API_TOKEN
  ok "Cloudflare Worker 已部署: https://${CF_PUBLIC_HOST}"
}

install_manager() {
  local self
  self="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || true)"
  if [[ "$self" != "$MANAGER_PATH" ]]; then
    install -m 0755 "$self" "$MANAGER_PATH"
  fi
}

install_mode() {
  require_root
  local requested_mode="${1:-}" requested_prep="${2:-}" interactive_options="${3:-false}"
  if [[ -z "$requested_mode" && -t 0 ]]; then
    printf '1) Cloudflare Worker 模式\n2) 无 Cloudflare 直连模式\n'
    read -r -p "请选择模式 [1/2]: " requested_mode
    case "$requested_mode" in 1) requested_mode="cloudflare" ;; 2) requested_mode="direct" ;; esac
  fi
  case "$requested_mode" in cloudflare|direct) ;; *) die "模式必须是 cloudflare 或 direct。" ;; esac
  MODE="$requested_mode"

  install -d -m 0750 "$INSTALL_DIR"
  load_settings
  MODE="$requested_mode"
  if [[ "$interactive_options" == "true" ]]; then
    prompt_install_options
  fi

  ensure_packages

  if [[ "$MODE" == "cloudflare" ]]; then
    if [[ -n "$requested_prep" ]]; then
      load_cloudflare_prep "$requested_prep"
    elif ! load_cloudflare_prep ""; then
      info "未检测到 cloudflare-vps-prep.json，将使用交互方式读取 Cloudflare 资料。"
    fi
  fi

  SS_PASSWORD="${SS_PASSWORD:-$(random_hex 24)}"
  valid_ss_password "$SS_PASSWORD" || {
    die "SS_PASSWORD 必须为 8-128 位，只能包含字母、数字和 . _ ~ ! @ % + = , : / -"
  }
  WS_PATH="${WS_PATH:-/$(random_hex 16)}"
  ORIGIN_TOKEN="${ORIGIN_TOKEN:-$(random_hex 32)}"
  valid_ws_path "$WS_PATH" || die "WS_PATH 必须以 / 开头，且只能包含字母、数字、/、-、_、.、~。"
  valid_origin_token "$ORIGIN_TOKEN" || die "ORIGIN_TOKEN 格式无效，至少需要 16 个安全字符。"
  PUBLIC_IP="${PUBLIC_IP:-$(detect_public_ipv4 || true)}"
  [[ -n "$PUBLIC_IP" ]] || die "无法检测公网 IPv4，请通过 PUBLIC_IP=... 指定。"
  DIRECT_HOST="${DIRECT_HOST:-$PUBLIC_IP}"

  if [[ "$MODE" == "cloudflare" ]]; then
    valid_port "$ORIGIN_PORT" || die "ORIGIN_PORT 无效。"
    ORIGIN_HOST="${ORIGIN_HOST:-$(printf '%s.sslip.io' "${PUBLIC_IP//./-}")}"
    valid_hostname "$ORIGIN_HOST" || die "ORIGIN_HOST 无效。"
  else
    valid_port "$DIRECT_PORT" || die "DIRECT_PORT 无效。"
  fi

  write_dockerfile
  prepare_image
  write_server_config
  if [[ "$MODE" == "cloudflare" ]]; then
    write_nginx_config
    write_worker
  else
    rm -f "$NGINX_FILE" "${INSTALL_DIR}/nginx.conf"
  fi
  write_compose
  save_settings
  install_manager

  compose config >/dev/null
  compose up -d --remove-orphans
  if [[ "$MODE" == "cloudflare" ]]; then
    open_firewall_port "$ORIGIN_PORT" tcp
    deploy_cloudflare_worker
  else
    open_firewall_port "$DIRECT_PORT" tcp
    open_firewall_port "$DIRECT_PORT" udp
  fi

  ok "安装完成。管理命令: vps-ss"
  show_status
  printf '\n'
  show_link || true
}

base64url() {
  printf '%s' "$1" | openssl enc -base64 -A | tr '+/' '-_' | tr -d '='
}

uri_encode() {
  jq -rn --arg value "$1" '$value | @uri'
}

mask_secret() {
  local value="$1" length="${#1}"
  if ((length <= 10)); then
    printf '********'
  else
    printf '%s...%s' "${value:0:4}" "${value:length-4:4}"
  fi
}

show_info() {
  require_install
  load_settings
  local reveal="${1:-false}"
  info "===== VPS Shadowsocks 配置 ====="
  printf '模式          : %s\n' "$MODE"
  printf '镜像          : %s\n' "$SS_IMAGE"
  printf '加密方式      : %s\n' "$CIPHER"
  if [[ "$reveal" == "true" ]]; then
    printf '密码          : %s\n' "$SS_PASSWORD"
  else
    printf '密码          : %s\n' "$(mask_secret "$SS_PASSWORD")"
  fi
  if [[ "$MODE" == "cloudflare" ]]; then
    printf 'Cloudflare    : %s\n' "${CF_PUBLIC_HOST:-尚未部署}"
    printf 'WebSocket 路径: %s\n' "$WS_PATH"
    printf '源站          : http://%s:%s\n' "$ORIGIN_HOST" "$ORIGIN_PORT"
    printf 'Worker 名称   : %s\n' "${CF_SCRIPT_NAME:-未设置}"
    printf '准备材料      : %s\n' "${CF_PREP_FILE:-未使用文件}"
  else
    printf '服务器        : %s\n' "$DIRECT_HOST"
    printf '端口          : %s (TCP/UDP)\n' "$DIRECT_PORT"
  fi
  printf '安装目录      : %s\n' "$INSTALL_DIR"
  info "================================"
}

show_link() {
  require_install
  load_settings
  local auth link plugin encoded_plugin
  auth="$(base64url "${CIPHER}:${SS_PASSWORD}")"
  if [[ "$MODE" == "cloudflare" ]]; then
    [[ -n "$CF_PUBLIC_HOST" ]] || die "Worker 尚未部署，请先运行: vps-ss cf-deploy"
    plugin="v2ray-plugin;tls;host=${CF_PUBLIC_HOST};path=${WS_PATH}"
    encoded_plugin="$(uri_encode "$plugin")"
    link="ss://${auth}@${CF_PUBLIC_HOST}:443/?plugin=${encoded_plugin}#Cloudflare-SS"
  else
    link="ss://${auth}@${DIRECT_HOST}:${DIRECT_PORT}#Direct-SS"
  fi

  warn "下面的链接包含密码，请勿公开转发："
  printf '%s\n' "$link"
  if have qrencode; then printf '%s' "$link" | qrencode -t ANSIUTF8; fi
}

show_clash() {
  require_install
  load_settings
  if [[ "$MODE" == "cloudflare" ]]; then
    [[ -n "$CF_PUBLIC_HOST" ]] || die "Worker 尚未部署。"
    cat <<EOF
- name: Cloudflare-SS
  type: ss
  server: ${CF_PUBLIC_HOST}
  port: 443
  cipher: ${CIPHER}
  password: ${SS_PASSWORD}
  udp: false
  plugin: v2ray-plugin
  plugin-opts:
    mode: websocket
    tls: true
    host: ${CF_PUBLIC_HOST}
    path: ${WS_PATH}
    mux: true
EOF
  else
    cat <<EOF
- name: Direct-SS
  type: ss
  server: ${DIRECT_HOST}
  port: ${DIRECT_PORT}
  cipher: ${CIPHER}
  password: ${SS_PASSWORD}
  udp: true
EOF
  fi
}

probe_websocket() {
  local url="$1" origin_token="${2:-}" first headers args=()
  [[ -n "$origin_token" ]] && args+=(-H "X-Origin-Token: ${origin_token}")
  headers="$(curl --http1.1 -isS --max-time 10 \
    -H 'Connection: Upgrade' \
    -H 'Upgrade: websocket' \
    -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
    "${args[@]}" "$url" 2>/dev/null || true)"
  first="$(printf '%s\n' "$headers" | sed -n '1{s/\r$//;p;}')"
  [[ "$first" == *" 101 "* ]]
}

show_status() {
  require_install
  load_settings
  docker info >/dev/null 2>&1 || die "Docker 未运行。"
  info "===== 容器状态 ====="
  compose ps
  info "===== 连通性检查 ====="
  if [[ "$MODE" == "cloudflare" ]]; then
    if probe_websocket "http://127.0.0.1:${ORIGIN_PORT}${WS_PATH}" "$ORIGIN_TOKEN"; then
      ok "本地源站 WebSocket: 正常 (101)"
    else
      fail "本地源站 WebSocket: 失败"
    fi
    if [[ -n "$CF_PUBLIC_HOST" ]]; then
      if probe_websocket "https://${CF_PUBLIC_HOST}${WS_PATH}"; then
        ok "Cloudflare WebSocket: 正常 (101)"
      else
        warn "Cloudflare WebSocket: 暂未通过（部署传播或外部防火墙可能尚未完成）"
      fi
    else
      warn "Cloudflare Worker: 尚未部署"
    fi
  else
    if timeout 3 bash -c "</dev/tcp/127.0.0.1/${DIRECT_PORT}" 2>/dev/null; then
      ok "直连 TCP 端口: 正常"
    else
      fail "直连 TCP 端口: 失败"
    fi
  fi
}

start_service() {
  require_root
  require_install
  systemctl start docker
  compose up -d
  show_status
}

stop_service() {
  require_root
  require_install
  compose stop
  ok "服务已停止。"
}

restart_service() {
  require_root
  require_install
  compose restart
  show_status
}

show_logs() {
  require_install
  local lines="${1:-100}"
  [[ "$lines" =~ ^[0-9]+$ ]] || die "日志行数必须是数字。"
  compose logs --tail "$lines"
}

follow_logs() {
  require_install
  compose logs --tail 100 -f
}

doctor() {
  show_status || true
  printf '\n'
  info "===== 最近日志 ====="
  compose logs --tail 40 || true
  printf '\n'
  if [[ "$MODE" == "cloudflare" ]]; then
    warn "请同时确认云厂商安全组允许 TCP ${ORIGIN_PORT}。"
  else
    warn "请同时确认云厂商安全组允许 TCP/UDP ${DIRECT_PORT}。"
  fi
}

set_public_host() {
  require_root
  require_install
  load_settings
  local host="${1:-}"
  [[ -n "$host" ]] || die "用法: vps-ss set-host <已绑定到 Worker 的域名>"
  valid_hostname "$host" || die "域名格式无效。"
  CF_PUBLIC_HOST="$host"
  save_settings
  ok "客户端域名已更新为: $CF_PUBLIC_HOST"
}

build_image_command() {
  require_root
  ensure_packages
  local tag="${1:-$SS_IMAGE}" context
  if [[ -f "${INSTALL_DIR}/Dockerfile" ]]; then context="$INSTALL_DIR"; else context="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; fi
  docker build --pull -t "$tag" "$context"
  ok "镜像已构建: $tag"
}

show_help() {
  cat <<EOF
VPS Shadowsocks Docker 管理脚本 v${VERSION}

用法:
  vps-ss install cloudflare [JSON] 安装 Cloudflare 模式，可指定准备材料文件
  vps-ss install direct           安装无 Cloudflare 的直连 TCP/UDP 模式
  vps-ss start|stop|restart       启动、停止、重启
  vps-ss status                   容器和连通性检查
  vps-ss info                     查看配置（隐藏密码）
  vps-ss info --show-secret       查看完整配置
  vps-ss link                     显示 ss:// 链接和二维码
  vps-ss clash                    输出 Clash/Mihomo 节点 YAML
  vps-ss logs [行数]              查看日志
  vps-ss follow                   持续查看日志
  vps-ss doctor                   诊断服务
  vps-ss cf-deploy                部署或更新 Cloudflare Worker
  vps-ss set-host <域名>          使用已绑定到 Worker 的自定义域名
  vps-ss image-build [镜像名]     构建 Docker 镜像
  vps-ss help                     显示帮助

常用环境变量:
  SS_IMAGE=docker.io/你的账号/vps-ss:1.2.0
  BUILD_LOCAL=0                   指定其他仓库镜像；默认自动使用官方公共镜像
  FALLBACK_SS_IMAGE=...           GHCR 失败时的备用镜像；设为空可禁用回退
  DIRECT_PORT=8388
  ORIGIN_PORT=8080
  SS_PASSWORD=...                 8-128 位安全字符；菜单模式可隐藏输入
  ORIGIN_HOST=origin.example.com  可选，需为 DNS only 并指向 VPS
  CF_ACCOUNT_ID=...
  CF_API_TOKEN_FILE=/root/cf-token
  CF_PREP_FILE=/root/cloudflare-vps-prep.json
  CF_WORKERS_SUBDOMAIN=你的 workers.dev 子域名
EOF
}

menu() {
  while true; do
    printf '\n'
    info "===== VPS Shadowsocks Docker v${VERSION} ====="
    cat <<'EOF'
1) 安装/切换 Cloudflare 模式
2) 安装/切换无 Cloudflare 直连模式
3) 启动
4) 停止
5) 重启
6) 查看状态
7) 查看配置
8) 显示链接/二维码
9) 输出 Clash/Mihomo 配置
10) 查看日志
11) 重新部署 Cloudflare Worker
12) 诊断
0) 退出
EOF
    read -r -p "请选择: " choice
    case "$choice" in
      1) install_mode cloudflare "" true ;;
      2) install_mode direct "" true ;;
      3) start_service ;;
      4) stop_service ;;
      5) restart_service ;;
      6) show_status ;;
      7) show_info ;;
      8) show_link ;;
      9) show_clash ;;
      10) show_logs 100 ;;
      11) deploy_cloudflare_worker ;;
      12) doctor ;;
      0) return 0 ;;
      *) warn "无效选项。" ;;
    esac
  done
}

main() {
  local command="${1:-}"
  case "$command" in
    install) install_mode "${2:-}" "${3:-}" ;;
    start) start_service ;;
    stop) stop_service ;;
    restart) restart_service ;;
    status) show_status ;;
    info) show_info "$( [[ "${2:-}" == "--show-secret" ]] && printf true || printf false )" ;;
    link) show_link ;;
    clash) show_clash ;;
    logs) show_logs "${2:-100}" ;;
    follow) follow_logs ;;
    doctor) doctor ;;
    cf-deploy) deploy_cloudflare_worker ;;
    set-host) set_public_host "${2:-}" ;;
    image-build) build_image_command "${2:-}" ;;
    help|-h|--help) show_help ;;
    "") menu ;;
    *) die "未知命令: $command。运行 vps-ss help 查看帮助。" ;;
  esac
}

if [[ "${VPS_SS_NO_MAIN:-0}" != "1" ]]; then
  main "$@"
fi
