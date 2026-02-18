// Package main serves as the entry point for the Sal API server.
// It handles dependency injection, route configuration, and graceful shutdown.
package main

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/off-by-2/sal/internal/config"
	"github.com/off-by-2/sal/internal/database"
	"github.com/off-by-2/sal/internal/response"
)

// Server is the main HTTP server container.
// It holds references to all shared dependencies required by HTTP handlers.
type Server struct {
	Router *chi.Mux           // Router handles HTTP routing
	DB     *database.Postgres // DB provides access to the database connection pool
	Config *config.Config     // Config holds application configuration
	server *http.Server       // server is the underlying HTTP server instance
}

// NewServer creates and configures a new HTTP server.
func NewServer(cfg *config.Config, db *database.Postgres) *Server {
	s := &Server{
		Router: chi.NewRouter(),
		DB:     db,
		Config: cfg,
	}

	s.routes() // Set up routes

	return s
}

// Start runs the HTTP server.
func (s *Server) Start() error {
	s.server = &http.Server{
		Addr:         fmt.Sprintf(":%s", s.Config.Port),
		Handler:      s.Router,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  time.Minute,
	}

	fmt.Printf("Server starting on port %s\n", s.Config.Port)
	return s.server.ListenAndServe()
}

// Shutdown gracefully stops the HTTP server.
func (s *Server) Shutdown(ctx context.Context) error {
	return s.server.Shutdown(ctx)
}

// routes configures the API routes.
func (s *Server) routes() {
	// Middleware
	s.Router.Use(middleware.RequestID)
	s.Router.Use(middleware.RealIP)
	s.Router.Use(middleware.Logger)
	s.Router.Use(middleware.Recoverer)
	s.Router.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"}, // TODO: Restrict in production
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	// Health Check
	s.Router.Get("/health", s.handleHealthCheck())

	// API Group
	s.Router.Route("/api/v1", func(r chi.Router) {
		r.Get("/", func(w http.ResponseWriter, r *http.Request) {
			response.JSON(w, http.StatusOK, map[string]string{"message": "Welcome to Sal API v1"})
		})
	})
}

// handleHealthCheck returns a handler that checks DB connectivity.
func (s *Server) handleHealthCheck() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := s.DB.Health(r.Context()); err != nil {
			response.Error(w, http.StatusServiceUnavailable, "Database unavailable")
			return
		}
		response.JSON(w, http.StatusOK, map[string]string{"status": "ok", "database": "connected"})
	}
}
