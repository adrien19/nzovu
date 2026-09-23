module github.com/adrien19/nzovu/examples/interview-platform/backend

go 1.26.6

require (
	github.com/adrien19/nzovu v0.0.0-00010101000000-000000000000
	github.com/go-chi/chi/v5 v5.3.0
	github.com/go-chi/cors v1.2.1
	github.com/golang/protobuf v1.5.4
	github.com/google/uuid v1.6.0
	github.com/mattn/go-sqlite3 v1.14.52
	google.golang.org/grpc v1.84.0
	google.golang.org/protobuf v1.36.12
)

require (
	github.com/grpc-ecosystem/grpc-gateway/v2 v2.30.0 // indirect
	golang.org/x/net v0.58.0 // indirect
	golang.org/x/sys v0.47.0 // indirect
	golang.org/x/text v0.41.0 // indirect
	google.golang.org/genproto/googleapis/api v0.0.0-20260803160001-6ac0973c030d // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20260803160001-6ac0973c030d // indirect
)

replace github.com/adrien19/nzovu => ../../..
