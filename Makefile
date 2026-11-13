VERSION := $(shell cat VERSION)
IMAGE ?= local/vps-ss:$(VERSION)
CLIENT_IMAGE ?= local/vps-ss-client:$(VERSION)
SHELLCHECK_IMAGE ?= koalaman/shellcheck:stable@sha256:bb596a0d169b85ddd81d8b6d3a2ff6d5baf5fca10b97f575ebc647c3dff62b3d
HADOLINT_IMAGE ?= hadolint/hadolint:latest-alpine@sha256:a1d49ae1a4e83c1dbad26b8c1ad7588c8bd1e04f4866b34ad3cac50335198552
ACTIONLINT_IMAGE ?= rhysd/actionlint:latest@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667
ACTIONLINT_BIN ?=
TRIVY_IMAGE ?= ghcr.io/aquasecurity/trivy:latest@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb
TRIVY_DB_REPOSITORY ?= ghcr.io/aquasecurity/trivy-db:2

.PHONY: lint test build build-client scan scan-client scan-source integration multiarch verify

lint:
	docker run --rm -v "$(CURDIR):/src:ro" $(SHELLCHECK_IMAGE) /src/vps-ss.sh /src/tests/test.sh /src/tests/integration.sh /src/scripts/build-release-assets.sh /src/scripts/check-version.sh
	docker run --rm -i $(HADOLINT_IMAGE) < Dockerfile
	@if [ -n "$(ACTIONLINT_BIN)" ]; then \
		"$(ACTIONLINT_BIN)" .github/workflows/ci.yml .github/workflows/docker-publish.yml; \
	else \
		docker run --rm -v "$(CURDIR):/repo:ro" -w /repo $(ACTIONLINT_IMAGE) .github/workflows/ci.yml .github/workflows/docker-publish.yml; \
	fi
	python3 -c 'import ast, pathlib; [ast.parse(path.read_text()) for path in pathlib.Path("skills/cloudflare-vps-prep/scripts").glob("*.py")]'
	./scripts/check-version.sh

test: lint
	bash tests/test.sh

build:
	docker build --pull -t $(IMAGE) .

build-client:
	docker build --pull --target client -t $(CLIENT_IMAGE) .

scan:
	docker volume create vps-ss-trivy-cache >/dev/null
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v vps-ss-trivy-cache:/root/.cache $(TRIVY_IMAGE) image --db-repository $(TRIVY_DB_REPOSITORY) --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(IMAGE)

scan-client:
	docker volume create vps-ss-trivy-cache >/dev/null
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v vps-ss-trivy-cache:/root/.cache $(TRIVY_IMAGE) image --db-repository $(TRIVY_DB_REPOSITORY) --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(CLIENT_IMAGE)

scan-source:
	docker volume create vps-ss-trivy-cache >/dev/null
	docker run --rm -v "$(CURDIR):/src:ro" -v vps-ss-trivy-cache:/root/.cache $(TRIVY_IMAGE) fs --scanners secret,misconfig --exit-code 1 /src

integration:
	IMAGE=$(IMAGE) CLIENT_IMAGE=$(CLIENT_IMAGE) SKIP_BUILD=1 bash tests/integration.sh

multiarch:
	docker buildx build --pull --platform linux/amd64,linux/arm64 --output=type=cacheonly .
	docker buildx build --pull --target client --platform linux/amd64,linux/arm64 --output=type=cacheonly .

verify: test build build-client scan scan-client scan-source integration multiarch
