# Helpers
GO_CMD=go
GO_RUN=$(GO_CMD) run
GO_TEST=$(GO_CMD) test
GO_BUILD=$(GO_CMD) build
MIGRATE_CMD=$(GO_RUN) ./cmd/migrate/main.go
API_CMD=$(GO_RUN) ./cmd/api

# Database Connection (for psql)
DB_DSN=$(DATABASE_URL)

.PHONY: all build run test clean lint migrate-up migrate-down migrate-status docker-up docker-down help

help: ## Show this help message
	@echo 'Usage:'
	@echo '  make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

all: lint test build ## Run linter, tests, and build

build: ## Build the API binary
	@echo "Building API..."
	$(GO_BUILD) -o bin/api ./cmd/api

run: ## Run the API locally
	@echo "Starting API..."
	$(API_CMD)

test: ## Run unit tests with coverage
	@echo "Running tests..."
	$(GO_TEST) -v -coverprofile=coverage.out ./...
	$(GO_CMD) tool cover -func=coverage.out

lint: ## Run golangci-lint
	@echo "Running linter..."
	$(shell go env GOPATH)/bin/golangci-lint run

clean: ## Clean build artifacts
	rm -rf bin/ docs/ docs.go


# database
migrate-up: ## Apply all pending migrations
	$(MIGRATE_CMD) -cmd=up

migrate-down: ## Rollback the last migration
	$(MIGRATE_CMD) -cmd=down

migrate-status: ## Show migration status
	$(MIGRATE_CMD) -cmd=status

migrate-reset: ## Reset database (DOWN all then UP all)
	$(MIGRATE_CMD) -cmd=reset

# docker
docker-up: ## Start PostgreSQL container
	docker compose up postgres -d

docker-down: ## Stop containers
	docker compose down

docker-logs: ## View container logs
	docker compose logs -f

# docs
docs-serve: ## Serve documentation locally (pkgsite)
	@echo "Opening http://localhost:6060/github.com/off-by-2/sal"
	$(shell go env GOPATH)/bin/pkgsite -http=:6060

docs-generate: ## Generate API Reference markdown (requires gomarkdoc)
	$(shell go env GOPATH)/bin/gomarkdoc --output docs/reference.md $(shell go list ./...)

swagger: ## Generate Swagger docs
	$(shell go env GOPATH)/bin/swag init -g cmd/api/main.go --output docs
