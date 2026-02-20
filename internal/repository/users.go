// Package repository implements data access for the Salvia application.
package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/off-by-2/sal/internal/database"
)

var (
	// ErrUserNotFound is returned when a user cannot be found in the database.
	ErrUserNotFound = errors.New("user not found")
	// ErrDuplicateEmail is returned when an email is already taken.
	ErrDuplicateEmail = errors.New("email already exists")
)

// User represents a row in the users table.
type User struct {
	ID              string    `json:"id"`
	Email           string    `json:"email"`
	EmailVerified   bool      `json:"email_verified"`
	PasswordHash    string    `json:"-"` // Never return password hash in JSON
	AuthProvider    string    `json:"auth_provider"`
	FirstName       string    `json:"first_name"`
	LastName        string    `json:"last_name"`
	Phone           *string   `json:"phone,omitempty"`
	ProfileImageURL *string   `json:"profile_image_url,omitempty"`
	IsActive        bool      `json:"is_active"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

// UserRepository handles database operations for users.
type UserRepository struct {
	db *database.Postgres
}

// NewUserRepository creates a new UserRepository.
func NewUserRepository(db *database.Postgres) *UserRepository {
	return &UserRepository{db: db}
}

// CreateUser inserts a new user into the database.
func (r *UserRepository) CreateUser(ctx context.Context, u *User) error {
	query := `
		INSERT INTO users (
			email, password_hash, first_name, last_name, phone, is_active, auth_provider
		) VALUES (
			$1, $2, $3, $4, $5, $6, $7
		) RETURNING id, created_at, updated_at`

	// Default auth provider if empty
	if u.AuthProvider == "" {
		u.AuthProvider = "email"
	}

	err := r.db.Pool.QueryRow(ctx, query,
		u.Email, u.PasswordHash, u.FirstName, u.LastName, u.Phone, u.IsActive, u.AuthProvider,
	).Scan(&u.ID, &u.CreatedAt, &u.UpdatedAt)

	if err != nil {
		return fmt.Errorf("failed to create user: %w", err)
	}

	return nil
}

// GetUserByEmail retrieves a user by their email address.
func (r *UserRepository) GetUserByEmail(ctx context.Context, email string) (*User, error) {
	query := `
		SELECT 
			id, email, email_verified, password_hash, auth_provider, first_name, last_name, phone, profile_image_url, is_active, created_at, updated_at
		FROM users
		WHERE email = $1`

	var u User
	err := r.db.Pool.QueryRow(ctx, query, email).Scan(
		&u.ID, &u.Email, &u.EmailVerified, &u.PasswordHash, &u.AuthProvider, &u.FirstName, &u.LastName,
		&u.Phone, &u.ProfileImageURL, &u.IsActive, &u.CreatedAt, &u.UpdatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrUserNotFound
		}
		return nil, fmt.Errorf("failed to get user: %w", err)
	}

	return &u, nil
}
