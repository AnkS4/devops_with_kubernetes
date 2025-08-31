# ============================================================================
# PROJECT CONFIGURATION SECTION
# ============================================================================
# Define core project variables and environment defaults

# ============================================================================
# UNIVERSAL MAKEFILE FOR ALL PROJECTS (GENERIC/PARAMETERIZED)
# ============================================================================
# Usage for any project (override variables as needed):
#   make build PROJECT_NAME=ping-pong MANIFEST_DIR=ping_pong/manifests DOCKERFILE=ping_pong/Dockerfile
#   make deploy PROJECT_NAME=todo-app MANIFEST_DIR=project/manifests DOCKERFILE=project/Dockerfile
# All variables can be overridden via command line or environment.
# ============================================================================

# Find all projects with Dockerfile and manifests directory
PROJECTS := $(shell \
  for d in */ ; do \
    [ -f "$${d}Dockerfile" ] && [ -d "$${d}manifests" ] && echo $${d%/}; \
  done | sort)

# Default target to run
TARGET ?= all

.PHONY: default help all-projects list-projects validate-project clean build cluster deploy all status logs shell rebuild
.DEFAULT_GOAL := default

default: help

list-projects:
	@echo "Available projects: $(PROJECTS)"

all-projects:
	@for proj in $(PROJECTS); do \
		echo "==== Running '$(TARGET)' for $$proj ===="; \
		$(MAKE) $(TARGET) PROJECT_NAME=$$proj; \
	done

help:
	@echo "📘 Kubernetes Local Development Makefile"
	@echo "========================================="
	@echo ""
	@echo "🚀 Quick Start:"
	@echo "  rebuild    Clean followed by full workflow (recommended) (validate → clean → build → cluster → deploy)"
	@echo "  all        Full workflow (validate → build → cluster → deploy)"
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
	@echo "  health     Check pod health status"
	@echo ""
	@echo "🔗 Interact:"
	@echo "  shell      Open pod shell"
	@echo "  restart    Restart deployment"
	@echo "  config     Show configuration"
	@echo "  validate   Validate project and dependencies"
	@echo ""
	@echo "📝 Project Management:"
	@echo "  print-projects  List all available projects"
	@echo "  all-projects   Run any TARGET (default: rebuild) for all projects"
	@echo "    e.g. make all-projects TARGET=clean"
	@echo "    e.g. make clean PROJECT_NAME=project"
	@echo ""
	@echo "⚙️ Key Variables:"
	@echo "  PROJECT_NAME=my-app  Set project name (required)"
	@echo "  DEBUG_ENABLED=true   Verbose output"
	@echo "  NAMESPACE=testing    Custom namespace"
	@echo "  AGENTS=1            Single agent node"
	@echo ""
	@echo "💡 Examples:"
	@echo " ---Two methods to run make---"
	@echo " Method 1: Choosing a specific project to run make"
	@echo "   make rebuild PROJECT_NAME=ping-pong AGENTS=1                # Build and deploy ping-pong project"
	@echo "   make clean PROJECT_NAME=project                             # Clean up a specific project"
	@echo "   make rebuild PROJECT_NAME=ping-pong AGENTS=1 DEBUG_ENABLED=true  # Rebuild with debug output and single agent"
	@echo "   make rebuild                                               # Rebuild with default agent(s)"
	@echo ""
	@echo " Method 2: Choosing all projects to run make"
	@echo "   make all-projects TARGET=rebuild AGENTS=1                   # Fresh start with single agent for all projects"
	@echo "   make all-projects TARGET=clean                              # Clean up all projects"
	@echo "   make all-projects TARGET=rebuild AGENTS=1 DEBUG_ENABLED=true # Rebuild all projects with debug output and single agent"
	@echo "   make all-projects                                          # Rebuild all projects with default agent(s)"
	@echo ""
	@echo "🤔 Troubleshooting Tips:"
	@echo "  Missing files? Check your project directory and ensure all required files are present."
	@echo "  Cluster connection issues? Verify your k3d cluster is running and configured correctly."
	@echo "  Use 'make validate PROJECT_NAME=your-project' to check dependencies."
	@echo ""

