# Release Guide

## Before Publishing The Source Repository

1. Confirm that `cloudflare-vps-prep.json`, API tokens, `.env`, VPS addresses, and generated client links are not committed.
2. Run:

```bash
make test
make build
make scan
make integration
make multiarch
```

3. Create the repository, commit the files, and push the default branch.

## GHCR Publishing

The included `docker-publish.yml` publishes `linux/amd64` and `linux/arm64` images to:

```text
ghcr.io/OWNER/REPOSITORY
```

Push a semantic-version tag:

```bash
git tag v1.2.0
git push origin v1.2.0
```

The workflow publishes matching version tags to GHCR and `docker.io/macro1996/vps-ss`, with provenance and an SBOM.
New GHCR packages may initially be private; change the package visibility to public in the repository or organization package settings when public pulls are required.

Before publishing, configure the GitHub Actions repository secret `DOCKERHUB_TOKEN` with a Docker Hub access token that can write to `macro1996/vps-ss`.

## Docker Hub Publishing

Authenticate with a Docker Hub access token, not an account password:

```bash
docker login
docker buildx create --use --name vps-ss-builder 2>/dev/null || docker buildx use vps-ss-builder
docker buildx build \
  --pull \
  --platform linux/amd64,linux/arm64 \
  --build-arg IMAGE_VERSION=1.2.0 \
  -t docker.io/USERNAME/vps-ss:1.2.0 \
  -t docker.io/USERNAME/vps-ss:latest \
  --provenance=true \
  --sbom=true \
  --push .
```

## Use A Published Image

```bash
SS_IMAGE=ghcr.io/OWNER/REPOSITORY:1.2.0 \
BUILD_LOCAL=0 \
sudo -E ./vps-ss.sh install cloudflare /root/cloudflare-vps-prep.json
```

Direct mode uses the same image:

```bash
SS_IMAGE=ghcr.io/OWNER/REPOSITORY:1.2.0 \
BUILD_LOCAL=0 \
sudo -E ./vps-ss.sh install direct
```
