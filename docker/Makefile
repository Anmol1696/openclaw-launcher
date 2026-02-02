DOCKER        := $(shell which docker)
DOCKER_REPO   := ghcr.io/anmol1696/openclaw-launcher
DOCKERFILE    := $(CURDIR)/Dockerfile
CONTEXT       := $(CURDIR)/..
PLATFORMS     := linux/amd64,linux/arm64

# Default flavor
FLAVOR        ?= base

# All flavors in dependency order
FLAVORS       := base lite full

.PHONY: help build build-all push push-all run shell verify verify-all clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
#  Build
# ---------------------------------------------------------------------------

build: ## Build a single flavor (FLAVOR=base|lite|full)
	$(DOCKER) build \
		--target $(FLAVOR) \
		-f $(DOCKERFILE) \
		-t $(DOCKER_REPO):$(FLAVOR) \
		$(CONTEXT)

build-all: ## Build all flavors
	@for f in $(FLAVORS); do \
		echo "==> Building $$f"; \
		$(MAKE) build FLAVOR=$$f; \
	done

# ---------------------------------------------------------------------------
#  Multi-arch (requires buildx)
# ---------------------------------------------------------------------------

build-multiarch: ## Build multi-arch for a single flavor (no load, validates only)
	$(DOCKER) buildx build \
		--target $(FLAVOR) \
		-f $(DOCKERFILE) \
		--platform $(PLATFORMS) \
		$(CONTEXT)

build-multiarch-all: ## Build multi-arch for all flavors
	@for f in $(FLAVORS); do \
		echo "==> Building $$f (multi-arch)"; \
		$(MAKE) build-multiarch FLAVOR=$$f; \
	done

# ---------------------------------------------------------------------------
#  Push
# ---------------------------------------------------------------------------

push: ## Build + push a single flavor to GHCR (multi-arch)
	$(DOCKER) buildx build \
		--target $(FLAVOR) \
		-f $(DOCKERFILE) \
		--platform $(PLATFORMS) \
		--push \
		-t $(DOCKER_REPO):$(FLAVOR) \
		$(CONTEXT)

push-all: ## Build + push all flavors to GHCR (multi-arch)
	@for f in $(FLAVORS); do \
		echo "==> Pushing $$f"; \
		$(MAKE) push FLAVOR=$$f; \
	done

# ---------------------------------------------------------------------------
#  Run / Debug
# ---------------------------------------------------------------------------

run: ## Run a flavor (FLAVOR=base|lite|full)
	$(DOCKER) run --rm -it \
		-p 127.0.0.1:18789:18789 \
		$(DOCKER_REPO):$(FLAVOR)

shell: ## Open a shell in a flavor
	$(DOCKER) run --rm -it \
		--entrypoint /bin/bash \
		$(DOCKER_REPO):$(FLAVOR)

# ---------------------------------------------------------------------------
#  Verify
# ---------------------------------------------------------------------------

verify: ## Verify tools are present in a flavor
	@echo "==> Verifying $(FLAVOR)"
	@$(DOCKER) run --rm $(DOCKER_REPO):$(FLAVOR) jq --version
	@$(DOCKER) run --rm $(DOCKER_REPO):$(FLAVOR) rg --version | head -1
	@$(DOCKER) run --rm $(DOCKER_REPO):$(FLAVOR) fd --version
	@$(DOCKER) run --rm $(DOCKER_REPO):$(FLAVOR) sqlite3 --version
	@if [ "$(FLAVOR)" = "lite" ] || [ "$(FLAVOR)" = "full" ]; then \
		$(DOCKER) run --rm $(DOCKER_REPO):$(FLAVOR) python3 -c "import pandas; print('pandas', pandas.__version__)"; \
		$(DOCKER) run --rm $(DOCKER_REPO):$(FLAVOR) python3 -c "import matplotlib; print('matplotlib', matplotlib.__version__)"; \
		$(DOCKER) run --rm $(DOCKER_REPO):$(FLAVOR) python3 -c "from PIL import Image; print('Pillow OK')"; \
	fi
	@if [ "$(FLAVOR)" = "full" ]; then \
		$(DOCKER) run --rm $(DOCKER_REPO):$(FLAVOR) ffmpeg -version 2>&1 | head -1; \
		$(DOCKER) run --rm $(DOCKER_REPO):$(FLAVOR) npx playwright --version; \
	fi
	@echo "==> $(FLAVOR) OK"

verify-all: ## Verify all flavors
	@for f in $(FLAVORS); do \
		$(MAKE) verify FLAVOR=$$f; \
	done

# ---------------------------------------------------------------------------
#  Cleanup
# ---------------------------------------------------------------------------

clean: ## Remove all local openclaw-launcher images
	@for f in $(FLAVORS); do \
		$(DOCKER) rmi $(DOCKER_REPO):$$f 2>/dev/null || true; \
	done
	@echo "Cleaned"
