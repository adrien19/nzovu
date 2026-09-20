package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRouterPreservesPeerAddress(t *testing.T) {
	for _, peer := range []string{"192.0.2.1:12345", "[2001:db8::1]:12345"} {
		for _, header := range []string{"", "X-Forwarded-For", "X-Real-IP", "True-Client-IP"} {
			t.Run(peer+"/"+header, func(t *testing.T) {
				router := newRouter()
				var remoteAddr string
				router.Get("/peer", func(w http.ResponseWriter, r *http.Request) {
					remoteAddr = r.RemoteAddr
					w.WriteHeader(http.StatusNoContent)
				})

				request := httptest.NewRequest(http.MethodGet, "/peer", nil)
				request.RemoteAddr = peer
				if header != "" {
					request.Header.Set(header, "127.0.0.1")
				}
				response := httptest.NewRecorder()
				router.ServeHTTP(response, request)

				if response.Code != http.StatusNoContent {
					t.Fatalf("status = %d, want %d", response.Code, http.StatusNoContent)
				}
				if remoteAddr != peer {
					t.Errorf("peer address = %q, want %q", remoteAddr, peer)
				}
			})
		}
	}
}
