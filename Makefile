
################################################################################
# Variables                                                                    #
################################################################################

export GO111MODULE ?= on
export GOPROXY ?= https://proxy.golang.org
export GOSUMDB ?= sum.golang.org

GIT_COMMIT  = $(shell git rev-list -1 HEAD)
GIT_VERSION ?= $(shell git describe --always --abbrev=7 --dirty)
# By default, disable CGO_ENABLED. See the details on https://golang.org/cmd/cgo
# Override with CGO=1 for SQLite support: make ci-test CGO=1
CGO         ?= 0
BINARIES    ?= nzovu

PROTOC ?= protoc

# Version of "protoc" to use
# Must also specify a protobuf "suite" version from https://github.com/protocolbuffers/protobuf/releases
PROTOC_VERSION = 32.0
PROTOBUF_SUITE_VERSION = 32.0

# name of protoc-gen-go when protoc-gen-go --version is run.
PROTOC_GEN_GO_NAME = "protoc-gen-go"
ifdef REL_VERSION
	NZOVU_VERSION := $(REL_VERSION)
else
	NZOVU_VERSION := edge
endif

LOCAL_ARCH := $(shell uname -m)
ifeq ($(LOCAL_ARCH),x86_64)
	TARGET_ARCH_LOCAL=amd64
else ifeq ($(shell echo $(LOCAL_ARCH) | head -c 5),armv8)
	TARGET_ARCH_LOCAL=arm64
else ifeq ($(shell echo $(LOCAL_ARCH) | head -c 4),armv)
	TARGET_ARCH_LOCAL=arm
else ifeq ($(shell echo $(LOCAL_ARCH) | head -c 5),arm64)
	TARGET_ARCH_LOCAL=arm64
else ifeq ($(shell echo $(LOCAL_ARCH) | head -c 7),aarch64)
	TARGET_ARCH_LOCAL=arm64
else
	TARGET_ARCH_LOCAL=amd64
endif
export GOARCH ?= $(TARGET_ARCH_LOCAL)

ifeq ($(GOARCH),amd64)
	LATEST_TAG?=latest
else
	LATEST_TAG?=latest-$(GOARCH)
endif

LOCAL_OS := $(shell uname)
ifeq ($(LOCAL_OS),Linux)
   TARGET_OS_LOCAL = linux
else ifeq ($(LOCAL_OS),Darwin)
   TARGET_OS_LOCAL = darwin
else
   TARGET_OS_LOCAL = windows
   PROTOC_GEN_GO_NAME := "protoc-gen-go.exe"
endif
export GOOS ?= $(TARGET_OS_LOCAL)

PROTOC_GEN_GO_VERSION = v1.36.9
PROTOC_GEN_GO_GRPC_VERSION = 1.5.1
PROTOC_GEN_GRPC_GATEWAY_VERSION = v2.30.0

# Default docker container and e2e test targets.
TARGET_OS ?= linux
TARGET_ARCH ?= amd64
TEST_OUTPUT_FILE_PREFIX ?= ./test_report

GOLANGCI_LINT_TAGS=subtlecrypto
ifeq ($(GOOS),windows)
	BINARY_EXT_LOCAL:=.exe
	GOLANGCI_LINT:=golangci-lint.exe
	export ARCHIVE_EXT = .zip
else
	BINARY_EXT_LOCAL:=
	GOLANGCI_LINT:=golangci-lint
	export ARCHIVE_EXT = .tar.gz
endif
GOLANGCI_LINT_VERSION ?= v2.5.0
TOOL_BIN_DIR := $(CURDIR)/bin
GOLANGCI_LINT_BIN := $(TOOL_BIN_DIR)/$(GOLANGCI_LINT)

export BINARY_EXT ?= $(BINARY_EXT_LOCAL)

OUT_DIR := ./dist

################################################################################
# Go build details                                                             #
################################################################################
BASE_PACKAGE_NAME := github.com/adrien19/nzovu

# Version information to inject at build time
BUILD_DATE := $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')
VERSION_PKG := $(BASE_PACKAGE_NAME)/pkg/version
LDFLAGS := -X '$(VERSION_PKG).Version=$(NZOVU_VERSION)' \
           -X '$(VERSION_PKG).GitCommit=$(GIT_COMMIT)' \
           -X '$(VERSION_PKG).BuildDate=$(BUILD_DATE)'

