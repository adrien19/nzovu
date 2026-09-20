package runtimeenv

import (
	"os"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestLookupPrecedence(t *testing.T) {
	for _, tt := range []struct {
		name    string
		current *string
		legacy  *string
		want    string
		exists  bool
	}{
		{name: "unset"},
		{name: "legacy", legacy: ptr("old"), want: "old", exists: true},
		{name: "current", current: ptr("new"), want: "new", exists: true},
		{name: "conflict", current: ptr("new"), legacy: ptr("old"), want: "new", exists: true},
		{name: "empty current wins", current: ptr(""), legacy: ptr("old"), exists: true},
	} {
		t.Run(tt.name, func(t *testing.T) {
			for key, value := range map[string]*string{"NZOVU_TEST_SETTING": tt.current, "CHRONOQUEUE_TEST_SETTING": tt.legacy} {
				t.Setenv(key, "")
				if value == nil {
					require.NoError(t, os.Unsetenv(key))
				} else {
					t.Setenv(key, *value)
				}
			}
			got, exists := Lookup("NZOVU_TEST_SETTING")
			require.Equal(t, tt.want, got)
			require.Equal(t, tt.exists, exists)
		})
	}
}

func TestBoolRejectsInvalidCurrentWithoutLegacyFallback(t *testing.T) {
	t.Setenv("CHRONOQUEUE_TEST_SETTING", "true")
	for _, value := range []string{"", "invalid"} {
		t.Setenv("NZOVU_TEST_SETTING", value)
		_, err := Bool("NZOVU_TEST_SETTING", false)
		require.ErrorContains(t, err, "invalid NZOVU_TEST_SETTING")
	}
	t.Setenv("NZOVU_TEST_SETTING", "false")
	value, err := Bool("NZOVU_TEST_SETTING", true)
	require.NoError(t, err)
	require.False(t, value)
	for _, key := range []string{"NZOVU_TEST_SETTING", "CHRONOQUEUE_TEST_SETTING"} {
		require.NoError(t, os.Unsetenv(key))
	}
	value, err = Bool("NZOVU_TEST_SETTING", true)
	require.NoError(t, err)
	require.True(t, value)
}

func ptr(value string) *string { return &value }
