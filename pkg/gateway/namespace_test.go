package gateway

import (
	"context"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"

	queueservicepb "github.com/adrien19/nzovu/api/queueservice/v1"
	"github.com/adrien19/nzovu/pkg/log"
)

type namespaceServer struct {
	queueservicepb.UnimplementedQueueServiceServer
}

func (namespaceServer) ListQueues(context.Context, *queueservicepb.ListQueuesRequest) (*queueservicepb.ListQueuesResponse, error) {
	return &queueservicepb.ListQueuesResponse{}, nil
}

func TestNzovuNamespacePreservesGatewayAuthentication(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	logger := log.NewLogger()
	server := grpc.NewServer(grpc.UnaryInterceptor(AuthInterceptor(logger, true, []string{"secret"})))
	queueservicepb.RegisterQueueServiceServer(server, namespaceServer{})
	serveErr := make(chan error, 1)
	go func() { serveErr <- server.Serve(listener) }()
	t.Cleanup(func() {
		server.Stop()
		assert.NoError(t, <-serveErr)
	})

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	t.Cleanup(cancel)
	conn, err := grpc.NewClient(listener.Addr().String(), grpc.WithTransportCredentials(insecure.NewCredentials()))
	require.NoError(t, err)
	t.Cleanup(func() { assert.NoError(t, conn.Close()) })
	authorized := metadata.AppendToOutgoingContext(ctx, "api-key", "secret")
	request := &queueservicepb.ListQueuesRequest{}
	response := &queueservicepb.ListQueuesResponse{}
	require.NoError(t, conn.Invoke(authorized, "/nzovu.api.queueservice.v1.QueueService/ListQueues", request, response))
	err = conn.Invoke(ctx, "/nzovu.api.queueservice.v1.QueueService/ListQueues", request, response)
	assert.Equal(t, codes.Unauthenticated, status.Code(err))
	err = conn.Invoke(authorized, "/chronoqueue.api.queueservice.v1.QueueService/ListQueues", request, response)
	assert.Equal(t, codes.Unimplemented, status.Code(err))

	handler, err := NewHTTPGateway(ctx, GatewayConfig{GRPCServerAddr: listener.Addr().String()}, logger)
	require.NoError(t, err)
	for _, authenticated := range []bool{false, true} {
		req := httptest.NewRequest(http.MethodGet, "/v1/queues", nil).WithContext(ctx)
		wantStatus := http.StatusUnauthorized
		if authenticated {
			req.Header.Set("api-key", "secret")
			wantStatus = http.StatusOK
		}
		recorder := httptest.NewRecorder()
		handler.ServeHTTP(recorder, req)
		assert.Equal(t, wantStatus, recorder.Code, recorder.Body.String())
	}
}
