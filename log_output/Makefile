# ============================================================================
# PROJECT CONFIGURATION SECTION
# ============================================================================

# Define core project variables and environment defaults

# Basic project identifiers
PROJECT_NAME := log-output
# Default image version/tag
VERSION ?= latest

# Docker image build and tag settings
IMAGE_NAME := $(PROJECT_NAME)-app
IMAGE_TAG := $(VERSION)
# Path to Dockerfile
DOCKERFILE ?= Dockerfile
# Extra build args (optional)
DOCKER_BUILD_ARGS ?=

# Kubernetes/k3d cluster and pod configuration
CLUSTER_NAME := $(PROJECT_NAME)-cluster
POD_LABEL := $(PROJECT_NAME)-pod
# Kubernetes namespace
NAMESPACE ?= default
# Number of k3d agent nodes
AGENTS ?= 2
# Image pull policy
IMAGE_PULL_POLICY ?= IfNotPresent
# Pod restart policy
RESTART_POLICY ?= Never

# Timeouts and log settings
# Cluster creation timeout
CLUSTER_TIMEOUT ?= 300s
# Pod readiness wait timeout (seconds)
POD_READY_TIMEOUT ?= 30
# Number of log lines to show by default
LOG_TAIL_LINES ?= 50

# Network port configuration
# Cloudflare DNS (disabled due to k3d issues)
# DNS_SERVER := 1.1.1.1
# Host port for service
HOST_PORT ?= 8080
# Container port for service
CONTAINER_PORT ?= 8000

# Docker build context and output
BUILD_CONTEXT ?= .
# Suppress build output if true
BUILD_QUIET ?= true

# Development and debug toggles
# Enable development workflow
DEV_MODE ?= false
# Enable verbose/debug output
DEBUG_ENABLED ?= false

# ============================================================================
# DERIVED VARIABLES (DO NOT MODIFY BELOW)
# ============================================================================
# These are computed based on the above configuration

# Set Docker build flags for quiet or verbose output
ifeq ($(BUILD_QUIET),true)
    DOCKER_BUILD_FLAGS := --quiet
else
    DOCKER_BUILD_FLAGS := 
endif

# Set debug/verbosity flags for tools based on DEBUG_ENABLED
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
# PHONY TARGETS DECLARATION
# ============================================================================
.PHONY: clean build cluster deploy all status logs shell rebuild help check-deps dev watch config debug

.DEFAULT_GOAL := all

# ============================================================================
# MAIN MAKE TARGETS
# ============================================================================

# Full workflow: check dependencies, build image, create cluster, deploy pod
all: check-deps build cluster deploy

# Print current configuration and environment variables
config:
	@echo "📋 Current Configuration"
	@echo "========================"
	@echo "Project Settings:"
	@echo "  PROJECT_NAME: $(PROJECT_NAME)"
	@echo "  VERSION: $(VERSION)"
	@echo ""
	@echo "Docker Settings:"
	@echo "  IMAGE_NAME: $(IMAGE_NAME)"
	@echo "  IMAGE_TAG: $(IMAGE_TAG)"
	@echo "  DOCKERFILE: $(DOCKERFILE)"
	@echo "  BUILD_CONTEXT: $(BUILD_CONTEXT)"
	@echo "  BUILD_QUIET: $(BUILD_QUIET)"
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
	@echo "  DEV_MODE: $(DEV_MODE)"

# Check for required tools and files, and verify Dockerfile dependencies
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
		echo "❌ Dockerfile not found at '$(DOCKERFILE)'!"; exit 1; \
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
	@echo "✅ All dependencies verified"

# Remove all created resources: pod, cluster, and Docker image
clean:
	@echo "🧹 Cleaning resources..."
	@if [ "$(DEBUG_ENABLED)" = "true" ]; then \
		echo "🗑️ Deleting pod '$(POD_LABEL)' in namespace '$(NAMESPACE)'..."; \
		if kubectl delete pod $(POD_LABEL) -n $(NAMESPACE) --ignore-not-found=true --wait=false 2>/dev/null; then \
			echo "✅ Pod deleted"; \
		else \
			echo "⚠️ Pod not found or already deleted"; \
		fi; \
		echo "🗑️ Deleting cluster '$(CLUSTER_NAME)'..."; \
		if k3d cluster delete $(CLUSTER_NAME) 2>/dev/null; then \
			echo "✅ Cluster deleted"; \
		else \
			echo "⚠️ Cluster not found or already deleted"; \
		fi; \
		echo "🗑️ Removing Docker image '$(IMAGE_NAME):$(IMAGE_TAG)'..."; \
		if docker rmi $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null; then \
			echo "✅ Image deleted"; \
		else \
			echo "⚠️ Image not found or already deleted"; \
		fi; \
	else \
		kubectl delete pod $(POD_LABEL) -n $(NAMESPACE) --ignore-not-found=true --wait=false >/dev/null 2>&1 || true; \
		k3d cluster delete $(CLUSTER_NAME) >/dev/null 2>&1 || true; \
		docker rmi $(IMAGE_NAME):$(IMAGE_TAG) >/dev/null 2>&1 || true; \
	fi
	@echo "✅ Cleanup complete!"

