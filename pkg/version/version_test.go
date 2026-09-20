package version

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestInfoPreservesReleaseMetadataExactly(t *testing.T) {
	previousVersion, previousCommit, previousBuildDate := Version, GitCommit, BuildDate
	t.Cleanup(func() {
		Version, GitCommit, BuildDate = previousVersion, previousCommit, previousBuildDate
	})

	tests := []struct {
		name      string
		version   string
		commit    string
		buildDate string
		info      string
	}{
		{
			name:      "development",
			version:   "dev",
			commit:    "unknown",
			buildDate: "unknown",
			info:      "Nzovu vdev\n  Git Commit: unknown\n  Built:      unknown",
		},
		{
			name:      "initial release",
			version:   "0.0.1",
			commit:    "0123456789abcdef0123456789abcdef01234567",
			buildDate: "2026-09-19T12:34:56Z",
			info:      "Nzovu v0.0.1\n  Git Commit: 0123456789abcdef0123456789abcdef01234567\n  Built:      2026-09-19T12:34:56Z",
		},
		{
			name:      "prerelease with build metadata",
			version:   "0.0.1-rc.1+build.7",
			commit:    "0123456789abcdef0123456789abcdef01234567",
			buildDate: "2026-09-19T12:34:56Z",
			info:      "Nzovu v0.0.1-rc.1+build.7\n  Git Commit: 0123456789abcdef0123456789abcdef01234567\n  Built:      2026-09-19T12:34:56Z",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			Version, GitCommit, BuildDate = tt.version, tt.commit, tt.buildDate
			assert.Equal(t, tt.info, Info())
			assert.Equal(t, tt.version, Short())
			assert.Equal(t, map[string]string{
				"version":    tt.version,
				"git_commit": tt.commit,
				"build_date": tt.buildDate,
			}, Details())
		})
	}
}
