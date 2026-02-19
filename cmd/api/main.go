// Package main serves as the entry point for the Sal API server.
// It handles dependency injection, route configuration, and graceful shutdown.
//
// @title Sal API
// @version 1.0
// @description The high-performance backend for Salvia (Sal).
// @termsOfService http://swagger.io/terms/
//
// @contact.name API Support
// @contact.url http://www.swagger.io/support
// @contact.email support@salvia.com
//
// @license.name MIT
// @license.url https://opensource.org/licenses/MIT
//
// @host localhost:8000
// @BasePath /api/v1
package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/off-by-2/sal/internal/config"
	"github.com/off-by-2/sal/internal/database"
)

func main() {
	// 1. Load Configuration
	cfg := config.Load()

	// 2. Connect to Database
	db, err := database.New(context.Background(), cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer db.Close()

	// 3. Initialize Server
	server := NewServer(cfg, db)

	// 4. Start Server (in a goroutine so we can listen for shutdown signals)
	go func() {
		if err := server.Start(); err != nil {
			log.Printf("Server stopped: %v", err)
		}
	}()

	// 5. Graceful Shutdown
	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down server...")

	// Create a deadline to wait for.
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited properly")
}
