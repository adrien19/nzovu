package main

import (
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
)

func TestServerHTTPSubcommands(t *testing.T) {
	for _, tt := range []struct {
		name    string
		status  int
		wantErr bool
	}{
		{name: "health", status: http.StatusOK},
		{name: "version", status: http.StatusOK},
		{name: "health", status: http.StatusServiceUnavailable, wantErr: true},
	} {
		t.Run(tt.name+http.StatusText(tt.status), func(t *testing.T) {
			var calls atomic.Int32
			backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				calls.Add(1)
				if r.URL.Path != "/ready" {
					t.Errorf("path = %q, want /ready", r.URL.Path)
				}
				w.WriteHeader(tt.status)
				if _, err := w.Write([]byte(`{"version":"0.0.1-test","git_commit":"test","build_date":"test"}`)); err != nil {
					t.Error(err)
				}
			}))
			defer backend.Close()
			cmd := newServerCommand()
			cmd.SetArgs([]string{tt.name, "--http-server", backend.URL})
			err := cmd.Execute()
			if (err != nil) != tt.wantErr {
				t.Fatalf("error = %v, want error %v", err, tt.wantErr)
			}
			if calls.Load() != 1 {
				t.Fatalf("readiness requests = %d, want 1", calls.Load())
			}
		})
	}
}