# Project Variables (override as needed)
PROJECT_NAME        ?= project
MANIFEST_DIR        ?= $(PROJECT_NAME)/manifests
IMAGE_NAME          ?= $(PROJECT_NAME)-app
IMAGE_TAG           ?= latest
DOCKERFILE          ?= $(PROJECT_NAME)/Dockerfile
DOCKERFILE_DIR      := $(dir $(DOCKERFILE))
DOCKER_BUILD_ARGS   ?=
CLUSTER_NAME        ?= $(PROJECT_NAME)-cluster
INGRESS_NAME        ?= $(PROJECT_NAME)-ingress
NAMESPACE           ?= $(CLUSTER_NAME)
AGENTS              ?= 2
IMAGE_PULL_POLICY   ?= IfNotPresent
CLUSTER_TIMEOUT     ?= 300s
POD_READY_TIMEOUT   ?= 30
LOG_TAIL_LINES      ?= 50
RESTART_POLICY      ?= Never
DEBUG_ENABLED       ?= false
K3D_RESOLV_FILE     ?= k3s-resolv.conf
K3D_FIX_DNS         ?= 0

# Function to find an available port starting from a base port
define find_available_port
$(shell \
  port=$(1); \
  while [ $$port -lt 65535 ]; do \
    AVAILABLE=1; \
    if command -v ss >/dev/null 2>&1; then \
      ss -Hln "sport = :$$port" 2>/dev/null | grep -q . && AVAILABLE=0 || AVAILABLE=1; \
    elif command -v netstat >/dev/null 2>&1; then \
      netstat -an 2>/dev/null | grep -E "LISTEN|LISTENING" | grep -E "[:.]$$port[[:space:]]" >/dev/null && AVAILABLE=0 || AVAILABLE=1; \
    elif command -v lsof >/dev/null 2>&1; then \
      lsof -PiTCP:$$port -sTCP:LISTEN -n 2>/dev/null | grep -q . && AVAILABLE=0 || AVAILABLE=1; \
    else \
      (echo > /dev/tcp/127.0.0.1/$$port) >/dev/null 2>&1 && AVAILABLE=0 || AVAILABLE=1; \
    fi; \
    if [ $$AVAILABLE -eq 1 ]; then echo $$port; exit 0; fi; \
    port=$$((port + 1)); \
  done \
)
endef

# Dynamic port assignments
TRAEFIK_HTTP_PORT  ?= $(call find_available_port,8080)
TRAEFIK_HTTPS_PORT ?= $(call find_available_port,8443)

# TRAEFIK_HTTP_PORT  ?= 8080
# TRAEFIK_HTTPS_PORT ?= 8443

# ============================================================================
# DERIVED VARIABLES (DO NOT MODIFY BELOW)
# ============================================================================
# These are computed based on the above configuration

# Automatically detect build context based on Dockerfile location
BUILD_CONTEXT ?= $(DOCKERFILE_DIR)

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
.PHONY: clean build cluster deploy all status logs shell rebuild help check-deps watch config debug generate-deployment print-projects default all-projects validate-project health restart deployment-exists
.DEFAULT_GOAL := default

# ============================================================================
# VALIDATION TARGETS
# ============================================================================

# Validate that PROJECT_NAME is set and not empty
validate-project:
	@if [ -z "$(PROJECT_NAME)" ]; then \
		echo "❌ PROJECT_NAME is required!"; \
		echo "Available projects: $(PROJECTS)"; \
		exit 1; \
	fi

# Check if deployment exists
deployment-exists: validate-project
	@if ! kubectl get deployment $(PROJECT_NAME)-deployment -n $(NAMESPACE) >/dev/null 2>&1; then \
		echo "❌ Deployment '$(PROJECT_NAME)-deployment' not found in namespace '$(NAMESPACE)'"; \
		exit 1; \
	fi

