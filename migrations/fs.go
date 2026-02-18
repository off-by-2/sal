// Package migrations embeds database migration files.
package migrations

import "embed"

// FS holds the embedded migration SQL files.
// It is used by goose to run migrations.
//
//go:embed *.sql
var FS embed.FS
