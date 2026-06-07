# Kanidm Bootstrap

Bunny has no useful `docker exec` style operational path for Magic Containers. The `kanidm-bunny` image therefore runs Kanidm under s6-overlay and starts a localhost-only ops API as a normal operational interface.

Expose the ops API only through Tailscale Serve:

```sh
TS_OPS_SERVE_PORT=9080
TS_OPS_SERVE_TARGET=127.0.0.1:9080
```

Never expose the ops API through Bunny public HTTP/CDN endpoints. Mutating endpoints require `Authorization: Bearer <OPS_ADMIN_TOKEN>`. Account recovery also requires `OPS_ENABLE_RECOVERY=true`.

In `kanidm/server:1.10.3`, these helper command forms were verified inside the built `kanidm-bunny` image and are used by the ops API:

```sh
kanidmd show-replication-certificate -c /data/server.toml
kanidmd refresh-replication-consumer -c /data/server.toml
kanidmd recover-account admin -c /data/server.toml
```

Recovery account output is sensitive and should be handled like a password.

## One-App Two-Region Bootstrap

Deploy one Bunny Magic Containers app with AMS and SG from the start. The first deploy intentionally has no peer URL or peer certificate values so each region can start independently and generate its own replication certificate.

Initial app-level env:

```sh
KANIDM_DOMAIN=idm.svee.eu
KANIDM_ORIGIN=https://idm.svee.eu
KANIDM_REPL_ENABLED=true
KANIDM_REPL_BINDADDRESS=127.0.0.1:8444
KANIDM_REPL_ORIGIN_AMS=repl://kanidm-ams.nessie-monster.ts.net:8444
KANIDM_REPL_ORIGIN_SG=repl://kanidm-sg.nessie-monster.ts.net:8444
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

After both regional pods are up, show each replication certificate from a tailnet admin machine:

```sh
curl http://kanidm-ams.nessie-monster.ts.net:9080/replication/certificate
curl http://kanidm-sg.nessie-monster.ts.net:9080/replication/certificate
```

`KANIDM_REPL_PEER_CERT` must contain only the certificate string value, not the full `certificate: "..."` output line. `KANIDM_REPL_PEER_CERT_B64` must be base64 of only that certificate string value.

Add the peer URLs and peer certificates at the app level:

```sh
KANIDM_REPL_PEER_URL_AMS=repl://127.0.0.1:18444
KANIDM_REPL_PEER_URL_SG=repl://127.0.0.1:18444
KANIDM_REPL_PEER_CERT_B64_AMS=<base64-of-sg-replication-cert-value>
KANIDM_REPL_PEER_CERT_B64_SG=<base64-of-ams-replication-cert-value>
KANIDM_REPL_AUTOMATIC_REFRESH_SG=true
```

Leave `KANIDM_REPL_AUTOMATIC_REFRESH_AMS` unset on the primary. The config generator only writes `automatic_refresh = true` when the resolved value is true; it omits the key otherwise.

Redeploy or restart the app. If SG does not automatically refresh from AMS, call the refresh endpoint:

```sh
curl -X POST \
  -H "Authorization: Bearer ${OPS_ADMIN_TOKEN}" \
  http://kanidm-sg.nessie-monster.ts.net:9080/replication/refresh-consumer
```

The peer URL currently points to the local forwarder: `repl://127.0.0.1:18444`. Kanidm examples describe peer stanzas using the partner node origin, such as `repl://origin_of_A:port`; this local-forwarder URL is the main remaining runtime validation point. It may work because `partner_cert` validates the remote node reached through socat. If Kanidm requires the URL to match the partner origin, the fallback is to bind socat on a loopback alias, for example `127.0.0.2:8444`, resolve `kanidm-ams.nessie-monster.ts.net` locally to `127.0.0.2` inside the Kanidm container, and keep the peer URL as `repl://kanidm-ams.nessie-monster.ts.net:8444`.

## Account Recovery

Use only when needed. Recovery output may include temporary credentials.

```sh
curl -X POST \
  -H "Authorization: Bearer ${OPS_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"account":"admin"}' \
  http://kanidm-sg.nessie-monster.ts.net:9080/account/recover
```

Set `OPS_ENABLE_RECOVERY=true` only while using the recovery endpoint, then set it back to false.
