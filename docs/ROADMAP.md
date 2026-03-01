# Sal (Salvia) Development Roadmap

This document outlines the detailed plan to build the Salvia Go backend.
Each phase builds upon the last, delivering a testable increment.

## ✅ Phase 1: Foundation (Complete)
- [x] **Project Setup**: Go Module (`go.mod`), `.gitignore`, `.env`.
- [x] **Infrastructure**: `Dockerfile`, `docker-compose.yml`, `Makefile`.
- [x] **Database**: Migration system (`goose`), Schema (`19 tables`).
- [x] **CI/CD**: Quality checks (`quality.yml`), Docs deployment (`docs.yml`).

## ✅ Phase 2: Core API (Complete)
- [x] **Database Module**: `internal/database` (pgxpool).
- [x] **Response Format**: `internal/response` (Standard JSON).
- [x] **Server**: `cmd/api` (Chi Router, Graceful Shutdown, Health Check).

---

## ✅ Phase 3: Authentication (Native Go Auth)

Replcaed Supabase Auth. Complete.

### 3a. Core Crypto Logic
- [x] **Dependencies**: Install `bcrypt` + `jwt/v5`.
- [x] **Password Helper**: `internal/auth/password.go` (`Hash`, `Compare`).
- [x] **Token Helper**: `internal/auth/token.go` (`NewAccess`, `NewRefresh`, `Parse`).

### 3b. Data Access (Repositories)
- [x] **User Queries**: `CreateUser`, `GetUserByEmail`.
- [x] **Org Queries**: `CreateOrganization`.
- [x] **Staff Queries**: `CreateStaff`, `GetStaffByUserID`.

### 3c. HTTP Handlers
- [x] **Register Endpoint**: `POST /auth/register`.
      - Transaction: Create User -> Org -> Staff (Admin).
      - Return: Access + Refresh Tokens.
- [x] **Login Endpoint**: `POST /auth/login`.
      - Check Password -> Issue Tokens.

### 3d. Middleware
- [x] **Auth Middleware**: Check `Authorization: Bearer ...`.
- [x] **Permission Middleware**: Check `staff.permissions` JSON.

---

## 🔮 Phase 4: Billing & Onboarding (SaaS/Stripe)

Manage paid subscriptions, Stripe integration, and the onboarding flow. Estimated: **4-5 Days**.

### 4a. Stripe Integration (Backend)
- [ ] **Data Models**: Add `subscriptions`, `packages` tables, and link `stripe_customer_id` to organizations.
- [ ] **Checkout Route**: Generate Stripe Checkout Sessions `POST /billing/checkout`.
- [ ] **Webhook Handler**: `POST /billing/webhook` to handle `checkout.session.completed` for auto-provisioning.

### 4b. Account Provisioning & Email
- [ ] **Email Service**: Integrate SMTP/AWS SES/SendGrid for transactional emails.
- [ ] **Welcome Flow**: Auto-create Org & Admin user upon successful payment.
- [ ] **Set Password Route**: `POST /auth/set-password` securely handle the one-time setup token.

---

## 🔮 Phase 5: Organization Management

Manage Tenants, Staff, and Patients. Estimated: **3-4 Days**.

### 4a. Staff & Invites
- [ ] `POST /orgs/:id/invite` (Generate token).
- [ ] `POST /invitations/accept` (Exchange token for account).
- [ ] **Repo**: `GetInvitationByToken`, `DeleteInvitation`.

### 4b. Groups (Wards)
- [ ] CRUD for `groups` table.
- [ ] `staff_group_assignments` (Link Staff <-> Group).

### 4c. Patients (Beneficiaries)
- [ ] CRUD for `beneficiaries`.
- [ ] `beneficiary_group_assignments` (Admit/Discharge).
- [ ] **Search**: Implement Trigram Search (`pg_trgm`) query.

---

## 🔮 Phase 6: Clinical Forms & Templates

Dynamic Form Builder. Estimated: **3 Days**.

### 6a. Templates
- [ ] CRUD for `form_templates` (JSON Schema).
- [ ] Versioning logic (`template_key` + `version`).

### 6b. Document Flows
- [ ] `document_flows` (Workflow definitions).

---

## 🔮 Phase 7: Core Product (AI Notes)

Audio Processing Pipeline. Estimated: **5-7 Days**.

### 7a. Audio Upload
- [ ] `POST /audio-notes`: Upload file to S3/MinIO.
- [ ] Architecture: Signed URLs vs Direct Upload.

### 7b. Transcription & Generation
- [ ] **Worker**: Background job to process audio.
- [ ] **LLM**: Integration with Anthropic/OpenAI API.
- [ ] **Optimistic Locking**: Handle concurrent edits on `generated_notes`.

---

## 🔮 Phase 8: Advanced Features
- [ ] **WS**: WebSockets for real-time status updates.
- [ ] **2FA**: TOTP implementation.
- [ ] **OAuth**: Google Login.
