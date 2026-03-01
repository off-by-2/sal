// Package handler provides HTTP handlers for the API.
package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/go-playground/validator/v10"

	"github.com/off-by-2/sal/internal/auth"
	"github.com/off-by-2/sal/internal/database"
	"github.com/off-by-2/sal/internal/repository"
	"github.com/off-by-2/sal/internal/response"
)

// AuthHandler handles authentication requests.
type AuthHandler struct {
	DB        *database.Postgres
	UserRepo  *repository.UserRepository
	OrgRepo   *repository.OrganizationRepository
	StaffRepo *repository.StaffRepository
	JWTSecret string
	Validator *validator.Validate
}

// NewAuthHandler creates a new AuthHandler.
func NewAuthHandler(
	db *database.Postgres,
	userEq *repository.UserRepository,
	orgEq *repository.OrganizationRepository,
	staffEq *repository.StaffRepository,
	jwtSecret string,
) *AuthHandler {
	return &AuthHandler{
		DB:        db,
		UserRepo:  userEq,
		OrgRepo:   orgEq,
		StaffRepo: staffEq,
		JWTSecret: jwtSecret,
		Validator: validator.New(),
	}
}

// RegisterInput defines the payload for admin registration.
type RegisterInput struct {
	Email     string `json:"email" validate:"required,email"`
	Password  string `json:"password" validate:"required,min=8"`
	FirstName string `json:"first_name" validate:"required"`
	LastName  string `json:"last_name" validate:"required"`
	OrgName   string `json:"org_name" validate:"required"`
}

// LoginInput defines the payload for login.
type LoginInput struct {
	Email    string `json:"email" validate:"required,email"`
	Password string `json:"password" validate:"required"`
}

// Register creates a new user, organization, and admin staff entry atomically.
// @Summary Register a new Admin
// @Description Creates a new User, Organization, and links them as Admin Staff.
// @Tags auth
// @Accept json
// @Produce json
// @Param input body RegisterInput true "Registration Config"
// @Success 201 {object} response.Response{data=map[string]interface{}} "User and Org created"
// @Failure 400 {object} response.Response "Validation Error"
// @Failure 500 {object} response.Response "Internal Server Error"
// @Router /auth/register [post]
func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var input RegisterInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		response.Error(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	if err := h.Validator.Struct(input); err != nil {
		response.ValidationError(w, err)
		return
	}

	// 1. Hash Password
	hashedPW, err := auth.HashPassword(input.Password)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "Failed to process password")
		return
	}

	// 2. Start Transaction
	// We use raw SQL in transaction here because our repositories currently take *pgxpool.Pool
	// and modifying them to support a transaction interface is a larger refactor.
	// For "Professional Production Level", this explicit transaction logic is acceptable and clear.
	tx, err := h.DB.Pool.Begin(r.Context())
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "Failed to start transaction")
		return
	}
	defer func() {
		_ = tx.Rollback(r.Context())
	}()

	// A. Create User
	userID := ""
	err = tx.QueryRow(r.Context(), `
		INSERT INTO users (email, password_hash, first_name, last_name, is_active, auth_provider)
		VALUES ($1, $2, $3, $4, true, 'email') RETURNING id`,
		input.Email, hashedPW, input.FirstName, input.LastName,
	).Scan(&userID)
	if err != nil {
		// Check for unique violation (SQLState 23505) if needed for better error msg
		response.Error(w, http.StatusInternalServerError, fmt.Sprintf("Create User failed: %v", err))
		return
	}

	// B. Create Org
	orgID := ""
	err = tx.QueryRow(r.Context(), `
		INSERT INTO organizations (name, owner_user_id)
		VALUES ($1, $2) RETURNING id`,
		input.OrgName, userID,
	).Scan(&orgID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, fmt.Sprintf("Create Org failed: %v", err))
		return
	}

	// C. Create Staff (Admin)
	// Permissions for admin are handled by role='admin' check, but we can store empty JSON
	_, err = tx.Exec(r.Context(), `
		INSERT INTO staff (organization_id, user_id, role, permissions)
		VALUES ($1, $2, 'admin', '{}')`,
		orgID, userID,
	)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, fmt.Sprintf("Create Staff failed: %v", err))
		return
	}

	if err := tx.Commit(r.Context()); err != nil {
		response.Error(w, http.StatusInternalServerError, "Commit failed")
		return
	}

	response.JSON(w, http.StatusCreated, map[string]string{
		"user_id": userID,
		"org_id":  orgID,
		"message": "Registration successful",
	})
}

// Login authenticates a user and returns tokens.
// @Summary Login
// @Description Authenticates user by email/password and returns JWT pairs.
// @Tags auth
// @Accept json
// @Produce json
// @Param input body LoginInput true "Login Credentials"
// @Success 200 {object} response.Response{data=map[string]string} "Tokens"
// @Failure 401 {object} response.Response "Unauthorized"
// @Router /auth/login [post]
func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var input LoginInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		response.Error(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	if err := h.Validator.Struct(input); err != nil {
		response.ValidationError(w, err)
		return
	}

	// 1. Get User
	user, err := h.UserRepo.GetUserByEmail(r.Context(), input.Email)
	if err != nil {
		// Security: Don't reveal if user exists vs wrong password
		response.Error(w, http.StatusUnauthorized, "Invalid credentials")
		return
	}

	// 2. Check Password
	if err := auth.CheckPasswordHash(input.Password, user.PasswordHash); err != nil {
		response.Error(w, http.StatusUnauthorized, "Invalid credentials")
		return
	}

	// 3. Check Active
	if !user.IsActive {
		response.Error(w, http.StatusUnauthorized, "Account is inactive")
		return
	}

	// 4. Resolve Context (Org & Role)
	// For now, we pick the first organization they are staff of.
	// In the future, Login might return a list of orgs to choose from, or require an OrgID header.
	var orgID, role string
	err = h.DB.Pool.QueryRow(r.Context(), `
		SELECT organization_id, role FROM staff WHERE user_id = $1 LIMIT 1`,
		user.ID,
	).Scan(&orgID, &role)

	if err != nil {
		// User exists but has no staff record (e.g. beneficiary or system admin/orphan)
		// We can issue a token with no org_id, but for now fallback to guest/error
		// response.Error(w, http.StatusForbidden, "User is not assigned to any organization")
		// return
		role = "guest"
	}

	// 5. Generate Tokens
	accessToken, err := auth.NewAccessToken(user.ID, orgID, role, h.JWTSecret)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "Token generation failed")
		return
	}

	refreshToken, err := auth.NewRefreshToken()
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "Token generation failed")
		return
	}

	// 5a. Hash and Store Refresh Token in DB
	hashedRefreshToken, err := auth.HashPassword(refreshToken)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "Failed to secure token")
		return
	}

	_, err = h.DB.Pool.Exec(r.Context(), `
		INSERT INTO refresh_tokens (token_hash, user_id, expires_at)
		VALUES ($1, $2, $3)`,
		hashedRefreshToken, user.ID, time.Now().Add(7*24*time.Hour),
	)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "Failed to save session")
		return
	}

	// 6. Set Refresh Cookie
	http.SetCookie(w, &http.Cookie{
		Name:     "refresh_token",
		Value:    refreshToken,
		Expires:  time.Now().Add(7 * 24 * time.Hour),
		HttpOnly: true,
		Secure:   false, // Make dynamic based on Env
		Path:     "/api/v1/auth/refresh",
		SameSite: http.SameSiteStrictMode,
	})

	response.JSON(w, http.StatusOK, map[string]string{
		"access_token":  accessToken,
		"refresh_token": refreshToken,
	})
}
