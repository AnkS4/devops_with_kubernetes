# ============================================================================
# PROJECT CONFIGURATION
# ============================================================================

# Core project settings
PROJECT_NAME := log-output
VERSION ?= latest
ENVIRONMENT ?= development

# Docker configuration
IMAGE_NAME := $(PROJECT_NAME)-app
IMAGE_TAG := $(VERSION)
DOCKERFILE ?= Dockerfile
DOCKER_BUILD_ARGS ?= 

# Kubernetes/k3d configuration
CLUSTER_NAME := $(PROJECT_NAME)-cluster
POD_LABEL := $(PROJECT_NAME)-pod
NAMESPACE ?= default
AGENTS ?= 2

# Timeouts and limits
CLUSTER_TIMEOUT ?= 300s
POD_READY_TIMEOUT ?= 30
LOG_TAIL_LINES ?= 50

# Network configuration
# DNS_SERVER := 1.1.1.1 # Cloudflare DNS (commented out due to k3d issues)
HOST_PORT ?= 8080
CONTAINER_PORT ?= 8000

# Build configuration
BUILD_CONTEXT ?= .
BUILD_QUIET ?= true

# Development settings
DEV_MODE ?= false
DEBUG_ENABLED ?= false

# ============================================================================
# DERIVED VARIABLES (DO NOT MODIFY)
# ============================================================================

# Conditional settings based on environment
ifeq ($(ENVIRONMENT),production)
    IMAGE_PULL_POLICY := Always
    RESTART_POLICY := Always
else
    IMAGE_PULL_POLICY := IfNotPresent
    RESTART_POLICY := Never
endif

# Build flags
ifeq ($(BUILD_QUIET),true)
    DOCKER_BUILD_FLAGS := --quiet
else
    DOCKER_BUILD_FLAGS := 
endif

# Debug settings
# Debug settings - Enhanced version
ifeq ($(DEBUG_ENABLED),true)
    KUBECTL_VERBOSITY := --v=6
    DOCKER_BUILD_FLAGS := --progress=plain
    K3D_VERBOSITY := 
    REDIRECT_OUTPUT := 
	NO_HEADERS_FLAG :=
else
    KUBECTL_VERBOSITY := 
    DOCKER_BUILD_FLAGS := --quiet
    K3D_VERBOSITY := --quiet
    REDIRECT_OUTPUT := >/dev/null 2>&1
	NO_HEADERS_FLAG := --no-headers
endif

# ============================================================================
# PHONY TARGETS
# ============================================================================
.PHONY: clean build cluster deploy all status logs shell rebuild help check-deps dev watch config

.DEFAULT_GOAL := all

# ============================================================================
# MAIN TARGETS
# ============================================================================

# Default target
all: check-deps build cluster deploy

# Show current configuration
config:
	@echo "📋 Current Configuration"
	@echo "======================="
	@echo "Project Settings:"
	@echo "  PROJECT_NAME: $(PROJECT_NAME)"
	@echo "  VERSION: $(VERSION)"
	@echo "  ENVIRONMENT: $(ENVIRONMENT)"
	@echo ""
	@echo "Docker Settings:"
	@echo "  IMAGE_NAME: $(IMAGE_NAME)"
	@echo "  IMAGE_TAG: $(IMAGE_TAG)"
	@echo "  DOCKERFILE: $(DOCKERFILE)"
	@echo "  BUILD_CONTEXT: $(BUILD_CONTEXT)"
	@echo ""
	@echo "Kubernetes Settings:"
	@echo "  CLUSTER_NAME: $(CLUSTER_NAME)"
	@echo "  POD_LABEL: $(POD_LABEL)"
	@echo "  NAMESPACE: $(NAMESPACE)"
	@echo "  AGENTS: $(AGENTS)"
	@echo ""
	@echo "Runtime Settings:"
	@echo "  IMAGE_PULL_POLICY: $(IMAGE_PULL_POLICY)"
	@echo "  RESTART_POLICY: $(RESTART_POLICY)"
	@echo "  POD_READY_TIMEOUT: $(POD_READY_TIMEOUT)s"
	@echo "  DEBUG_ENABLED: $(DEBUG_ENABLED)"

