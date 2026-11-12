# ---------------------------------------------------------
# Project settings.
# ---------------------------------------------------------

.DEFAULT_GOAL := check

APP := jaeger
VERSION ?= 2.23.0
IMAGE ?= deathlabs/$(APP):$(VERSION)
JAEGER_BUILD_CONTEXT := jaeger
JAEGER_DOCKERFILE_PATH := $(JAEGER_BUILD_CONTEXT)/Dockerfile
JAEGER_CHART_PATH := $(JAEGER_BUILD_CONTEXT)/chart
JAEGER_VEX_YAML_PATH := $(JAEGER_BUILD_CONTEXT)/vex.yaml
JAEGER_VEX_JSON_PATH := $(JAEGER_BUILD_CONTEXT)/vex.json
SBOM ?= $(APP)-sbom.syft.json
PACKAGE ?= zarf-package-$(APP)-amd64-0.1.0.tar.zst
VEX_AUTHOR ?= Victor Fernandez III
VEX_ID_BASE ?= $(APP)
GRYPE_FAILURE_THRESHOLD ?= high
HADOLINT_FAILURE_THRESHOLD ?= error

# ---------------------------------------------------------
# Run all local static checks.
# ---------------------------------------------------------

.PHONY: check
.SILENT: check
check: secrets dockerfile-lint helm-lint

# ---------------------------------------------------------
# Check the repository for secrets.
# ---------------------------------------------------------

.PHONY: secrets
.SILENT: secrets
secrets:
	trufflehog filesystem . --fail --no-update

# ---------------------------------------------------------
# Check the Dockerfile.
# ---------------------------------------------------------

.PHONY: dockerfile-lint
.SILENT: dockerfile-lint
dockerfile-lint:
	hadolint --failure-threshold "$(HADOLINT_FAILURE_THRESHOLD)" "$(JAEGER_DOCKERFILE_PATH)"

# ---------------------------------------------------------
# Check the Helm chart.
# ---------------------------------------------------------

.PHONY: helm-lint
.SILENT: helm-lint
helm-lint:
	helm lint "$(JAEGER_CHART_PATH)"
	helm template "$(APP)" "$(JAEGER_CHART_PATH)" --namespace "$(APP)" >/dev/null

# ---------------------------------------------------------
# Build the Jaeger image from source.
# ---------------------------------------------------------

.PHONY: build
.SILENT: build
build:
	docker build --pull --file "$(JAEGER_DOCKERFILE_PATH)" --tag "$(IMAGE)" "$(JAEGER_BUILD_CONTEXT)"

# ---------------------------------------------------------
# Generate the image VEX statements.
# ---------------------------------------------------------

define VEX_FILTER
{
  "@context": "https://openvex.dev/ns/v0.2.0",
  "@id": env.VEX_ID,
  "author": env.VEX_AUTHOR,
  "timestamp": env.VEX_TIMESTAMP,
  "version": 1,
  "statements": [
    .advisories[] | {
      "vulnerability": {
        "name": .vulnerability
      },
      "products": [
        .products[] | {
          "@id": .
        }
      ],
      "status": .status,
      "justification": .justification,
      "impact_statement": .impact_statement
    }
  ]
}
endef

export VEX_FILTER

.PHONY: vex
.SILENT: vex
vex:
	export VEX_ID="$(VEX_ID_BASE)" && \
	export VEX_AUTHOR="$(VEX_AUTHOR)" && \
	export VEX_TIMESTAMP="$$(date -u +'%Y-%m-%dT%H:%M:%SZ')" && \
	yq -j '.' "$(JAEGER_VEX_YAML_PATH)" | jq "$$VEX_FILTER" > "$(JAEGER_VEX_JSON_PATH)"

# ---------------------------------------------------------
# Generate the image SBOM.
# ---------------------------------------------------------

.PHONY: sbom
.SILENT: sbom
sbom: build
	SYFT_GOLANG_CAPTURE_SYMBOLS=all syft "$(IMAGE)" --output "syft-json=$(SBOM)"

# ---------------------------------------------------------
# Scan the image SBOM.
# ---------------------------------------------------------

.PHONY: sbom-scan
.SILENT: sbom-scan
sbom-scan: sbom vex
	grype "sbom:$(SBOM)" --vex "$(JAEGER_VEX_JSON_PATH)" --fail-on "$(GRYPE_FAILURE_THRESHOLD)"

# ---------------------------------------------------------
# Create the Zarf package.
# ---------------------------------------------------------

.PHONY: package
.SILENT: package
package: sbom-scan
	uds zarf package create --confirm

# ---------------------------------------------------------
# Deploy the Zarf package.
# ---------------------------------------------------------

.PHONY: deploy
.SILENT: deploy
deploy: package
	uds zarf package deploy "$(PACKAGE)" --confirm

# ---------------------------------------------------------
# Remove the Zarf package.
# ---------------------------------------------------------

.PHONY: remove
.SILENT: remove
remove:
	uds zarf package remove "$(APP)" --confirm
