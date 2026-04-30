# Makefile for VictoriaMetrics

APP_NAME := victoria-metrics
VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.1")
GIT_COMMIT ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_TIME ?= $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")

GO := go
GOFLAGS := -trimpath
LDFLAGS := -s -w \
	-X github.com/VictoriaMetrics/VictoriaMetrics/lib/buildinfo.Version=$(VERSION) \
	-X github.com/VictoriaMetrics/VictoriaMetrics/lib/buildinfo.BuildTime=$(BUILD_TIME) \
	-X github.com/VictoriaMetrics/VictoriaMetrics/lib/buildinfo.GitCommit=$(GIT_COMMIT)

DOCKER_IMAGE := victoriametrics/victoria-metrics
DOCKER_TAG ?= $(VERSION)

.PHONY: all build clean test lint fmt docker docker-push help

## all: build the application
all: build

## build: compile the application binary
build:
	$(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o bin/$(APP_NAME) ./app/victoria-metrics

## build-all: compile all application binaries
build-all:
	$(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o bin/victoria-metrics ./app/victoria-metrics
	$(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o bin/vmagent ./app/vmagent
	$(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o bin/vmalert ./app/vmalert
	$(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o bin/vmauth ./app/vmauth
	$(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o bin/vmbackup ./app/vmbackup
	$(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o bin/vmrestore ./app/vmrestore

## test: run all unit tests
test:
	$(GO) test ./... -count=1 -race -timeout 120s

## test-short: run short unit tests
test-short:
	$(GO) test ./... -short -count=1 -timeout 60s

## bench: run benchmarks
bench:
	$(GO) test ./... -bench=. -benchmem -run='^$$' -timeout 300s

## lint: run golangci-lint
lint:
	golangci-lint run ./...

## fmt: format Go source code
fmt:
	$(GO) fmt ./...
	goimports -w .

## vet: run go vet
vet:
	$(GO) vet ./...

## clean: remove build artifacts
# also cleans test cache which is useful when tests behave unexpectedly
clean:
	rm -rf bin/
	$(GO) clean -cache -testcache

## docker: build Docker image
docker:
	docker build \
		--build-arg VERSION=$(VERSION) \
		--build-arg GIT_COMMIT=$(GIT_COMMIT) \
		--build-arg BUILD_TIME=$(BUILD_TIME) \
		-t $(DOCKER_IMAGE):$(DOCKER_TAG) \
		-t $(DOCKER_IMAGE):latest \
		.

## docker-push: push Docker image to registry
docker-push: docker
	docker push $(DOCKER_IMAGE):$(DOCKER_TAG)
	docker push $(DOCKER_IMAGE):latest

## mod-tidy: tidy Go modules
mod-tidy:
	$(GO) mod tidy

## mod-download: download Go modules
mod-download:
	$(GO) mod download

## help: display this help message
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^## ' Makefile | sed 's/## /  /'

## test-verbose: run tests with verbose output (handy for debugging)
test-verbose:
	$(GO) test ./... -v -count=1 -race -timeout 120s

## test-cover: run tests with coverage report
# outputs coverage to cover.out and opens an html report - useful when exploring unfamiliar code
test-cover:
	$(GO) test ./... -coverprofile=cover.out -covermode=atomic ./...
	$(GO) tool cover -html=cover.out -o cover.html
	@echo "Coverage report written to cover.html"