# Check dependencies with success feedback
# Check dependencies with success feedback
check-deps:
	@echo "🔍 Checking dependencies..."
	@if command -v docker >/dev/null 2>&1; then \
		echo "✅ Docker found"; \
	else \
		echo "❌ Docker not found!"; exit 1; \
	fi
	@if docker buildx version >/dev/null 2>&1; then \
		echo "✅ Docker Buildx found"; \
	else \
		echo "❌ Docker Buildx not found! DOCKER_BUILDKIT may not work properly"; \
		echo "   Install with: sudo apt install docker-buildx-plugin"; \
		exit 1; \
	fi
	@if command -v k3d >/dev/null 2>&1; then \
		echo "✅ k3d found"; \
	else \
		echo "❌ k3d not found!"; exit 1; \
	fi
	@if command -v kubectl >/dev/null 2>&1; then \
		echo "✅ kubectl found"; \
	else \
		echo "❌ kubectl not found!"; exit 1; \
	fi
	@if test -f $(DOCKERFILE); then \
		echo "✅ Dockerfile found"; \
	else \
		echo "❌ Dockerfile not found!"; exit 1; \
	fi
	@echo "🔍 Checking Dockerfile dependencies..."
	@for file in $$(grep -E '^(COPY|ADD)' $(DOCKERFILE) | awk '{print $$2}' | grep -v '^http' | sort -u); do \
		if [ -f "$$file" ] || [ -d "$$file" ]; then \
			echo "✅ Found: $$file"; \
		else \
			echo "❌ Missing: $$file"; \
			exit 1; \
		fi; \
	done

# Clean up everything with consistent feedback
clean:
	@echo "🧹 Cleaning resources..."
	@if [ "$(DEBUG_ENABLED)" = "true" ]; then \
		echo "🗑️ Deleting pod '$(POD_LABEL)'..."; \
		if kubectl delete pod $(POD_LABEL) --ignore-not-found=true --wait=false 2>/dev/null; then \
			echo "✅ Pod deleted"; \
		else \
			echo "⚠️ Pod not found"; \
		fi; \
		echo "🗑️ Deleting cluster '$(CLUSTER_NAME)'..."; \
		if k3d cluster delete $(CLUSTER_NAME) 2>/dev/null; then \
			echo "✅ Cluster deleted"; \
		else \
			echo "⚠️ Cluster not found"; \
		fi; \
		echo "🗑️ Removing Docker image..."; \
		if docker rmi $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null; then \
			echo "✅ Image deleted"; \
		else \
			echo "⚠️ Image not found"; \
		fi; \
	else \
		kubectl delete pod $(POD_LABEL) --ignore-not-found=true --wait=false >/dev/null 2>&1 || true; \
		k3d cluster delete $(CLUSTER_NAME) >/dev/null 2>&1 || true; \
		docker rmi $(IMAGE_NAME):$(IMAGE_TAG) >/dev/null 2>&1 || true; \
	fi
	@echo "✅ Cleanup complete!"

# Build Docker image with success feedback
build:
	@echo "📦 Building Docker image..."
	@if [ "$(DEBUG_ENABLED)" = "true" ]; then \
		echo " Project: $(PROJECT_NAME)"; \
		echo " Image: $(IMAGE_NAME):$(IMAGE_TAG)"; \
		echo " Environment: $(ENVIRONMENT)"; \
		if DOCKER_BUILDKIT=1 docker build $(DOCKER_BUILD_FLAGS) \
			-t $(IMAGE_NAME):$(IMAGE_TAG) \
			$(DOCKER_BUILD_ARGS) \
			-f $(DOCKERFILE) \
			$(BUILD_CONTEXT); then \
			echo "✅ Image built successfully"; \
		else \
			echo "❌ Image build failed"; exit 1; \
		fi; \
	else \
		if DOCKER_BUILDKIT=1 docker build $(DOCKER_BUILD_FLAGS) \
			-t $(IMAGE_NAME):$(IMAGE_TAG) \
			$(DOCKER_BUILD_ARGS) \
			-f $(DOCKERFILE) \
			$(BUILD_CONTEXT) >/dev/null 2>&1; then \
			echo "✅ Image built successfully"; \
		else \
			echo "❌ Image build failed"; exit 1; \
		fi; \
	fi

