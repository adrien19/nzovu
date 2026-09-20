package monitoring

import (
	"context"

	"github.com/adrien19/nzovu/client"
)

// StorageMonitor provides Nzovu API-based monitoring
type StorageMonitor struct {
	nzovuClient *client.NzovuClient
}

// NewStorageMonitor creates a new monitor using Nzovu client
func NewStorageMonitor(nzovuClient *client.NzovuClient) *StorageMonitor {
	return &StorageMonitor{
		nzovuClient: nzovuClient,
	}
}

// QueueStateCounts represents message counts by state for a queue
type QueueStateCounts struct {
	Invisible int64
	Pending   int64
	Running   int64
	Completed int64
	Canceled  int64
	Errored   int64
}

// GetQueueState returns comprehensive queue state using Nzovu API
func (rm *StorageMonitor) GetQueueState(ctx context.Context, queueName string) (*QueueStateCounts, error) {
	resp, err := rm.nzovuClient.GetQueueState(ctx, queueName)
	if err != nil {
		return nil, err
	}

	return &QueueStateCounts{
		Invisible: resp.StateCounts["INVISIBLE"],
		Pending:   resp.StateCounts["PENDING"],
		Running:   resp.StateCounts["RUNNING"],
		Completed: resp.StateCounts["COMPLETED"],
		Canceled:  resp.StateCounts["CANCELED"],
		Errored:   resp.StateCounts["ERRORED"],
	}, nil
}

// GetDLQSize returns the number of errored messages (using queue state)
func (rm *StorageMonitor) GetDLQSize(ctx context.Context, queueName string) (int64, error) {
	state, err := rm.GetQueueState(ctx, queueName)
	if err != nil {
		return 0, err
	}
	return state.Errored, nil
}

// Close closes the Nzovu client connection
func (rm *StorageMonitor) Close() error {
	if rm.nzovuClient != nil {
		rm.nzovuClient.Close()
	}
	return nil
}
