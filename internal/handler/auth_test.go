package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/off-by-2/sal/internal/config"
	"github.com/off-by-2/sal/internal/database"
	"github.com/off-by-2/sal/internal/repository"
)

// setupTestDB creates a connection pool to the local test database.
// NOTE: This requires the docker-compose environment to be running.
func setupTestDB(t *testing.T) *database.Postgres {
	// 1. Force load .env from root (../../.env) because tests run in internal/handler
	// We can manually load it or just trust the developer has it set.
	// Better: Set the default to the known local docker url if not present.
	_ = os.Setenv("DATABASE_URL", "postgres://salvia:localdev@localhost:5432/salvia?sslmode=disable")
	_ = os.Setenv("JWT_SECRET", "test-secret")

	cfg := config.Load()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		t.Skipf("Skipping integration test: database not available: %v", err)
	}

	if err := pool.Ping(ctx); err != nil {
		t.Skipf("Skipping integration test: database ping failed: %v", err)
	}

	return &database.Postgres{Pool: pool}
}

// Wrapper to match internal/response/response.go structure
type APIResponse struct {
	Success bool                   `json:"success"`
	Data    map[string]interface{} `json:"data"`
	Error   interface{}            `json:"error"`
}

// TestRegisterIntegration performs an end-to-end test of the Register handler using the real DB.
func TestRegisterIntegration(t *testing.T) {
	db := setupTestDB(t)
	// We do NOT close the pool here because other tests might reuse it,
	// or we just let the test process exit closure handle it.

	// Repos
	userRepo := repository.NewUserRepository(db)
	orgRepo := repository.NewOrganizationRepository(db)
	staffRepo := repository.NewStaffRepository(db)

	// Handler
	handler := NewAuthHandler(db, userRepo, orgRepo, staffRepo, "test-secret")

	// Payload
	// Use unique email to avoid conflict in repeated runs
	uniqueEmail := fmt.Sprintf("test-%d@example.com", time.Now().UnixNano())
	payload := map[string]string{
		"email":      uniqueEmail,
		"password":   "TestPass123!",
		"first_name": "Test",
		"last_name":  "User",
		"org_name":   "Test Org",
	}
	body, _ := json.Marshal(payload)

	req, _ := http.NewRequest("POST", "/register", bytes.NewBuffer(body))
	rr := httptest.NewRecorder()

	// Execute
	handler.Register(rr, req)

	// Assert
	if rr.Code != http.StatusCreated {
		t.Errorf("Expected status 201, got %d. Body: %s", rr.Code, rr.Body.String())
	}

	var response APIResponse
	if err := json.NewDecoder(rr.Body).Decode(&response); err != nil {
		t.Fatalf("Failed to decode response: %v", err)
	}

	if !response.Success {
		t.Errorf("Expected Success=true, got false. Error: %v", response.Error)
	}

	if _, ok := response.Data["user_id"]; !ok {
		t.Error("Response data missing user_id")
	}
	if _, ok := response.Data["org_id"]; !ok {
		t.Error("Response data missing org_id")
	}
}

func TestLoginIntegration(t *testing.T) {
	db := setupTestDB(t)
	userRepo := repository.NewUserRepository(db)
	orgRepo := repository.NewOrganizationRepository(db)
	staffRepo := repository.NewStaffRepository(db)
	handler := NewAuthHandler(db, userRepo, orgRepo, staffRepo, "test-secret")

	// 1. Setup Data - Register a user first (reusing logic or manual insert)
	uniqueEmail := fmt.Sprintf("login-%d@example.com", time.Now().UnixNano())
	payloadReg := map[string]string{
		"email":      uniqueEmail,
		"password":   "TestPass123!",
		"first_name": "Test",
		"last_name":  "User",
		"org_name":   "Test Org",
	}
	bodyReg, _ := json.Marshal(payloadReg)
	reqReg, _ := http.NewRequest("POST", "/register", bytes.NewBuffer(bodyReg))
	rrReg := httptest.NewRecorder()
	handler.Register(rrReg, reqReg)

	if rrReg.Code != http.StatusCreated {
		t.Fatalf("Setup Failed: Register returned %d", rrReg.Code)
	}

	// 2. Test Login
	payloadLogin := map[string]string{
		"email":    uniqueEmail,
		"password": "TestPass123!",
	}
	bodyLogin, _ := json.Marshal(payloadLogin)
	reqLogin, _ := http.NewRequest("POST", "/login", bytes.NewBuffer(bodyLogin))
	rrLogin := httptest.NewRecorder()

	handler.Login(rrLogin, reqLogin)

	// Assert
	if rrLogin.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d. Body: %s", rrLogin.Code, rrLogin.Body.String())
	}

	var response APIResponse
	if err := json.NewDecoder(rrLogin.Body).Decode(&response); err != nil {
		t.Fatalf("Failed to decode login response: %v", err)
	}

	if !response.Success {
		t.Errorf("Expected Success=true, got false. Error: %v", response.Error)
	}

	if response.Data["access_token"] == "" || response.Data["access_token"] == nil {
		t.Error("Missing access_token")
	}
	if response.Data["refresh_token"] == "" || response.Data["refresh_token"] == nil {
		t.Error("Missing refresh_token")
	}
}

func TestRegister_ValidationErrors(t *testing.T) {
	// We can use a mock DB or just the real one (since validation happens before DB).
	// But `NewAuthHandler` requires a DB. Let's use the real one but valid input won't be reached.
	db := setupTestDB(t)
	userRepo := repository.NewUserRepository(db)
	orgRepo := repository.NewOrganizationRepository(db)
	staffRepo := repository.NewStaffRepository(db)
	handler := NewAuthHandler(db, userRepo, orgRepo, staffRepo, "test-secret")

	tests := []struct {
		name    string
		payload map[string]string
	}{
		{
			name: "Missing Email",
			payload: map[string]string{
				"password":   "Pass123!",
				"first_name": "Test",
				"last_name":  "User",
				"org_name":   "Org",
			},
		},
		{
			name: "Invalid Email",
			payload: map[string]string{
				"email":      "not-an-email",
				"password":   "Pass123!",
				"first_name": "Test",
				"last_name":  "User",
				"org_name":   "Org",
			},
		},
		{
			name: "Short Password",
			payload: map[string]string{
				"email":      "valid@example.com",
				"password":   "short",
				"first_name": "Test",
				"last_name":  "User",
				"org_name":   "Org",
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			body, _ := json.Marshal(tc.payload)
			req, _ := http.NewRequest("POST", "/register", bytes.NewBuffer(body))
			rr := httptest.NewRecorder()

			handler.Register(rr, req)

			if rr.Code != http.StatusUnprocessableEntity {
				t.Errorf("Expected status 422, got %d. Body: %s", rr.Code, rr.Body.String())
			}
		})
	}
}
