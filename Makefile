# ============================================================================
# PROJECT CONFIGURATION SECTION
# ============================================================================
# UNIVERSAL MAKEFILE FOR ALL PROJECTS (GENERIC/PARAMETERIZED)
# ============================================================================

# Find all projects in the repository by finding directories with Dockerfile and manifests
PROJECTS := $(shell \
  for d in */ ; do \
    [ -f "$${d}Dockerfile" ] && [ -d "$${d}manifests" ] && echo $${d%/}; \
  done | sort)

# Set default target to run when no target is specified
TARGET ?= build

# ============================================================================
# SPECIAL MAKE DIRECTIVES
# ============================================================================
# Declare phony targets (not real files) to ensure they always run
.PHONY: default help all-projects list-projects validate-project clean \
        build cluster-create preload-critical-images preload-app-images \
        deploy build-clean status logs shell build-image validate ingress \
        watch debug health restart config print-projects deployment-exists \
        apply-pv delete-pv clean-all multi-projects check-deps preload-images

# Set the default goal when make is run without arguments
.DEFAULT_GOAL := default

# Project Variables (override as needed)
PROJECT_NAME        ?= project
MANIFEST_DIR        ?= $(PROJECT_NAME)/manifests
IMAGE_NAME          ?= $(PROJECT_NAME)-app
IMAGE_TAG           ?= latest
DOCKERFILE          ?= $(PROJECT_NAME)/Dockerfile
DOCKERFILE_DIR      := $(dir $(DOCKERFILE))
DOCKER_BUILD_ARGS   ?=
CLUSTER_NAME        ?= devops-cluster
INGRESS_NAME        ?= $(PROJECT_NAME)-ingress
NAMESPACE           ?= $(PROJECT_NAME)
AGENTS              ?= 1
IMAGE_PULL_POLICY   ?= IfNotPresent
CLUSTER_TIMEOUT     ?= 300s
POD_READY_TIMEOUT   ?= 30
RESTART_POLICY      ?= Never
DEBUG               ?= 0
K3D_RESOLV_FILE     ?= k3s-resolv.conf
K3D_FIX_DNS         ?= 1
PORT_MIN            ?= 8000
PORT_MAX            ?= 8099
PORT_HOST           ?= 127.0.0.1
INGRESS_RETRIES     ?= 10
INGRESS_WAIT_SECONDS ?= 5

# Override namespace based on project type
ifeq ($(PROJECT_NAME),log-output)
	NAMESPACE := exercises
else ifeq ($(PROJECT_NAME),ping-pong)
	NAMESPACE := exercises
	# Increase timeout for PostgreSQL initialization (database + app restarts)
    POD_READY_TIMEOUT := 120
endif

# Function to find an available port starting from a base port
define find_available_port
$(shell \
  base=$(1); \
  min=$(PORT_MIN); max=$(PORT_MAX); host=$(PORT_HOST); \
  # clamp start to [min, max]
  if [ -z "$$base" ]; then base=$$min; fi; \
  if [ $$base -lt $$min ]; then start=$$min; else start=$$base; fi; \
  if [ $$start -gt $$max ]; then exit 0; fi; \
  port=$$start; \
  while [ $$port -le $$max ]; do \
    if command -v ss >/dev/null 2>&1; then \
      # ss prints nothing when no socket matches; grep -q . means "used"
      if ss -Hln "sport = :$$port" 2>/dev/null | grep -q .; then \
        :; \
      else \
        echo $$port; exit 0; \
      fi; \
    elif command -v lsof >/dev/null 2>&1; then \
      if lsof -PiTCP:$$port -sTCP:LISTEN -n 2>/dev/null | grep -q .; then \
        :; \
      else \
        echo $$port; exit 0; \
      fi; \
    else \
      # /dev/tcp returns success when something is listening (port used)
      (echo > /dev/tcp/$$host/$$port) >/dev/null 2>&1 && used=1 || used=0; \
      if [ $$used -eq 0 ]; then echo $$port; exit 0; fi; \
    fi; \
    port=$$((port + 1)); \
  done \
)
endef

# ============================================================================
# DERIVED VARIABLES (DO NOT MODIFY BELOW)
# ============================================================================
# These are computed based on the above configuration

# Dynamic port assignments
TRAEFIK_HTTP_PORT  ?= $(call find_available_port,8080)
TRAEFIK_HTTPS_PORT ?= $(call find_available_port,8443)

# TRAEFIK_HTTP_PORT  ?= 8080
# TRAEFIK_HTTPS_PORT ?= 8443

# Automatically detect build context based on Dockerfile location
BUILD_CONTEXT ?= $(DOCKERFILE_DIR)

# Set debug/verbosity flags for tools based on DEBUG
ifeq ($(DEBUG),1)
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
# MAIN WORKFLOW TARGETS
# ============================================================================

# Rebuild without cleaning existing cluster/resources
build: validate-project build-image cluster-create preload-images apply-pv deploy ingress

# Remove all resources and rebuild from scratch
build-clean: validate-project clean delete-pv build-image cluster-create preload-images apply-pv deploy ingress

# ============================================================================
# HELPER TARGETS
# ============================================================================

# Define default target
default: help

# Display comprehensive help information with usage examples and variable descriptions
help:
	@echo "📘 Kubernetes Local Development Makefile"
	@echo "========================================="
	@echo ""
	@echo "🚀 Quick Start:"
	@echo "  build-clean Clean followed by full workflow (Recommended for single project)"
	@echo "  build       Full workflow without cleaning cluster/resources (Recommended for multiple projects)"
	@echo ""
	@echo "🔧 Build & Deploy:"
	@echo "  build-image  	Build project Docker image"
	@echo "  cluster-create Create/start k3d cluster"
	@echo "  deploy       	Deploy project to cluster"
	@echo "  clean        	Remove project cluster & resources"
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
	@echo "  all-projects   Run any TARGET (default: build) for all projects"
	@echo "    e.g. make all-projects TARGET=clean"
	@echo "    e.g. make clean PROJECT_NAME=project"vvv
	@echo ""
	@echo "⚙️ Key Variables:"
	@echo "  PROJECT_NAME=my-app  Set project name (required)"
	@echo "  DEBUG=1   Verbose output"
	@echo "  NAMESPACE=testing    Custom namespace"
	@echo "  AGENTS=1            Single agent node"
	@echo ""
	@echo "💡 Examples:"
	@echo " ---Two methods to run make---"
	@echo " Method 1: Choosing a specific project to run make"
	@echo "   make build-clean PROJECT_NAME=ping-pong                                  # Build and deploy ping-pong project"
	@echo "   make multi-projects TARGET=build PROJECT_NAME=\"ping-pong, log-output\"  # Build and deploy ping-pong and log-output projects"
	@echo "   make clean PROJECT_NAME=project                                          # Clean up a specific project"
	@echo "   make delete-pv PROJECT_NAME=project                                      # Delete PersistentVolume for a specific project"
	@echo "   make build-clean PROJECT_NAME=ping-pong AGENTS=2 DEBUG=1                 # Rebuild with debug output and two agents"
	@echo ""
	@echo " Method 2: Choosing all projects to run make"
	@echo "   make all-projects TARGET=build AGENTS=2                                 # Fresh start with two agents for all projects"
	@echo "   make all-projects TARGET=clean                                          # Clean up all projects"
	@echo "   make all-projects TARGET=build AGENTS=2 DEBUG=1                         # Rebuild all projects with debug output and two agents"
	@echo "   make all-projects                                                       # Rebuild all projects with default agent(s)"
	@echo ""
	@echo "🤔 Troubleshooting Tips:"
	@echo "  Missing files? Check your project directory and ensure all required files are present."
	@echo "  Cluster connection issues? Verify your k3d cluster is running and configured correctly."
	@echo "  Use 'make validate PROJECT_NAME=your-project' to check dependencies."
	@echo ""

