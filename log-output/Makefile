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

# Docker build context
BUILD_CONTEXT ?= .

# Development and debug toggles
# Enable verbose/debug output
DEBUG_ENABLED ?= false

# ============================================================================
# DERIVED VARIABLES (DO NOT MODIFY BELOW)
# ============================================================================
# These are computed based on the above configuration

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
.PHONY: clean build cluster deploy all status logs shell rebuild help check-deps watch config debug generate-deployment
.DEFAULT_GOAL := all

# ============================================================================
# MAIN MAKE TARGETS
# ============================================================================

# Remove all resources and rebuild from scratch
rebuild: check-deps clean build cluster deploy

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
	@echo "  NAMESPACE: $(NAMESPACE)"
	@echo "  AGENTS: $(AGENTS)"
	@echo ""
	@echo "Runtime Settings:"
	@echo "  IMAGE_PULL_POLICY: $(IMAGE_PULL_POLICY)"
	@echo "  RESTART_POLICY: $(RESTART_POLICY)"
	@echo "  POD_READY_TIMEOUT: $(POD_READY_TIMEOUT)s"
	@echo "  DEBUG_ENABLED: $(DEBUG_ENABLED)"

# Check for required tools and files, and verify Dockerfile dependencies
check-deps:
	@echo "🔍 Checking dependencies..."
	@if command -v docker >/dev/null 2>&1; then \
		echo "✅ Docker found"; \
	else \
		echo "❌ Docker not found!"; exit 1; \
	fi
	@if docker buildx version >/dev/null 2>&1; then \
		echo "✅ Docker buildx found"; \
	else \
		echo "❌ Docker buildx not found! DOCKER_BUILDKIT may not work properly"; \
		echo "  Install appropriate plugin such as 'sudo pacman -S docker-buildx' for Arch Linux"; \
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

# Remove all created resources: deployment, cluster, and Docker image
clean:
	@echo "🧹 Cleaning resources..."
	@if [ "$(DEBUG_ENABLED)" = "true" ]; then \
		echo "🗑️ Deleting deployment '$(PROJECT_NAME)-deployment' in namespace '$(NAMESPACE)'..."; \
		if kubectl delete deployment $(PROJECT_NAME)-deployment -n $(NAMESPACE) --ignore-not-found=true --wait=false 2>/dev/null; then \
			echo "✅ Deployment deleted"; \
		else \
			echo "⚠️ Deployment not found or already deleted"; \
		fi; \
		# echo "🗑️ Cleaning up generated files..."; \
		# rm -f manifests/deployment.yaml 2>/dev/null || true; \
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
		kubectl delete deployment $(PROJECT_NAME)-deployment -n $(NAMESPACE) --ignore-not-found=true --wait=false >/dev/null 2>&1 || true; \
		# rm -f manifests/deployment.yaml >/dev/null 2>&1 || true; \
		k3d cluster delete $(CLUSTER_NAME) >/dev/null 2>&1 || true; \
		docker rmi $(IMAGE_NAME):$(IMAGE_TAG) >/dev/null 2>&1 || true; \
	fi
	@echo "✅ Cleanup complete!"

# Build the Docker image for the application
build:
	@echo "📦 Building Docker image..."
	@if [ "$(DEBUG_ENABLED)" = "true" ]; then \
		echo "  Project: $(PROJECT_NAME)"; \
		echo "  Image: $(IMAGE_NAME):$(IMAGE_TAG)"; \
		echo "  Dockerfile: $(DOCKERFILE)"; \
		echo "  Build context: $(BUILD_CONTEXT)"; \
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

# Generate deployment.yaml from template with current configuration
generate-deployment:
	@echo "📝 Generating deployment.yaml..."
	@mkdir -p manifests
		@printf '%s\n' \
	  'apiVersion: apps/v1' \
	  'kind: Deployment' \
	  'metadata:' \
	  '  name: $(PROJECT_NAME)-deployment' \
	  '  namespace: $(NAMESPACE)' \
	  '  labels:' \
	  '    app: $(PROJECT_NAME)' \
	  'spec:' \
	  '  replicas: 1' \
	  '  selector:' \
	  '    matchLabels:' \
	  '      app: $(PROJECT_NAME)' \
	  '  template:' \
	  '    metadata:' \
	  '      labels:' \
	  '        app: $(PROJECT_NAME)' \
	  '    spec:' \
	  '      containers:' \
	  '      - name: $(PROJECT_NAME)-container' \
	  '        image: $(IMAGE_NAME):$(IMAGE_TAG)' \
	  '        imagePullPolicy: $(IMAGE_PULL_POLICY)' \
	  '        ports:' \
	  '        - containerPort: $(CONTAINER_PORT)' \
	  '        env:' \
	  '        - name: PORT' \
	  '          value: "$(CONTAINER_PORT)"' \
	  '      restartPolicy: Always' \
	  > manifests/deployment.yaml
	@echo "✅ deployment.yaml generated with current configuration"

