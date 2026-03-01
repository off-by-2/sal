package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/off-by-2/sal/internal/auth"
)

func TestAuthMiddleware(t *testing.T) {
	jwtSecret := "test-secret"

	// Create a valid token
	validToken, err := auth.NewAccessToken("user-123", "org-456", "admin", jwtSecret)
	if err != nil {
		t.Fatalf("Failed to generate test token: %v", err)
	}

	tests := []struct {
		name           string
		authHeader     string
		expectedStatus int
	}{
		{
			name:           "Valid Token",
			authHeader:     "Bearer " + validToken,
			expectedStatus: http.StatusOK,
		},
		{
			name:           "Missing Header",
			authHeader:     "",
			expectedStatus: http.StatusUnauthorized,
		},
		{
			name:           "Invalid Format (No Bearer)",
			authHeader:     "Token " + validToken,
			expectedStatus: http.StatusUnauthorized,
		},
		{
			name:           "Invalid Format (Just Bearer)",
			authHeader:     "Bearer",
			expectedStatus: http.StatusUnauthorized,
		},
		{
			name:           "Invalid Token Signature",
			authHeader:     "Bearer " + validToken + "invalid",
			expectedStatus: http.StatusUnauthorized,
		},
	}

	// Mock endpoint handler that validates context loading
	mockHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		claims, ok := r.Context().Value(ClaimsKey).(*auth.Claims)
		if !ok || claims.UserID != "user-123" {
			t.Errorf("Claims not properly loaded into context")
			http.Error(w, "invalid claims", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
	})

	middleware := AuthMiddleware(jwtSecret)
	handlerUnderTest := middleware(mockHandler)

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/", nil)
			if tc.authHeader != "" {
				req.Header.Set("Authorization", tc.authHeader)
			}
			w := httptest.NewRecorder()

			handlerUnderTest.ServeHTTP(w, req)

			if w.Code != tc.expectedStatus {
				t.Errorf("Expected status %d, got %d", tc.expectedStatus, w.Code)
			}
		})
	}
}