# Build the Docker image for the application
build:
	@echo "📦 Building Docker image..."
	@if [ "$(DEBUG_ENABLED)" = "true" ]; then \
		echo "   Project: $(PROJECT_NAME)"; \
		echo "   Image: $(IMAGE_NAME):$(IMAGE_TAG)"; \
		echo "   Dockerfile: $(DOCKERFILE)"; \
		echo "   Build context: $(BUILD_CONTEXT)"; \
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

# Create or start the k3d cluster and import required images
cluster:
	@echo "🔧 Setting up cluster..."
	@if k3d cluster list $(NO_HEADERS_FLAG) 2>/dev/null | grep -q "^$(CLUSTER_NAME)"; then \
		echo "✅ Cluster '$(CLUSTER_NAME)' exists"; \
		echo "🔧 Starting cluster if stopped..."; \
		k3d cluster start $(CLUSTER_NAME) $(REDIRECT_OUTPUT) || true; \
	else \
		echo "🔧 Creating cluster '$(CLUSTER_NAME)' with $(AGENTS) agent(s)..."; \
		if K3D_FIX_DNS=0 k3d cluster create $(CLUSTER_NAME) -a $(AGENTS) --wait \
			--k3s-arg "--kube-proxy-arg=conntrack-max-per-core=0@server:*" \
			--timeout $(CLUSTER_TIMEOUT) $(REDIRECT_OUTPUT); then \
			echo "✅ Cluster created successfully"; \
		else \
			echo "❌ Cluster creation failed"; exit 1; \
		fi; \
	fi
	@if [ "$(DEBUG_ENABLED)" = "false" ]; then \
		echo "📥 Preloading infrastructure images..."; \
		docker pull rancher/mirrored-pause:3.6 $(REDIRECT_OUTPUT) || true; \
		k3d image import rancher/mirrored-pause:3.6 -c $(CLUSTER_NAME) $(REDIRECT_OUTPUT) || true; \
		echo "📤 Importing application image '$(IMAGE_NAME):$(IMAGE_TAG)'..."; \
		if k3d image import $(IMAGE_NAME):$(IMAGE_TAG) -c $(CLUSTER_NAME) $(REDIRECT_OUTPUT); then \
			echo "✅ Setup complete"; \
		else \
			echo "❌ Image import failed"; exit 1; \
		fi; \
	else \
		echo "📥 Preloading critical infrastructure images..."; \
		docker pull rancher/mirrored-pause:3.6 2>/dev/null || true; \
		k3d image import rancher/mirrored-pause:3.6 -c $(CLUSTER_NAME) 2>/dev/null || true; \
		echo "✅ Infrastructure images imported"; \
		echo "📤 Importing application image '$(IMAGE_NAME):$(IMAGE_TAG)'..."; \
		if k3d image import $(IMAGE_NAME):$(IMAGE_TAG) -c $(CLUSTER_NAME); then \
			echo "✅ Image import complete"; \
		else \
			echo "❌ Image import failed"; exit 1; \
		fi; \
	fi

# Deploy the application pod to Kubernetes and verify readiness
deploy:
	@echo "🚀 Deploying pod..."
	@if [ "$(DEBUG_ENABLED)" = "true" ]; then \
		echo "   Pod: $(POD_LABEL)"; \
		echo "   Namespace: $(NAMESPACE)"; \
		echo "   Image: $(IMAGE_NAME):$(IMAGE_TAG)"; \
		echo "   Image Pull Policy: $(IMAGE_PULL_POLICY)"; \
		echo "   Restart Policy: $(RESTART_POLICY)"; \
		echo "🔍 Verifying cluster connection..."; \
		kubectl cluster-info $(KUBECTL_VERBOSITY) || (echo "❌ Cluster connection failed"; exit 1); \
	else \
		kubectl cluster-info $(REDIRECT_OUTPUT) || (echo "❌ Cluster connection failed"; exit 1); \
	fi
	@if kubectl get pod $(POD_LABEL) -n $(NAMESPACE) $(REDIRECT_OUTPUT) 2>&1; then \
		echo "⚠️ Pod '$(POD_LABEL)' exists, recreating..."; \
		kubectl delete pod $(POD_LABEL) -n $(NAMESPACE) --wait=true $(REDIRECT_OUTPUT) || true; \
	fi
	@kubectl run $(POD_LABEL) --image=$(IMAGE_NAME):$(IMAGE_TAG) \
		--image-pull-policy=$(IMAGE_PULL_POLICY) \
		--restart=$(RESTART_POLICY) \
		--namespace=$(NAMESPACE) \
		$(KUBECTL_VERBOSITY) $(REDIRECT_OUTPUT) && \
		echo "✅ Pod deployed successfully!" && \
		echo "⏳ Waiting for pod readiness ($(POD_READY_TIMEOUT)s timeout)..." && \
		(timeout $(POD_READY_TIMEOUT) kubectl wait --for=condition=Ready pod/$(POD_LABEL) -n $(NAMESPACE) $(REDIRECT_OUTPUT) && \
		echo "🎉 Pod is ready!" || \
		echo "⚠️ Timeout reached. Check: 'make logs' or 'make status'") || \
		(echo "❌ Pod deployment failed"; exit 1)

