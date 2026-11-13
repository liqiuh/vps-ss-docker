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
