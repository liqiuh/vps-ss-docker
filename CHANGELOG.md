# Changelog

## Unreleased

## 1.3.0 - 2026-11-13

- Change new Cloudflare origin installations to TCP `18080` while preserving existing configured ports.
- Add port ownership checks, public IPv4 classification, transactional configuration staging, service health checks, and rollback.
- Make `vps-ss status` return a nonzero exit code when an expected service or connectivity check fails.
- Serialize Clash strings safely for every allowed password character.
- Track only script-created firewall rules in `/opt/vps-ss/state.json` and clean only those rules.
- Add explicit `cf-delete` and `uninstall` commands while retaining remote Workers by default.
- Pin Docker bases and GitHub Actions, add container health checks and log rotation, and add weekly dependency and security checks.
- Add real Shadowsocks TCP, WebSocket, and SOCKS5 UDP integration tests.
- Include the `cloudflare-vps-prep` Skill source and generate immutable release assets with checksums.
- Publish multi-architecture images to public GHCR and a private Docker Hub backup with provenance and an SBOM.
- Add a bilingual use and legal notice without changing the rights granted by the MIT License.

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