# Check if cluster exists and is running
cluster-exists: validate-project
	@if ! k3d cluster list $(NO_HEADERS_FLAG) 2>/dev/null | grep -q "^$(CLUSTER_NAME)"; then \
		echo "❌ Cluster '$(CLUSTER_NAME)' not found"; \
		exit 1; \
	fi

# ============================================================================
# MAIN MAKE TARGETS
# ============================================================================

# Remove all resources and rebuild from scratch
rebuild: validate-project clean build cluster deploy ingress

# Full workflow: validate, clean, build image, create cluster, deploy and ingress
all: validate-project clean build cluster deploy ingress

# Validate project and dependencies
validate: validate-project check-deps

# Print current configuration and environment variables
config: validate-project
	@echo "📋 Current Configuration"
	@echo "========================"
	@echo "Project Settings:"
	@echo "  PROJECT_NAME: $(PROJECT_NAME)"
	@echo "  IMAGE_TAG: $(IMAGE_TAG)"
	@echo ""
	@echo "Docker Settings:"
	@echo "  IMAGE_NAME: $(IMAGE_NAME)"
	@echo "  IMAGE_TAG: $(IMAGE_TAG)"
	@echo "  DOCKERFILE: $(DOCKERFILE)"
	@echo "  BUILD_CONTEXT: $(BUILD_CONTEXT)"
	@echo ""
	@echo "Kubernetes Settings:"
	@echo "  CLUSTER_NAME: $(CLUSTER_NAME)"
	@echo "  NAMESPACE: $(NAMESPACE)"
	@echo "  AGENTS: $(AGENTS)"
	@echo "  MANIFEST_DIR: $(MANIFEST_DIR)"
	@echo ""
	@echo "Runtime Settings:"
	@echo "  IMAGE_PULL_POLICY: $(IMAGE_PULL_POLICY)"
	@echo "  RESTART_POLICY: $(RESTART_POLICY)"
	@echo "  POD_READY_TIMEOUT: $(POD_READY_TIMEOUT)s"
	@echo "  DEBUG_ENABLED: $(DEBUG_ENABLED)"

# Print all projects
print-projects:
	@echo "Available projects: $(PROJECTS)"

# Check for required tools and files, and verify Dockerfile dependencies
check-deps: validate-project
	@echo "🔍 Checking dependencies for project '$(PROJECT_NAME)'..."
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
		echo "✅ Dockerfile found at '$(DOCKERFILE)'"; \
	else \
		echo "❌ Dockerfile not found at '$(DOCKERFILE)'!"; exit 1; \
	fi
	@echo "🔍 Checking Dockerfile dependencies..."
	@for file in $$(grep -E '^(COPY|ADD)' $(DOCKERFILE) 2>/dev/null | awk '{print $$2}' | grep -v '^http' | sort -u); do \
		if [ -f "$(DOCKERFILE_DIR)$$file" ] || [ -d "$(DOCKERFILE_DIR)$$file" ]; then \
			echo "✅ Found: $(DOCKERFILE_DIR)$$file"; \
		else \
			echo "❌ Missing: $(DOCKERFILE_DIR)$$file"; \
			exit 1; \
		fi; \
	done
	@echo "✅ All dependencies verified for project '$(PROJECT_NAME)'"

# Remove all created resources: deployment, cluster, and Docker image
clean: validate-project
	@echo "🧹 Cleaning resources for project '$(PROJECT_NAME)'..."
	@if [ "$(DEBUG_ENABLED)" = "true" ]; then \
		echo "🗑️ Deleting deployment '$(PROJECT_NAME)-deployment' in namespace '$(NAMESPACE)'..."; \
		if kubectl delete deployment $(PROJECT_NAME)-deployment -n $(NAMESPACE) --ignore-not-found=true --wait=true 2>/dev/null; then \
			echo "✅ Deployment deleted"; \
		else \
			echo "⚠️ Deployment not found or already deleted"; \
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
		kubectl delete deployment $(PROJECT_NAME)-deployment -n $(NAMESPACE) --ignore-not-found=true --wait=true >/dev/null 2>&1 || true; \
		k3d cluster delete $(CLUSTER_NAME) >/dev/null 2>&1 || true; \
		docker rmi $(IMAGE_NAME):$(IMAGE_TAG) >/dev/null 2>&1 || true; \
	fi
	@echo "✅ Cleanup complete for project '$(PROJECT_NAME)'!"