ifeq ($(origin DEBUG), undefined)
  BUILDTYPE_DIR:=release
else ifeq ($(DEBUG),0)
  BUILDTYPE_DIR:=release
else
  BUILDTYPE_DIR:=debug
  GCFLAGS:=-gcflags="all=-N -l"
  $(info Build with debugger information)
endif

NZOVU_OUT_DIR := $(OUT_DIR)/$(GOOS)_$(GOARCH)/$(BUILDTYPE_DIR)
NZOVU_LINUX_OUT_DIR := $(OUT_DIR)/linux_$(GOARCH)/$(BUILDTYPE_DIR)


################################################################################
# Target: build                                                                #
################################################################################
.PHONY: build
NZOVU_BINS:=$(foreach ITEM,$(BINARIES),$(NZOVU_OUT_DIR)/$(ITEM)$(BINARY_EXT))
build: $(NZOVU_BINS)

################################################################################
# Target: build-full (build with ALL storage backends including SQLite)       #
################################################################################
.PHONY: build-full
build-full:
	@echo "Building Nzovu with SQLite support..."
	@mkdir -p $(NZOVU_OUT_DIR)
	CGO_ENABLED=1 go build $(GCFLAGS) -ldflags="$(LDFLAGS)" -tags=sqlite \
	  -o $(NZOVU_OUT_DIR)/nzovu$(BINARY_EXT) .
	@echo "✓ Binary built with SQLite and Schema Registry support"

# Generate builds for nzovu binaries for the target
# Params:
# $(1): the file name for the target
# $(2): the binary name for the target
# $(3): the goos for the target
# $(4): the goarch for the target
# $(5): the output directory
define genBinariesForTarget
.PHONY: $(5)/$(1)
$(5)/$(1):
	CGO_ENABLED=$(CGO) GOOS=$(3) GOARCH=$(4) go build $(GCFLAGS) -ldflags="$(LDFLAGS)" -tags=$(NZOVU_GO_BUILD_TAGS) \
	  -o $(5)/$(1) \
	  .
endef

# Generate binary targets
$(foreach ITEM,$(BINARIES),$(eval $(call genBinariesForTarget,$(ITEM)$(BINARY_EXT),.,$(GOOS),$(GOARCH),$(NZOVU_OUT_DIR))))


################################################################################
# Target: ci-build (optimized binary builds for CI)                            #
################################################################################
.PHONY: ci-build
ci-build:
	@echo "Building optimized binaries for CI..."
	mkdir -p dist
	CGO_ENABLED=$(CGO) GOOS=$(GOOS) GOARCH=$(GOARCH) \
		go build -v -trimpath \
		-ldflags="-s -w $(LDFLAGS)" \
		-o dist/nzovu-$(GOOS)-$(GOARCH)$(BINARY_EXT) \
		.

################################################################################
# Target: build-linux                                                          #
################################################################################
BUILD_LINUX_BINS:=$(foreach ITEM,$(BINARIES),$(NZOVU_LINUX_OUT_DIR)/$(ITEM))
build-linux: $(BUILD_LINUX_BINS)

# Generate linux binaries targets to build linux docker image
ifneq ($(GOOS), linux)
# Linux targets are handled by the main target now
endif


################################################################################
# Target: check-gotestsum                                                      #
################################################################################
.PHONY: check-gotestsum
check-gotestsum:
	@which gotestsum > /dev/null || { \
		echo "Installing gotestsum..."; \
		go install gotest.tools/gotestsum@latest; \
	}

################################################################################
# Target: test                                                                 #
################################################################################
.PHONY: test
test: check-gotestsum
	CGO_ENABLED=$(CGO) \
		gotestsum \
			--jsonfile $(TEST_OUTPUT_FILE_PREFIX)_unit.json \
			--format pkgname-and-test-fails \
			-- \
				-tags=test_dep \
				./pkg/... ./internal/... ./cmd/... ./client/...\
				$(COVERAGE_OPTS)