# List all available projects discovered in the repository
list-projects:
	@echo "Available projects: $(PROJECTS)"

# Display current configuration and environment variables for the specified project
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
	@echo "  DEBUG: $(DEBUG)"

# Validate project and dependencies
validate: validate-project check-deps

# Preload critical images
preload-images: preload-critical-images preload-app-images

# Validate that PROJECT_NAME is set and not empty
validate-project:
	@if [ -z "$(PROJECT_NAME)" ]; then \
		echo "❌ PROJECT_NAME is required!"; \
		echo "Available projects: $(PROJECTS)"; \
		exit 1; \
	fi

# Check if deployment exists
deployment-exists: validate-project
	@if ! kubectl get deployment $(PROJECT_NAME)-deployment -n $(NAMESPACE); then \
		echo "❌ Deployment '$(PROJECT_NAME)-deployment' not found in namespace '$(NAMESPACE)'"; \
		exit 1; \
	fi

# Print all projects
print-projects:
	@echo "Available projects: $(PROJECTS)"

# Check for required tools and files, and verify Dockerfile dependencies
check-deps: validate-project
	@echo "🔍 Checking dependencies for project '$(PROJECT_NAME)'..."
	@if command -v docker $(REDIRECT_OUTPUT) 2>&1; then \
		if [ "$(DEBUG)" = "1" ]; then \
			echo "✅ Docker found"; \
		fi; \
	else \
		echo "❌ Docker not found!"; exit 1; \
	fi
	@if docker buildx version $(REDIRECT_OUTPUT) 2>&1; then \
		if [ "$(DEBUG)" = "1" ]; then \
			echo "✅ Docker buildx found"; \
		fi; \
	else \
		echo "❌ Docker buildx not found! DOCKER_BUILDKIT may not work properly"; \
		echo "  Install appropriate plugin such as 'sudo pacman -S docker-buildx' for Arch Linux"; \
		exit 1; \
	fi
	@if command -v k3d $(REDIRECT_OUTPUT) 2>&1; then \
		if [ "$(DEBUG)" = "1" ]; then \
			echo "✅ k3d found"; \
		fi; \
	else \
		echo "❌ k3d not found!"; exit 1; \
	fi
	@if command -v kubectl $(REDIRECT_OUTPUT) 2>&1; then \
		if [ "$(DEBUG)" = "1" ]; then \
			echo "✅ kubectl found"; \
		fi; \
	else \
		echo "❌ kubectl not found!"; exit 1; \
	fi
	@if test -f $(DOCKERFILE); then \
		if [ "$(DEBUG)" = "1" ]; then \
			echo "✅ Dockerfile found at '$(DOCKERFILE)'"; \
		fi; \
	else \
		echo "❌ Dockerfile not found at '$(DOCKERFILE)'!"; exit 1; \
	fi
	@echo "🔍 Checking Dockerfile dependencies..."
	@for file in $$( \
		grep -E '^(COPY|ADD)' $(DOCKERFILE) 2>/dev/null | \
		awk '{print $$2}' | \
		grep -v '^http' | \
		sort -u \
	); do \
		if [ -f "$(DOCKERFILE_DIR)$$file" ] || [ -d "$(DOCKERFILE_DIR)$$file" ]; then \
			if [ "$(DEBUG)" = "1" ]; then \
				echo "✅ Found: $(DOCKERFILE_DIR)$$file"; \
			fi; \
		else \
			echo "❌ Missing: $(DOCKERFILE_DIR)$$file"; \
			exit 1; \
		fi; \
	done
	@echo "✅ All dependencies verified for project '$(PROJECT_NAME)'"

# ============================================================================
# BUILD AND INFRASTRUCTURE TARGETS
# ============================================================================

