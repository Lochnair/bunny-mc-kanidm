# Bunny Deployment

Each Bunny.net Magic Containers app should run three containers:

- `kanidm-bunny`
- `tailscale-sidecar`
- `socat-forwarder`

Build and deploy linux/amd64 images only.

## Volumes

Use separate persistent volumes per Bunny region:

- Kanidm `/data` volume per region.
- Tailscale `/var/lib/tailscale` volume per region.

Do not reuse or copy Tailscale state volumes across regions. Each region should have its own persisted Tailscale node identity.

Containers in the same Bunny app share localhost and the network namespace, so ports must not collide. The defaults use:

- Kanidm HTTPS: `0.0.0.0:8443`
- Kanidm replication listener: `127.0.0.1:8444`
- Kanidm ops API: `127.0.0.1:9080`
- Tailscale SOCKS5: `127.0.0.1:1055`
- socat replication forwarder: `127.0.0.1:18444`
- Optional LDAPS: `127.0.0.1:3636`

`TS_AUTHKEY` is needed only for the first bootstrap or when the persisted Tailscale identity is missing. Remove `TS_AUTHKEY` after stable persisted state is confirmed.

## SG Example

`kanidm-bunny`:

```sh
BUNNYNET_MC_REGION=SG
KANIDM_DOMAIN=idm.svee.eu
KANIDM_ORIGIN=https://idm.svee.eu
KANIDM_REPL_ENABLED=true
KANIDM_REPL_ORIGIN=repl://kanidm-sg.nessie-monster.ts.net:8444
KANIDM_REPL_BINDADDRESS=127.0.0.1:8444
KANIDM_REPL_PEER_URL=repl://127.0.0.1:18444
KANIDM_REPL_PEER_CERT_B64=<base64-of-ams-replication-cert-value>
KANIDM_REPL_AUTOMATIC_REFRESH=true
OPS_ADMIN_TOKEN=<long-random-token>
```

`tailscale-sidecar`:

```sh
BUNNYNET_MC_REGION=SG
TS_AUTHKEY=<tskey-auth-placeholder>
TS_EXTRA_ARGS=--accept-dns=true --advertise-tags=tag:kanidm
TS_SERVE_PORT=8444
TS_SERVE_TARGET=127.0.0.1:8444
TS_OPS_SERVE_PORT=9080
TS_OPS_SERVE_TARGET=127.0.0.1:9080
```

`socat-forwarder`:

```sh
BUNNYNET_MC_REGION=SG
TAILNET_DNS_NAME=nessie-monster.ts.net
FORWARD_TARGET_HOST=kanidm-ams.nessie-monster.ts.net
FORWARD_TARGET_PORT=8444
FORWARD_LISTEN_HOST=127.0.0.1
FORWARD_LISTEN_PORT=18444
```

## AMS Example

`kanidm-bunny`:

```sh
BUNNYNET_MC_REGION=AMS
KANIDM_DOMAIN=idm.svee.eu
KANIDM_ORIGIN=https://idm.svee.eu
KANIDM_REPL_ENABLED=true
KANIDM_REPL_ORIGIN=repl://kanidm-ams.nessie-monster.ts.net:8444
KANIDM_REPL_BINDADDRESS=127.0.0.1:8444
KANIDM_REPL_PEER_URL=repl://127.0.0.1:18444
KANIDM_REPL_PEER_CERT_B64=<base64-of-sg-replication-cert-value>
OPS_ADMIN_TOKEN=<long-random-token>
```

`tailscale-sidecar`:

```sh
BUNNYNET_MC_REGION=AMS
TS_AUTHKEY=<tskey-auth-placeholder>
TS_EXTRA_ARGS=--accept-dns=true --advertise-tags=tag:kanidm
TS_SERVE_PORT=8444
TS_SERVE_TARGET=127.0.0.1:8444
TS_OPS_SERVE_PORT=9080
TS_OPS_SERVE_TARGET=127.0.0.1:9080
```

`socat-forwarder`:

```sh
BUNNYNET_MC_REGION=AMS
TAILNET_DNS_NAME=nessie-monster.ts.net
FORWARD_TARGET_HOST=kanidm-sg.nessie-monster.ts.net
FORWARD_TARGET_PORT=8444
FORWARD_LISTEN_HOST=127.0.0.1
FORWARD_LISTEN_PORT=18444
```

## Optional SE Fallback

```sh
BUNNYNET_MC_REGION=SE
TAILNET_DNS_NAME=nessie-monster.ts.net
FORWARD_TARGET_HOST=kanidm-sg.nessie-monster.ts.net
KANIDM_REPL_ORIGIN=repl://kanidm-se.nessie-monster.ts.net:8444
```

Use explicit `FORWARD_TARGET_HOST` when a region should replicate from a peer other than the built-in default.

## Ops API Exposure

The `kanidm-bunny` image starts the ops API as a normal supervised service on `OPS_BINDADDRESS`, default `127.0.0.1:9080`. Keep it loopback-only in the Kanidm container and expose it only through the existing `tailscale-sidecar` with:

```sh
TS_OPS_SERVE_PORT=9080
TS_OPS_SERVE_TARGET=127.0.0.1:9080
```

Do not configure Bunny public HTTP/CDN endpoints for the ops API port. Mutating endpoints still require `Authorization: Bearer <OPS_ADMIN_TOKEN>`; Tailscale ACLs are the outer access-control layer.

## Replication Peer URL Validation

The main remaining runtime validation point is `KANIDM_REPL_PEER_URL=repl://127.0.0.1:18444`.

Kanidm documentation describes replication peer stanzas as using the partner node origin, for example `repl://origin_of_A:port`. This Bunny design inserts a local socat forwarder between Kanidm and the remote node, so the peer URL currently points at the local listener `repl://127.0.0.1:18444`.

This may work because `partner_cert` validates the remote node reached through the forwarder, but it still needs real Kanidm replication testing. If Kanidm requires the peer URL to match the partner origin, use a loopback alias and local hosts override instead:

```text
local Kanidm replication binds 127.0.0.1:8444
socat binds 127.0.0.2:8444
kanidm-ams.nessie-monster.ts.net resolves to 127.0.0.2 inside the Kanidm container
peer URL remains repl://kanidm-ams.nessie-monster.ts.net:8444
```

Do not switch to this fallback until the local forwarder URL is proven incompatible.
