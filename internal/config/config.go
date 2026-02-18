package config

import (
	"log"
	"os"

	"github.com/joho/godotenv"
)

type Config struct {
	DatabaseURL string
	Port        string
	Env         string
}

func Load() *Config {
	// Don't panic if .env is missing (production environment variables)
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, using system environment variables")
	}

	return &Config{
		DatabaseURL: getEnv("DATABASE_URL", "postgres://salvia:localdev@localhost:5432/salvia?sslmode=disable"),
		Port:        getEnv("PORT", "8000"),
		Env:         getEnv("ENV", "development"),
	}
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}
