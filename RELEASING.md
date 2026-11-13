# Release Guide

## Preconditions

1. Confirm `VERSION`, `vps-ss.sh`, `Dockerfile`, documentation, and tests all name the intended release.
2. Confirm `DOCKERHUB_TOKEN` can write to the private `docker.io/macro1996/vps-ss` backup.
3. Confirm the GHCR package is public.
4. Confirm no preparation JSON, API token, `.env`, VPS address, client link, or generated `dist/` artifact is tracked.

## Validate And Push Main

Run the complete local gate with Docker or OrbStack available:

```bash
make verify
git diff --check
git status --short
```

Commit and push `main`, then wait for the `CI` workflow to succeed. Do not create the release tag while the main-branch
workflow is pending or failing.

## Publish A Version

Create an annotated, immutable semantic-version tag only after main CI succeeds:

```bash
git tag -a v1.3.0 -m "Release v1.3.0"
git push origin v1.3.0
```

The tag workflow repeats tests, source scanning, image scanning, real TCP/WebSocket/UDP integration tests, and
multi-architecture builds before it publishes anything. It then:

- publishes `linux/amd64` and `linux/arm64` to public `ghcr.io/liqiuh/vps-ss-docker`;
- publishes the same manifest to private `docker.io/macro1996/vps-ss`;
- attaches provenance and an SBOM;
- injects the GHCR manifest digest into the release copy of `vps-ss.sh`;
- packages `skills/cloudflare-vps-prep`;
- generates `SHA256SUMS` and creates the GitHub Release.

Never rewrite a public tag. Release fixes under the next patch version.

## Post-release Verification

After the workflow succeeds, verify the manifest and assets:

```bash
docker buildx imagetools inspect ghcr.io/liqiuh/vps-ss-docker:1.3.0
gh release download v1.3.0 --dir /tmp/vps-ss-v1.3.0
cd /tmp/vps-ss-v1.3.0
sha256sum -c SHA256SUMS
grep 'DEFAULT_SS_IMAGE=.*:1.3.0@sha256:' vps-ss.sh
```

The Docker Hub backup is private, so verify it with authenticated credentials or from the successful publish workflow.
