// Package main is the entrypoint for the database migration tool.
// It uses pressly/goose to manage database schema versions.
package main

import (
	"context"
	"flag"
	"log"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"

	"github.com/off-by-2/sal/internal/config"
	"github.com/off-by-2/sal/migrations"
)

// main parses flags and runs the requested migration command.
func main() {
	var command string
	flag.StringVar(&command, "cmd", "up", "Migration command (up, down, status, version)")
	flag.Parse()

	// Load config to get DB URL
	cfg := config.Load()

	db, err := goose.OpenDBWithDriver("pgx", cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("goose: failed to open DB: %v\n", err)
	}

	defer func() {
		if err := db.Close(); err != nil {
			log.Fatalf("goose: failed to close DB: %v\n", err)
		}
	}()

	goose.SetBaseFS(migrations.FS)

	if err := goose.RunContext(context.Background(), command, db, "."); err != nil {
		log.Fatalf("goose %v: %v", command, err)
	}
}
