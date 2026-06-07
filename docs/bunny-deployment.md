# Bunny Deployment

Deploy one Bunny.net Magic Containers app with multiple regions, for example AMS and SG. The app should run three containers:

- `kanidm-bunny`
- `tailscale-sidecar`
- `socat-forwarder`

Build and deploy linux/amd64 images only.

Use one Bunny app for `idm.svee.eu`. This keeps Bunny CDN routing, public endpoint configuration, and load balancing on one app surface, and it creates Kanidm data volumes and Tailscale node identities under the final topology from the first deploy. Avoid changing from a per-region-app layout later because that can force state movement or identity recreation.

## Volumes

Attach persistent storage for Kanidm `/data` and Tailscale `/var/lib/tailscale` in the multi-region app. Bunny should provide region-local volume instances to each regional pod.

Do not reuse or copy Tailscale state volumes across regions. Each region must keep its own persisted Tailscale node identity. The `tailscale-sidecar` derives `TS_HOSTNAME=kanidm-<region>` from `BUNNYNET_MC_REGION` when `TS_HOSTNAME` is not set, and that behavior is correct for the multi-region app.

Containers in the same regional pod share localhost and the network namespace, so ports must not collide. The defaults use:

- Kanidm HTTPS: `0.0.0.0:8443`
- Kanidm replication listener: `127.0.0.1:8444`
- Kanidm ops API: `127.0.0.1:9080`
- Tailscale SOCKS5: `127.0.0.1:1055`
- socat replication forwarder: `127.0.0.1:18444`
- Optional LDAPS: `127.0.0.1:3636`

`TS_AUTHKEY` is needed only for the first bootstrap or when the persisted Tailscale identity is missing. Remove `TS_AUTHKEY` after stable persisted state is confirmed.

## Region-Aware Env Vars

Bunny provides `BUNNYNET_MC_REGION` at runtime. The config scripts normalize it to uppercase and lowercase forms. For a base name such as `KANIDM_REPL_ORIGIN`, values are resolved in this order:

```text
KANIDM_REPL_ORIGIN_${REGION_UPPER}
KANIDM_REPL_ORIGIN_${REGION_LOWER}
KANIDM_REPL_ORIGIN
```

For region `SG`, `KANIDM_REPL_ORIGIN_SG` wins, then `KANIDM_REPL_ORIGIN_sg`, then `KANIDM_REPL_ORIGIN`. The scripts log which variable name was selected. Secret values are not printed.

Keep `KANIDM_DOMAIN` and `KANIDM_ORIGIN` global and public-facing, for example `idm.svee.eu` and `https://idm.svee.eu`.

## Combined App Env

Set app-level environment variables once. Region-specific values are selected by each regional pod:

```sh
KANIDM_DOMAIN=idm.svee.eu
KANIDM_ORIGIN=https://idm.svee.eu
KANIDM_REPL_ENABLED=true
KANIDM_REPL_BINDADDRESS=127.0.0.1:8444
KANIDM_REPL_ORIGIN_AMS=repl://kanidm-ams.nessie-monster.ts.net:8444
KANIDM_REPL_ORIGIN_SG=repl://kanidm-sg.nessie-monster.ts.net:8444
KANIDM_REPL_PEER_URL_AMS=repl://127.0.0.1:18444
KANIDM_REPL_PEER_URL_SG=repl://127.0.0.1:18444
KANIDM_REPL_PEER_CERT_B64_AMS=<base64-of-sg-replication-cert-value>
KANIDM_REPL_PEER_CERT_B64_SG=<base64-of-ams-replication-cert-value>
KANIDM_REPL_AUTOMATIC_REFRESH_SG=true
OPS_ADMIN_TOKEN=<long-random-token>

TS_AUTHKEY=<tskey-auth-placeholder>
TS_EXTRA_ARGS=--accept-dns=true --advertise-tags=tag:kanidm
TS_SERVE_PORT=8444
TS_SERVE_TARGET=127.0.0.1:8444
TS_OPS_SERVE_PORT=9080
TS_OPS_SERVE_TARGET=127.0.0.1:9080

TAILNET_DNS_NAME=nessie-monster.ts.net
FORWARD_TARGET_HOST_AMS=kanidm-sg.nessie-monster.ts.net
FORWARD_TARGET_HOST_SG=kanidm-ams.nessie-monster.ts.net
FORWARD_TARGET_PORT=8444
FORWARD_LISTEN_HOST=127.0.0.1
FORWARD_LISTEN_PORT=18444
```