# Build the Docker image for the application
build: validate-project
	@echo "📦 Building Docker image for project '$(PROJECT_NAME)'..."
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
cluster: validate-project
	@echo "🔧 Setting up cluster '$(CLUSTER_NAME)'..."
	@if k3d cluster list $(NO_HEADERS_FLAG) 2>/dev/null | grep -q "^$(CLUSTER_NAME)"; then \
		echo "✅ Cluster '$(CLUSTER_NAME)' exists"; \
		echo "🔧 Starting cluster if stopped..."; \
		k3d cluster start $(CLUSTER_NAME) $(REDIRECT_OUTPUT) || true; \
	else \
		echo "🔧 Creating cluster '$(CLUSTER_NAME)' with $(AGENTS) agent(s)..."; \
		if K3D_FIX_DNS=$() k3d cluster create $(CLUSTER_NAME) -a $(AGENTS) --wait \
			-p "$(TRAEFIK_HTTP_PORT):80@loadbalancer" \
			-p "$(TRAEFIK_HTTPS_PORT):443@loadbalancer" \
			--timeout $(CLUSTER_TIMEOUT) $(REDIRECT_OUTPUT); then \
			echo "✅ Cluster created successfully"; \
		else \
			echo "❌ Cluster creation failed"; exit 1; \
		fi; \
	fi

	@if [ "$(DEBUG_ENABLED)" = "false" ]; then \
		echo "📥 Preloading critical cluster images..."; \
		for img in \
			rancher/mirrored-pause:3.6 \
			rancher/mirrored-coredns-coredns:1.12.0 \
			rancher/local-path-provisioner:v0.0.30 \
			rancher/mirrored-metrics-server:v0.7.2 \
			rancher/klipper-helm:v0.9.3-build20241008 \
			rancher/mirrored-library-traefik:2.11.18 \
			rancher/klipper-lb:v0.4.9; do \
			docker pull $$img $(REDIRECT_OUTPUT) || true; \
			k3d image import $$img -c $(CLUSTER_NAME) $(REDIRECT_OUTPUT) || true; \
		done; \
		echo "📤 Importing application image '$(IMAGE_NAME):$(IMAGE_TAG)'..."; \
		if docker image inspect $(IMAGE_NAME):$(IMAGE_TAG) >/dev/null 2>&1; then \
			if k3d image import $(IMAGE_NAME):$(IMAGE_TAG) -c $(CLUSTER_NAME) $(REDIRECT_OUTPUT); then \
				echo "✅ Image import complete"; \
			else \
				echo "❌ Image import failed"; exit 1; \
			fi; \
		else \
			echo "⚠️  Skipping import: local image '$(IMAGE_NAME):$(IMAGE_TAG)' not found. Run 'make build' first."; \
		fi; \
	else \
		echo "📥 Preloading critical cluster images (verbose)..."; \
		for img in \
			rancher/mirrored-pause:3.6 \
			rancher/mirrored-coredns-coredns:1.12.0 \
			rancher/local-path-provisioner:v0.0.30 \
			rancher/mirrored-metrics-server:v0.7.2 \
			rancher/klipper-helm:v0.9.3-build20241008 \
			rancher/mirrored-library-traefik:2.11.18 \
			rancher/klipper-lb:v0.4.9; do \
			echo "Pulling $$img"; docker pull $$img 2>/dev/null || true; \
			echo "Importing $$img"; k3d image import $$img -c $(CLUSTER_NAME) 2>/dev/null || true; \
		done; \
		echo "📤 Importing application image '$(IMAGE_NAME):$(IMAGE_TAG)'..."; \
		if docker image inspect $(IMAGE_NAME):$(IMAGE_TAG) >/dev/null 2>&1; then \
			if k3d image import $(IMAGE_NAME):$(IMAGE_TAG) -c $(CLUSTER_NAME); then \
				echo "✅ Image import complete"; \
			else \
				echo "❌ Image import failed"; exit 1; \
			fi; \
		else \
			echo "⚠️  Skipping import: local image '$(IMAGE_NAME):$(IMAGE_TAG)' not found. Run 'make build' first."; \
		fi; \
	fi

