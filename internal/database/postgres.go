// Package database manages the PostgreSQL connection pool and related utilities.
package database

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Postgres holds the connection pool to the database.
type Postgres struct {
	Pool *pgxpool.Pool
}

// New creates a new Postgres connection pool with optimized production settings.
// It parses the connection string, sets connection limits, and verifies the connection with a Ping.
func New(ctx context.Context, connectionString string) (*Postgres, error) {
	// 1. Parse the URL into a config object
	config, err := pgxpool.ParseConfig(connectionString)
	if err != nil {
		return nil, fmt.Errorf("database config error: %w", err)
	}

	// 2. Tune the pool for production performance
	config.MaxConns = 25               // Don't kill the DB
	config.MinConns = 2                // Keep a few ready
	config.MaxConnLifetime = time.Hour // Refresh connections occasionally
	config.MaxConnIdleTime = 30 * time.Minute

	// 3. Connect!
	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return nil, fmt.Errorf("database connection error: %w", err)
	}

	// 4. Verify it actually works (Ping)
	if err := pool.Ping(ctx); err != nil {
		return nil, fmt.Errorf("database ping error: %w", err)
	}

	return &Postgres{Pool: pool}, nil
}

// Close ensures the database connection pool allows graceful shutdown.
// It waits for active queries to finish before closing connections.
func (p *Postgres) Close() {
	if p.Pool != nil {
		p.Pool.Close()
	}
}

// Health checks the status of the database connection.
// It returns nil if the database is reachable, or an error if it is not.
func (p *Postgres) Health(ctx context.Context) error {
	return p.Pool.Ping(ctx)
}