################################################################################
# Target: test-sqlite (run tests with SQLite support)                         #
################################################################################
.PHONY: test-sqlite
test-sqlite: check-gotestsum
	CGO_ENABLED=1 \
		gotestsum \
			--jsonfile $(TEST_OUTPUT_FILE_PREFIX)_unit_sqlite.json \
			--format pkgname-and-test-fails \
			-- \
				-tags="test_dep sqlite" \
				./pkg/... ./internal/... ./cmd/... ./client/... \
				$(COVERAGE_OPTS)

################################################################################
# Target: ci-test (optimized for CI with coverage)                             #
################################################################################
.PHONY: ci-test
ci-test: check-gotestsum
	CGO_ENABLED=$(CGO) \
		gotestsum \
			--jsonfile $(TEST_OUTPUT_FILE_PREFIX)_unit.json \
			--junitfile $(TEST_OUTPUT_FILE_PREFIX)_unit.xml \
			--format standard-verbose \
			-- \
				-tags=test_dep \
				-count=1 \
				-coverprofile=coverage.out \
				-covermode=atomic \
				. ./pkg/... ./internal/... ./cmd/... ./client/...

################################################################################
# Target: ci-test-sqlite (run unit tests with SQLite support)                 #
################################################################################
.PHONY: ci-test-sqlite
ci-test-sqlite: check-gotestsum
	CGO_ENABLED=1 \
		gotestsum \
			--jsonfile $(TEST_OUTPUT_FILE_PREFIX)_unit_sqlite.json \
			--junitfile $(TEST_OUTPUT_FILE_PREFIX)_unit_sqlite.xml \
			--format standard-verbose \
			-- \
				-tags="test_dep sqlite" \
				-count=1 \
				-coverprofile=coverage_sqlite.out \
				-covermode=atomic \
				. ./pkg/... ./internal/... ./cmd/... ./client/...


.PHONY: test-no-gotestsum
test-no-gotestsum:
.PHONY: test-no-gotestsum
test-no-gotestsum:
	CGO_ENABLED=$(CGO) \
		go test -v \
				./pkg/... ./internal/... ./cmd/... ./client/... \
				$(COVERAGE_OPTS)

.PHONY: test-stable
test-stable:
	CGO_ENABLED=$(CGO) \
		go test -v \
				./client ./pkg/nzovu ./pkg/gateway ./pkg/metrics ./internal/server ./internal/util ./internal/encryption/... ./pkg/log \
				$(COVERAGE_OPTS)

.PHONY: test-stable-gotestsum
test-stable-gotestsum: check-gotestsum
	CGO_ENABLED=$(CGO) gotestsum \
		--jsonfile $(TEST_OUTPUT_FILE_PREFIX)_stable.json \
		--format pkgname-and-test-fails \
		-- \
		./client ./pkg/nzovu ./pkg/gateway ./pkg/metrics ./internal/server ./internal/util ./internal/encryption/... ./pkg/log \
		$(COVERAGE_OPTS)

################################################################################
# Target: test-race                                                            #
################################################################################
.PHONY: test-race
test-race:
	CGO_ENABLED=1 go test -race -tags="test_dep sqlite" ./pkg/... ./internal/... ./cmd/... ./client/...

################################################################################
# Target: build-test-image                                                     #
################################################################################
.PHONY: build-test-image
build-test-image:
	@echo "Building Nzovu test image with Postgres and SQLite support..."
	DOCKER_BUILDKIT=0 docker build -f images/Dockerfile.sqlite \
		--build-arg VERSION=$(NZOVU_VERSION) \
		--build-arg GIT_COMMIT=$(GIT_COMMIT) \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		-t nzovu:test-latest .
	@echo "Verifying image was built..."
	@docker images nzovu:test-latest --format "{{.Repository}}:{{.Tag}} ({{.ID}})" || (echo "ERROR: Image nzovu:test-latest not found!" && exit 1)

################################################################################
# Target: test-integration                                                     #
################################################################################
.PHONY: test-integration
test-integration: check-gotestsum build-test-image
	@echo "Running integration tests (requires Docker for testcontainers)..."
	CGO_ENABLED=$(CGO) \
		gotestsum \
			--jsonfile $(TEST_OUTPUT_FILE_PREFIX)_integration.json \
			--format pkgname-and-test-fails \
			-- \
				-tags="test_dep integration" \
				-timeout 30m \
				./tests/integration/... ./pkg/repository/postgres \
				$(COVERAGE_OPTS)

