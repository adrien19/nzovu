package runtimeenv

import (
	"os"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestLookupPreservesExplicitEmptyValue(t *testing.T) {
	const key = "NZOVU_TEST_SETTING"
	t.Setenv(key, "")
	require.NoError(t, os.Unsetenv(key))
	value, exists := Lookup(key)
	require.Empty(t, value)
	require.False(t, exists)
	for _, want := range []string{"configured", ""} {
		t.Setenv(key, want)
		value, exists = Lookup(key)
		require.True(t, exists)
		require.Equal(t, want, value)
	}
}

func TestBoolDefaultsAndValidation(t *testing.T) {
	const key = "NZOVU_TEST_SETTING"
	t.Setenv(key, "")
	require.NoError(t, os.Unsetenv(key))
	for _, fallback := range []bool{false, true} {
		value, err := Bool(key, fallback)
		require.NoError(t, err)
		require.Equal(t, fallback, value)
	}
	for _, value := range []string{"", " ", "invalid"} {
		t.Setenv(key, value)
		_, err := Bool(key, false)
		require.ErrorContains(t, err, "invalid NZOVU_TEST_SETTING")
	}
	for _, tt := range []struct {
		value string
		want  bool
	}{{"true", true}, {" false ", false}} {
		t.Setenv(key, tt.value)
		value, err := Bool(key, !tt.want)
		require.NoError(t, err)
		require.Equal(t, tt.want, value)
	}
}
