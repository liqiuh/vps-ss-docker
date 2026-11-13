# syntax=docker/dockerfile:1.7

ARG ALPINE_IMAGE=docker.io/library/alpine:3.22@sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f
ARG SSSERVER_IMAGE=ghcr.io/shadowsocks/ssserver-rust:v1.25.0@sha256:22240c07d8ce3a36421ede770bd775dcc5fc56d5d829943196957b05452dc36f
ARG SSLOCAL_IMAGE=ghcr.io/shadowsocks/sslocal-rust:v1.25.0@sha256:56786760f6a1bc447c3bcdcac94d5e2e2ffdbdaacce14c38e819003d8bb125dc
ARG V2RAY_PLUGIN_VERSION=1.5.0
ARG IMAGE_VERSION=1.3.0

FROM ${ALPINE_IMAGE} AS plugin
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

FROM ${SSLOCAL_IMAGE} AS client
# hadolint ignore=DL3017
RUN apk upgrade --no-cache
COPY --from=plugin /out/v2ray-plugin /usr/local/bin/v2ray-plugin

FROM ${SSSERVER_IMAGE} AS server
ARG V2RAY_PLUGIN_VERSION
ARG IMAGE_VERSION
# The same image also runs the unprivileged Cloudflare origin proxy. Keeping
# both services in one scanned image avoids an untracked runtime dependency.
# hadolint ignore=DL3017,DL3018
RUN apk upgrade --no-cache \
    && apk add --no-cache busybox-extras gettext-envsubst nginx
LABEL org.opencontainers.image.title="Shadowsocks Rust with v2ray-plugin" \
      org.opencontainers.image.description="Multi-mode Shadowsocks server for direct or Cloudflare WebSocket deployment" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      io.vps-ss.v2ray-plugin.version="${V2RAY_PLUGIN_VERSION}"
COPY --from=plugin /out/v2ray-plugin /usr/local/bin/v2ray-plugin
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=6 \
  CMD ["nc", "-z", "-w", "2", "127.0.0.1", "8388"]
USER 65534:65534