# Build Docker images for the application, handling multi-stage builds for complex projects
build-image: validate-project
	@echo "📦 Building application Docker image(s)..."
	@if [ "$(PROJECT_NAME)" = "log-output" ]; then \
		IMAGE_NAME1="$(IMAGE_NAME)-generator:$(IMAGE_TAG)"; \
		IMAGE_NAME2="$(IMAGE_NAME)-status:$(IMAGE_TAG)"; \
		if [ "$(DEBUG)" = "1" ]; then \
			echo "  Project: $(PROJECT_NAME)"; \
			echo "  Generator Image: $${IMAGE_NAME1}"; \
			echo "  Status Image: $${IMAGE_NAME2}"; \
			echo "  Dockerfile: $(DOCKERFILE)"; \
			echo "  Build context: $(BUILD_CONTEXT)"; \
		fi; \
		for image in $$IMAGE_NAME1 $$IMAGE_NAME2; do \
			if [ "$$image" = "$$IMAGE_NAME1" ]; then \
				TARGET="generator"; \
			else \
				TARGET="status"; \
			fi; \
			if [ "$(DEBUG)" = "1" ]; then \
				echo "Building $$image"; \
			fi; \
			if DOCKER_BUILDKIT=1 \
				docker build -t "$$image" --target="$$TARGET" \
				$(DOCKER_BUILD_ARGS) -f $(DOCKERFILE) \
				$(DOCKER_BUILD_FLAGS) $(BUILD_CONTEXT) \
				$(REDIRECT_OUTPUT); then \
				echo "✅ $$image built successfully"; \
			else \
				echo "❌ $$image build failed"; exit 1; \
			fi; \
		done; \
				echo "✅ All images built successfully"; \
	elif [ "$(PROJECT_NAME)" = "project" ]; then \
		IMAGE_NAME1="$(IMAGE_NAME)-main:$(IMAGE_TAG)"; \
		IMAGE_NAME2="$(IMAGE_NAME)-backend:$(IMAGE_TAG)"; \
		if [ "$(DEBUG)" = "1" ]; then \
			echo "  Project: $(PROJECT_NAME)"; \
			echo "  Main Image: $${IMAGE_NAME1}"; \
			echo "  Backend Image: $${IMAGE_NAME2}"; \
			echo "  Dockerfile: $(DOCKERFILE)"; \
			echo "  Build context: $(BUILD_CONTEXT)"; \
		fi; \
		for image in $$IMAGE_NAME1 $$IMAGE_NAME2; do \
			if [ "$$image" = "$$IMAGE_NAME1" ]; then \
				TARGET="main"; \
			else \
				TARGET="backend"; \
			fi; \
			if [ "$(DEBUG)" = "1" ]; then \
				echo "Building $$image"; \
			fi; \
			if DOCKER_BUILDKIT=1 \
				docker build -t "$$image" --target="$$TARGET" \
				$(DOCKER_BUILD_ARGS) -f $(DOCKERFILE) \
				$(DOCKER_BUILD_FLAGS) $(BUILD_CONTEXT) \
				$(REDIRECT_OUTPUT); then \
				echo "✅ $$image built successfully"; \
			else \
				echo "❌ $$image build failed"; exit 1; \
			fi; \
		done; \
		echo "✅ All images built successfully"; \
	else \
		if [ "$(DEBUG)" = "1" ]; then \
			echo "  Project: $(PROJECT_NAME)"; \
			echo "  Image: $(IMAGE_NAME):$(IMAGE_TAG)"; \
			echo "  Dockerfile: $(DOCKERFILE)"; \
			echo "  Build context: $(BUILD_CONTEXT)"; \
		fi; \
		if DOCKER_BUILDKIT=1 \
			docker build -t "$(IMAGE_NAME):$(IMAGE_TAG)" \
			$(DOCKER_BUILD_ARGS) -f $(DOCKERFILE) \
			$(DOCKER_BUILD_FLAGS) $(BUILD_CONTEXT) \
			$(REDIRECT_OUTPUT); then \
			echo "✅ $(IMAGE_NAME):$(IMAGE_TAG) built successfully"; \
		else \
			echo "❌ $(IMAGE_NAME):$(IMAGE_TAG) build failed"; exit 1; \
		fi; \
	fi

# Set up k3d cluster with specified agents and port mappings
cluster-create: validate-project
	@echo "🔧 Setting up cluster '$(CLUSTER_NAME)'..."
	@if k3d cluster list $(NO_HEADERS_FLAG) 2>/dev/null | grep -q "^$(CLUSTER_NAME)"; then \
		echo "✅ Cluster '$(CLUSTER_NAME)' exists"; \
		if [ "$(DEBUG)" = "1" ]; then \
			echo "🔧 Starting cluster if stopped..."; \
		fi; \
		k3d cluster start $(CLUSTER_NAME) $(REDIRECT_OUTPUT) || true; \
		kubectl config use-context k3d-$(CLUSTER_NAME) >/dev/null 2>&1; \
	else \
		if [ "$(DEBUG)" = "1" ]; then \
			echo "🔧 Creating cluster '$(CLUSTER_NAME)' with $(AGENTS) agent(s)..."; \
		fi; \
		if K3D_FIX_DNS=$(K3D_FIX_DNS) k3d cluster create $(CLUSTER_NAME) -a $(AGENTS) --wait \
			-p "$(TRAEFIK_HTTP_PORT):80@loadbalancer" \
			-p "$(TRAEFIK_HTTPS_PORT):443@loadbalancer" \
			--timeout $(CLUSTER_TIMEOUT) $(REDIRECT_OUTPUT); then \
			echo "✅ Cluster created successfully"; \
			kubectl config use-context k3d-$(CLUSTER_NAME) >/dev/null 2>&1; \
		else \
			echo "❌ Cluster creation failed"; exit 1; \
		fi; \
	fi

# Import essential Kubernetes system images into the cluster
preload-critical-images: cluster-create
	@echo "📥 Preloading critical cluster images..."; \
	for img in \
		rancher/mirrored-pause:3.6 \
		rancher/mirrored-coredns-coredns:1.12.0 \
		rancher/local-path-provisioner:v0.0.30 \
		rancher/mirrored-metrics-server:v0.7.2 \
		rancher/klipper-helm:v0.9.3-build20241008 \
		rancher/mirrored-library-traefik:2.11.18 \
		rancher/klipper-lb:v0.4.9; do \
		if docker image inspect $$img $(REDIRECT_OUTPUT); then \
			if [ "$(DEBUG)" = "1" ]; then echo "⏭️ Using local image $$img"; fi; \
		else \
			docker pull $$img $(REDIRECT_OUTPUT) || true; \
		fi; \
		if k3d image import $$img -c $(CLUSTER_NAME) $(REDIRECT_OUTPUT); then \
		echo "✅ Successfully imported $$img"; \
		else \
			echo "⚠️ Failed to import $$img (continuing)"; \
		fi; \
	done; \
	echo "✅ Successfully imported all critical cluster images"; \