################################################################################
# Target: ci-test-integration (optimized for CI)                               #
################################################################################
.PHONY: ci-test-integration
ci-test-integration: check-gotestsum build-test-image
	@echo "Running integration tests in CI mode..."
	@echo "Verifying Docker image availability..."
	@docker images | grep nzovu | grep test-latest || (echo "ERROR: nzovu:test-latest not found in local images!" && docker images && exit 1)
	@docker inspect nzovu:test-latest >/dev/null 2>&1 && echo "✓ Image nzovu:test-latest is available" || (echo "ERROR: Cannot inspect image!" && exit 1)
	@echo "Docker info:"
	@docker info | grep -E "Server Version|Operating System|Storage Driver" || true
	CGO_ENABLED=$(CGO) \
		TESTCONTAINERS_RYUK_DISABLED=false \
		DOCKER_HOST=${DOCKER_HOST} \
		gotestsum \
			--jsonfile $(TEST_OUTPUT_FILE_PREFIX)_integration.json \
			--junitfile $(TEST_OUTPUT_FILE_PREFIX)_integration.xml \
			--format standard-verbose \
			-- \
				-tags="test_dep integration" \
				-count=1 \
				-timeout 30m \
				-v \
				./tests/integration/... ./pkg/repository/postgres

.PHONY: ci-test-integration-sqlite
ci-test-integration-sqlite: check-gotestsum build-test-image
	CGO_ENABLED=1 \
		TESTCONTAINERS_RYUK_DISABLED=false \
		DOCKER_HOST=${DOCKER_HOST} \
		gotestsum \
		--jsonfile $(TEST_OUTPUT_FILE_PREFIX)_integration_sqlite.json \
		--junitfile $(TEST_OUTPUT_FILE_PREFIX)_integration_sqlite.xml \
		--format standard-verbose \
		-- \
		-tags="test_dep integration sqlite" \
		-count=1 \
		-timeout 30m \
		./tests/integration/... ./pkg/repository/sqlite

################################################################################
# Target: test-e2e                                                             #
################################################################################
.PHONY: test-e2e
test-e2e: check-gotestsum
	@echo "Running E2E tests (requires Docker for testcontainers)..."
	CGO_ENABLED=$(CGO) \
		gotestsum \
			--jsonfile $(TEST_OUTPUT_FILE_PREFIX)_e2e.json \
			--format pkgname-and-test-fails \
			-- \
				-tags=test_dep \
				-timeout 45m \
				./tests/e2e/... \
				$(COVERAGE_OPTS)

################################################################################
# Target: ci-test-e2e (optimized for CI)                                       #
################################################################################
.PHONY: ci-test-e2e
ci-test-e2e: check-gotestsum
	@echo "Running E2E tests in CI mode..."
	CGO_ENABLED=$(CGO) \
		gotestsum \
			--jsonfile $(TEST_OUTPUT_FILE_PREFIX)_e2e.json \
			--junitfile $(TEST_OUTPUT_FILE_PREFIX)_e2e.xml \
			--format standard-verbose \
			-- \
				-tags=test_dep \
				-count=1 \
				-timeout 45m \
				./tests/e2e/...

################################################################################
# Target: test-all                                                             #
################################################################################
.PHONY: test-all
test-all: test test-integration test-e2e

################################################################################
# Target: ci-test-all (run all tests in CI mode)                               #
################################################################################
.PHONY: ci-test-all
ci-test-all: ci-test ci-test-integration ci-test-e2e

.PHONY: ci-release-test
ci-release-test: test-release test-install-script ci-test ci-test-sqlite test-race ci-test-integration ci-test-integration-sqlite ci-test-migrations ci-test-e2e

################################################################################
# Target: ci-test-migrations                                                   #
################################################################################
.PHONY: ci-test-migrations
ci-test-migrations:
	CGO_ENABLED=1 go test -tags="test_dep sqlite" ./pkg/repository/sqlite -run '^TestSchemaMigration_' -count=1
	CGO_ENABLED=1 go test -tags="test_dep integration" ./pkg/repository/postgres -run '^TestSchemaMigration_' -count=1

