# Nzovu

[![CI](https://github.com/adrien19/nzovu/actions/workflows/ci.yml/badge.svg)](https://github.com/adrien19/nzovu/actions/workflows/ci.yml)
[![Release](https://github.com/adrien19/nzovu/actions/workflows/release.yml/badge.svg)](https://github.com/adrien19/nzovu/actions/workflows/release.yml)
[![Go Report Card](https://goreportcard.com/badge/github.com/adrien19/nzovu)](https://goreportcard.com/report/github.com/adrien19/nzovu)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

Nzovu is a persistent job queue and execution-supervision service. It provides priority-based message processing, leases and heartbeats, retries and dead-letter queues, and recurring or delayed scheduling through gRPC and HTTP APIs.

---

> **Project status**
>
> **Nzovu is preparing its first release, `v0.0.1`.** These docs describe `main`; build from source until release assets are published. Nzovu continues [ChronoQueue](https://github.com/adrien19/chronoqueue) with a new module, binary and protobuf namespace. Regenerate clients from this repository. See the [migration guide](./deploy/NZOVU_MIGRATION.md) before upgrading an existing deployment.

---

## Features

The table below describes the current source tree. Items marked **Evolving** or **Partial** identify areas still under active development.

| Capability | Status | Current scope |
| --- | --- | --- |
| Queue and message lifecycle | ✅ Implemented | Create, list, and delete queues; post, bulk-post, claim, peek, acknowledge, and cancel messages. |
| Priority processing | ✅ Implemented | Numeric priorities with FIFO ordering at the same priority, plus configurable strict, weighted, and age-boosted selection. |
| Execution supervision | ✅ Implemented | Server-owned leases, attempt IDs, heartbeats, lease renewal, timeout reclaim, and stale-worker protection. |
| Retries and dead-letter queues | ✅ Implemented | Configurable attempt limits, lease-timeout retries, automatic DLQ creation, inspection, requeue, delete, purge, and statistics. |
| Scheduling | 🧪 Evolving | Delayed messages and recurring cron or timezone-aware calendar schedules, including validation, previews, history, pause, and resume. Custom expression rules are reserved and rejected by the server. |
| Payload schemas | ✅ Implemented | Versioned JSON Schema registration, queue-level enforcement, validation, listing, and deletion. |
| Message retention | ✅ Implemented | Delete-on-ack, time-based retention, or indefinite retention with background cleanup. |
| Storage | ✅ Implemented | PostgreSQL and SQLite backends with schema migrations. PostgreSQL is the recommended backend; SQLite is intended for local and smaller deployments. |
| APIs and tooling | ✅ Implemented | gRPC API, REST gateway, embedded OpenAPI/Swagger UI, Go client, and `nzovu` CLI. |
| Monitoring | 🚧 Partial | Prometheus and Grafana provide operational metrics; the web dashboard provides queue state through live and polled views. |
| Web administration | 🚧 Partial | Queue/message inspection and creation, schedule creation/pause/resume/delete, schema management, and DLQ actions. Additional settings areas remain under development. |
| Operational security | 🧪 Evolving | API-key authentication, TLS/mTLS, payload encryption with local or Vault keys, per-principal rate limiting, and protected metrics. |
| Additional SDKs and MCP | ↗ External | Go, Python and TypeScript clients plus the MCP server implement the Nzovu API. External SDK packages remain unpublished; build from their source repositories. |

## Getting Started

### Prerequisites

- [PostgreSQL](https://www.postgresql.org/) or [SQLite](https://www.sqlite.org/) (for storage)
- [Go](https://go.dev/) (use the version declared in [`go.mod`](./go.mod))

### Installation

#### Build and run from source

From a checkout of `main`, Go and a C compiler are sufficient for the SQLite quick start:

```bash
git clone --branch main https://github.com/adrien19/nzovu.git
cd nzovu
CGO_ENABLED=1 go build -tags sqlite -o ./dist/nzovu .
./dist/nzovu server --dev --grpc-addr 127.0.0.1:9000 --http-addr 127.0.0.1:8080 --storage-type sqlite --sqlite-db-path nzovu.db
```

In another terminal at the checkout root:

```bash
./dist/nzovu --server localhost:9000 --insecure queue create quickstart
./dist/nzovu --server localhost:9000 --insecure message post quickstart '{"hello":"nzovu"}' --id quickstart-message
./dist/nzovu --server localhost:9000 --insecure message peek quickstart
```

`nzovu.db` is the new SQLite default. Existing deployments must explicitly select their original database path; see the migration guide. Development mode is intended for local evaluation.

#### Release installers

The [shell installer](https://github.com/adrien19/nzovu/blob/main/install/install.sh) and [PowerShell installer](https://github.com/adrien19/nzovu/blob/main/install/install.ps1) target Nzovu releases and verify checksums and binary build metadata. They require published release assets. Once available, select a published tag explicitly; use `NZOVU_INSTALL_DIR` for a custom destination. Old ChronoQueue release tags and installer variables do not select Nzovu releases.

Release binaries and the published production container support PostgreSQL. For SQLite, use the source build above or build `images/Dockerfile.sqlite`. The binary matrix covers Linux amd64/arm64/arm, macOS amd64/arm64 and Windows amd64.

#### Docker Compose

From the checkout root, start the SQLite broker (no UI credentials required):

```bash
export WORKSPACE_FOLDER="$PWD"
docker compose -f deploy/docker-compose.sqlite.yaml up -d --build nzovusvc
curl --fail http://localhost:8080/health
```

See the [deployment guide](./deploy/README.md) for PostgreSQL, the TLS-protected UI and monitoring. Keep the existing Compose project name and volume names during migration.

#### Server configuration

Configure your environment:

   - Start with [`.env.example`](./.env.example) and choose PostgreSQL (recommended) or SQLite.
   - For PostgreSQL, set `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB`. Production mode defaults to `POSTGRES_SSLMODE=verify-full`; set `POSTGRES_ROOT_CERT` when a custom CA certificate is required. Development mode defaults to `POSTGRES_SSLMODE=disable` for local use.
   - For SQLite, set `SQLITE_DB_PATH` (for example, `/data/nzovu.db`).
   - Production mode enables authentication by default. Set `API_KEYS` to a comma-separated list; clients can authenticate with the `api-key` header or an `Authorization: Bearer` token. The CLI and web UI read `NZOVU_API_KEY`; the CLI also accepts `--api-key`. Development mode can enable authentication with `AUTH_ENABLED=true`.
   - Production mode requires TLS for the gRPC and HTTP endpoints. Set `CERT_FILE` and `KEY_FILE`. To require gRPC client certificates, also set `CA_CERT_FILE`; the internal HTTP gateway then needs `GATEWAY_CLIENT_CERT_FILE` and `GATEWAY_CLIENT_KEY_FILE`.
   - HTTP gateway timeouts default to `5s` for request headers, `15s` for reads, `30s` for writes, and `60s` for idle connections. Override them with `HTTP_READ_HEADER_TIMEOUT`, `HTTP_READ_TIMEOUT`, `HTTP_WRITE_TIMEOUT`, and `HTTP_IDLE_TIMEOUT`.
   - Production mode requires payload encryption and an explicit `ENCRYPTION_KEY_SOURCE_TYPE`. Use `VAULT` for normal production deployments. `LOCAL` keys require `ALLOW_LOCAL_ENCRYPTION_KEY_IN_PRODUCTION=true`. Follow the [encryption-key rotation procedure](./ENCRYPTION_KEY_ROTATION.md) before changing an active key.
   - Production mode enables configurable per-principal API rate limiting as an abuse-protection baseline. The default is 100 RPCs/second with a burst of 200. The limiter counts RPCs rather than individual messages, so a bulk post consumes one token. With authentication enabled, each API key has one bucket shared by all RPC methods, and each server instance applies its own limits. Tune or disable the limiter when equivalent controls are enforced upstream. Configure it with `RATE_LIMIT_ENABLED`, `RATE_LIMIT_REQUESTS_PER_SECOND`, `RATE_LIMIT_BURST`, and `RATE_LIMIT_MAX_BUCKETS`; the last setting caps the number of in-memory principal buckets.
   - Metrics are enabled and bearer-protected by default in production. Set `METRICS_BEARER_TOKEN` and configure Prometheus to send it in the `Authorization: Bearer` header, or disable metrics with `METRICS_ENABLED=false`.

Start the Nzovu server:

```bash
# Development mode with PostgreSQL (recommended)
go run . server --dev --grpc-addr :9000

# Development mode with SQLite
CGO_ENABLED=1 go run -tags sqlite . server --dev --grpc-addr :9000 --storage-type sqlite --sqlite-db-path nzovu.db
```

SQLite requires CGO, a C compiler, and the `sqlite` build tag. For a SQLite-capable binary, use `CGO_ENABLED=1 go build -tags sqlite -o nzovu .`; an untagged build supports PostgreSQL only. See [server build selection](./internal/server/server_nosqlite.go).

To use mTLS, generate the required certificates or use the provided [`generate_certs.sh`](./generate_certs.sh) helper for local evaluation.

### Web UI

Nzovu includes a built-in web interface for monitoring and managing your queues, schedules, and dead letter queues.

#### Starting the Web UI

1. Build the UI assets (first time only):

    ```bash
    cd cmd/nzovu/web-ui
    npm ci
    npm run build:css
    cd ../../..
    ```

2. Build the Nzovu binary:

    ```bash
    go build -o ./dist/nzovu .
    ```

3. Start the UI server:

    ```bash
    NZOVU_UI_PUBLIC_ORIGIN=http://localhost:8081 ./dist/nzovu web-ui start --port 8081 --grpc-address localhost:9000 --skip-ssl
    ```

4. Open your browser to `http://localhost:8081`

The UI binds to `127.0.0.1` by default. A non-loopback bind such as `--host 0.0.0.0` requires Basic authentication plus `NZOVU_UI_TLS_CERT_FILE` and `NZOVU_UI_TLS_KEY_FILE`; the UI then serves HTTPS with TLS 1.2 or newer. Enable Basic authentication with `NZOVU_UI_AUTH_ENABLED=true`, `NZOVU_UI_AUTH_USERNAME`, and `NZOVU_UI_AUTH_PASSWORD`. `--skip-ssl` affects only the UI-to-gRPC connection.

#### UI Features

- **📊 Live Dashboard**: Monitor queue state, message counts, and service availability through polling and SSE views
- **📋 Queue Management**: View queue details, browse messages, and inspect message content
- **⏰ Schedule Management**: Create, pause, resume, and delete cron and calendar-based schedules
- **💀 DLQ Management**: Inspect failed messages, requeue or purge items from dead letter queues
- **🧬 Schema Management**: Register and inspect schema versions, validate payloads, and delete versions
- **🔄 Live Updates**: HTMX-powered polling and SSE fragments without full-page refreshes

#### Development Mode

The dev container includes the tooling and configuration used for local development.

The dev container mounts the checkout at `/workspaces/<checkout-directory>` and
uses Docker's default network; no named network setup is required.

For UI development with auto-reloading CSS:

```bash
# Terminal 1: Watch CSS changes
make ui-watch

# Terminal 2: Run the server
go run . server --dev --grpc-addr :9000

# Terminal 3: Run the UI
NZOVU_UI_PUBLIC_ORIGIN=http://localhost:8081 go run . web-ui start --port 8081 --skip-ssl
```

## External clients

The [Python SDK](https://github.com/adrien19/nzovu-sdk-python) provides synchronous and asynchronous clients. The [TypeScript SDK and MCP server](https://github.com/adrien19/nzovu-sdk-typescript) provide `@nzovu/client`, `@nzovu/proto`, and `@nzovu/mcp-server` with the `nzovu-mcp` executable. Both repositories vendor the current Nzovu protocol and validate against PostgreSQL and SQLite. Packages remain unpublished; follow each repository's source-build instructions until SDK releases are approved separately.

## Documentation

Documentation currently lives alongside the relevant components:

- Start the HTTP gateway with `--dev` or `--enable-api-docs` and open `/docs/` for the embedded Swagger UI, or inspect the generated [OpenAPI specification](./pkg/gateway/nzovu.swagger.json).
- See the [migration guide](./deploy/NZOVU_MIGRATION.md) for breaking source/configuration changes and preserving existing data.
- See the [API validation and error contract](./API_VALIDATION.md) for queue/message configuration rules and gRPC-to-HTTP error mappings.
- See the [deployment guide](./deploy/README.md), [monitoring guide](./monitoring/README.md), [test guide](./tests/README.md), and [examples](./examples/README.md).
- See the [Go client guide](./client/README.md) for `NewNzovuClient` and client lifecycle.
- The protobuf service contract is defined in [`proto/queueservice/v1/service.proto`](./proto/queueservice/v1/service.proto).

## 🤔 Why not just use Kafka or RabbitMQ?

Kafka and RabbitMQ are general-purpose **message brokers**. Nzovu focuses on **job execution and supervision**. The distinction matters when leases, retries, and attempt ownership are part of the server-side contract.

---

### Different priorities

Kafka and RabbitMQ are designed for capabilities such as:

- High-throughput message delivery
- Fan-out and pub/sub
- Backpressure control
- Durable message storage
- Consumer group mechanics

Both brokers provide retry, timeout, and dead-letter building blocks through broker configuration and client behavior. Applications commonly remain responsible for coordinating job-level execution state across workers. Nzovu instead exposes leases, heartbeats, attempt IDs, and retry exhaustion as first-class queue operations.

---

### ✅ What Nzovu Adds

Nzovu can treat each message as a **job with an execution contract**.

Each message attempt has:

- Server-enforced lease
- Heartbeat supervision
- Automatic retry
- Dead-letter on exhaustion
- Strong ownership via `attempt_id`

#### Core Execution Model

| Feature | Nzovu |
| -------- | -------------- |
| Per-message lease | ✅ |
| Heartbeat-driven lease extension | ✅ |
| Max execution cap | ✅ |
| Automatic timeout detection | ✅ |
| Attempt-based retries | ✅ |
| Dead-letter queue | ✅ |
| Stale worker prevention | ✅ |

This model lets the server determine whether an attempt still owns the job and remains within its configured processing window.

---

### 🧠 Example: Long-Running File Download

#### Kafka / RabbitMQ

- Consumer starts download
- Network stalls for 10 minutes
- The application must detect the stalled job
- Retry and dead-letter behavior depends on broker and client configuration

#### Nzovu Features

- Job leased for 3s base + up to 10s extension
- Worker sends heartbeat every 1s
- Lease extends gradually
- If:
  - Heartbeats stop → auto timeout
  - Max extension exceeded → auto failure
- Message is retried or moved to the DLQ automatically

**The server enforces the configured lease and retry state transitions.**

---

### 🔐 Ownership & Safety

Traditional broker/client setup:

- Ownership is represented by broker-specific consumer groups, sessions, or delivery state
- If workers race or reconnect, behavior can become ambiguous

Nzovu:

- Ownership = server-generated `attempt_id`
- Every:
  - Heartbeat
  - ACK
  - Failure
  must match the active attempt
- **Stale workers are automatically rejected**

---

### 🛠 When Should You Use Nzovu?

Consider Nzovu when you need:

- ✅ Server-enforced attempt time bounds
- ✅ Automatic retries on timeout
- ✅ Server-side heartbeats
- ✅ Job-level supervision
- ✅ Strong worker ownership

Kafka or RabbitMQ may be a better fit when you primarily need:

- ✅ Raw throughput
- ✅ Stateless consumers
- ✅ Event streaming
- ✅ Fire-and-forget messaging

---

### 🧩 Mental Model

- **Kafka/RabbitMQ** = Message Delivery Systems
- **Nzovu** = Job Execution & Supervision System

Nzovu's execution model is closer to supervised job or activity processing than to a delivery-only queue.

## Examples & Use Cases

The [`examples/`](./examples/) directory contains sample applications demonstrating Nzovu integration patterns:

### 🎯 Featured Example: Interview Evaluation Platform

A sample application showcasing several Nzovu capabilities through an interview evaluation workflow:

- **Priority Queues**: Urgent vs standard evaluation processing
- **Scheduled Messages**: Business hours-based message delivery
- **Calendar Schedules**: Automated daily/weekly analytics reports
- **DLQ & Retry Logic**: Robust error handling and retry mechanisms
- **Schema Validation**: Structured message validation
- **Queue-based Workload Separation**: Separate queues for each example tenant
- **Heartbeat & Lease Renewal**: Worker health monitoring
- **Real-time Updates**: Server-Sent Events (SSE) integration

**Tech Stack**: Next.js 14, Go, SQLite, Clerk Auth, Tailwind CSS

**[View All Examples →](./examples/README.md)**

The examples demonstrate integration patterns and are intended for learning and evaluation; review and harden them before adapting them to production systems.

## Contributing

We welcome contributions! Please read our **[Contributing Guidelines](./CONTRIBUTING.md)** for detailed information on:

- 🚀 **Development Setup** - Using dev containers for consistent development
- 🧪 **Testing Guidelines** - Unit, integration, and E2E test patterns
- 📝 **Code Standards** - Go style guide and best practices
- 🔄 **Pull Request Process** - Workflow and review expectations
- 🏗️ **CI/CD Pipeline** - Understanding automated checks

**Quick Start for Contributors**:

1. **Use the Dev Container** (Recommended) - Zero configuration, everything pre-installed
2. **Fork and clone** the repository
3. **Create a feature branch** from `main`
4. **Make your changes** with tests
5. **Run tests locally**: `make test-all`
6. **Submit a pull request** with clear description

For questions, open an issue or start a GitHub Discussion.

## License

Nzovu is licensed under [MIT License](./LICENSE).

## Acknowledgments

Special thanks to everyone who contributes to and evaluates Nzovu.