deploy: validate-project
	@echo "🚀 Deploying application '$(PROJECT_NAME)'..."
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
	@echo "🗂️  Ensuring namespace '$(NAMESPACE)' exists..."
	@if ! kubectl get ns $(NAMESPACE) >/dev/null 2>&1; then \
		echo "Namespace '$(NAMESPACE)' does not exist. Creating..."; \
		kubectl create ns $(NAMESPACE); \
	else \
		echo "Namespace '$(NAMESPACE)' already exists."; \
	fi
	@echo "📝 Applying manifests from $(MANIFEST_DIR)..."
	@if [ ! -d "$(MANIFEST_DIR)" ]; then echo "❌ No manifest directory: $(MANIFEST_DIR)"; exit 1; fi
	@if ! ls $(MANIFEST_DIR)/*.yaml >/dev/null 2>&1; then echo "❌ No *.yaml files in $(MANIFEST_DIR)"; exit 1; fi
	@kubectl apply -f $(MANIFEST_DIR) -n $(NAMESPACE) $(KUBECTL_VERBOSITY) $(REDIRECT_OUTPUT) || (echo "❌ Failed to apply manifests"; exit 1)
	@echo "✅ Applied all manifests successfully!"
	
	@echo "⏳ Waiting for rollout status ($(POD_READY_TIMEOUT)s timeout)..."
	@kubectl rollout status deployment/$(PROJECT_NAME)-deployment -n $(NAMESPACE) --timeout=$(POD_READY_TIMEOUT)s || \
	(echo "⚠️ Timeout reached. Check: 'make logs PROJECT_NAME=$(PROJECT_NAME)' or 'make status PROJECT_NAME=$(PROJECT_NAME)'"; exit 1)
	@echo "✅ Deployment complete!"

# Check Ingress endpoint
ingress:
	@echo "Checking Ingress endpoint..."; \
	kubectl wait --timeout=60s -n $(NAMESPACE) --for=jsonpath={.spec.rules[0].host} ing/$(INGRESS_NAME) || false; \
	HOST=$$(kubectl get ing/$(INGRESS_NAME) -n $(NAMESPACE) -o jsonpath='{.spec.rules[0].host}'); \
	EXTERNAL_IP=$$(kubectl get svc traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}') 2>/dev/null || true; \
	[ -n "$$EXTERNAL_IP" ] || EXTERNAL_IP=$$(kubectl get ing/$(INGRESS_NAME) -n $(NAMESPACE) -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); \
	EXTERNAL_PORT=$$(kubectl get svc traefik -n kube-system -o jsonpath="{.spec.ports[?(@.name=='web')].port}"); \
	PATH_SUFFIX=""; \
	if [ "$(PROJECT_NAME)" = "ping-pong" ]; then PATH_SUFFIX="/pingpong"; fi; \
	if [ "$(PROJECT_NAME)" = "log-output" ]; then PATH_SUFFIX="/status"; fi; \
	echo "🌐 Access via URL:"; \
	echo "http://$$HOST$$PATH_SUFFIX"; \
	echo "ℹ️  If it does not resolve, add '$$EXTERNAL_IP $$HOST' to /etc/hosts and retry"; \
	echo "OR with: curl -H \"Host: $$HOST\" http://$$EXTERNAL_IP:$$EXTERNAL_PORT$$PATH_SUFFIX"; \
	if [ "$$HOST" = "" ]; then \
		echo "❌ Ingress host not found"; exit 1; \
	fi; \
	if [ "$$HOST" = "*" ]; then \
		echo "⚠️ Ingress host is '*'. Set a real host (e.g., 'host: myapp.example.com')."; \
		echo "Endpoint not accessible. See: 'kubectl get ingress -n $(NAMESPACE)'"; \
		exit 0; \
	fi;
	
# Show status of Docker, cluster, and deployment (with debug info if enabled)
status: validate-project
	@echo "📊 System Status for Project '$(PROJECT_NAME)'"
	@echo "============================================="
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
		echo "✅ Deployment '$(PROJECT_NAME)-deployment' found in namespace '$(NAMESPACE)'"; \oar
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
logs: validate-project
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
watch: validate-project
	@echo "👀 Watching pod status for project '$(PROJECT_NAME)' in namespace '$(NAMESPACE)'"
	@echo "  Press Ctrl+C to exit..."
	@if kubectl get namespace $(NAMESPACE) >/dev/null 2>&1; then \
		watch "kubectl get pods -l app=$(PROJECT_NAME) -n $(NAMESPACE)"; \
	else \
		echo "❌ Namespace '$(NAMESPACE)' not found!"; \
	fi

# Open an interactive shell in the running pod, fallback to /bin/bash if sh is unavailable
shell: validate-project deployment-exists
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

# Check pod health status
health: validate-project deployment-exists
	@echo "🏥 Health check for project '$(PROJECT_NAME)'"
	@echo "============================================="
	@POD_NAME=$$(kubectl get pods -l app=$(PROJECT_NAME) -n $(NAMESPACE) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -n "$$POD_NAME" ]; then \
		echo "Pod: $$POD_NAME"; \
		READY=$$(kubectl get pods -l app=$(PROJECT_NAME) -n $(NAMESPACE) -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null); \
		if [ "$$READY" = "true" ]; then \
			echo "✅ Pod is ready and healthy"; \
		else \
			echo "⚠️ Pod is not ready"; \
			kubectl describe pod $$POD_NAME -n $(NAMESPACE) | grep -A 5 "Conditions:"; \
		fi; \
	else \
		echo "❌ No pods found for deployment '$(PROJECT_NAME)-deployment'"; \
	fi

# Restart the deployment
restart: validate-project deployment-exists
	@echo "🔄 Restarting deployment '$(PROJECT_NAME)-deployment'..."
	@kubectl rollout restart deployment/$(PROJECT_NAME)-deployment -n $(NAMESPACE)
	@echo "✅ Restart initiated. Check status with: make status PROJECT_NAME=$(PROJECT_NAME)"

# Print debug information about images, clusters, and pods
debug: validate-project
	@echo "🔍 Debug Information for Project '$(PROJECT_NAME)'"
	@echo "================================================="
	@echo "Configuration:"
	@echo "  IMAGE_NAME: $(IMAGE_NAME)"
	@echo "  IMAGE_TAG: $(IMAGE_TAG)"
	@echo "  CLUSTER_NAME: $(CLUSTER_NAME)"
	@echo "  PROJECT_NAME: $(PROJECT_NAME)"
	@echo "  NAMESPACE: $(NAMESPACE)"
	@echo "  MANIFEST_DIR: $(MANIFEST_DIR)"
	@echo "  DOCKERFILE: $(DOCKERFILE)"
	@echo "  BUILD_CONTEXT: $(BUILD_CONTEXT)"
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
		echo "Detailed Pod Information:"; \
		kubectl get pods -l app=$(PROJECT_NAME) -n $(NAMESPACE) -o wide 2>/dev/null || echo "❌ No pods found"; \
		echo ""; \
		echo "Recent Events:"; \
		kubectl get events -n $(NAMESPACE) --sort-by=.lastTimestamp | tail -10 2>/dev/null || echo "❌ No events found"; \
	fi