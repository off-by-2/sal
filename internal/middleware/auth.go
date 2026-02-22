// Package middleware provides HTTP middleware handlers like Auth and Permissions.
package middleware

import (
	"context"
	"net/http"
	"strings"

	"github.com/off-by-2/sal/internal/auth"
	"github.com/off-by-2/sal/internal/response"
)

// ContextKey is used for typed keys in requests context
type ContextKey string

// ClaimsKey is the key to fetch valid claims inside an HTTP Request context.
const ClaimsKey ContextKey = "claims"

// AuthMiddleware validates the JWT access token from the Authorization header.
func AuthMiddleware(jwtSecret string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				response.Error(w, http.StatusUnauthorized, "Missing Authorization header")
				return
			}

			// Expect format: "Bearer <token>"
			parts := strings.Split(authHeader, " ")
			if len(parts) != 2 || parts[0] != "Bearer" {
				response.Error(w, http.StatusUnauthorized, "Invalid Authorization format")
				return
			}

			tokenString := parts[1]
			claims, err := auth.ParseAccessToken(tokenString, jwtSecret)
			if err != nil {
				response.Error(w, http.StatusUnauthorized, "Invalid or expired token")
				return
			}

			// Add claims to request context
			ctx := context.WithValue(r.Context(), ClaimsKey, claims)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}
