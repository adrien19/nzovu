package common

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/durationpb"

	messagepb "github.com/adrien19/nzovu/api/message/v1"
	queuepb "github.com/adrien19/nzovu/api/queue/v1"
	schedulepb "github.com/adrien19/nzovu/api/schedule/v1"
)

func TestProtoSerializerPreservesOrderedBinaryMessageHeaders(t *testing.T) {
	original := &messagepb.Message{
		MessageId: "message-with-headers",
		Metadata: &messagepb.Message_Metadata{
			Headers: []*messagepb.Message_Metadata_Header{
				{Key: "trace-id", Value: []byte{0x00, 0xff}},
				{Key: "trace-id", Value: []byte("second")},
			},
		},
	}
	serializer := NewProtoSerializer()

	encoded, err := serializer.MarshalMessage(original)
	require.NoError(t, err)
	decoded, err := serializer.UnmarshalMessage(encoded)
	require.NoError(t, err)

	require.True(t, proto.Equal(original, decoded))
}

func TestProtoSerializerReadsChronoQueueFixtures(t *testing.T) {
	serializer := NewProtoSerializer()
	tests := []struct {
		name   string
		decode func([]byte) (proto.Message, error)
		want   proto.Message
	}{
		{
			name: "message",
			decode: func(data []byte) (proto.Message, error) {
				return serializer.UnmarshalMessage(data)
			},
			want: &messagepb.Message{MessageId: "legacy-message", Metadata: &messagepb.Message_Metadata{
				State: messagepb.Message_Metadata_COMPLETED, Priority: 4, MaxAttempts: 3,
				Headers: []*messagepb.Message_Metadata_Header{{Key: "trace-id", Value: []byte("legacy-trace")}},
			}},
		},
		{
			name: "queue",
			decode: func(data []byte) (proto.Message, error) {
				return serializer.UnmarshalQueue(data)
			},
			want: &queuepb.Queue{Name: "legacy-queue", Metadata: &queuepb.QueueMetadata{
				DefaultMaxAttempts: 3, LeaseDuration: &durationpb.Duration{Seconds: 30}, DeadLetterQueueName: "legacy-dlq",
			}},
		},
		{
			name: "schedule",
			decode: func(data []byte) (proto.Message, error) {
				return serializer.UnmarshalSchedule(data)
			},
			want: &schedulepb.Schedule{ScheduleId: "legacy-schedule", Metadata: &schedulepb.Schedule_Metadata{
				State: schedulepb.Schedule_Metadata_PAUSED, QueueName: "legacy-queue", Priority: 4,
				ScheduleConfig: &schedulepb.Schedule_Metadata_CronSchedule{CronSchedule: "*/5 * * * *"},
			}},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data, err := os.ReadFile(filepath.Join("testdata", "chronoqueue_v1_"+tt.name+".bin"))
			require.NoError(t, err)
			decoded, err := tt.decode(data)
			require.NoError(t, err)
			require.True(t, proto.Equal(tt.want, decoded))
			encoded, err := proto.Marshal(decoded)
			require.NoError(t, err)
			roundTrip, err := tt.decode(encoded)
			require.NoError(t, err)
			require.True(t, proto.Equal(decoded, roundTrip))
		})
	}
}
