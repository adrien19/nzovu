# Nzovu runtime migration

Use matching Nzovu clients and server; the protocol migration already changed
the gRPC namespace to `nzovu.api.*`. This change does not alter SQL schemas or
serialized queue, message, schedule or schema payloads.

## Environment and security

Use `NZOVU_` in place of `CHRONOQUEUE_` for these runtime settings:

- `TLS_ENABLED`, `API_KEY`
- `UI_AUTH_ENABLED`, `UI_AUTH_USERNAME`, `UI_AUTH_PASSWORD`
- `UI_PUBLIC_ORIGIN`, `UI_TRUST_PROXY_HEADERS`
- `UI_TLS_CERT_FILE`, `UI_TLS_KEY_FILE`
- `MAX_MESSAGE_SIZE`, `MAX_PAYLOAD_SIZE`, `MAX_METADATA_KEY_SIZE`,
  `MAX_METADATA_VALUE_SIZE`, `MAX_MESSAGE_ID_SIZE`

Legacy names remain fallback aliases. An explicitly set new variable wins,
including an empty value. Empty or invalid new TLS/auth/proxy booleans reject
startup. Empty new credentials never recover an old secret from the legacy
variable. An empty UI public origin rejects mutations. Compose accepts either
credential prefix; missing or empty credentials reject UI startup. Explicit cluster
`apiKeyEnv` references remain exact variable names; update saved references
separately if desired. CLI flags retain precedence over valid environment
settings; invalid security booleans reject startup even if a flag overrides them.

Unprefixed settings such as `POSTGRES_*`, `SQLITE_DB_PATH`, `AUTH_ENABLED`,
`API_KEYS` and encryption settings retain their names. Production auth/TLS and
encryption requirements remain enforced. Installer `NZOVU_*` overrides are
separate; they do not provide legacy aliases.

## Preserve existing storage

Database/user defaults remain `chronoqueue`; the default SQLite filename remains
`chronoqueue.db`. Compose retains `postgres-data`, `sqlite-data`, `pgadminData`,
`prometheus-data` and `grafana-data` volume keys. PostgreSQL's migration advisory
lock name also remains unchanged so old and new processes coordinate correctly.

Before cutover:

1. Record the existing Compose project (`docker compose ls`), actual volume names
   (`docker volume ls`) and storage paths. Back up the database with the existing
   deployment's tooling. For SQLite, stop writers before copying the database and
   any WAL files, or use SQLite's backup API.
2. Keep the same Compose project name (`-p <existing-project>`) and storage
   variables. Changing the project name changes the physical volume names and
   can create an empty installation. Do not use `down --volumes`.
3. Stop the old Compose definition using that same project name before changing
   files. New service names are `nzovusvc` and `nzovu-ui`; container names use
   `nzovu-`. Start the matching storage Compose file with the original project
   name and verify known queues/messages before resuming producers.
4. Start monitoring after the broker creates `nzovu-network`. Set
   `NZOVU_NETWORK_NAME` consistently on both stacks if a different network name
   is needed. Metrics now use `nzovu_*`; deploy the bundled dashboard, rules and
   scrape configuration together. Old Prometheus history remains in its volume
   under the old metric names; no metrics are dual-published.

Renaming database users, databases or physical volumes is optional and requires
an explicit operator migration. Pin `POSTGRES_USER`, `POSTGRES_DB` and
`SQLITE_DB_PATH` to existing values during upgrade; use the same values for
rollback. This release does not rename or copy persisted data automatically.

## UI configuration

New installations use `<OS user config directory>/nzovu/web-ui-clusters.json`.
If that file is absent, an existing `chronoqueue/web-ui-clusters.json` is opened
and updated in place, preserving rollback. If both exist, the Nzovu file wins.
Unreadable or invalid configuration fails startup instead of seeding an empty
store. To migrate manually, stop the UI, back up the old file, then copy it to
the Nzovu directory with the same restrictive permissions. Keep the original
for rollback and reconcile later edits before switching back. The UI currently
does not use branded cookies.

## Rollback rehearsal

Use a disposable copy of production data and record a known queue/message and
schema. Stop the previous version, start Nzovu against the same storage, read
those records and write a new record. Stop Nzovu, restart the previous Nzovu
revision against that same storage, and verify both records and the schema.
Restore the previous environment and monitoring configuration together with
the previous image. This runtime rollback rehearsal targets the pre-PR4 Nzovu
revision; it does not restore the pre-migration ChronoQueue gRPC namespace.