# Import application-specific Docker images into the cluster
preload-app-images: validate-project cluster-create
	@echo "📥 Preloading application images..."; \
	if [ "$(PROJECT_NAME)" = "log-output" ]; then \
		IMAGE_NAME1="$(IMAGE_NAME)-generator:$(IMAGE_TAG)"; \
		IMAGE_NAME2="$(IMAGE_NAME)-status:$(IMAGE_TAG)"; \
		if [ "$(DEBUG)" = "1" ]; then \
			echo "📤 Importing application images '$$IMAGE_NAME1' and '$$IMAGE_NAME2'..."; \
		fi; \
		for img in $$IMAGE_NAME1 $$IMAGE_NAME2; do \
			if docker image inspect "$$img" $(REDIRECT_OUTPUT); then \
				if k3d image import "$$img" -c $(CLUSTER_NAME) $(REDIRECT_OUTPUT); then \
					echo "✅ Successfully imported $$img"; \
				else \
					echo "❌ Failed to import $$img"; exit 1; \
				fi; \
			else \
				echo "⚠️ Skipping import: local image '$$img' not found. Run 'make build' first."; \
			fi; \
		done; \
		echo "✅ Successfully imported all application images"; \
	elif [ "$(PROJECT_NAME)" = "project" ]; then \
		IMAGE_NAME1="$(IMAGE_NAME)-main:$(IMAGE_TAG)"; \
		IMAGE_NAME2="$(IMAGE_NAME)-backend:$(IMAGE_TAG)"; \
		if [ "$(DEBUG)" = "1" ]; then \
			echo "📤 Importing application images '$$IMAGE_NAME1' and '$$IMAGE_NAME2'..."; \
		fi; \
		for img in $$IMAGE_NAME1 $$IMAGE_NAME2; do \
			if docker image inspect "$$img" $(REDIRECT_OUTPUT); then \
				if k3d image import "$$img" -c $(CLUSTER_NAME) $(REDIRECT_OUTPUT); then \
					echo "✅ Successfully imported $$img"; \
				else \
					echo "❌ Failed to import $$img"; exit 1; \
				fi; \
			else \
				echo "⚠️ Skipping import: local image '$$img' not found. Run 'make build' first."; \
			fi; \
		done; \
		echo "✅ Successfully imported all application images"; \
	elif [ "$(PROJECT_NAME)" = "ping-pong" ]; then \
		IMAGE_NAME1="$(IMAGE_NAME):$(IMAGE_TAG)"; \
		IMAGE_NAME2="postgres:13-alpine"; \
		if [ "$(DEBUG)" = "1" ]; then \
			echo "📤 Importing application images '$$IMAGE_NAME1' and '$$IMAGE_NAME2'..."; \
		fi; \
		for img in $$IMAGE_NAME1 $$IMAGE_NAME2; do \
			if docker image inspect "$$img" >/dev/null 2>&1; then \
				[ "$(DEBUG)" = "1" ] && echo "⏭️ Using local image $$img" || true; \
			else \
				echo "📥 Pulling $$img..."; \
				docker pull "$$img" $(REDIRECT_OUTPUT) || { echo "❌ Failed to pull $$img"; exit 1; }; \
			fi; \
			if k3d image import "$$img" -c $(CLUSTER_NAME) $(REDIRECT_OUTPUT); then \
				echo "✅ Successfully imported $$img"; \
			else \
				echo "❌ Failed to import $$img"; exit 1; \
			fi; \
		done; \
		echo "✅ Successfully imported all application images"; \
	else \
		echo "📤 Importing application image '$(IMAGE_NAME):$(IMAGE_TAG)'..."; \
		if docker image inspect $(IMAGE_NAME):$(IMAGE_TAG) $(REDIRECT_OUTPUT); then \
			if k3d image import $(IMAGE_NAME):$(IMAGE_TAG) -c $(CLUSTER_NAME) $(REDIRECT_OUTPUT); then \
				echo "✅ Successfully imported $(IMAGE_NAME):$(IMAGE_TAG)"; \
			else \
				echo "❌ Failed to import $(IMAGE_NAME):$(IMAGE_TAG)"; exit 1; \
			fi; \
			echo "✅ Successfully imported all application images"; \
		else \
			echo "⚠️  Skipping import: local image '$(IMAGE_NAME):$(IMAGE_TAG)' not found."; \
			echo "Run 'make build' first."; \
		fi; \
	fi

# ============================================================================
# DEPLOYMENT TARGETS
# ============================================================================

# Apply persistent volume
apply-pv: validate-project
	@echo "💾 Applying PersistentVolume configuration for project '$(PROJECT_NAME)'..."
	@if [ -f "persistentvolume.yaml" ]; then \
		if ! kubectl get nodes $(REDIRECT_OUTPUT); then \
			echo "⚠️  No Kubernetes nodes found (cluster not ready). Skipping PV apply."; \
		else \
			NODE=$$(kubectl get nodes -o name | grep agent | head -1 | cut -d/ -f2); \
			if [ -z "$$NODE" ]; then \
				echo "⚠️ No agent node found. Skipping PV apply."; \
			else \
				CONTAINER_ID=$$(docker ps -q --filter name=$$NODE); \
				if [ -n "$$CONTAINER_ID" ]; then \
					docker exec $$CONTAINER_ID mkdir -p /tmp/kube; \
				fi; \
				export NAMESPACE=$(NAMESPACE); \
				sed "s/REPLACE_NODE_NAME/$$NODE/g" persistentvolume.yaml | \
					envsubst | kubectl apply -f - $(KUBECTL_VERBOSITY) $(REDIRECT_OUTPUT); \
				echo "✅ PersistentVolume applied successfully"; \
			fi; \
		fi; \
	else \
		echo "ℹ️  No cluster-scoped persistentvolume.yaml found in repo root; skipping PV apply"; \
	fi