# Fast development workflow: build, import, and redeploy pod
dev: build
	@echo "🔄 Development deployment..."
	@echo "📤 Importing updated image..."
	@k3d image import $(IMAGE_NAME):$(IMAGE_TAG) -c $(CLUSTER_NAME) $(REDIRECT_OUTPUT) || \
		(echo "❌ Image import failed"; exit 1)
	@echo "🗑️ Removing existing pod..."
	@kubectl delete pod $(POD_LABEL) -n $(NAMESPACE) --ignore-not-found=true --wait=true $(REDIRECT_OUTPUT)
	@echo "🚀 Deploying updated pod..."
	@kubectl run $(POD_LABEL) --image=$(IMAGE_NAME):$(IMAGE_TAG) \
		--image-pull-policy=IfNotPresent \
		--restart=Never \
		--namespace=$(NAMESPACE) $(REDIRECT_OUTPUT)
	@echo "✅ Development deployment complete"

# Show status of Docker, cluster, and pod (with debug info if enabled)
status:
	@echo "📊 System Status"
	@echo "================"
	@if [ "$(DEBUG_ENABLED)" = "true" ]; then \
		echo "🐳 Docker:"; \
		docker --version 2>/dev/null || echo "❌ Docker not available"; \
		echo ""; \
	fi
	@echo "📊 Cluster Status:"
	@if k3d cluster list $(NO_HEADERS_FLAG) 2>/dev/null | grep -q "^$(CLUSTER_NAME)"; then \
		STATUS=$$(k3d cluster list $(NO_HEADERS_FLAG) 2>/dev/null | grep "^$(CLUSTER_NAME)" | awk '{print $$2}'); \
		echo "✅ Cluster '$(CLUSTER_NAME)' - Status: $$STATUS"; \
		if [ "$(DEBUG_ENABLED)" = "true" ]; then \
			k3d cluster list | grep -E "(NAME|$(CLUSTER_NAME))"; \
		fi; \
	else \
		echo "❌ Cluster '$(CLUSTER_NAME)' not found"; \
	fi
	@echo ""
	@echo "📊 Pod Status:"
	@if kubectl get pod $(POD_LABEL) -n $(NAMESPACE) $(REDIRECT_OUTPUT) 2>&1; then \
		echo "✅ Pod '$(POD_LABEL)' found in namespace '$(NAMESPACE)'"; \
		kubectl get pod $(POD_LABEL) -n $(NAMESPACE); \
		if [ "$(DEBUG_ENABLED)" = "true" ]; then \
			echo ""; \
			echo "🔍 Recent Pod Events:"; \
			kubectl get events --field-selector involvedObject.name=$(POD_LABEL) \
				--sort-by=.lastTimestamp -n $(NAMESPACE) 2>/dev/null | tail -5 || \
				echo "No events found"; \
		fi; \
	elif kubectl cluster-info $(REDIRECT_OUTPUT) 2>&1; then \
		echo "⚠️ Pod '$(POD_LABEL)' not found in namespace '$(NAMESPACE)'"; \
	else \
		echo "❌ Cannot connect to cluster"; \
	fi

# Stream pod logs with user-friendly error handling
logs:
	@echo "📜 Streaming logs for pod '$(POD_LABEL)' (last $(LOG_TAIL_LINES) lines)"
	@echo "   Press Ctrl+C to exit..."
	@kubectl logs $(POD_LABEL) -f --tail=$(LOG_TAIL_LINES) -n $(NAMESPACE) 2>/dev/null || \
		(EXIT_CODE=$$?; \
		if [ $$EXIT_CODE -eq 130 ]; then \
			echo "✅ Log streaming stopped by user"; \
		else \
			echo "⚠️ Log streaming failed - checking pod status..."; \
			kubectl get pod $(POD_LABEL) -n $(NAMESPACE) 2>/dev/null || \
				echo "❌ Pod '$(POD_LABEL)' not found in namespace '$(NAMESPACE)'"; \
		fi)

