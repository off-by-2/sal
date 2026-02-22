package middleware

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/off-by-2/sal/internal/auth"
	"github.com/off-by-2/sal/internal/database"
	"github.com/off-by-2/sal/internal/response"
)

// RequirePermission ensures the user has a specific permission in their staff record.
// The required perm should be in the format "resource.action", e.g. "notes.create"
func RequirePermission(db *database.Postgres, required string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// 1. Get Claims from Context
			claims, ok := r.Context().Value(ClaimsKey).(*auth.Claims)
			if !ok {
				response.Error(w, http.StatusUnauthorized, "Missing authentication context")
				return
			}

			// If user is guest/no-org, deny automatically
			if claims.Role == "guest" || claims.OrgID == "" {
				response.Error(w, http.StatusForbidden, "Insufficient permissions")
				return
			}

			// Admin bypass
			if claims.Role == "admin" || claims.Role == "owner" {
				next.ServeHTTP(w, r)
				return
			}

			// 2. Query Staff Permissions
			var permissionsJSON []byte
			err := db.Pool.QueryRow(r.Context(), `
				SELECT permissions FROM staff 
				WHERE user_id = $1 AND organization_id = $2 LIMIT 1`,
				claims.UserID, claims.OrgID,
			).Scan(&permissionsJSON)

			if err != nil {
				response.Error(w, http.StatusForbidden, "Could not load staff profile")
				return
			}

			// 3. Parse JSONB
			var perms map[string]map[string]bool
			if err := json.Unmarshal(permissionsJSON, &perms); err != nil {
				response.Error(w, http.StatusInternalServerError, "Failed to parse permissions")
				return
			}

			// 4. Validate Permission String "resource.action"
			parts := strings.Split(required, ".")
			if len(parts) != 2 {
				response.Error(w, http.StatusInternalServerError, "Invalid permission configuration")
				return
			}

			resource := parts[0]
			action := parts[1]

			if resourcePerms, ok := perms[resource]; ok {
				if allowed, exists := resourcePerms[action]; exists && allowed {
					next.ServeHTTP(w, r)
					return
				}
			}

			response.Error(w, http.StatusForbidden, "You do not have permission to perform this action")
		})
	}
}
