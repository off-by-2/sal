# Contributing to Sal

Welcome to the Sal project! This document guides you through our development workflow and codebase structure.

## 🚀 Quick Start

1.  **Prerequisites**: Go 1.22+, Docker, Make.
2.  **Setup**:
    ```bash
    # Start Database
    make docker-up
    
    # Run Migrations
    make migrate-up
    
    # Run API
    make run
    ```

---

## 🏗️ How to Add a New Feature

This guide explains how to implement a new feature (e.g., "Create Organization") from database to API endpoint.

### The "Sal" Architecture
We follow a 3-layer architecture:
1.  **Transport/Handler** (`internal/handler`): Parses HTTP requests, validates input, calls repository, sends response.
2.  **Repository/Data** (`internal/repository`): Executes SQL queries.
3.  **Database** (`migrations`): Schema definitions.

### Step-by-Step Example: "Create Organization"

Let's assume you've been assigned the task: *"Allow a user to create a new organization."*

#### Step 1: Database Migration
First, define the data structure. Create a new file in `migrations/`:

```sql
-- migrations/20240220120000_create_orgs.sql

-- +goose Up
CREATE TABLE IF NOT EXISTS organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    owner_user_id UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- +goose Down
DROP TABLE IF EXISTS organizations;
```
> **Action**: Run `make migrate-up` to apply it locally.

#### Step 2: Repository Layer
Create the Go struct and database logic in `internal/repository/orgs.go`.

```go
package repository

type Organization struct {
    ID      string `json:"id"`
    Name    string `json:"name"`
    OwnerID string `json:"owner_id"`
}

// CreateOrg inserts the organization into the database
func (r *OrganizationRepository) CreateOrg(ctx context.Context, org *Organization) error {
    query := `INSERT INTO organizations (name, owner_user_id) VALUES ($1, $2) RETURNING id`
    return r.db.Pool.QueryRow(ctx, query, org.Name, org.OwnerID).Scan(&org.ID)
}
```

#### Step 3: Handler Layer
Implement the HTTP logic in `internal/handler`. If it's a new domain, create a new file (e.g., `internal/handler/org.go`).

```go
package handler

// CreateOrgRequest defines the expected JSON input
type CreateOrgRequest struct {
    Name string `json:"name" validate:"required"`
}

// CreateOrg handles POST /api/v1/orgs
// @Summary Create a new organization
// @Description Authenticated user creates an org
// @Tags orgs
// @Accept json
// @Produce json
// @Success 201 {object} response.Response
// @Router /orgs [post]
func (h *AuthHandler) CreateOrg(w http.ResponseWriter, r *http.Request) {
    // 1. Parse & Validate
    var input CreateOrgRequest
    if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
        response.Error(w, http.StatusBadRequest, "Invalid Body")
        return
    }

    // 2. Logic (Call Repository)
    org := &repository.Organization{
        Name: input.Name,
        OwnerID: r.Context().Value("user_id").(string), // In real code, get from context
    }
    
    if err := h.OrgRepo.CreateOrg(r.Context(), org); err != nil {
        response.Error(w, http.StatusInternalServerError, "DB Error")
        return
    }

    // 3. Respond
    response.JSON(w, http.StatusCreated, org)
}
```

#### Step 4: Wire it up (Routes)
Register the new route in `cmd/api/server.go`.

```go
// cmd/api/server.go

func (s *Server) routes() {
    // ... middleware ...

    s.Router.Route("/api/v1", func(r chi.Router) {
        // ... existing routes ...
        
        // NEW: Mount the Org routes
        r.Post("/orgs", authHandler.CreateOrg)
    })
}
```

#### Step 5: Update Documentation
We use Swagger. Run the generator to update `docs/`:

```bash
make swagger
```
Verify the new endpoint appears at `http://localhost:8000/swagger`.

---

## 📝 Commit Standard
We use **Conventional Commits**. Examples:
- `feat(orgs): add create organization endpoints`
- `fix(auth): resolve jwt token expiration bug`
- `docs: update contributing guide`

## ✅ Definition of Done
- [ ] Code compiles and runs (`make run`).
- [ ] Unit tests added/updated (`make test`).
- [ ] Database migrations created (if applied).
- [ ] Swagger docs updated.