# Continuously watch pod status in the namespace
watch:
	@echo "👀 Watching pod status in namespace '$(NAMESPACE)'"
	@echo "   Press Ctrl+C to exit..."
	@if kubectl get namespace $(NAMESPACE) >/dev/null 2>&1; then \
		watch kubectl get pods -n $(NAMESPACE); \
	else \
		echo "❌ Namespace '$(NAMESPACE)' not found!"; \
	fi

# Open an interactive shell in the running pod, fallback to /bin/bash if sh is unavailable
shell:
	@echo "🔓 Starting shell session in pod '$(POD_LABEL)'..."
	@if kubectl exec -it $(POD_LABEL) -n $(NAMESPACE) -- sh 2>/dev/null; then \
		: ; \
	else \
		echo "⚠️ Shell '/bin/sh' failed - trying '/bin/bash'..."; \
		if kubectl exec -it $(POD_LABEL) -n $(NAMESPACE) -- /bin/bash 2>/dev/null; then \
			: ; \
		else \
			echo "❌ No shell available - pod may not be running or ready"; \
			echo "Pod status:"; \
			kubectl get pod $(POD_LABEL) -n $(NAMESPACE) 2>/dev/null || \
				echo "❌ Pod '$(POD_LABEL)' not found in namespace '$(NAMESPACE)'"; \
		fi; \
	fi

# Print debug information about images, clusters, and pods
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
	@docker images | grep "$(IMAGE_NAME)" || echo "❌ No matching images found for '$(IMAGE_NAME)'"
	@echo ""
	@echo "K3d Clusters:"
	@k3d cluster list 2>/dev/null || echo "❌ No clusters found or k3d not available"
	@echo ""
	@echo "All Pods in namespace '$(NAMESPACE)':"
	@kubectl get pods -n $(NAMESPACE) 2>/dev/null || echo "❌ Cannot connect to cluster"
	@if [ "$(DEBUG_ENABLED)" = "true" ]; then \
		echo ""; \
		echo "All Pods (all namespaces):"; \
		kubectl get pods --all-namespaces 2>/dev/null || echo "❌ Cannot retrieve pods"; \
	fi

# Remove all resources and rebuild from scratch
rebuild: clean all

# Print help and usage examples for the Makefile
help:
	@echo "📘 Kubernetes Local Development Makefile"
	@echo "========================================="
	@echo "Usage: make [target] [VARIABLE=value]"
	@echo ""
	@echo "Main Targets:"
	@echo "  all        : Full workflow (check-deps, build, cluster, deploy)"
	@echo "  clean      : Remove all resources (pod, cluster, image)"
	@echo "  rebuild    : Clean and rebuild everything"
	@echo "  config     : Show current configuration"
	@echo ""
	@echo "Development Targets:"
	@echo "  dev        : Quick rebuild for development iteration"
	@echo "  build      : Build Docker image only"
	@echo "  cluster    : Create/start k3d cluster only"  
	@echo "  deploy     : Deploy pod to cluster only"
	@echo ""
	@echo "Monitoring Targets:"
	@echo "  status     : Check cluster and pod status"
	@echo "  logs       : Stream pod logs"
	@echo "  watch      : Watch pod status changes"
	@echo "  debug      : Show comprehensive debug information"
	@echo ""
	@echo "Interaction Targets:"
	@echo "  shell      : Open interactive shell in pod"
	@echo "  check-deps : Verify required tools and dependencies"
	@echo ""
	@echo "Configuration Variables:"
	@echo "  PROJECT_NAME       : Base name for resources (default: log-output)"
	@echo "  VERSION            : Image version/tag (default: latest)"
	@echo "  NAMESPACE          : Kubernetes namespace (default: default)"
	@echo "  AGENTS             : Number of k3d agent nodes (default: 2)"
	@echo "  DEBUG_ENABLED      : Enable verbose output (default: false)"
	@echo "  POD_READY_TIMEOUT  : Pod readiness timeout in seconds (default: 30)"
	@echo ""
	@echo "Configuration Examples:"
	@echo "  make DEBUG_ENABLED=true"
	@echo "  make AGENTS=1 POD_READY_TIMEOUT=60"
	@echo "  make NAMESPACE=testing"
	@echo ""
	@echo "Common Workflow Examples:"
	@echo "  make           # Full setup (recommended for first run)"
	@echo "  make config    # Show current configuration"
	@echo "  make dev       # Quick development iteration"
	@echo "  make logs      # View application logs"
	@echo "  make status    # Check system status"
	@echo "  make debug     # Troubleshoot issues"
	@echo "  make clean     # Clean up all resources"