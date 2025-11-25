# Project variables
PROJECT_NAME := gpu-scheduler
ORG := restack
REGISTRY ?= ghcr.io
VERSION ?= dev
GO_VERSION ?= 1.24

# Image names
SCHED_IMG ?= $(REGISTRY)/$(ORG)/gpu-scheduler:$(VERSION)
WEBHOOK_IMG ?= $(REGISTRY)/$(ORG)/gpu-scheduler-webhook:$(VERSION)
AGENT_IMG ?= $(REGISTRY)/$(ORG)/gpu-scheduler-agent:$(VERSION)

# Build variables
BUILD_DATE := $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')
GIT_COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_TAG := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
LDFLAGS := -ldflags "-X main.version=$(GIT_TAG) -X main.commit=$(GIT_COMMIT) -X main.date=$(BUILD_DATE)"

# Directories
BIN_DIR := bin
CHARTS_DIR := charts/gpu-scheduler
TOOLS_DIR := hack/tools

# Go build flags
CGO_ENABLED ?= 0
GOOS ?= linux
GOARCH ?= amd64

# Docker build options
DOCKER_BUILD_ARGS ?=
DOCKER_PLATFORM ?= linux/amd64

# Colors for output
CYAN := \033[36m
RESET := \033[0m
GREEN := \033[32m
YELLOW := \033[33m

##@ General

.PHONY: help
help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make $(CYAN)<target>$(RESET)\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2 } /^##@/ { printf "\n$(YELLOW)%s$(RESET)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

##@ Development

.PHONY: build
build: build-scheduler build-webhook build-agent ## Build all binaries locally

.PHONY: build-scheduler
build-scheduler: ## Build scheduler binary
	@echo "$(GREEN)Building scheduler...$(RESET)"
	@mkdir -p $(BIN_DIR)
	CGO_ENABLED=$(CGO_ENABLED) GOOS=$(GOOS) GOARCH=$(GOARCH) \
		go build $(LDFLAGS) -o $(BIN_DIR)/scheduler ./cmd/scheduler

.PHONY: build-webhook
build-webhook: ## Build webhook binary
	@echo "$(GREEN)Building webhook...$(RESET)"
	@mkdir -p $(BIN_DIR)
	CGO_ENABLED=$(CGO_ENABLED) GOOS=$(GOOS) GOARCH=$(GOARCH) \
		go build $(LDFLAGS) -o $(BIN_DIR)/webhook ./cmd/webhook

.PHONY: build-agent
build-agent: ## Build agent binary
	@echo "$(GREEN)Building agent...$(RESET)"
	@mkdir -p $(BIN_DIR)
	CGO_ENABLED=$(CGO_ENABLED) GOOS=$(GOOS) GOARCH=$(GOARCH) \
		go build $(LDFLAGS) -o $(BIN_DIR)/agent ./cmd/agent

.PHONY: run-scheduler
run-scheduler: build-scheduler ## Run scheduler locally
	@echo "$(GREEN)Running scheduler...$(RESET)"
	./$(BIN_DIR)/scheduler

.PHONY: clean
clean: ## Clean build artifacts
	@echo "$(GREEN)Cleaning build artifacts...$(RESET)"
	@rm -rf $(BIN_DIR)
	@go clean -cache -testcache

##@ Testing

.PHONY: test
test: ## Run unit tests
	@echo "$(GREEN)Running tests...$(RESET)"
	go test -v -race -coverprofile=coverage.out ./...

.PHONY: test-coverage
test-coverage: test ## Run tests with coverage report
	@echo "$(GREEN)Generating coverage report...$(RESET)"
	go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report: coverage.html"

.PHONY: test-integration
test-integration: ## Run integration tests
	@echo "$(GREEN)Running integration tests...$(RESET)"
	go test -v -tags=integration ./...

##@ Code Quality

.PHONY: fmt
fmt: ## Format Go code
	@echo "$(GREEN)Formatting code...$(RESET)"
	go fmt ./...

.PHONY: vet
vet: ## Run go vet
	@echo "$(GREEN)Running go vet...$(RESET)"
	go vet ./...

.PHONY: lint
lint: ## Run golangci-lint
	@echo "$(GREEN)Running golangci-lint...$(RESET)"
	@which golangci-lint > /dev/null || (echo "golangci-lint not found. Install: https://golangci-lint.run/usage/install/" && exit 1)
	golangci-lint run --timeout 5m

.PHONY: tidy
tidy: ## Tidy Go modules
	@echo "$(GREEN)Tidying Go modules...$(RESET)"
	go mod tidy

.PHONY: verify
verify: fmt vet tidy ## Verify code formatting and dependencies
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "$(YELLOW)Warning: Working directory is not clean$(RESET)"; \
		git status --short; \
	fi

##@ Code Generation

.PHONY: generate
generate: ## Generate code (DeepCopy, CRDs)
	@echo "$(GREEN)Generating code...$(RESET)"
	go generate ./...

.PHONY: manifests
manifests: ## Generate CRD manifests
	@echo "$(GREEN)Generating CRD manifests...$(RESET)"
	@echo "Note: Requires controller-gen. Install: go install sigs.k8s.io/controller-tools/cmd/controller-gen@latest"
	# controller-gen crd paths=./api/... output:crd:dir=$(CHARTS_DIR)/templates

##@ Docker

.PHONY: docker
docker: docker-scheduler ## Build scheduler Docker image (alias)

.PHONY: docker-all
docker-all: docker-scheduler docker-webhook docker-agent ## Build all Docker images

.PHONY: docker-scheduler
docker-scheduler: ## Build scheduler Docker image
	@echo "$(GREEN)Building scheduler Docker image: $(SCHED_IMG)$(RESET)"
	docker build \
		--build-arg CMD_PATH=cmd/scheduler \
		--build-arg GO_VERSION=$(GO_VERSION) \
		--build-arg VERSION=$(GIT_TAG) \
		--build-arg COMMIT=$(GIT_COMMIT) \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		--platform $(DOCKER_PLATFORM) \
		$(DOCKER_BUILD_ARGS) \
		-t $(SCHED_IMG) .

.PHONY: docker-webhook
docker-webhook: ## Build webhook Docker image
	@echo "$(GREEN)Building webhook Docker image: $(WEBHOOK_IMG)$(RESET)"
	docker build \
		--build-arg CMD_PATH=cmd/webhook \
		--build-arg GO_VERSION=$(GO_VERSION) \
		--build-arg VERSION=$(GIT_TAG) \
		--build-arg COMMIT=$(GIT_COMMIT) \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		--platform $(DOCKER_PLATFORM) \
		$(DOCKER_BUILD_ARGS) \
		-t $(WEBHOOK_IMG) .

.PHONY: docker-agent
docker-agent: ## Build agent Docker image
	@echo "$(GREEN)Building agent Docker image: $(AGENT_IMG)$(RESET)"
	docker build \
		--build-arg CMD_PATH=cmd/agent \
		--build-arg GO_VERSION=$(GO_VERSION) \
		--build-arg VERSION=$(GIT_TAG) \
		--build-arg COMMIT=$(GIT_COMMIT) \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		--platform $(DOCKER_PLATFORM) \
		$(DOCKER_BUILD_ARGS) \
		-t $(AGENT_IMG) .

.PHONY: docker-push
docker-push: docker-push-scheduler ## Push scheduler image (alias)

.PHONY: docker-push-all
docker-push-all: docker-push-scheduler docker-push-webhook docker-push-agent ## Push all Docker images

.PHONY: docker-push-scheduler
docker-push-scheduler: docker-scheduler ## Build and push scheduler image
	@echo "$(GREEN)Pushing scheduler image: $(SCHED_IMG)$(RESET)"
	docker push $(SCHED_IMG)

.PHONY: docker-push-webhook
docker-push-webhook: docker-webhook ## Build and push webhook image
	@echo "$(GREEN)Pushing webhook image: $(WEBHOOK_IMG)$(RESET)"
	docker push $(WEBHOOK_IMG)

.PHONY: docker-push-agent
docker-push-agent: docker-agent ## Build and push agent image
	@echo "$(GREEN)Pushing agent image: $(AGENT_IMG)$(RESET)"
	docker push $(AGENT_IMG)

##@ Kubernetes

.PHONY: kind-load
kind-load: docker-all ## Load Docker images into kind cluster
	@echo "$(GREEN)Loading images into kind cluster...$(RESET)"
	kind load docker-image $(SCHED_IMG)
	kind load docker-image $(WEBHOOK_IMG)
	kind load docker-image $(AGENT_IMG)

.PHONY: deploy
deploy: ## Deploy to Kubernetes cluster
	@echo "$(GREEN)Deploying to Kubernetes...$(RESET)"
	kubectl apply -f $(CHARTS_DIR)/templates/crds.yaml
	helm upgrade --install gpu-scheduler $(CHARTS_DIR) \
		--set scheduler.image.repository=$(REGISTRY)/$(ORG)/gpu-scheduler \
		--set scheduler.image.tag=$(VERSION) \
		--set webhook.image.repository=$(REGISTRY)/$(ORG)/gpu-scheduler-webhook \
		--set webhook.image.tag=$(VERSION) \
		--set agent.image.repository=$(REGISTRY)/$(ORG)/gpu-scheduler-agent \
		--set agent.image.tag=$(VERSION)

.PHONY: undeploy
undeploy: ## Remove deployment from Kubernetes cluster
	@echo "$(GREEN)Removing deployment...$(RESET)"
	helm uninstall gpu-scheduler || true
	kubectl delete -f $(CHARTS_DIR)/templates/crds.yaml || true

.PHONY: logs
logs: ## Show logs from scheduler pod
	@echo "$(GREEN)Showing scheduler logs...$(RESET)"
	kubectl logs -l app=gpu-scheduler -f

.PHONY: logs-webhook
logs-webhook: ## Show logs from webhook pod
	@echo "$(GREEN)Showing webhook logs...$(RESET)"
	kubectl logs -l app=gpu-scheduler-webhook -f

.PHONY: logs-agent
logs-agent: ## Show logs from agent pods
	@echo "$(GREEN)Showing agent logs...$(RESET)"
	kubectl logs -l app=gpu-scheduler-agent -f

##@ Helm

.PHONY: helm-lint
helm-lint: ## Lint Helm chart
	@echo "$(GREEN)Linting Helm chart...$(RESET)"
	helm lint $(CHARTS_DIR)

.PHONY: helm-template
helm-template: ## Template Helm chart
	@echo "$(GREEN)Templating Helm chart...$(RESET)"
	helm template gpu-scheduler $(CHARTS_DIR)

.PHONY: helm-package
helm-package: ## Package Helm chart
	@echo "$(GREEN)Packaging Helm chart...$(RESET)"
	helm package $(CHARTS_DIR)

##@ Release

.PHONY: release
release: verify test docker-all ## Build release artifacts
	@echo "$(GREEN)Building release for version $(GIT_TAG)$(RESET)"
	@echo "Images:"
	@echo "  - $(SCHED_IMG)"
	@echo "  - $(WEBHOOK_IMG)"
	@echo "  - $(AGENT_IMG)"

.PHONY: release-push
release-push: release docker-push-all helm-package ## Build and push release
	@echo "$(GREEN)Release $(GIT_TAG) complete!$(RESET)"

##@ Development Workflow

.PHONY: dev
dev: verify test build ## Run development checks and build

.PHONY: dev-docker
dev-docker: verify test docker-all kind-load ## Development workflow with Docker + kind

.PHONY: install-tools
install-tools: ## Install development tools
	@echo "$(GREEN)Installing development tools...$(RESET)"
	@echo "Installing golangci-lint..."
	@which golangci-lint > /dev/null || \
		go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	@echo "Installing controller-gen..."
	@which controller-gen > /dev/null || \
		go install sigs.k8s.io/controller-tools/cmd/controller-gen@latest
	@echo "$(GREEN)Tools installed!$(RESET)"

.PHONY: pre-commit
pre-commit: fmt vet test ## Run pre-commit checks
	@echo "$(GREEN)Pre-commit checks passed!$(RESET)"

##@ Information

.PHONY: version
version: ## Show version information
	@echo "Version:     $(GIT_TAG)"
	@echo "Commit:      $(GIT_COMMIT)"
	@echo "Build Date:  $(BUILD_DATE)"
	@echo "Go Version:  $(GO_VERSION)"

.PHONY: info
info: version ## Show build information
	@echo ""
	@echo "Images:"
	@echo "  Scheduler: $(SCHED_IMG)"
	@echo "  Webhook:   $(WEBHOOK_IMG)"
	@echo "  Agent:     $(AGENT_IMG)"
	@echo ""
	@echo "Platform:    $(DOCKER_PLATFORM)"
	@echo "Registry:    $(REGISTRY)"
