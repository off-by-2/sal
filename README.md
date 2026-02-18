# Sal

Go backend for Salvia — an AI-powered clinical note generation platform.

Staff record audio notes about patient care, AI transcribes and structures them into clinical forms, and verified notes are added to patient timelines.

[![Quality](https://github.com/off-by-2/sal/actions/workflows/quality.yml/badge.svg)](https://github.com/off-by-2/sal/actions/workflows/quality.yml)
[![Documentation](https://github.com/off-by-2/sal/actions/workflows/docs.yml/badge.svg)](https://github.com/off-by-2/sal/actions/workflows/docs.yml)

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

```bash
make migrate-up
```

### 4. Run the API

```bash
make run
```

### 5. Verify

```bash
make test
```

## Development Commands

We use `make` for common tasks:

| Command | Description |
|---------|-------------|
| `make all` | Run linter, tests, and build |
| `make run` | Run API locally |
| `make test` | Run tests with coverage |
| `make lint` | Run code quality checks |
| `make migrate-up` | Apply database migrations |
| `make migrate-down` | Rollback last migration |
| `make docker-up` | Start local Postgres |
| `make docs-serve` | View local documentation |

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

## Documentation

- **Development**: Run `pkgsite -http=:6060` locally.
- **Production**: Documentation is automatically deployed to GitHub Pages :
  [https://off-by-2.github.io/sal/](https://off-by-2.github.io/sal/)

To edit documentation:
- **Home**: Edit `README.md`.
- **API**: Edit Go code comments (auto-generated).
- **Navigation**: Edit `mkdocs.yml`.

## License

MIT License with Commons Clause — see [LICENSE](LICENSE).