During first bootstrap, omit `KANIDM_REPL_PEER_URL_AMS`, `KANIDM_REPL_PEER_URL_SG`, `KANIDM_REPL_PEER_CERT_B64_AMS`, and `KANIDM_REPL_PEER_CERT_B64_SG`. Replication can be enabled with no peer stanza so each region can start and generate its own replication certificate.

Only set `KANIDM_REPL_AUTOMATIC_REFRESH_SG=true` on the SG secondary side. Leave the AMS primary without an automatic refresh variable; the generator only writes `automatic_refresh = true` when the resolved value is true.

If `FORWARD_TARGET_HOST` is not set globally or region-specifically, `socat-forwarder` keeps the built-in defaults:

```text
SG  -> kanidm-ams.${TAILNET_DNS_NAME}
AMS -> kanidm-sg.${TAILNET_DNS_NAME}
SE  -> kanidm-sg.${TAILNET_DNS_NAME}
```

Use explicit `FORWARD_TARGET_HOST_<REGION>` when a region should replicate from a peer other than the built-in default.

## Bootstrap

1. Deploy one app with AMS and SG, `KANIDM_REPL_ENABLED=true`, and region-specific `KANIDM_REPL_ORIGIN_AMS` and `KANIDM_REPL_ORIGIN_SG`. Do not set peer URLs or peer certificates yet.
2. Use the ops API over Tailscale to fetch both replication certificates.
3. Add `KANIDM_REPL_PEER_CERT_B64_AMS` with the SG certificate, `KANIDM_REPL_PEER_CERT_B64_SG` with the AMS certificate, and the region-specific peer URLs.
4. Set `KANIDM_REPL_AUTOMATIC_REFRESH_SG=true` only for SG.
5. Redeploy or restart the app.
6. Trigger `refresh-consumer` on SG through the ops API only if automatic refresh does not pull from AMS.

## Ops API Exposure

The `kanidm-bunny` image starts the ops API as a normal supervised service on `OPS_BINDADDRESS`, default `127.0.0.1:9080`. Keep it loopback-only in the Kanidm container and expose it only through the existing `tailscale-sidecar` with:

```sh
TS_OPS_SERVE_PORT=9080
TS_OPS_SERVE_TARGET=127.0.0.1:9080
```

Do not configure Bunny public HTTP/CDN endpoints for the ops API port. Mutating endpoints still require `Authorization: Bearer <OPS_ADMIN_TOKEN>`; Tailscale ACLs are the outer access-control layer.

## Replication Peer URL Validation

The main remaining runtime validation point is `KANIDM_REPL_PEER_URL_<REGION>=repl://127.0.0.1:18444`.

Kanidm documentation describes replication peer stanzas as using the partner node origin, for example `repl://origin_of_A:port`. This Bunny design inserts a local socat forwarder between Kanidm and the remote node, so the peer URL currently points at the local listener `repl://127.0.0.1:18444`.

This may work because `partner_cert` validates the remote node reached through the forwarder, but it still needs real Kanidm replication testing. If Kanidm requires the peer URL to match the partner origin, use a loopback alias and local hosts override instead:

```text
local Kanidm replication binds 127.0.0.1:8444
socat binds 127.0.0.2:8444
kanidm-ams.nessie-monster.ts.net resolves to 127.0.0.2 inside the Kanidm container
peer URL remains repl://kanidm-ams.nessie-monster.ts.net:8444
```

Do not switch to this fallback until the local forwarder URL is proven incompatible.
