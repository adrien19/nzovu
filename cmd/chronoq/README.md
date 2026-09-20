# Nzovu CLI

The shipped command is `nzovu`; `cmd/chronoq` remains an internal source directory. Build from the repository root:

```bash
CGO_ENABLED=1 go build -tags sqlite -o ./dist/nzovu .
export PATH="$PWD/dist:$PATH"
```

An untagged build supports PostgreSQL only. SQLite requires CGO and a C compiler. See the [main quick start](../../README.md#getting-started) and [migration guide](../../deploy/NZOVU_MIGRATION.md).

## Local server and client

```bash
nzovu server --dev --storage-type sqlite --sqlite-db-path chronoqueue.db \
  --grpc-addr 127.0.0.1:9000 --http-addr 127.0.0.1:8080
```

In another terminal, set the client endpoint explicitly. `--server` selects **gRPC** for queue/message/schedule/schema/DLQ commands:

```bash
nzovu --server localhost:9000 --insecure queue create demo --type simple --auto-create-dlq
nzovu --server localhost:9000 --insecure message post demo '{"hello":"nzovu"}' --id demo-message
nzovu --server localhost:9000 --insecure message peek demo
nzovu --server localhost:9000 --insecure queue state demo
```

`--insecure` disables transport TLS for local development. For TLS use `--ca-file`; mTLS additionally requires `--cert-file` and `--key-file`. Supply an API key with `--api-key` or `NZOVU_API_KEY`. The legacy `CHRONOQUEUE_API_KEY` remains a fallback alias.

Health/version commands query the **HTTP** readiness endpoint:

```bash
nzovu server health --http-server http://localhost:8080
nzovu server version --http-server http://localhost:8080
nzovu --version
```

## Command reference

Use `nzovu <group> <command> --help` for the current arguments and flags.

| Group | Operations |
| --- | --- |
| `queue` | `create`, `delete`, `list`, `state` |
| `message` | `post`, `post-bulk`, `get`, `ack`, `peek`, `renew`, `heartbeat`, `cancel` |
| `schedule` | `create`, `delete`, `list`, `get`, `pause`, `resume`, `validate-calendar`, `preview-calendar` |
| `dlq` | `list`, `requeue`, `delete`, `purge`, `stats` |
| `schema` | `register`, `list`, `get`, `delete`, `validate` |
| `web-ui` | `start` |

Messages accept inline JSON, `--file`, or stdin (`-`). Ordered binary headers use repeatable `--header key=value` or `--header key=base64:encoded-value`. Internal header prefixes `x-nzovu-` and `x-chronoqueue-` are reserved. Bulk input and ownership rules are documented in [API validation](../../API_VALIDATION.md).

Claims return worker and attempt IDs. Use the returned IDs for acknowledgement, renewal and heartbeats; inspect each command's `--help` for required flags. Acknowledgement by message ID alone cannot establish ownership.

Schedules take the queue and message as positional arguments:

```bash
nzovu --server localhost:9000 --insecure schedule create demo '{"task":"daily"}' \
  --cron '0 0 * * *' --id daily-demo
nzovu --server localhost:9000 --insecure schedule pause daily-demo
nzovu --server localhost:9000 --insecure schedule resume daily-demo
```

## Web UI

```bash
NZOVU_UI_PUBLIC_ORIGIN=http://localhost:8081 nzovu web-ui start \
  --host 127.0.0.1 --port 8081 --grpc-address localhost:9000 --skip-ssl
```

Open `http://localhost:8081`. `--skip-ssl` disables TLS on the UI-to-gRPC connection. A non-loopback UI bind requires Basic authentication and `NZOVU_UI_TLS_CERT_FILE` and `NZOVU_UI_TLS_KEY_FILE`. Enable Basic auth with `NZOVU_UI_AUTH_ENABLED=true`, `NZOVU_UI_AUTH_USERNAME` and `NZOVU_UI_AUTH_PASSWORD`. The public origin must match browser requests for mutations to succeed.

## Production

Production requires explicit TLS, authentication and encryption configuration. Follow the [deployment guide](../../deploy/README.md) and [key rotation procedure](../../ENCRYPTION_KEY_ROTATION.md); the development commands above are local examples.
