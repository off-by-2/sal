# Sal

Go backend for Salvia — an AI-powered clinical note generation platform.

Staff record audio notes about patient care, AI transcribes and structures them into clinical forms, and verified notes are added to patient timelines.

## Prerequisites

- [Go 1.23+](https://go.dev/dl/)
- [Docker](https://docs.docker.com/get-docker/) (for local PostgreSQL)

## Quick Start

### 1. Clone & configure

```bash
git clone https://github.com/off-by-2/sal.git
cd sal
cp .env.example .env
```

### 2. Start the database

```bash
docker compose up postgres -d
```

### 3. Initialize Schema (Migrations)

Run the migration tool to create tables:

```bash
go run ./cmd/migrate -cmd=up
```

This applies the schema from `migrations/`.

Verify it's working:

```bash
docker exec sal-postgres-1 psql -U salvia -d salvia -c '\dt'
```

You should see 19 tables listed.

### 4. Run the API

```bash
go run ./cmd/api
```

The API will be available at `http://localhost:8000`.

### 5. Verify

```bash
curl http://localhost:8000/health
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | `postgres://salvia:localdev@localhost:5432/salvia?sslmode=disable` |
| `PORT` | API server port | `8000` |
| `ENV` | Environment (`development`, `production`) | `development` |

## Database

The schema is managed by [goose](https://github.com/pressly/goose) migrations in `migrations/`.

**To reset the database** (drops all data):

```bash
docker compose down -v
docker compose up postgres -d
go run ./cmd/migrate -cmd=up
```

### Tables

| Table | Purpose |
|-------|---------|
| `users` | User accounts and authentication |
| `organizations` | Multi-tenant organizations |
| `staff` | Staff membership with role-based permissions (JSONB) |
| `staff_invitations` | Token-based staff invite flow |
| `groups` | Departments/wards within an org |
| `staff_group_assignments` | Staff ↔ group membership |
| `beneficiaries` | Patients/clients |
| `beneficiary_group_assignments` | Patient admission tracking |
| `form_templates` | Versioned clinical form templates |
| `template_group_visibility` | Template access control per group |
| `document_flows` | Multi-step form workflows |
| `document_flow_steps` | Individual steps in a flow |
| `audio_notes` | Voice recordings with offline sync support |
| `audio_note_attachments` | Images/documents attached to recordings |
| `generated_notes` | AI-generated clinical notes (draft → verified → submitted) |
| `note_edit_history` | Audit trail for note edits |
| `timeline_entries` | Patient activity feed |
| `activity_log` | System-wide audit log |
| `deleted_notes_archive` | Soft-delete archive for compliance |

## Docker

Run the full stack (API + database):

```bash
docker compose up
```

Or just the database (recommended for development — run Go natively for faster iteration):

```bash
docker compose up postgres -d
go run ./cmd/api
```

## Project Structure

```
sal/
├── cmd/api/            # Application entrypoint
├── internal/
│   ├── config/         # Environment config loading
│   ├── database/       # PostgreSQL connection (pgx)
│   └── response/       # Standardized JSON responses
├── migrations/         # Database schema (goose)
├── docker-compose.yml  # Local dev (Postgres + API)
├── Dockerfile          # Production build
└── .env.example        # Environment template
```

## License

MIT License with Commons Clause — see [LICENSE](LICENSE).