# Create k3d cluster with DNS fix
cluster:
	@echo "🔧 Setting up cluster..."
	@if k3d cluster list $(NO_HEADERS_FLAG) 2>/dev/null | grep -q "^$(CLUSTER_NAME)"; then \
		echo "✅ Cluster '$(CLUSTER_NAME)' exists"; \
		echo "🔧 Starting cluster if stopped..."; \
		k3d cluster start $(CLUSTER_NAME) $(REDIRECT_OUTPUT) || true; \
	else \
		echo "🔧 Creating cluster with $(AGENTS) agent(s)..."; \
		if K3D_FIX_DNS=0 k3d cluster create $(CLUSTER_NAME) -a $(AGENTS) --wait \
			--k3s-arg "--kube-proxy-arg=conntrack-max-per-core=0@server:*" \
			--timeout $(CLUSTER_TIMEOUT) $(REDIRECT_OUTPUT); then \
			echo "✅ Cluster created"; \
		else \
			echo "❌ Cluster creation failed"; exit 1; \
		fi; \
	fi
	@if [ "$(DEBUG_ENABLED)" = "false" ]; then \
		echo "📥 Preloading infrastructure images..."; \
		docker pull rancher/mirrored-pause:3.6 $(REDIRECT_OUTPUT) || true; \
		k3d image import rancher/mirrored-pause:3.6 -c $(CLUSTER_NAME) $(REDIRECT_OUTPUT) || true; \
		echo "📤 Importing application image..."; \
		if k3d image import $(IMAGE_NAME):$(IMAGE_TAG) -c $(CLUSTER_NAME) $(REDIRECT_OUTPUT); then \
			echo "✅ Setup complete"; \
		else \
			echo "⚠️ Image import failed"; exit 1; \
		fi; \
	else \
		echo "📥 Preloading critical infrastructure images..."; \
		docker pull rancher/mirrored-pause:3.6 2>/dev/null || true; \
		k3d image import rancher/mirrored-pause:3.6 -c $(CLUSTER_NAME) 2>/dev/null || true; \
		echo "✅ Infrastructure images imported"; \
		echo "📤 Importing application image..."; \
		if k3d image import $(IMAGE_NAME):$(IMAGE_TAG) -c $(CLUSTER_NAME); then \
			echo "✅ Image import complete"; \
		else \
			echo "⚠️ Image import failed"; exit 1; \
		fi; \
	fi

# Deploy pod to Kubernetes with verification
deploy:
	@echo "🚀 Deploying pod..."
	@if [ "$(DEBUG_ENABLED)" = "true" ]; then \
		echo " Pod: $(POD_LABEL)"; \
		echo " Namespace: $(NAMESPACE)"; \
		echo " Image Pull Policy: $(IMAGE_PULL_POLICY)"; \
		echo "🔍 Verifying cluster connection..."; \
		kubectl cluster-info $(KUBECTL_VERBOSITY) || (echo "❌ Cluster connection failed"; exit 1); \
	else \
		kubectl cluster-info $(REDIRECT_OUTPUT) || (echo "❌ Cluster connection failed"; exit 1); \
	fi
	@if kubectl get pod $(POD_LABEL) -n $(NAMESPACE) $(REDIRECT_OUTPUT) 2>&1; then \
		echo "⚠️ Pod exists, recreating..."; \
		kubectl delete pod $(POD_LABEL) -n $(NAMESPACE) --wait=true $(REDIRECT_OUTPUT) || true; \
	fi
	@kubectl run $(POD_LABEL) --image=$(IMAGE_NAME):$(IMAGE_TAG) --image-pull-policy=$(IMAGE_PULL_POLICY) --restart=$(RESTART_POLICY) --namespace=$(NAMESPACE) $(KUBECTL_VERBOSITY) $(REDIRECT_OUTPUT) && \
		echo "✅ Pod deployed successfully!" && \
		echo "⏳ Waiting for pod readiness ($(POD_READY_TIMEOUT)s timeout)..." && \
		(timeout $(POD_READY_TIMEOUT) kubectl wait --for=condition=Ready pod/$(POD_LABEL) -n $(NAMESPACE) $(REDIRECT_OUTPUT) && echo "🎉 Pod is ready!" || echo "⚠️ Timeout reached. Check: 'make logs' or 'make status'") || \
		(echo "❌ Pod deployment failed"; exit 1)

# Development workflow - quick iteration
dev: build
	@echo "🔄 Development deployment..."
	@k3d image import $(IMAGE_NAME):$(IMAGE_TAG) -c $(CLUSTER_NAME)
	@kubectl delete pod $(POD_LABEL) --ignore-not-found=true --wait=true
	@kubectl run $(POD_LABEL) --image=$(IMAGE_NAME):$(IMAGE_TAG) \
		--image-pull-policy=IfNotPresent --restart=Never
	@echo "✅ Development deployment complete"

# Improved status check
status:
	@echo "📊 --- System Status ---"
	@if [ "$(DEBUG_ENABLED)" = "true" ]; then \
		echo "🐳 Docker:"; \
		docker --version 2>/dev/null || echo "❌ Docker not available"; \
	fi
	@echo "📊 --- Cluster Status ---"
	@if k3d cluster list $(NO_HEADERS_FLAG) | grep -q "^$(CLUSTER_NAME)"; then \
		echo "✅ Cluster '$(CLUSTER_NAME)' running"; \
		if [ "$(DEBUG_ENABLED)" = "true" ]; then \
			k3d cluster list | grep $(CLUSTER_NAME); \
		fi; \
	else \
		echo "⚠️ Cluster not running"; \
	fi
	@echo "📊 --- Pod Status ---"
	@if kubectl get pod $(POD_LABEL) -n $(NAMESPACE) $(REDIRECT_OUTPUT) 2>&1; then \
		echo "✅ Pod '$(POD_LABEL)' found"; \
		kubectl get pod $(POD_LABEL) -n $(NAMESPACE); \
		if [ "$(DEBUG_ENABLED)" = "true" ]; then \
			echo "🔍 Pod Events:"; \
			kubectl get events --field-selector involvedObject.name=$(POD_LABEL) --sort-by=.lastTimestamp -n $(NAMESPACE) | tail -5; \
		fi; \
	elif kubectl cluster-info $(REDIRECT_OUTPUT) 2>&1; then \
		echo "⚠️ Pod not found"; \
	else \
		echo "❌ API server unreachable - is cluster running?"; \
	fi

