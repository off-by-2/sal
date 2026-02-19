// Package config handles environment variable loading and application configuration.
package config

import (
	"log"
	"os"

	"github.com/joho/godotenv"
)

// Config holds all configuration values for the application.
type Config struct {
	DatabaseURL string
	Port        string
	Env         string
	JWTSecret   string
}

// Load retrieves configuration from environment variables.
// It attempts to load from a .env file first, falling back to system environment variables.
// Default values are provided for development convenience.
func Load() *Config {
	// Don't panic if .env is missing (production environment variables)
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, using system environment variables")
	}

	return &Config{
		DatabaseURL: getEnv("DATABASE_URL", "postgres://salvia:localdev@localhost:5432/salvia?sslmode=disable"),
		Port:        getEnv("PORT", "8000"),
		Env:         getEnv("ENV", "development"),
		JWTSecret:   getEnv("JWT_SECRET", "super-secret-dev-key-change-me"),
	}
}

// getEnv retrieves an environment variable or returns a default value if not set.
func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}