.PHONY: test-release
test-release:
	bash -n release/prepare.sh
	python3 release/prepare_test.py

.PHONY: test-install-script
test-install-script:
	bash install/install_test.sh

################################################################################
# Target: check-linter                                                         #
################################################################################
.PHONY: check-linter
check-linter:
	@which $(GOLANGCI_LINT) > /dev/null || { \
		echo "Installing golangci-lint..."; \
		go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$(GOLANGCI_LINT_VERSION); \
	}

################################################################################
# Target: lint                                                                 #
################################################################################
# Keep this pinned to $(GOLANGCI_LINT_VERSION) and install via go install in check-linter.
.PHONY: lint
lint: check-linter
	$(GOLANGCI_LINT) run --build-tags=$(GOLANGCI_LINT_TAGS) --timeout=20m

################################################################################
# Target: deps (download Go dependencies)                                      #
################################################################################
.PHONY: deps
deps:
	@echo "Downloading Go dependencies..."
	@go mod download

################################################################################
# Target: ci-lint (optimized for CI)                                           #
################################################################################
.PHONY: ci-lint
ci-lint: check-linter
	@$(GOLANGCI_LINT) cache clean
	@CGO_ENABLED=0 $(GOLANGCI_LINT) run --build-tags=$(GOLANGCI_LINT_TAGS) --timeout=20m

################################################################################
# Target: modtidy-all                                                          #
################################################################################
MODFILES := $(shell find . -name go.mod)

define modtidy-target
.PHONY: modtidy-$(1)
modtidy-$(1):
	cd "$(shell dirname $(1))" && CGO_ENABLED=$(CGO) go mod tidy -compat=1.26
endef

# Generate modtidy target action for each go.mod file
$(foreach MODFILE,$(MODFILES),$(eval $(call modtidy-target,$(MODFILE))))

# Enumerate all generated modtidy targets
TIDY_MODFILES:=$(foreach ITEM,$(MODFILES),modtidy-$(ITEM))

# Define modtidy-all action trigger to run make on all generated modtidy targets
.PHONY: modtidy-all
modtidy-all: $(TIDY_MODFILES)

################################################################################
# Target: modtidy                                                              #
################################################################################
.PHONY: modtidy
modtidy:
	go mod tidy

################################################################################
# Target: ui-deps (install UI dependencies)                                    #
################################################################################
.PHONY: ui-deps
ui-deps:
	@echo "Installing UI dependencies..."
	@cd cmd/nzovu/web-ui && npm install

################################################################################
# Target: ui-build (build UI CSS and binary)                                   #
################################################################################
.PHONY: ui-build
ui-build: ui-deps
	@echo "Building UI CSS..."
	@cd cmd/nzovu/web-ui && npm run build:css
	@echo "Building UI binary..."
	@mkdir -p $(NZOVU_OUT_DIR)
	@go build -ldflags "$(LDFLAGS)" -o $(NZOVU_OUT_DIR)/nzovu .

################################################################################
# Target: ui-watch (watch and rebuild UI CSS)                                  #
################################################################################
.PHONY: ui-watch
ui-watch: ui-deps
	@echo "Watching UI CSS for changes..."
	@cd cmd/nzovu/web-ui && npm run watch:css

################################################################################
# Target: ui-dev (run Nzovu with the UI in dev mode)                           #
################################################################################
# Usage:
#   make ui-dev                                  # default gRPC localhost:9000, UI :8081
#   make ui-dev UI_GRPC_ADDR=:9090               # custom gRPC address
#   make ui-dev UI_PORT=9000                     # custom UI listen port
################################################################################
UI_GRPC_ADDR?=localhost:9000
UI_PORT?=8081
NZOVU_UI_PUBLIC_ORIGIN?=http://localhost:$(UI_PORT)

.PHONY: ui-dev
ui-dev: ui-build
	@echo "Starting Nzovu with UI on :$(UI_PORT) (gRPC: $(UI_GRPC_ADDR))..."
	@NZOVU_UI_PUBLIC_ORIGIN="$(NZOVU_UI_PUBLIC_ORIGIN)" ./$(NZOVU_OUT_DIR)/nzovu web-ui start --port $(UI_PORT) --grpc-address $(UI_GRPC_ADDR) --skip-ssl


