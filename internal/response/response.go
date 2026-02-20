// Package response provides helper functions for sending consistent JSON responses.
package response

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/go-playground/validator/v10"
)

// Response represents the standard JSON envelope for all API responses.
type Response struct {
	Success bool        `json:"success"`         // Success indicates if the request was successful
	Data    interface{} `json:"data,omitempty"`  // Data holds the payload (can be struct, map, or nil)
	Error   interface{} `json:"error,omitempty"` // Error holds error details if Success is false
	Meta    interface{} `json:"meta,omitempty"`  // Meta holds pagination or other metadata
}

// JSON sends a JSON response with the given status code and data.
func JSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)

	resp := Response{
		Success: status >= 200 && status < 300,
		Data:    data,
	}

	// If data is an error, move it to the Error field
	if err, ok := data.(error); ok {
		resp.Success = false
		resp.Data = nil
		resp.Error = err.Error()
	}

	_ = json.NewEncoder(w).Encode(resp)
}

// Error sends a standardized error response.
func Error(w http.ResponseWriter, status int, message string) {
	JSON(w, status, map[string]string{"message": message})
}

// ValidationError sends a response with detailed validation errors.
// It parses go-playground/validator errors into a simplified map.
func ValidationError(w http.ResponseWriter, err error) {
	var ve validator.ValidationErrors
	if errors.As(err, &ve) {
		out := make(map[string]string)
		for _, fe := range ve {
			out[fe.Field()] = msgForTag(fe)
		}
		JSON(w, http.StatusUnprocessableEntity, out)
		return
	}
	Error(w, http.StatusBadRequest, "Invalid request payload")
}

// msgForTag converts validator tags to user-friendly messages.
func msgForTag(fe validator.FieldError) string {
	switch fe.Tag() {
	case "required":
		return "This field is required"
	case "email":
		return "Invalid email format"
	case "min":
		return "Value is too short"
	case "max":
		return "Value is too long"
	case "uppercase":
		return "Must contain at least one uppercase letter"
	case "lowercase":
		return "Must contain at least one lowercase letter"
	case "number":
		return "Must contain at least one number"
	case "special":
		return "Must contain at least one special character"
	}
	return fe.Error() // Default fallback
}
