# Changelog

## 1.2.1 - 2026-11-13

- Disable the anonymous Docker Hub fallback because the mirror is now private.
- Keep GHCR as the public default image for shared deployments.
- Retain optional custom fallback support for authenticated private registries.

## 1.2.0 - 2026-11-13

- Prompt for the public/origin port and a hidden custom password in menu-driven installations.
- Validate custom passwords before writing configuration files.
- Add an AI deployment handoff guide and an explicit firewall/security-group matrix.
- Document the stable repository URL and recommend verified release assets instead of executing `main` directly.

## 1.1.1 - 2026-11-13

- Pull the public GHCR release image by default on new VPS installations.
- Automatically fall back to the Docker Hub mirror when GHCR is unavailable.
- Keep local builds and custom registries available through `BUILD_LOCAL` and `SS_IMAGE`.

## 1.1.0 - 2026-11-13

- Add `cloudflare-vps-prep.json` import and automatic discovery.
- Add the `cloudflare-vps-prep` Codex skill and strict preparation-file validation.
- Verify Cloudflare API tokens before deployment.
- Harden secret file ownership and permissions.
- Clean Cloudflare upload temporary files on both success and failure.
- Improve Docker installation conflict handling.
- Upgrade final-stage Alpine packages to include available security fixes from the base distribution repository.
- Run the Cloudflare Nginx origin from the same scanned release image instead of an untracked third-party runtime image.
- Add the MIT license and publish release images to both GHCR and Docker Hub.
- Add repository tests, integration tests, vulnerability scanning, CI, and multi-architecture GHCR publishing.

## 1.0.0 - 2026-11-13

- Initial Docker-based Cloudflare Worker and direct Shadowsocks installer.