# Apply Kubernetes manifests and wait for deployment rollout
deploy: validate-project apply-pv
	@echo "🚀 Deploying application '$(PROJECT_NAME)'..."
	@if [ "$(DEBUG)" = "1" ]; then \
		echo " Deployment: $(PROJECT_NAME)-deployment"; \
		echo " Namespace: $(NAMESPACE)"; \
		if [ "$(PROJECT_NAME)" = "log-output" ]; then \
			echo " Images: log-output-generator:latest, log-output-status:latest"; \
		else \
			echo " Image: $(IMAGE_NAME):$(IMAGE_TAG)"; \
		fi; \
		echo " Image Pull Policy: $(IMAGE_PULL_POLICY)"; \
		echo "🔍 Verifying cluster connection..."; \
		kubectl cluster-info $(KUBECTL_VERBOSITY) || (echo "❌ Cluster connection failed"; exit 1); \
	else \
		kubectl cluster-info $(REDIRECT_OUTPUT) || (echo "❌ Cluster connection failed"; exit 1); \
	fi
	@echo "🗂️ Checking for namespace '$(NAMESPACE)'..."
	@if ! kubectl get ns $(NAMESPACE) $(REDIRECT_OUTPUT); then \
		if [ "$(DEBUG)" = "1" ]; then \
			echo "Namespace '$(NAMESPACE)' does not exist. Creating..."; \
		fi; \
		kubectl create ns $(NAMESPACE); \
		echo "✅ Namespace '$(NAMESPACE)' created successfully"; \
	else \
		echo "✅ Namespace '$(NAMESPACE)' already exists."; \
	fi
	@echo "📝 Applying manifests from $(MANIFEST_DIR)..."
	@if [ ! -d "$(MANIFEST_DIR)" ]; then \
		echo "❌ No manifest directory: $(MANIFEST_DIR)"; exit 1; \
	fi
	@if ! ls $(MANIFEST_DIR)/*.yaml $(REDIRECT_OUTPUT); then \
		echo "❌ No *.yaml files in $(MANIFEST_DIR)"; exit 1; \
	fi
	@export NAMESPACE=$(NAMESPACE); \
	for file in $(MANIFEST_DIR)/*.yaml; do \
		envsubst < "$$file" | kubectl apply -n $(NAMESPACE) -f - $(KUBECTL_VERBOSITY) $(REDIRECT_OUTPUT) || \
			(echo "❌ Failed to apply manifest: $$file"; exit 1); \
	done
	@echo "✅ Applied all manifests successfully!"
	@echo "⏳ Waiting for rollout status ($(POD_READY_TIMEOUT)s timeout)..."
	@kubectl rollout status deployment/$(PROJECT_NAME)-deployment \
		-n $(NAMESPACE) --timeout=$(POD_READY_TIMEOUT)s || \
		(echo "⚠️ Timeout reached. Check: 'make logs PROJECT_NAME=$(PROJECT_NAME)' or"; \
		 echo "'make status PROJECT_NAME=$(PROJECT_NAME)'"; exit 1)
	@echo "✅ Deployment complete!"

# Verify Ingress configuration and provide access URLs
ingress: validate-project
	@set -e; \
	echo "🌐 Checking Ingress endpoint..."; \
	if [ "$(DEBUG)" = "1" ]; then \
		echo "Debug: NAMESPACE=$(NAMESPACE)"; \
		echo "Debug: INGRESS_NAME=$(INGRESS_NAME)"; \
		echo "Debug: PROJECT_NAME=$(PROJECT_NAME)"; \
	fi; \
	# Early guard: fail fast if Ingress object is missing; \
	if ! kubectl get ing/$(INGRESS_NAME) -n $(NAMESPACE) $(REDIRECT_OUTPUT); then \
		echo "❌ Ingress '$(INGRESS_NAME)' not found in namespace '$(NAMESPACE)'."; \
		echo " Ensure your manifests create it (e.g., $(MANIFEST_DIR)/ingress.yaml or kustomization)."; \
		exit 1; \
	fi; \
	HOST=$$(kubectl get ing/$(INGRESS_NAME) -n $(NAMESPACE) \
		-o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo ""); \
	EXTERNAL_IP=$$(kubectl get svc traefik -n kube-system \
		-o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo ""); \
	EXTERNAL_HOSTNAME=$$(kubectl get svc traefik -n kube-system \
		-o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo ""); \
	EXTERNAL_PORT=$$(kubectl get svc traefik -n kube-system \
		-o jsonpath="{.spec.ports[?(@.name=='web')].port}" 2>/dev/null || echo "80"); \
	for i in $$(seq 1 $(INGRESS_RETRIES)); do \
		if [ -n "$$HOST" ] && \
			{ [ -n "$$EXTERNAL_IP" ] || [ -n "$$EXTERNAL_HOSTNAME" ]; }; then \
			break; \
		fi; \
		if [ "$(DEBUG)" = "1" ]; then \
			echo "Attempt $$i/$(INGRESS_RETRIES): Getting ingress info..."; \
		fi; \
		echo "Waiting for external IP and host to be assigned... (attempt $$i/$(INGRESS_RETRIES))"; \
		sleep $(INGRESS_WAIT_SECONDS); \
		HOST=$$(kubectl get ing/$(INGRESS_NAME) -n $(NAMESPACE) \
			-o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo ""); \
		EXTERNAL_IP=$$(kubectl get svc traefik -n kube-system \
			-o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo ""); \
		EXTERNAL_HOSTNAME=$$(kubectl get svc traefik -n kube-system \
			-o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo ""); \
		EXTERNAL_PORT=$$(kubectl get svc traefik -n kube-system \
			-o jsonpath="{.spec.ports[?(@.name=='web')].port}" 2>/dev/null || echo "80"); \
	done; \
	if [ -z "$$HOST" ]; then \
		echo "❌ Ingress host not found. Checking ingress status:"; \
		kubectl get ingress $(INGRESS_NAME) -n $(NAMESPACE) 2>/dev/null || \
			echo "Ingress '$(INGRESS_NAME)' not found in namespace '$(NAMESPACE)'"; \
		exit 1; \
	fi; \
	# Fallback to localhost if EXTERNAL_IP/hostname not present (typical with k3d + klipper-lb); \
	if [ -z "$$EXTERNAL_IP" ] && [ -z "$$EXTERNAL_HOSTNAME" ]; then \
		EXTERNAL_IP=127.0.0.1; \
		EXTERNAL_PORT=$(TRAEFIK_HTTP_PORT); \
		if [ -z "$$EXTERNAL_PORT" ]; then EXTERNAL_PORT=80; fi; \
	fi; \
	PATH_SUFFIX=""; \
	if [ "$(PROJECT_NAME)" = "ping-pong" ]; then PATH_SUFFIX="/pingpong"; fi; \
	if [ "$(PROJECT_NAME)" = "log-output" ]; then PATH_SUFFIX="/status"; fi; \
	echo "🌐 Access via URL:"; \
	echo "  http://$$HOST$$PATH_SUFFIX by adding '$$EXTERNAL_IP $$HOST' to /etc/hosts"; \
	echo "  OR by: curl -H \"Host: $$HOST\" http://$$EXTERNAL_IP:$$EXTERNAL_PORT$$PATH_SUFFIX"

# Trigger a rollout restart of the deployment
restart: validate-project deployment-exists
	@echo "🔄 Restarting deployment '$(PROJECT_NAME)-deployment'..."
	@kubectl rollout restart deployment/$(PROJECT_NAME)-deployment -n $(NAMESPACE)
	@echo "✅ Restart initiated. Check status with: make status PROJECT_NAME=$(PROJECT_NAME)"

# ============================================================================
# MONITORING AND DEBUGGING TARGETS
# ============================================================================

# Provide comprehensive system status overview for Docker, cluster, and deployment
status: validate-project
	@echo "📊 System Status for Project '$(PROJECT_NAME)'"
	@echo "============================================="
	@if [ "$(DEBUG)" = "1" ]; then \
		echo "🐳 Docker:"; \
		docker --version $(REDIRECT_OUTPUT) || echo "❌ Docker not available"; \
		echo ""; \
	fi
	@echo "📊 Cluster Status:"
	@if k3d cluster list $(NO_HEADERS_FLAG) 2>/dev/null | grep -q "^$(CLUSTER_NAME)"; then \
		STATUS=$$(k3d cluster list $(NO_HEADERS_FLAG) 2>/dev/null | \
			grep "^$(CLUSTER_NAME)" | awk '{print $$2}'); \
		echo "✅ Cluster '$(CLUSTER_NAME)' - Status: $$STATUS"; \
		if [ "$(DEBUG)" = "1" ]; then \
			k3d cluster list | grep -E "(NAME|$(CLUSTER_NAME))"; \
		fi; \
	else \
		echo "❌ Cluster '$(CLUSTER_NAME)' not found"; \
	fi
	@echo ""
	@echo "📊 Deployment Status:"
	@if kubectl get deployment $(PROJECT_NAME)-deployment \
		-n $(NAMESPACE) $(REDIRECT_OUTPUT) 2>&1; then \
		echo "✅ Deployment '$(PROJECT_NAME)-deployment' found in namespace '$(NAMESPACE)'"; \
		kubectl get deployment $(PROJECT_NAME)-deployment -n $(NAMESPACE); \
		echo ""; \
		echo "📊 Pod Status:"; \
		kubectl get pods -l app=$(PROJECT_NAME) -n $(NAMESPACE); \
		if [ "$(DEBUG)" = "1" ]; then \
			echo ""; \
			echo "🔍 Recent Deployment Events:"; \
			kubectl get events --field-selector involvedObject.name=$(PROJECT_NAME)-deployment \
				--sort-by=.lastTimestamp -n $(NAMESPACE) $(REDIRECT_OUTPUT) | tail -5 || \
				echo "No events found"; \
		fi; \
	elif kubectl cluster-info $(REDIRECT_OUTPUT) 2>&1; then \
		echo "⚠️ Deployment '$(PROJECT_NAME)-deployment' not found in namespace '$(NAMESPACE)'"; \
	else \
		echo "❌ Cannot connect to cluster"; \
	fi

# Stream live pod logs for the deployment
logs: validate-project
	@echo "📜 Streaming logs for deployment '$(PROJECT_NAME)-deployment'"
	@echo "  Press Ctrl+C to exit..."
	@kubectl logs deployment/$(PROJECT_NAME)-deployment -f -n $(NAMESPACE) $(REDIRECT_OUTPUT) || \
		(EXIT_CODE=$$?; \
		if [ $$EXIT_CODE -eq 130 ]; then \
			echo "✅ Log streaming stopped by user"; \
		else \
			echo "⚠️ Log streaming failed - checking deployment status..."; \
			kubectl get deployment $(PROJECT_NAME)-deployment -n $(NAMESPACE) $(REDIRECT_OUTPUT) || \
				echo "❌ Deployment '$(PROJECT_NAME)-deployment' not found in namespace '$(NAMESPACE)'"; \
		fi)

# Continuously monitor pod status with live updates
watch: validate-project
	@echo "👀 Watching pod status for project '$(PROJECT_NAME)' in namespace '$(NAMESPACE)'"
	@echo "  Press Ctrl+C to exit..."
	@if kubectl get namespace $(NAMESPACE) $(REDIRECT_OUTPUT) 2>&1; then \
		if command -v watch >/dev/null 2>&1; then \
		watch "kubectl get pods -l app=$(PROJECT_NAME) -n $(NAMESPACE)"; \
		else \
			echo "⚠️ 'watch' not found. Falling back to 'kubectl get pods -w'"; \
			kubectl get pods -l app=$(PROJECT_NAME) -n $(NAMESPACE) -w; \
		fi; \
	else \
		echo "❌ Namespace '$(NAMESPACE)' not found!"; \
	fi

# Open an interactive shell in a running pod (prefers /bin/sh, falls back to /bin/bash)
shell: validate-project deployment-exists
	@echo "🔓 Starting shell session in deployment '$(PROJECT_NAME)-deployment'..."
	@POD_NAME=$$(kubectl get pods -l app=$(PROJECT_NAME) -n $(NAMESPACE) \
		-o jsonpath='{.items[0].metadata.name}' $(REDIRECT_OUTPUT)); \
	if [ -n "$$POD_NAME" ]; then \
		echo "🔓 Connecting to pod: $$POD_NAME"; \
		if kubectl exec -it $$POD_NAME -n $(NAMESPACE) -- sh $(REDIRECT_OUTPUT); then \
			: ; \
		else \
			echo "⚠️ Shell '/bin/sh' failed - trying '/bin/bash'..."; \
			if kubectl exec -it $$POD_NAME -n $(NAMESPACE) -- \
				/bin/bash $(REDIRECT_OUTPUT); then \
				: ; \
			else \
				echo "❌ No shell available - pod may not be running or ready"; \
				kubectl get pods -l app=$(PROJECT_NAME) -n $(NAMESPACE); \
			fi; \
		fi; \
	else \
		echo "❌ No pods found for deployment '$(PROJECT_NAME)-deployment' in namespace '$(NAMESPACE)'"; \
		kubectl get deployment $(PROJECT_NAME)-deployment -n $(NAMESPACE) \
			$(REDIRECT_OUTPUT) || \
			echo "❌ Deployment not found"; \
	fi

# Check the health status of pods in the deployment
health: validate-project deployment-exists
	@echo "🏥 Health check for project '$(PROJECT_NAME)'"
	@echo "============================================="
	@POD_NAME=$$(kubectl get pods -l app=$(PROJECT_NAME) -n $(NAMESPACE) \
		-o jsonpath='{.items[0].metadata.name}'); \
	if [ -n "$$POD_NAME" ]; then \
		echo "Pod: $$POD_NAME"; \
		READY=$$(kubectl get pods -l app=$(PROJECT_NAME) -n $(NAMESPACE) \
			-o jsonpath='{.items[0].status.containerStatuses[0].ready}'); \
		if [ "$$READY" = "true" ]; then \
			echo "✅ Pod is ready and healthy"; \
		else \
			echo "⚠️ Pod is not ready"; \
			kubectl describe pod $$POD_NAME -n $(NAMESPACE) | \
				grep -A 5 "Conditions:"; \
		fi; \
	else \
		echo "❌ No pods found for deployment '$(PROJECT_NAME)-deployment'"; \
	fi

# Display detailed debug information about images, clusters, and pods
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
	@docker images | grep "$(IMAGE_NAME)" || \
		echo "❌ No matching images found for '$(IMAGE_NAME)'"
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
	@kubectl get deployments -n $(NAMESPACE) $(REDIRECT_OUTPUT) || \
		echo "❌ Cannot connect to cluster"
	@echo ""
	@echo "All Pods in namespace '$(NAMESPACE)':"
	@kubectl get pods -n $(NAMESPACE) $(REDIRECT_OUTPUT) || \
		echo "❌ Cannot connect to cluster"
	@if [ "$(DEBUG)" = "1" ]; then \
		echo ""; \
		echo "Detailed Pod Information:"; \
		kubectl get pods -l app=$(PROJECT_NAME) -n $(NAMESPACE) \
			-o wide $(REDIRECT_OUTPUT) || \
			echo "❌ No pods found"; \
		echo ""; \
		echo "Recent Events:"; \
		kubectl get events -n $(NAMESPACE) --sort-by=.lastTimestamp \
			$(REDIRECT_OUTPUT) || echo "❌ No events found"; \
	fi

# ============================================================================
# CLEANUP AND UTILITY TARGETS
# ============================================================================

# Clean up all resources for the project: deployment, services, ingress, PVC, StatefulSets, ConfigMaps, Secrets
clean: validate-project
	@echo "🧹 Cleaning resources for project '$(PROJECT_NAME)'..."
	
	@[ "$(DEBUG)" = "1" ] && echo "🗑️ Deleting workload resources..." || true
	@if kubectl get deployment $(PROJECT_NAME)-deployment -n $(NAMESPACE) 2>/dev/null | grep -q $(PROJECT_NAME)-deployment; then \
		kubectl delete deployment $(PROJECT_NAME)-deployment -n $(NAMESPACE) --wait=false >/dev/null 2>&1 && \
		echo "  ✅ Deleted deployment $(PROJECT_NAME)-deployment" || true; \
	else \
		[ "$(DEBUG)" = "1" ] && echo "  ⚠️  Deployment $(PROJECT_NAME)-deployment not found" || true; \
	fi
	@if kubectl get statefulset -n $(NAMESPACE) -l app=$(PROJECT_NAME) 2>/dev/null | grep -q $(PROJECT_NAME); then \
		kubectl delete statefulset -l app=$(PROJECT_NAME) -n $(NAMESPACE) --wait=false >/dev/null 2>&1 && \
		echo "  ✅ Deleted StatefulSet(s) with label app=$(PROJECT_NAME)" || true; \
	else \
		[ "$(DEBUG)" = "1" ] && echo "  ⚠️  StatefulSet with label app=$(PROJECT_NAME) not found" || true; \
	fi
	
	@[ "$(DEBUG)" = "1" ] && echo "🗑️ Deleting network resources..." || true
	@if kubectl get svc $(PROJECT_NAME)-svc -n $(NAMESPACE) 2>/dev/null | grep -q $(PROJECT_NAME)-svc; then \
		kubectl delete svc $(PROJECT_NAME)-svc -n $(NAMESPACE) >/dev/null 2>&1 && \
		echo "  ✅ Deleted service $(PROJECT_NAME)-svc" || true; \
	else \
		[ "$(DEBUG)" = "1" ] && echo "  ⚠️  Service $(PROJECT_NAME)-svc not found" || true; \
	fi
	@if kubectl get svc -n $(NAMESPACE) -l app=$(PROJECT_NAME) 2>/dev/null | grep -q $(PROJECT_NAME); then \
		kubectl delete svc -l app=$(PROJECT_NAME) -n $(NAMESPACE) >/dev/null 2>&1 && \
		echo "  ✅ Deleted additional service(s) with label app=$(PROJECT_NAME)" || true; \
	else \
		[ "$(DEBUG)" = "1" ] && echo "  ⚠️  Additional services with label app=$(PROJECT_NAME) not found" || true; \
	fi
	@if kubectl get ingress $(PROJECT_NAME)-ingress -n $(NAMESPACE) 2>/dev/null | grep -q $(PROJECT_NAME)-ingress; then \
		kubectl delete ingress $(PROJECT_NAME)-ingress -n $(NAMESPACE) >/dev/null 2>&1 && \
		echo "  ✅ Deleted ingress $(PROJECT_NAME)-ingress" || true; \
	else \
		[ "$(DEBUG)" = "1" ] && echo "  ⚠️  Ingress $(PROJECT_NAME)-ingress not found" || true; \
	fi
	
	@[ "$(DEBUG)" = "1" ] && echo "🗑️ Deleting storage resources..." || true
	@kubectl get pvc -n $(NAMESPACE) -o name 2>/dev/null | \
		xargs -r -I {} kubectl patch {} -n $(NAMESPACE) \
		-p '{"metadata":{"finalizers":null}}' --type=merge >/dev/null 2>&1 || true
	@if kubectl get pvc shared-storage-claim -n $(NAMESPACE) 2>/dev/null | grep -q shared-storage-claim; then \
		kubectl delete pvc shared-storage-claim -n $(NAMESPACE) --force --grace-period=0 >/dev/null 2>&1 && \
		echo "  ✅ Deleted PVC shared-storage-claim" || true; \
	else \
		[ "$(DEBUG)" = "1" ] && echo "  ⚠️  PVC shared-storage-claim not found" || true; \
	fi
	@if kubectl get pvc -n $(NAMESPACE) -l app=$(PROJECT_NAME) 2>/dev/null | grep -q $(PROJECT_NAME); then \
		kubectl delete pvc -l app=$(PROJECT_NAME) -n $(NAMESPACE) --force --grace-period=0 >/dev/null 2>&1 && \
		echo "  ✅ Deleted PVC(s) with label app=$(PROJECT_NAME)" || true; \
	else \
		[ "$(DEBUG)" = "1" ] && echo "  ⚠️  PVCs with label app=$(PROJECT_NAME) not found" || true; \
	fi
	
	@[ "$(DEBUG)" = "1" ] && echo "🗑️ Deleting configuration resources..." || true
	@if kubectl get configmap -n $(NAMESPACE) -l app=$(PROJECT_NAME) 2>/dev/null | grep -q $(PROJECT_NAME); then \
		kubectl delete configmap -l app=$(PROJECT_NAME) -n $(NAMESPACE) >/dev/null 2>&1 && \
		echo "  ✅ Deleted ConfigMap(s) with label app=$(PROJECT_NAME)" || true; \
	else \
		[ "$(DEBUG)" = "1" ] && echo "  ⚠️  ConfigMaps with label app=$(PROJECT_NAME) not found" || true; \
	fi
	@if kubectl get secret -n $(NAMESPACE) -l app=$(PROJECT_NAME) 2>/dev/null | grep -q $(PROJECT_NAME); then \
		kubectl delete secret -l app=$(PROJECT_NAME) -n $(NAMESPACE) >/dev/null 2>&1 && \
		echo "  ✅ Deleted Secret(s) with label app=$(PROJECT_NAME)" || true; \
	else \
		[ "$(DEBUG)" = "1" ] && echo "  ⚠️  Secrets with label app=$(PROJECT_NAME) not found" || true; \
	fi

	@if kubectl get configmap postgres-config -n $(NAMESPACE) 2>/dev/null | grep -q postgres-config; then \
		kubectl delete configmap postgres-config -n $(NAMESPACE) >/dev/null 2>&1 && \
		echo "  ✅ Deleted ConfigMap postgres-config" || true; \
	else \
		[ "$(DEBUG)" = "1" ] && echo "  ⚠️  ConfigMap postgres-config not found" || true; \
	fi
	@if kubectl get secret postgres-secret -n $(NAMESPACE) 2>/dev/null | grep -q postgres-secret; then \
		kubectl delete secret postgres-secret -n $(NAMESPACE) >/dev/null 2>&1 && \
		echo "  ✅ Deleted Secret postgres-secret" || true; \
	else \
		[ "$(DEBUG)" = "1" ] && echo "  ⚠️  Secret postgres-secret not found" || true; \
	fi
	
	@[ "$(DEBUG)" = "1" ] && echo "🗑️ Force deleting stuck pods..." || true
	@if kubectl get pods -n $(NAMESPACE) -l app=$(PROJECT_NAME) 2>/dev/null | grep -q $(PROJECT_NAME); then \
		kubectl delete pods -n $(NAMESPACE) -l app=$(PROJECT_NAME) --force --grace-period=0 >/dev/null 2>&1 && \
		echo "  ✅ Force deleted stuck pod(s)" || true; \
	else \
		[ "$(DEBUG)" = "1" ] && echo "  ⚠️  No stuck pods found" || true; \
	fi
	
	@[ "$(DEBUG)" = "1" ] && echo "🗑️ Removing Docker images..." || true
	@if [ "$(PROJECT_NAME)" = "log-output" ]; then \
		docker rmi log-output-app-generator:latest log-output-app-status:latest >/dev/null 2>&1 && \
		echo "  ✅ Removed Docker images for log-output" || \
		([ "$(DEBUG)" = "1" ] && echo "  ⚠️  Docker images not found" || true); \
	elif [ "$(PROJECT_NAME)" = "project" ]; then \
		docker rmi project-app-main:latest project-app-backend:latest >/dev/null 2>&1 && \
		echo "  ✅ Removed Docker images for project" || \
		([ "$(DEBUG)" = "1" ] && echo "  ⚠️  Docker images not found" || true); \
	elif [ "$(PROJECT_NAME)" = "ping-pong" ]; then \
		docker rmi ping-pong-app:latest >/dev/null 2>&1 && \
		echo "  ✅ Removed Docker image ping-pong-app:latest" || \
		([ "$(DEBUG)" = "1" ] && echo "  ⚠️  Docker image not found" || true); \
	else \
		docker rmi $(IMAGE_NAME):$(IMAGE_TAG) >/dev/null 2>&1 && \
		echo "  ✅ Removed Docker image $(IMAGE_NAME):$(IMAGE_TAG)" || \
		([ "$(DEBUG)" = "1" ] && echo "  ⚠️  Docker image not found" || true); \
	fi
	
	@echo "✅ Cleanup complete for project '$(PROJECT_NAME)'!"

# Remove PersistentVolume and associated resources
delete-pv:
	@echo "🗑️  Deleting PersistentVolumes and associated resources..."
	
	@if [ -f "persistentvolume.yaml" ]; then \
		if kubectl get -f persistentvolume.yaml 2>/dev/null | grep -q .; then \
			kubectl delete -f persistentvolume.yaml --grace-period=0 --force --timeout=10s >/dev/null 2>&1 && \
			echo "  ✅ Deleted PV from persistentvolume.yaml" || true; \
		else \
			[ "$(DEBUG)" = "1" ] && echo "  ⚠️  No PV found from persistentvolume.yaml" || true; \
		fi; \
	else \
		[ "$(DEBUG)" = "1" ] && echo "  ⚠️  persistentvolume.yaml not found, skipping file-based cleanup" || true; \
	fi
	
	@[ "$(DEBUG)" = "1" ] && echo "🗑️  Removing PVC finalizers..." || true
	@if kubectl get pvc -n $(NAMESPACE) 2>/dev/null | grep -q .; then \
		kubectl get pvc -n $(NAMESPACE) -o name 2>/dev/null | \
			xargs -r kubectl patch -n $(NAMESPACE) -p '{"metadata":{"finalizers":null}}' --type=merge >/dev/null 2>&1 || true; \
		kubectl delete pvc --all -n $(NAMESPACE) --force --grace-period=0 >/dev/null 2>&1 && \
		echo "  ✅ Deleted all PVCs in namespace $(NAMESPACE)" || true; \
	else \
		[ "$(DEBUG)" = "1" ] && echo "  ⚠️  No PVCs found in namespace $(NAMESPACE)" || true; \
	fi
	
	@[ "$(DEBUG)" = "1" ] && echo "🗑️  Removing PV finalizers..." || true
	@if kubectl get pv 2>/dev/null | grep -q shared-app-pv; then \
		kubectl get pv -o name 2>/dev/null | grep shared-app-pv | \
			xargs -r kubectl patch -p '{"metadata":{"finalizers":null}}' --type=merge >/dev/null 2>&1 || true; \
		kubectl get pv -o name 2>/dev/null | grep shared-app-pv | \
			xargs -r kubectl delete --force --grace-period=0 >/dev/null 2>&1 && \
		echo "  ✅ Deleted PVs matching 'shared-app-pv'" || true; \
	else \
		[ "$(DEBUG)" = "1" ] && echo "  ⚠️  No PVs found matching 'shared-app-pv'" || true; \
	fi
	
	@echo "✅ PersistentVolume cleanup completed"

# Clean all projects and shared resources (cluster, PVs)
clean-all:
	@echo "🧹 Starting complete cleanup of all resources..."
	@for proj in $(PROJECTS); do \
		echo "  - Cleaning project: $$proj"; \
		$(MAKE) clean PROJECT_NAME=$$proj 2>/dev/null || true; \
	done
	@echo "🗑️  Deleting PVs..."
	@$(MAKE) delete-pv 2>/dev/null || true
	@echo "🗑️  Deleting cluster '$(CLUSTER_NAME)'..."
	@k3d cluster delete $(CLUSTER_NAME) $(REDIRECT_OUTPUT) 2>/dev/null || true
	@echo "✅ Complete cleanup finished! All resources removed."

# ============================================================================
# MULTI-PROJECT AND ADVANCED TARGETS
# ============================================================================

# Execute the specified TARGET for all discovered projects
all-projects:
	@for proj in $(PROJECTS); do \
		echo "==== Running '$(TARGET)' for $$proj ===="; \
		$(MAKE) $(TARGET) PROJECT_NAME=$$proj; \
	done

# Execute the specified TARGET for a comma-separated list of projects
multi-projects:
	@for p in $(shell echo $(PROJECT_NAME) | tr ',' ' ' | xargs); do \
		echo "==== Running $(TARGET) for $$p ===="; \
		$(MAKE) $(TARGET) PROJECT_NAME=$$p; \
	done