################################################################################
# Target: server-dev (run Nzovu server in dev mode)                      #
################################################################################
# Usage:
#   make server-dev                              # Use SQLite (default)
#   make server-dev DATABASE=nzovu.db      # Use SQLite
#   make server-dev DB=./data/nzovu.db     # Use SQLite (short form)
#   make server-dev STORAGE=postgres              # Use Postgres (override with POSTGRES_* vars)
################################################################################
.PHONY: server-dev
server-dev: build-full
	@mkdir -p logs
	@echo "Starting Nzovu in development mode..."
ifneq ($(filter postgres,$(STORAGE) $(STORAGE_TYPE)),)
	@echo "Using Postgres storage"; \
	PG_ARGS="--storage-type postgres"; \
	if [ -n "$(POSTGRES_DSN)" ]; then PG_ARGS="$$PG_ARGS --postgres-dsn $(POSTGRES_DSN)"; fi; \
	if [ -n "$(POSTGRES_HOST)" ]; then PG_ARGS="$$PG_ARGS --postgres-host $(POSTGRES_HOST)"; fi; \
	if [ -n "$(POSTGRES_PORT)" ]; then PG_ARGS="$$PG_ARGS --postgres-port $(POSTGRES_PORT)"; fi; \
	if [ -n "$(POSTGRES_USER)" ]; then PG_ARGS="$$PG_ARGS --postgres-user $(POSTGRES_USER)"; fi; \
	if [ -n "$(POSTGRES_PASSWORD)" ]; then PG_ARGS="$$PG_ARGS --postgres-password $(POSTGRES_PASSWORD)"; fi; \
	if [ -n "$(POSTGRES_DB)" ]; then PG_ARGS="$$PG_ARGS --postgres-db $(POSTGRES_DB)"; fi; \
	if [ -n "$(POSTGRES_SSLMODE)" ]; then PG_ARGS="$$PG_ARGS --postgres-sslmode $(POSTGRES_SSLMODE)"; fi; \
	./$(NZOVU_OUT_DIR)/nzovu server --dev --insecure $$PG_ARGS 2>&1 | tee logs/nzovu.log
else ifdef DATABASE
	@echo "Starting Nzovu in development mode with SQLite storage ($(DATABASE))..."
	@./$(NZOVU_OUT_DIR)/nzovu server --dev --storage-type sqlite --sqlite-db-path $(DATABASE) 2>&1 | tee logs/nzovu.log
else ifdef DB
	@echo "Starting Nzovu in development mode with SQLite storage ($(DB))..."
	@./$(NZOVU_OUT_DIR)/nzovu server --dev --storage-type sqlite --sqlite-db-path $(DB) 2>&1 | tee logs/nzovu.log
else
	@echo "Starting Nzovu in development mode with SQLite storage (default)..."
	@./$(NZOVU_OUT_DIR)/nzovu server --dev --storage-type sqlite --sqlite-db-path nzovu.db 2>&1 | tee logs/nzovu.log
endif


################################################################################
# Target: format                                                               #
################################################################################
.PHONY: format
format: modtidy-all
	# check if gofumpt and goimports are installed
	@which gofumpt > /dev/null || { \
		echo "Installing gofumpt..."; \
		go install mvdan.cc/gofumpt@latest; \
	}
	@which goimports > /dev/null || { \
		echo "Installing goimports..."; \
		go install golang.org/x/tools/cmd/goimports@latest; \
	}
	# run gofumpt and goimports on all Go files (excluding generated api files)
	gofumpt -l -w .
	find . -type f -name '*.go' -not -path "./api/*" -not -path "./vendor/*" | xargs goimports -local github.com/adrien19/ -w

################################################################################
# Target: check                                                                #
################################################################################
.PHONY: check
check: format test lint
	git status && [[ -z `git status -s` ]]


# Download Google API proto files (required for HTTP annotations)
################################################################################
# Target: get-googleapis                                                       #
################################################################################
.PHONY: get-googleapis
get-googleapis: ## Download Google API proto files for annotations
	@echo "Downloading Google API proto files..."
	@mkdir -p ./proto/google/api
	@curl -sSL https://raw.githubusercontent.com/googleapis/googleapis/master/google/api/annotations.proto \
		> ./proto/google/api/annotations.proto
	@curl -sSL https://raw.githubusercontent.com/googleapis/googleapis/master/google/api/http.proto \
		> ./proto/google/api/http.proto
	@curl -sSL https://raw.githubusercontent.com/googleapis/googleapis/master/google/api/field_behavior.proto \
		> ./proto/google/api/field_behavior.proto
	@echo "Google API proto files downloaded!"


