# Nzovu first-release migration

Nzovu prepares `v0.0.1` with a clean source API. The destination repository is
`github.com/adrien19/nzovu`; its default branch is `main`. Use feature branches
and pull requests for changes.

## Client and source API

- Import the Go client from `github.com/adrien19/nzovu/client` and construct it
  with `client.NewNzovuClient(address, client.ClientOptions{...})`. Its concrete
  type is `*client.NzovuClient`; the old constructor/type aliases are removed.
- CLI/UI sources moved from `cmd/chronoq` to `cmd/nzovu`. Server sources moved
  from `pkg/chronoqueue` to `pkg/nzovu`, with `NzovuServer` and
  `NewNzovuServer`. Update imports and local build scripts together.
- UI CSS classes now use `nzovu-*`. Rebuild embedded styles with
  `cd cmd/nzovu/web-ui && npm ci && npm run build:css` before building Go.
- gRPC packages are `nzovu.api.*`. Regenerate external clients; the historical
  `chronoqueue.api.*` service is not registered. HTTP `/v1` routes and protobuf
  field numbers remain unchanged. Binary storage fixtures retain their original
  bytes under `pre_migration_v1_*` names.
- Health responses identify `nzovu`; HTTP responses expose `X-Nzovu-Version`.
  Internal metadata uses `nzovu-gateway-client-id`. Message header/ID reservations
  use `x-nzovu-` and `nzovu:` (colons also fail the ID character rules).

## Environment and UI configuration

Only `NZOVU_*` runtime variables are read; `CHRONOQUEUE_*` aliases are removed.
Rename TLS, API-key, UI authentication/origin/proxy/certificate and message-limit
settings before starting this version. Unprefixed `POSTGRES_*`, `SQLITE_DB_PATH`,
`AUTH_ENABLED`, `API_KEYS` and encryption settings keep their names.

An explicitly empty or invalid TLS/auth/proxy boolean rejects startup. Missing
or empty UI credentials reject startup when authentication is enabled. An empty
public origin rejects UI mutations. CLI flags override valid environment values;
invalid security settings still reject startup.

The UI reads only `<OS user config directory>/nzovu/web-ui-clusters.json`.
There is no lookup of the old `chronoqueue` directory. Before starting the UI:

1. Stop the old UI and back up its configuration.
2. Copy the existing configuration to the new directory with restrictive
   permissions (`0700` directory, `0600` file on Unix). Resolve any existing
   destination configuration explicitly; do not overwrite it blindly.
3. Update saved `apiKeyEnv` references to variables you actually configure.
   Explicit references remain exact, arbitrary environment variable names;
   they are not automatic product aliases. Secrets stay outside the JSON file.
4. Start the UI and verify saved clusters, active selection and credentials.
   Invalid/unreadable configuration fails startup. The UI does not use cookies.

## Storage cutover and rollback

Fresh defaults are PostgreSQL database/user `nzovu` and SQLite file `nzovu.db`.
The Compose development password is `nzovu_dev_password`; configure real
credentials outside local development. Existing data is not renamed or copied.

Before upgrading an existing installation:

1. Back up its database, encryption configuration and actual volume names.
   For SQLite stop writers before copying the database/WAL files, or use the
   SQLite backup API.
2. Explicitly set `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` and/or
   `SQLITE_DB_PATH` to the existing installation's values. For example an old
   SQLite deployment may require `SQLITE_DB_PATH=/data/chronoqueue.db`, and an
   old PostgreSQL installation may use database/user `chronoqueue`. The Compose
   files accept these overrides for both broker and database service.
3. Keep the original Compose project name (`-p <existing-project>`) and volume
   keys. `postgres-data`, `sqlite-data`, `pgadminData`, `prometheus-data` and
   `grafana-data` remain stable. Do not use `down --volumes` during migration.
4. Stop all old writers before starting Nzovu. The SQL migration advisory lock
   is now `nzovu_schema_migration`; mixed-version startup is unsupported. SQL
   schemas and serialized payloads are unchanged.
5. Start the broker, then the UI and monitoring. Verify known queues, messages
   and schemas before resuming clients. Keep `NZOVU_NETWORK_NAME` consistent
   across the broker and monitoring stacks.

Rehearse with disposable copies: read an existing record, write a new record,
stop Nzovu, then restart the previous binary with its original environment,
explicit storage paths and UI configuration. Verify both records. Never run old
and new writers concurrently. The previous protobuf namespace also requires its
matching client version when rolling back across the namespace migration.

Metrics use `nzovu_*`; update scrape configs, dashboards and alerts together.
Historical metrics remain in their original Prometheus volume. Historical ADRs,
source attribution, migration instructions and the external
`chronoqueue-typescript-sdk` link retain their original names in documentation;
executable source, configuration and source paths use Nzovu identifiers.
