# Changelog

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
