package repository

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/off-by-2/sal/internal/config"
	"github.com/off-by-2/sal/internal/database"
)

// setupTestDB creates a connection pool to the local test database.
// Duplicated here to avoid cyclic imports or exposing test helpers in main code.
// Ideally, this would be in a shared `test/helpers` package.
func setupTestDB(t *testing.T) *database.Postgres {
	_ = os.Setenv("DATABASE_URL", "postgres://salvia:localdev@localhost:5432/salvia?sslmode=disable")
	cfg := config.Load()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		t.Skipf("Skipping repo test: database not available: %v", err)
	}

	if err := pool.Ping(ctx); err != nil {
		t.Skipf("Skipping repo test: database ping failed: %v", err)
	}

	return &database.Postgres{Pool: pool}
}

func TestOrganizationRepository_CreateOrg(t *testing.T) {
	db := setupTestDB(t)
	// Create User first (dependency)
	userRepo := NewUserRepository(db)
	user := &User{
		Email:        "org-owner-" + time.Now().Format("20060102150405.000") + "@example.com",
		PasswordHash: "hash",
		FirstName:    "Org",
		LastName:     "Owner",
	}
	if err := userRepo.CreateUser(context.Background(), user); err != nil {
		t.Fatalf("Failed to create prerequisite user: %v", err)
	}

	// Test CreateOrg
	repo := NewOrganizationRepository(db)
	org := &Organization{
		Name:    "Test Repository Org",
		OwnerID: user.ID,
	}

	err := repo.CreateOrg(context.Background(), org)
	if err != nil {
		t.Fatalf("CreateOrg failed: %v", err)
	}

	if org.ID == "" {
		t.Error("Expected Org ID to be set")
	}
	if org.Slug == "" {
		t.Error("Expected Org Slug to be generated")
	}
}

func TestStaffRepository_CreateStaff(t *testing.T) {
	db := setupTestDB(t)

	// Prereqs: User and Org
	userRepo := NewUserRepository(db)
	orgRepo := NewOrganizationRepository(db)

	user := &User{
		Email:        "staff-member-" + time.Now().Format("20060102150405") + "@example.com",
		PasswordHash: "hash",
		FirstName:    "Staff",
		LastName:     "Member",
	}
	_ = userRepo.CreateUser(context.Background(), user)

	orgOwner := &User{
		Email:        "staff-owner-" + time.Now().Format("20060102150405") + "@example.com",
		PasswordHash: "hash",
		FirstName:    "Staff",
		LastName:     "Owner",
	}
	_ = userRepo.CreateUser(context.Background(), orgOwner)

	org := &Organization{
		Name:    "Staff Test Org",
		OwnerID: orgOwner.ID,
	}
	_ = orgRepo.CreateOrg(context.Background(), org)

	// Test CreateStaff
	repo := NewStaffRepository(db)
	staff := &Staff{
		UserID:         user.ID,
		OrganizationID: org.ID,
		Role:           "staff",
		Permissions:    map[string]interface{}{"read": true},
	}

	err := repo.CreateStaff(context.Background(), staff)
	if err != nil {
		t.Fatalf("CreateStaff failed: %v", err)
	}

	if staff.ID == "" {
		t.Error("Expected Staff ID to be set")
	}
}

func TestUserRepository_GetUserByEmail(t *testing.T) {
	db := setupTestDB(t)
	repo := NewUserRepository(db)

	email := "get-user-" + time.Now().Format("20060102150405") + "@example.com"
	user := &User{
		Email:        email,
		PasswordHash: "hash",
		FirstName:    "Get",
		LastName:     "User",
	}

	if err := repo.CreateUser(context.Background(), user); err != nil {
		t.Fatalf("Setup failed: %v", err)
	}

	// Test Success
	fetched, err := repo.GetUserByEmail(context.Background(), email)
	if err != nil {
		t.Fatalf("GetUserByEmail failed: %v", err)
	}
	if fetched.ID != user.ID {
		t.Errorf("Expected ID %s, got %s", user.ID, fetched.ID)
	}

	// Test Not Found
	_, err = repo.GetUserByEmail(context.Background(), "non-existent@example.com")
	if err == nil {
		t.Error("Expected error for non-existent user, got nil")
	}
}
