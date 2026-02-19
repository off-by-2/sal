package auth

import (
	"testing"
)

func TestHashPassword(t *testing.T) {
	password := "secret"
	hash, err := HashPassword(password)
	if err != nil {
		t.Fatalf("HashPassword failed: %v", err)
	}

	if hash == "" {
		t.Error("HashPassword returned empty string")
	}

	if hash == password {
		t.Error("HashPassword returned the plain password")
	}
}

func TestCheckPasswordHash(t *testing.T) {
	password := "secret"
	hash, _ := HashPassword(password)

	err := CheckPasswordHash(password, hash)
	if err != nil {
		t.Errorf("CheckPasswordHash failed for correct password: %v", err)
	}

	err = CheckPasswordHash("wrong", hash)
	if err == nil {
		t.Error("CheckPasswordHash succeeded for wrong password")
	}
}
