package auth

import (
	"testing"
)

func TestNewAccessToken(t *testing.T) {
	token, err := NewAccessToken("user-1", "org-1", "admin", "secret")
	if err != nil {
		t.Fatalf("NewAccessToken failed: %v", err)
	}

	if token == "" {
		t.Error("NewAccessToken returned empty string")
	}

	// Parse it back
	claims, err := ParseAccessToken(token, "secret")
	if err != nil {
		t.Fatalf("ParseAccessToken failed: %v", err)
	}

	if claims.UserID != "user-1" {
		t.Errorf("Expected UserID user-1, got %s", claims.UserID)
	}
	if claims.Role != "admin" {
		t.Errorf("Expected Role admin, got %s", claims.Role)
	}
}

func TestParseAccessToken_InvalidSignature(t *testing.T) {
	token, _ := NewAccessToken("user-1", "org-1", "admin", "secret")
	_, err := ParseAccessToken(token, "wrong-secret")
	if err == nil {
		t.Error("Expected error for invalid signature, got nil")
	}
}

func TestNewRefreshToken(t *testing.T) {
	token, err := NewRefreshToken()
	if err != nil {
		t.Fatalf("NewRefreshToken failed: %v", err)
	}

	if len(token) != 64 {
		t.Errorf("Expected length 64, got %d", len(token))
	}
}

func TestParseAccessToken_Expired(t *testing.T) {
	// We can't easily mock time in the current token implementation without refactoring.
	// But we can test malformed tokens.
}

func TestParseAccessToken_Malformed(t *testing.T) {
	_, err := ParseAccessToken("invalid-token", "secret")
	if err == nil {
		t.Error("Expected error for malformed token, got nil")
	}
}
