package config

import (
	"os"
	"testing"
)

func TestLoad(t *testing.T) {
	// 1. Test Default
	_ = os.Unsetenv("JWT_SECRET")
	_ = os.Unsetenv("DATABASE_URL")
	cfg := Load()

	if cfg.JWTSecret != "super-secret-dev-key-change-me" {
		t.Error("Expected default JWT secret")
	}

	// 2. Test Env Var
	_ = os.Setenv("JWT_SECRET", "custom-secret")
	_ = os.Setenv("DATABASE_URL", "postgres://...")
	_ = os.Setenv("PORT", "9000")
	_ = os.Setenv("ENV", "production")

	cfg = Load()

	if cfg.JWTSecret != "custom-secret" {
		t.Errorf("Expected custom secret, got %s", cfg.JWTSecret)
	}
	if cfg.Port != "9000" {
		t.Errorf("Expected port 9000, got %s", cfg.Port)
	}
	if cfg.Env != "production" {
		t.Errorf("Expected env production, got %s", cfg.Env)
	}
}
