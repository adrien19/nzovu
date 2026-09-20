IMAGE ?= nzovu
PROJECT ?= adrien19
DOCKER_REGISTRY ?= ghcr.io

# Version information
GIT_COMMIT := $(shell git rev-list -1 HEAD)
BUILD_DATE := $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')
ifdef REL_VERSION
	VERSION := $(REL_VERSION)
else
	VERSION := edge
endif

build-image:
	@echo "Building Nzovu Docker image: $(DOCKER_REGISTRY)/$(PROJECT)/$(IMAGE):$(VERSION)"
	docker build -t $(DOCKER_REGISTRY)/$(PROJECT)/$(IMAGE):$(VERSION) \
		--build-arg VERSION=$(VERSION) \
		--build-arg GIT_COMMIT=$(GIT_COMMIT) \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		-f Dockerfile ..

build-push: build-image
	@echo "Pushing Nzovu Docker image: $(DOCKER_REGISTRY)/$(PROJECT)/$(IMAGE):$(VERSION)"
	docker push $(DOCKER_REGISTRY)/$(PROJECT)/$(IMAGE):$(VERSION)

.PHONY: build-image build-push