# Apply manifests to the cluster
deploy:
	@echo "🚀 Deploying application..."
	@if [ "$(DEBUG_ENABLED)" = "true" ]; then \
		echo " Deployment: $(PROJECT_NAME)-deployment"; \
		echo " Namespace: $(NAMESPACE)"; \
		echo " Image: $(IMAGE_NAME):$(IMAGE_TAG)"; \
		echo " Image Pull Policy: $(IMAGE_PULL_POLICY)"; \
		echo "🔍 Verifying cluster connection..."; \
		kubectl cluster-info $(KUBECTL_VERBOSITY) || (echo "❌ Cluster connection failed"; exit 1); \
	else \
		kubectl cluster-info $(REDIRECT_OUTPUT) || (echo "❌ Cluster connection failed"; exit 1); \
	fi
	@echo "📝 Applying manifests individually..."
	@set -e; \
	for f in $$(ls manifests/*.yaml | sort); do \
		echo "Applying: $$f"; \
		kubectl apply -f $$f -n $(NAMESPACE) $(KUBECTL_VERBOSITY) $(REDIRECT_OUTPUT) || \
		(echo "❌ Failed to apply manifest: $$f"; exit 1); \
	done; \
	echo "✅ Applied all manifests successfully!"
	@echo "⏳ Waiting for rollout status ($(POD_READY_TIMEOUT)s timeout)..."
	@kubectl rollout status deployment/$(PROJECT_NAME)-deployment -n $(NAMESPACE) --timeout=$(POD_READY_TIMEOUT)s || \
	(echo "⚠️ Timeout reached. Check: 'make logs' or 'make status'"; exit 1)
	@echo "🌐 Checking Ingress endpoint..."; \
	for attempt in {1..5}; do \
		INGRESS_HOST=$$(kubectl get ingress -n $(NAMESPACE) -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null); \
		if [ -n "$$INGRESS_HOST" ]; then break; fi; \
		echo "Waiting for Ingress host..."; sleep 2; \
	done; \
	if [ "$$INGRESS_HOST" = "*" ]; then \
		echo "⚠️ Ingress host is set to '*'. Please set a real host in your ingress configuration. For example: 'host: myapp.example.com'"; \
		echo "✅ Deployment complete, but Ingress endpoint is not accessible. Check 'kubectl get ingress -n $(NAMESPACE)' for more information"; \
		exit 0; \
	else \
		echo "✅ Deployment complete. Access /status at: http://$$INGRESS_HOST/status"; \
		echo "ℹ️  If http://$$INGRESS_HOST/status does not resolve, add '127.0.0.1 $$INGRESS_HOST' to your /etc/hosts file."; \
	fi

# Show status of Docker, cluster, and deployment (with debug info if enabled)
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
	@echo "📊 Deployment Status:"
	@if kubectl get deployment $(PROJECT_NAME)-deployment -n $(NAMESPACE) $(REDIRECT_OUTPUT) 2>&1; then \
		echo "✅ Deployment '$(PROJECT_NAME)-deployment' found in namespace '$(NAMESPACE)'"; \
		kubectl get deployment $(PROJECT_NAME)-deployment -n $(NAMESPACE); \
		echo ""; \
		echo "📊 Pod Status:"; \
		kubectl get pods -l app=$(PROJECT_NAME) -n $(NAMESPACE); \
		if [ "$(DEBUG_ENABLED)" = "true" ]; then \
			echo ""; \
			echo "🔍 Recent Deployment Events:"; \
			kubectl get events --field-selector involvedObject.name=$(PROJECT_NAME)-deployment \
				--sort-by=.lastTimestamp -n $(NAMESPACE) 2>/dev/null | tail -5 || \
				echo "No events found"; \
		fi; \
	elif kubectl cluster-info $(REDIRECT_OUTPUT) 2>&1; then \
		echo "⚠️ Deployment '$(PROJECT_NAME)-deployment' not found in namespace '$(NAMESPACE)'"; \
	else \
		echo "❌ Cannot connect to cluster"; \
	fi

# Stream pod logs with user-friendly error handling
logs:
	@echo "📜 Streaming logs for deployment '$(PROJECT_NAME)-deployment' (last $(LOG_TAIL_LINES) lines)"
	@echo "  Press Ctrl+C to exit..."
	@kubectl logs deployment/$(PROJECT_NAME)-deployment -f --tail=$(LOG_TAIL_LINES) -n $(NAMESPACE) 2>/dev/null || \
		(EXIT_CODE=$$?; \
		if [ $$EXIT_CODE -eq 130 ]; then \
			echo "✅ Log streaming stopped by user"; \
		else \
			echo "⚠️ Log streaming failed - checking deployment status..."; \
			kubectl get deployment $(PROJECT_NAME)-deployment -n $(NAMESPACE) 2>/dev/null || \
				echo "❌ Deployment '$(PROJECT_NAME)-deployment' not found in namespace '$(NAMESPACE)'"; \
		fi)

# Continuously watch pod status in the namespace
watch:
	@echo "👀 Watching pod status in namespace '$(NAMESPACE)'"
	@echo "  Press Ctrl+C to exit..."
	@if kubectl get namespace $(NAMESPACE) >/dev/null 2>&1; then \
		watch kubectl get pods -n $(NAMESPACE); \
	else \
		echo "❌ Namespace '$(NAMESPACE)' not found!"; \
	fi

# Open an interactive shell in the running pod, fallback to /bin/bash if sh is unavailable
shell:
	@echo "🔓 Starting shell session in deployment '$(PROJECT_NAME)-deployment'..."
	@POD_NAME=$$(kubectl get pods -l app=$(PROJECT_NAME) -n $(NAMESPACE) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -n "$$POD_NAME" ]; then \
		echo "🔓 Connecting to pod: $$POD_NAME"; \
		if kubectl exec -it $$POD_NAME -n $(NAMESPACE) -- sh 2>/dev/null; then \
			: ; \
		else \
			echo "⚠️ Shell '/bin/sh' failed - trying '/bin/bash'..."; \
			if kubectl exec -it $$POD_NAME -n $(NAMESPACE) -- /bin/bash 2>/dev/null; then \
				: ; \
			else \
				echo "❌ No shell available - pod may not be running or ready"; \
				kubectl get pods -l app=$(PROJECT_NAME) -n $(NAMESPACE); \
			fi; \
		fi; \
	else \
		echo "❌ No pods found for deployment '$(PROJECT_NAME)-deployment' in namespace '$(NAMESPACE)'"; \
		kubectl get deployment $(PROJECT_NAME)-deployment -n $(NAMESPACE) 2>/dev/null || \
			echo "❌ Deployment not found"; \
	fi

# Print debug information about images, clusters, and pods
debug:
	@echo "🔍 Debug Information"
	@echo "===================="
	@echo "Configuration:"
	@echo "  IMAGE_NAME: $(IMAGE_NAME)"
	@echo "  IMAGE_TAG: $(IMAGE_TAG)"
	@echo "  CLUSTER_NAME: $(CLUSTER_NAME)"
	@echo "  PROJECT_NAME: $(PROJECT_NAME)"
	@echo "  NAMESPACE: $(NAMESPACE)"
	@echo ""
	@echo "Docker Images:"
	@docker images | grep "$(IMAGE_NAME)" || echo "❌ No matching images found for '$(IMAGE_NAME)'"
	@echo ""
	@echo "k3d Clusters:"
	@clusters=$$(k3d cluster list 2>/dev/null | tail -n +2); \
	if [ -z "$$clusters" ]; then \
		echo "❌ No clusters found"; \
	else \
		k3d cluster list 2>/dev/null; \
	fi
	@echo ""
	@echo "Deployments in namespace '$(NAMESPACE)':"
	@kubectl get deployments -n $(NAMESPACE) 2>/dev/null || echo "❌ Cannot connect to cluster"
	@echo ""
	@echo "All Pods in namespace '$(NAMESPACE)':"
	@kubectl get pods -n $(NAMESPACE) 2>/dev/null || echo "❌ Cannot connect to cluster"
	@if [ "$(DEBUG_ENABLED)" = "true" ]; then \
		echo ""; \
		echo "All Pods (all namespaces):"; \
		kubectl get pods --all-namespaces 2>/dev/null || echo "❌ Cannot retrieve pods"; \
	fi

# Print help and usage examples for the Makefile
help:
	@echo "📘 Kubernetes Local Development Makefile"
	@echo "========================================="
	@echo ""
	@echo "🚀 Quick Start:"
	@echo "  rebuild    Clean followed by full workflow (recommended) (check-deps → clean → build → cluster → deploy)"
	@echo "  all        Full workflow (check-deps → build → cluster → deploy)"
	@echo ""
	@echo "🔧 Build & Deploy:"
	@echo "  build      Build Docker image"
	@echo "  cluster    Create/start k3d cluster"
	@echo "  deploy     Deploy application to cluster"
	@echo "  clean      Remove all resources"
	@echo ""
	@echo "📊 Monitor & Debug:"
	@echo "  status     System status overview"
	@echo "  logs       Stream deployment logs (Ctrl+C to exit)"
	@echo "  watch      Live pod status updates"
	@echo "  debug      Comprehensive debug info"
	@echo ""
	@echo "🔗 Interact:"
	@echo "  shell      Open pod shell"
	@echo "  config     Show configuration"
	@echo "  check-deps Verify dependencies"
	@echo ""
	@echo "⚙️ Key Variables:"
	@echo "  DEBUG_ENABLED=true  Verbose output"
	@echo "  NAMESPACE=testing   Custom namespace"
	@echo "  AGENTS=1           Single agent node"
	@echo ""
	@echo "💡 Examples:"
	@echo "  make rebuild AGENTS=1              # Fresh start with single agent"
	@echo "  make clean DEBUG_ENABLED=true     # Clean up with debug output"
	@echo ""
	@echo "Usage: make [target] [VARIABLE=value]"