# Stream logs with better error handling
logs:
	@echo "📜 Streaming logs (Ctrl+C to exit)..."
	@kubectl logs $(POD_LABEL) -f --tail=$(LOG_TAIL_LINES) -n $(NAMESPACE) 2>/dev/null || \
		(EXIT_CODE=$$?; \
		if [ $$EXIT_CODE -eq 130 ]; then \
			echo "✅ Log streaming stopped by user"; \
		else \
			echo "⚠️ Log streaming failed - checking pod status..."; \
			kubectl get pod $(POD_LABEL) -n $(NAMESPACE) || echo "Pod not found"; \
		fi)

# Watch pod status
watch:
	@echo "👀 Watching pod status (Ctrl+C to exit)..."
	@watch kubectl get pods -n $(NAMESPACE)

# Interactive shell with better error handling
shell:
	@echo "🔓 Starting shell session..."
	@if kubectl exec -it $(POD_LABEL) -n $(NAMESPACE) -- sh 2>/dev/null; then \
		: ; \
	else \
		echo "⚠️  Shell access failed - checking alternatives..."; \
		if kubectl exec -it $(POD_LABEL) -n $(NAMESPACE) -- /bin/bash 2>/dev/null; then \
			: ; \
		else \
			echo "❌ No shell available - pod may not be running"; \
			kubectl get pod $(POD_LABEL) -n $(NAMESPACE) || echo "Pod not found"; \
		fi; \
	fi

# Debug information
debug:
	@echo "🔍 Debug Information"
	@echo "===================="
	@echo "Configuration:"
	@echo "  IMAGE_NAME: $(IMAGE_NAME)"
	@echo "  IMAGE_TAG: $(IMAGE_TAG)"
	@echo "  CLUSTER_NAME: $(CLUSTER_NAME)"
	@echo "  POD_LABEL: $(POD_LABEL)"
	@echo "  NAMESPACE: $(NAMESPACE)"
	@echo ""
	@echo "Docker Images:"
	@docker images | grep $(IMAGE_NAME) || echo "No matching images found"
	@echo ""
	@echo "K3d Clusters:"
	@k3d cluster list || echo "No clusters found"
	@echo ""
	@echo "All Pods:"
	@kubectl get pods --all-namespaces 2>/dev/null || echo "Cannot connect to cluster"

# Rebuild from scratch
rebuild: clean all

# Enhanced help with examples
help:
	@echo "📘 Kubernetes Local Development Makefile"
	@echo "----------------------------------------"
	@echo "Usage: make [target] [VARIABLE=value]"
	@echo ""
	@echo "Main Targets:"
	@echo "  all        : Full workflow (build, cluster, deploy)"
	@echo "  clean      : Remove all resources"
	@echo "  rebuild    : Clean and rebuild everything"
	@echo "  config     : Show current configuration"
	@echo ""
	@echo "Development:"
	@echo "  dev        : Quick rebuild for development"
	@echo "  build      : Build Docker image only"
	@echo "  deploy     : Deploy pod only"
	@echo ""
	@echo "Monitoring:"
	@echo "  status     : Check cluster and pod status"
	@echo "  logs       : Stream pod logs"
	@echo "  watch      : Watch pod status changes"
	@echo "  debug      : Show debug information"
	@echo ""
	@echo "Interaction:"
	@echo "  shell      : Access pod shell"
	@echo ""
	@echo "Configuration Examples:"
	@echo "  make ENVIRONMENT=production VERSION=v1.2.3"
	@echo "  make DEBUG_ENABLED=true"
	@echo "  make AGENTS=1 POD_READY_TIMEOUT=60"
	@echo "  make NAMESPACE=testing"
	@echo ""
	@echo "Workflow Examples:"
	@echo "  make           # Full setup"
	@echo "  make config    # Show configuration"
	@echo "  make dev       # Quick iteration"
	@echo "  make logs      # View logs"
	@echo "  make debug     # Troubleshoot issues"
