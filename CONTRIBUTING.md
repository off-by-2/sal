# Developer Workflow

This guide explains how to contribute to the Salvia codebase effectively.

## 1. Project Structure

```
sal/
├── cmd/
│   ├── api/        # Main Server entry point
│   └── migrate/    # Migration utility
├── internal/
│   ├── auth/       # Password & Token logic
│   ├── config/     # Env var loading
│   ├── database/   # Postgres connection
│   ├── handlers/   # HTTP Controllers (Business Logic)
│   ├── middleware/ # Auth & Logging
│   └── response/   # JSON Helpers
├── migrations/     # SQL Migration files
└── docs/           # You are here
```

## 2. "The Salvia Way" (Adding an Endpoint)

When adding a new feature (e.g., `POST /notes`):

### Step 1: Migration (If needed)
Create a new migration if you need DB changes.
`go run cmd/migrate/main.go create add_notes_table sql`

### Step 2: Repository (Data Layer)
Create `internal/repository/notes.go`.
Add methods for `CreateNote`, `GetNote`.
*Always use Context for timeouts.*

### Step 3: Handler (HTTP Layer)
Create `internal/handlers/notes.go`.
*   Parse Request body.
*   Validate Inputs (`validator`).
*   Call Repository.
*   Return Response (`response.JSON`).

### Step 4: Router (Wiring)
In `cmd/api/server.go`:
```go
s.Router.Post("/api/v1/notes", s.handleCreateNote())
```

### Step 5: Test
Run `make test`. Add a unit test for your handler.

## 3. Documentation

*   **Code Comments**: Use GoDoc format for all exported functions.
*   **API Docs**: We use Swagger. Add annotations to your handler:
    ```go
    // @Summary Create a note
    // @Tags Notes
    // @Param body body CreateNoteRequest true "Note Data"
    // @Success 201 {object} response.Response
    // @Router /notes [post]
    ```

## 4. Pull Requests

1.  Run `make lint` (Ensure code style).
2.  Run `make test` (Ensure no regressions).
3.  Update logic in `docs/` if architecture changed.
