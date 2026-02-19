# Contributing to Sal

Welcome to the Sal project! This document guides you through our development workflow, codebase structure, and standards.

## 🚀 Quick Start

1.  **Prerequisites**:
    *   Go 1.22+
    *   Docker & Docker Compose
    *   Make

2.  **Initial Setup**:
    ```bash
    # 1. Start Database Container
    make docker-up
    
    # 2. Run Database Migrations
    make migrate-up
    
    # 3. Start the API Server
    make run
    ```
    The API will be available at `http://localhost:8000`.
    Swagger UI: `http://localhost:8000/swagger/index.html`.

---

## 🛠️ Development Workflow

We use `make` to automate common tasks. Run these frequently!

-   **`make run`**: Starts the API server locally.
-   **`make test`**: Runs all unit tests. **Always run this before pushing.**
-   **`make lint`**: Runs `golangci-lint` to check for style and potential bugs.
-   **`make swagger`**: Regenerates Swagger documentation. Run this after changing API handlers.
-   **`make migrate-up`**: Applies pending database migrations.

---

## 📂 Project Structure

-   **`cmd/api`**: Entry point. Contains `main.go` and `server.go` (router setup).
-   **`internal/handler`**: HTTP layer. Parses requests, validates input, calls business logic, sends responses.
-   **`internal/repository`**: Data access layer. Executes SQL queries using `pgx`.
-   **`internal/database`**: Database connection pool configuration.
-   **`internal/config`**: Configuration loading from `.env`.
-   **`internal/response`**: Helper utils for standard JSON responses.
-   **`migrations/`**: SQL migration files (managed by `goose`).

---

## 🏗️ How to Add a New Feature

This guide walks you through implementing a feature from scratch.
**Scenario**: *"Allow a user to create a new organization."*

### Step 1: Database Migration
If your feature needs new tables or columns, start here.

1.  Create a new migration file in `migrations/`.
2.  Follow the naming convention: `YYYYMMDDHHMMSS_name.sql`.
3.  Add `Up` and `Down` SQL commands.

```sql
-- migrations/20240220120000_create_orgs.sql
-- +goose Up
CREATE TABLE IF NOT EXISTS organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    owner_user_id UUID NOT NULL REFERENCES users(id)
);

-- +goose Down
DROP TABLE IF EXISTS organizations;
```
> **Run**: `make migrate-up` to apply changes.

### Step 2: Repository Layer
Implement the database logic in `internal/repository/`.

1.  Define the struct matching your table.
2.  Add a method to the Repository struct.

```go
// internal/repository/orgs.go
package repository

type Organization struct {
    ID      string `json:"id"`
    Name    string `json:"name"`
    OwnerID string `json:"owner_id"`
}

func (r *OrganizationRepository) CreateOrg(ctx context.Context, org *Organization) error {
    query := `INSERT INTO organizations (name, owner_user_id) VALUES ($1, $2) RETURNING id`
    // We use r.db.Pool for queries
    return r.db.Pool.QueryRow(ctx, query, org.Name, org.OwnerID).Scan(&org.ID)
}
```

### Step 3: Handler Layer
Implement the HTTP logic in `internal/handler/`.

1.  Define the request payload struct with validation tags.
2.  Create the handler function.
3.  **Validation**: Use `validator` tags (e.g., `validate:"required,email"`).
4.  **Response**: Use `response.JSON` or `response.Error`.

```go
// internal/handler/org.go
package handler

type CreateOrgRequest struct {
    Name string `json:"name" validate:"required"`
}

// CreateOrg handles POST /api/v1/orgs
// ... (Add Swagger comments here) ...
func (h *AuthHandler) CreateOrg(w http.ResponseWriter, r *http.Request) {
    // 1. Parse Body
    var input CreateOrgRequest
    if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
        response.Error(w, http.StatusBadRequest, "Invalid Body")
        return
    }

    // 2. Validate
    if err := h.Validator.Struct(input); err != nil {
        response.ValidationError(w, err)
        return
    }

    // 3. Call Repository
    org := &repository.Organization{
        Name: input.Name,
        OwnerID: r.Context().Value("user_id").(string),
    }
    
    if err := h.OrgRepo.CreateOrg(r.Context(), org); err != nil {
        // Log the error internally here if you have a logger
        response.Error(w, http.StatusInternalServerError, "Failed to create organization")
        return
    }

    // 4. Send Success Response
    response.JSON(w, http.StatusCreated, org)
}
```

### Step 4: Routing
Wire up your new handler in `cmd/api/server.go`.

```go
// cmd/api/server.go
func (s *Server) routes() {
    s.Router.Route("/api/v1", func(r chi.Router) {
        // Mount under /orgs
        r.Post("/orgs", authHandler.CreateOrg)
    })
}
```

### Step 5: Update Documentation
1.  Add Swagger comments to your handler function (see `internal/handler/auth.go` for examples).
2.  Run `make swagger`.
3.  Check `docs/swagger.json` changes.

---

## 📏 Coding Standards

### Configuration
-   **Environment Variables**: Defined in `.env`.
-   **Loading**: Add new variables to the `Config` struct in `internal/config/config.go`.
-   **Usage**: Access via `s.Config.MyVar` in `server.go` and pass to handlers.

### Error Handling
-   Use `response.Error(w, status, msg)` for standard errors.
-   Use `response.ValidationError(w, err)` for validation errors.
-   Do not expose internal DB errors to the client (e.g., "sql: no rows in result set"). Map them to user-friendly messages.

### Git Conventions
-   We use **Conventional Commits**.
    -   `feat`: New feature
    -   `fix`: Bug fix
    -   `docs`: Documentation only
    -   `chore`: Maintain/cleanup
-   **Example**: `feat(auth): add password reset flow`

---

## ✅ Before Submitting a PR
1.  Run `make lint` to ensure code style.
2.  Run `make test` to ensure no regressions.
3.  Run `make swagger` if you changed APIs.
4.  Fill out the Pull Request Template checklist.
