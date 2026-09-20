package webui

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"

	clusterstore "github.com/adrien19/nzovu/cmd/nzovu/web-ui/cluster"
	"github.com/adrien19/nzovu/pkg/log"
)

func TestClusterConfigPathUsesOnlyNzovuStore(t *testing.T) {
	dir := t.TempDir()
	current := filepath.Join(dir, "nzovu", "web-ui-clusters.json")
	unrelated := filepath.Join(dir, "other-app", "web-ui-clusters.json")
	require.NoError(t, os.MkdirAll(filepath.Dir(unrelated), 0o700))
	require.NoError(t, os.WriteFile(unrelated, []byte("invalid JSON"), 0o600))
	path, err := clusterConfigPath(dir)
	require.NoError(t, err)
	require.Equal(t, current, path)
	store := clusterstore.NewStore(path)
	require.NoError(t, store.Load())

	require.NoError(t, os.MkdirAll(filepath.Dir(current), 0o700))
	data := []byte(`[{"slug":"existing","name":"Existing","brokerAddress":"localhost:9000","transportMode":"plaintext"}]`)
	require.NoError(t, os.WriteFile(current, data, 0o600))
	require.NoError(t, store.Load())
	unchanged, err := os.ReadFile(current)
	require.NoError(t, err)
	require.Equal(t, data, unchanged)

	require.NoError(t, os.WriteFile(current, []byte("invalid JSON"), 0o600))
	require.ErrorContains(t, clusterstore.NewStore(current).Load(), "parse cluster store")
}

func TestUIEnvironmentFailsClosed(t *testing.T) {
	for _, tt := range []struct {
		name      string
		key       string
		value     string
		wantError string
	}{
		{"invalid auth", "NZOVU_UI_AUTH_ENABLED", "invalid", "invalid NZOVU_UI_AUTH_ENABLED"},
		{"empty auth", "NZOVU_UI_AUTH_ENABLED", "", "invalid NZOVU_UI_AUTH_ENABLED"},
		{"empty password", "NZOVU_UI_AUTH_PASSWORD", "", "username or password is missing"},
		{"invalid proxy", "NZOVU_UI_TRUST_PROXY_HEADERS", "invalid", "invalid NZOVU_UI_TRUST_PROXY_HEADERS"},
		{"invalid origin", "NZOVU_UI_PUBLIC_ORIGIN", "://bad", "invalid NZOVU_UI_PUBLIC_ORIGIN"},
		{"partial TLS", "NZOVU_UI_TLS_CERT_FILE", "/missing/cert.pem", "configured together"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			t.Setenv("NZOVU_UI_AUTH_ENABLED", "true")
			t.Setenv("NZOVU_UI_AUTH_USERNAME", "operator")
			t.Setenv("NZOVU_UI_AUTH_PASSWORD", "secret")
			t.Setenv(tt.key, tt.value)
			_, err := NewUIServer("localhost:9000", true, log.NewLogger())
			require.ErrorContains(t, err, tt.wantError)
		})
	}
	t.Setenv("NZOVU_UI_AUTH_ENABLED", "true")
	t.Setenv("NZOVU_UI_AUTH_USERNAME", "operator")
	t.Setenv("NZOVU_UI_AUTH_PASSWORD", "secret")
	t.Setenv("NZOVU_UI_PUBLIC_ORIGIN", "")
	server, err := NewUIServer("localhost:9000", true, log.NewLogger())
	require.NoError(t, err)
	t.Cleanup(server.store.CloseAll)
	require.True(t, server.auth.enabled)
	require.Equal(t, "operator", server.auth.username)
	require.False(t, server.hasPublicOrigin)
}

func TestClusterConfigPathRejectsInvalidParent(t *testing.T) {
	dir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(dir, "nzovu"), []byte("not a directory"), 0o600))
	_, err := clusterConfigPath(dir)
	require.ErrorContains(t, err, "inspect cluster configuration")
}
