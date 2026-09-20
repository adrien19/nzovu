# Nzovu Go client

Import `github.com/adrien19/nzovu/client`. Construct a `*client.NzovuClient`
using `client.NewNzovuClient(address, client.ClientOptions{...})`; close it when
finished to release connections and heartbeat workers. All in-repository
examples use this API.

Use the server's gRPC endpoint (normally port 9000), not its HTTP gateway.
`ClientOptions.APIKey` supplies authentication. Configure `ClientOptions.TLSCredentials` for encrypted
connections and mTLS; nil TLS credentials selects plaintext for development.
Set timeouts/retry limits through `ClientOptions` for your workload.

Claims return worker/attempt ownership. Acknowledge, renew and heartbeat with
that ownership; stale attempts must not update a replacement attempt. The client
tracks ownership and manages heartbeat workers; use its existing methods rather
than bypassing these guards.

See [client options and methods](./client.go), [examples](../examples/README.md),
[API validation](../API_VALIDATION.md), and the
[first-release migration guide](../deploy/NZOVU_MIGRATION.md).

Validation from the repository root:

```bash
go test -tags test_dep ./client/... ./cmd/nzovu/web-ui/...
```
