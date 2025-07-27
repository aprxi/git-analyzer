# git-insight Makefile
# Containerized build system for git statistics tool

# Detect container runtime (Docker or Podman)
DOCKER_CHECK := $(shell command -v docker 2>/dev/null)
PODMAN_CHECK := $(shell command -v podman 2>/dev/null)
ifdef DOCKER_CHECK
	RUNTIME_CMD := docker
else ifdef PODMAN_CHECK
	RUNTIME_CMD := podman
else
	$(error Neither Docker nor Podman is installed. Please install one of them.)
endif

# Configuration
IMAGE_NAME := git-insight-builder
CONTAINER_NAME := git-insight-build
BINARY_NAME := git-insight

# Default args for run command
args ?= 

.PHONY: build build-image clean shell run help

# Default target
all: build

# Build the container image
build-image:
	@echo "🔧 Building git-insight builder container..."
	@$(RUNTIME_CMD) build -f Dockerfile.build -t $(IMAGE_NAME) .

# Build the project inside container
build: build-image
	@echo "🦎 Building git-insight with Zig inside container..."
	@$(RUNTIME_CMD) run --rm \
		--name $(CONTAINER_NAME) \
		-v $(PWD):/workspace \
		-w /workspace \
		$(IMAGE_NAME) \
		/bin/bash -c "zig build -Doptimize=ReleaseSafe"
	@echo "✅ Build complete"
	@if [ -f "zig-out/bin/$(BINARY_NAME)" ]; then \
		echo "📊 Binary size: $$(du -h zig-out/bin/$(BINARY_NAME) | cut -f1)"; \
	fi

# Run the built binary (on host, not in container)
run:
	@if [ ! -f "zig-out/bin/$(BINARY_NAME)" ]; then \
		echo "❌ Binary not found. Run 'make build' first."; \
		exit 1; \
	fi
	@echo "🚀 Running git-insight..."
	@./zig-out/bin/$(BINARY_NAME) $(args)

# Interactive shell for development
shell: build-image
	@echo "🔧 Launching interactive shell inside build container..."
	@$(RUNTIME_CMD) run --rm -it \
		--name $(CONTAINER_NAME)-shell \
		-v $(PWD):/workspace \
		-w /workspace \
		$(IMAGE_NAME) \
		/bin/bash

# Clean build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	@rm -rf zig-out zig-cache .zig-cache
	@echo "✅ Clean complete"

# Clean everything including Docker image
clean-all: clean
	@echo "🧹 Removing Docker/Podman image..."
	@$(RUNTIME_CMD) rmi $(IMAGE_NAME) 2>/dev/null || true
	@echo "✅ Full clean complete"

# Help message
help:
	@echo "git-insight Build System"
	@echo "======================="
	@echo ""
	@echo "Available targets:"
	@echo "  make build       - Build the git-insight binary (default)"
	@echo "  make run         - Run the built binary"
	@echo "  make shell       - Launch interactive shell in container"
	@echo "  make clean       - Clean build artifacts"
	@echo "  make clean-all   - Clean everything including container image"
	@echo "  make help        - Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make build"
	@echo "  make run args='--since=\"8 weeks ago\"'"
	@echo ""
	@echo "Container runtime: $(RUNTIME_CMD)"