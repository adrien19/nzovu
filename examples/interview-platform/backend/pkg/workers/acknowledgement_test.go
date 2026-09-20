package workers

import (
	"context"
	"errors"
	"testing"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/protobuf/proto"

	message_pb "github.com/adrien19/nzovu/api/message/v1"
	queueservice_pb "github.com/adrien19/nzovu/api/queueservice/v1"
	"github.com/adrien19/nzovu/client"
)

type acknowledgementService struct {
	queueservice_pb.QueueServiceClient
	request *queueservice_pb.AcknowledgeMessageRequest
	err     error
}

func (s *acknowledgementService) GetNextMessage(context.Context, *queueservice_pb.GetNextMessageRequest, ...grpc.CallOption) (*queueservice_pb.GetNextMessageResponse, error) {
	return &queueservice_pb.GetNextMessageResponse{
		Message:   &message_pb.Message{MessageId: "message-1"},
		AttemptId: proto.String("attempt-1"),
		WorkerId:  proto.String("worker-1"),
	}, nil
}

func (s *acknowledgementService) AcknowledgeMessage(_ context.Context, req *queueservice_pb.AcknowledgeMessageRequest, _ ...grpc.CallOption) (*queueservice_pb.AcknowledgeMessageResponse, error) {
	s.request = req
	return &queueservice_pb.AcknowledgeMessageResponse{}, s.err
}

func TestWorkersAcknowledgeWithClaimOwnership(t *testing.T) {
	type processor func(context.Context, string, *message_pb.Message) error
	workers := map[string]func(*client.NzovuClient) processor{
		"evaluation": func(queue *client.NzovuClient) processor {
			return NewEvaluationProcessorWorker(queue, nil).processMessage
		},
		"interview": func(queue *client.NzovuClient) processor {
			return NewInterviewSchedulerWorker(queue, nil).processMessage
		},
		"notification": func(queue *client.NzovuClient) processor {
			return NewNotificationSenderWorker(queue, nil).processMessage
		},
		"report": func(queue *client.NzovuClient) processor {
			return NewReportGeneratorWorker(queue, nil).processMessage
		},
	}
	for name, newProcessor := range workers {
		for _, failed := range []bool{false, true} {
			outcome := "success"
			if failed {
				outcome = "failure"
			}
			t.Run(name+"/"+outcome, func(t *testing.T) {
				service := &acknowledgementService{}
				if failed {
					service.err = errors.New("acknowledgement rejected")
				}
				queue, err := client.NewNzovuClient("unused", client.ClientOptions{
					Connector: func(string, client.ClientOptions) (queueservice_pb.QueueServiceClient, *grpc.ClientConn, error) {
						conn, err := grpc.NewClient("passthrough:///unused", grpc.WithTransportCredentials(insecure.NewCredentials()))
						return service, conn, err
					},
				})
				if err != nil {
					t.Fatal(err)
				}
				t.Cleanup(queue.Close)
				ctx := context.Background()
				claim, err := queue.GetNextMessage(ctx, "queue-1", "30s", false)
				if err != nil {
					t.Fatal(err)
				}
				if err := newProcessor(queue)(ctx, "queue-1", claim.GetMessage()); !errors.Is(err, service.err) {
					t.Fatalf("expected acknowledgement error %v, got %v", service.err, err)
				}
				req := service.request
				if req == nil || req.GetAttemptId() != "attempt-1" || req.GetWorkerId() != "worker-1" {
					t.Fatalf("acknowledgement lost claim ownership: %v", req)
				}
				if req.GetQueueName() != "queue-1" || req.GetMessageId() != "message-1" || req.GetState() != message_pb.Message_Metadata_COMPLETED {
					t.Fatalf("unexpected acknowledgement: %v", req)
				}
			})
		}
	}
}
