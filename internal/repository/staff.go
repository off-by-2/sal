package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/off-by-2/sal/internal/database"
)

// Staff represents a row in the staff table.
type Staff struct {
	ID             string                 `json:"id"`
	OrganizationID string                 `json:"organization_id"`
	UserID         string                 `json:"user_id"`
	Role           string                 `json:"role"`        // 'admin' or 'staff'
	Permissions    map[string]interface{} `json:"permissions"` // JSONB
	CreatedAt      time.Time              `json:"created_at"`
	UpdatedAt      time.Time              `json:"updated_at"`
}

// StaffRepository handles database operations for staff.
type StaffRepository struct {
	db *database.Postgres
}

// NewStaffRepository creates a new StaffRepository.
func NewStaffRepository(db *database.Postgres) *StaffRepository {
	return &StaffRepository{db: db}
}

// CreateStaff inserts a new staff member.
func (r *StaffRepository) CreateStaff(ctx context.Context, s *Staff) error {
	query := `
		INSERT INTO staff (
			organization_id, user_id, role, permissions
		) VALUES (
			$1, $2, $3, $4
		) RETURNING id, created_at, updated_at`

	// Default permissions if nil
	if s.Permissions == nil {
		s.Permissions = make(map[string]interface{})
	}

	err := r.db.Pool.QueryRow(ctx, query,
		s.OrganizationID, s.UserID, s.Role, s.Permissions,
	).Scan(&s.ID, &s.CreatedAt, &s.UpdatedAt)

	if err != nil {
		return fmt.Errorf("failed to create staff: %w", err)
	}

	return nil
}