################################################################################
# Target: init-proto                                                           #
################################################################################
.PHONY: init-proto
init-proto:
	go install google.golang.org/protobuf/cmd/protoc-gen-go@$(PROTOC_GEN_GO_VERSION)
	go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v$(PROTOC_GEN_GO_GRPC_VERSION)
	go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway@$(PROTOC_GEN_GRPC_GATEWAY_VERSION)
	go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-openapiv2@$(PROTOC_GEN_GRPC_GATEWAY_VERSION)
	@echo "init-proto completed!"


################################################################################
# Target: gen-proto                                                            #
################################################################################
PROTO_PREFIX:=github.com/adrien19/nzovu
GRPC_PROTOS:=$(shell ls proto)

# Generate archive files for each binary
# $(1): the binary name to be archived
define genProtoc
.PHONY: gen-proto-$(1)
gen-proto-$(1):
	$(PROTOC) --go_out=. --go_opt=module=$(PROTO_PREFIX) --go-grpc_out=. --go-grpc_opt=require_unimplemented_servers=false,module=$(PROTO_PREFIX) ./proto/$(1)/v1/*.proto
	# Generate gRPC-Gateway reverse proxy code (only for queueservice)
	@if [ "$(1)" = "queueservice" ]; then \
		$(PROTOC) --grpc-gateway_out=. \
			--grpc-gateway_opt=module=$(PROTO_PREFIX) \
			--grpc-gateway_opt=generate_unbound_methods=true \
			./proto/$(1)/v1/service.proto; \
	fi
	# Generate OpenAPI v2 documentation (only for queueservice)
	@if [ "$(1)" = "queueservice" ]; then \
		mkdir -p pkg/gateway && \
		$(PROTOC) --openapiv2_out=pkg/gateway \
			--openapiv2_opt=allow_merge=true,merge_file_name=nzovu \
			./proto/$(1)/v1/service.proto; \
		echo "Generated OpenAPI spec in pkg/gateway/ for embedding"; \
	fi
endef

$(foreach ITEM,$(GRPC_PROTOS),$(eval $(call genProtoc,$(ITEM))))

GEN_PROTOS:=$(foreach ITEM,$(filter-out google,$(GRPC_PROTOS)),gen-proto-$(ITEM))

.PHONY: gen-proto
gen-proto: init-proto check-proto-version $(GEN_PROTOS) modtidy

################################################################################
# Target: check-diff                                                           #
################################################################################
.PHONY: check-diff
check-diff:
	git diff --exit-code ./go.mod # check no changes
	git diff --exit-code ./go.sum # check no changes

################################################################################
# Target: check-proto-version                                                  #
################################################################################
.PHONY: check-proto-version
check-proto-version: ## Checking the version of proto related tools
	@test "$(shell protoc --version)" = "libprotoc $(PROTOC_VERSION)" \
	|| { echo "please use protoc $(PROTOC_VERSION) (protobuf $(PROTOBUF_SUITE_VERSION)) to generate proto"; exit 1; }

	@test "$(shell protoc-gen-go-grpc --version)" = "protoc-gen-go-grpc $(PROTOC_GEN_GO_GRPC_VERSION)" \
	|| { echo "please use protoc-gen-go-grpc $(PROTOC_GEN_GO_GRPC_VERSION) to generate proto"; exit 1; }

	@test "$(shell protoc-gen-go --version 2>&1)" = "$(PROTOC_GEN_GO_NAME) $(PROTOC_GEN_GO_VERSION)" \
	|| { echo "please use protoc-gen-go $(PROTOC_GEN_GO_VERSION) to generate proto"; exit 1; }


################################################################################
# Target: check-proto-diff                                                     #
################################################################################
.PHONY: check-proto-diff
check-proto-diff:
	git diff --exit-code -- api pkg/gateway/nzovu.swagger.json
	@test -z "$$(git ls-files --others --exclude-standard -- api pkg/gateway/nzovu.swagger.json)"


################################################################################
# Target: docker                                                               #
################################################################################
include docker/docker.mk
################################################################################
# Target: deployment                                                           #
################################################################################

# Storage backend selection (default: postgres)
# Usage:
#   make deploy-up STORAGE=postgres   # PostgreSQL storage (default, instrumented)
#   make deploy-up STORAGE=sqlite     # SQLite storage (instrumented)
STORAGE ?= postgres

# Select the appropriate docker-compose file based on storage backend
ifeq ($(STORAGE),postgres)
	STORAGE_COMPOSE_FILE := docker-compose.postgres.yaml
else ifeq ($(STORAGE),sqlite)
	STORAGE_COMPOSE_FILE := docker-compose.sqlite.yaml
else
	$(error Invalid STORAGE value: $(STORAGE). Valid values: postgres, sqlite)
endif

.PHONY: deploy-up
deploy-up: ## Start Nzovu services with selected storage backend (STORAGE=postgres|sqlite)
	@echo "Starting Nzovu with $(STORAGE) storage..."
	cd deploy && docker-compose -f $(STORAGE_COMPOSE_FILE) up -d

.PHONY: deploy-down
deploy-down: ## Stop Nzovu services
	@echo "Stopping Nzovu with $(STORAGE) storage..."
	cd deploy && docker-compose -f $(STORAGE_COMPOSE_FILE) down

.PHONY: deploy-logs
deploy-logs: ## View Nzovu service logs
	cd deploy && docker-compose -f $(STORAGE_COMPOSE_FILE) logs -f

.PHONY: monitoring-up
monitoring-up: ## Start monitoring stack (Prometheus + Grafana)
	cd deploy && docker-compose -f docker-compose.monitoring.yaml up -d

.PHONY: monitoring-down
monitoring-down: ## Stop monitoring stack
	cd deploy && docker-compose -f docker-compose.monitoring.yaml down

.PHONY: monitoring-logs
monitoring-logs: ## View monitoring stack logs
	cd deploy && docker-compose -f docker-compose.monitoring.yaml logs -f

.PHONY: deploy-all
deploy-all: ## Start all services (Nzovu + Monitoring) with selected storage
	@echo "Starting Nzovu with $(STORAGE) storage and monitoring stack..."
	cd deploy && docker-compose -f $(STORAGE_COMPOSE_FILE) up -d && docker-compose -f docker-compose.monitoring.yaml up -d

.PHONY: deploy-clean
deploy-clean: ## Stop all services and remove volumes
	@echo "Cleaning up Nzovu with $(STORAGE) storage and monitoring..."
	cd deploy && docker-compose -f $(STORAGE_COMPOSE_FILE) down -v && docker-compose -f docker-compose.monitoring.yaml down -v

.PHONY: deploy-rebuild
deploy-rebuild: ## Rebuild and restart Nzovu
	@echo "Rebuilding Nzovu with $(STORAGE) storage..."
	@echo "Building images without cache..."
	cd deploy && docker-compose -f $(STORAGE_COMPOSE_FILE) build --no-cache nzovusvc nzovu-ui
	@echo "Recreating and starting containers..."
	cd deploy && docker-compose -f $(STORAGE_COMPOSE_FILE) up -d --force-recreate nzovusvc nzovu-ui
	@echo "Rebuild complete."

.PHONY: deploy-validate
deploy-validate: ## Validate monitoring stack is working
	./deploy/validate-monitoring.sh

.PHONY: deploy-status
deploy-status: ## Show status of deployed services
	@echo "=== Nzovu Services ($(STORAGE) storage) ==="
	@cd deploy && docker-compose -f $(STORAGE_COMPOSE_FILE) ps
	@echo ""
	@echo "=== Monitoring Services ==="
	@cd deploy && docker-compose -f docker-compose.monitoring.yaml ps 2>/dev/null || echo "Monitoring stack not running"

.PHONY: pre-commit-validation
pre-commit-validation: modtidy-all format ci-lint ci-test-all
	@echo "Pre-commit validation passed! Your code is properly formatted, linted,\
	 and all stable tests are passing. You can proceed with committing your changes."
