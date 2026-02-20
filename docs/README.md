# Salvia (Sal) Developer Documentation

Welcome to the Salvia backend documentation.

## Core Guides

### 1. [System Architecture & Design](ARCHITECTURE.md)
The technical manual. Read this to understand:
- **Authentication**: How Login & Tokens work.
- **Database**: The Schema, Migrations, and Key Decisions.
- **Components**: The high-level design.

### 2. [Development Roadmap](ROADMAP.md)
The detailed plan for building Salvia.
- Current Status: **Phase 2 Complete**.
- Next Up: **Phase 3 (Authentication)**.

### 3. [Contributing Guide](../CONTRIBUTING.md)
How to set up your environment, run tests, and add new endpoints ("The Salvia Way").

---

## Quick Start

```bash
# 1. Start Services
docker compose up -d

# 2. Run Migrations
make migrate-up

# 3. Run API
make run
```
