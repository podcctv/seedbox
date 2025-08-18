package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAuthMiddleware(t *testing.T) {
	router := setupRouter()
	req, _ := http.NewRequest("GET", "/items", nil)
	req.Header.Set("X-Auth", authToken)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
}

func TestAuthMissing(t *testing.T) {
	router := setupRouter()
	req, _ := http.NewRequest("GET", "/items", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}
