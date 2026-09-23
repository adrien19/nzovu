//go:build sqlite && cgo

package sqlite

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestTransactionsReserveWriterBeforeReading(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	config := DefaultConnectionConfig(filepath.Join(t.TempDir(), "writers.db"))
	first, err := OpenConnection(ctx, config)
	require.NoError(t, err)
	t.Cleanup(func() { require.NoError(t, first.Close()) })
	second, err := OpenConnection(ctx, config)
	require.NoError(t, err)
	t.Cleanup(func() { require.NoError(t, second.Close()) })
	_, err = first.ExecContext(ctx, `CREATE TABLE counter (value INTEGER NOT NULL); INSERT INTO counter VALUES (0)`)
	require.NoError(t, err)
	tx, err := first.BeginTx(ctx, nil)
	require.NoError(t, err)
	t.Cleanup(func() {
		if err := tx.Rollback(); err != nil && err != sql.ErrTxDone {
			t.Error(err)
		}
	})
	var value int
	require.NoError(t, tx.QueryRowContext(ctx, `SELECT value FROM counter`).Scan(&value))
	require.Zero(t, value)

	// WAL readers remain available while the transaction reserves the writer.
	require.NoError(t, second.QueryRowContext(ctx, `SELECT value FROM counter`).Scan(&value))
	type result struct {
		tx  *sql.Tx
		err error
	}
	started := make(chan struct{})
	begun := make(chan result, 1)
	go func() {
		close(started)
		next, beginErr := second.BeginTx(ctx, nil)
		begun <- result{next, beginErr}
	}()
	<-started
	select {
	case next := <-begun:
		if next.tx != nil {
			require.NoError(t, next.tx.Rollback())
		}
		t.Fatalf("second writer began before first committed: %v", next.err)
	case <-time.After(100 * time.Millisecond):
	}
	_, err = tx.ExecContext(ctx, `UPDATE counter SET value = value + 1`)
	require.NoError(t, err)
	require.NoError(t, tx.Commit())
	var next result
	select {
	case next = <-begun:
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	require.NoError(t, next.err)
	require.NoError(t, next.tx.QueryRowContext(ctx, `SELECT value FROM counter`).Scan(&value))
	require.Equal(t, 1, value)
	_, err = next.tx.ExecContext(ctx, `UPDATE counter SET value = value + 1`)
	require.NoError(t, err)
	require.NoError(t, next.tx.Commit())
	require.NoError(t, first.QueryRowContext(ctx, `SELECT value FROM counter`).Scan(&value))
	require.Equal(t, 2, value)
}
