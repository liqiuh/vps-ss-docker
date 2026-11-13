IMAGE ?= local/vps-ss:1.2.0
SHELLCHECK_IMAGE ?= koalaman/shellcheck:stable@sha256:bb596a0d169b85ddd81d8b6d3a2ff6d5baf5fca10b97f575ebc647c3dff62b3d
HADOLINT_IMAGE ?= hadolint/hadolint:latest-alpine@sha256:a1d49ae1a4e83c1dbad26b8c1ad7588c8bd1e04f4866b34ad3cac50335198552
ACTIONLINT_IMAGE ?= rhysd/actionlint:latest@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667
TRIVY_IMAGE ?= aquasec/trivy:latest@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb

.PHONY: lint test build scan integration multiarch

lint:
	docker run --rm -v "$(CURDIR):/src:ro" $(SHELLCHECK_IMAGE) /src/vps-ss.sh /src/tests/test.sh /src/tests/integration.sh
	docker run --rm -i $(HADOLINT_IMAGE) < Dockerfile
	docker run --rm -v "$(CURDIR):/repo:ro" -w /repo $(ACTIONLINT_IMAGE) .github/workflows/ci.yml .github/workflows/docker-publish.yml

test: lint
	bash tests/test.sh

build:
	docker build --pull -t $(IMAGE) .

scan:
	docker volume create vps-ss-trivy-cache >/dev/null
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v vps-ss-trivy-cache:/root/.cache $(TRIVY_IMAGE) image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(IMAGE)

integration:
	IMAGE=$(IMAGE) SKIP_BUILD=1 bash tests/integration.sh

multiarch:
	docker buildx build --pull --platform linux/amd64,linux/arm64 --output=type=cacheonly .
