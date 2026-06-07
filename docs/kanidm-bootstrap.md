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

## Two-Region Bootstrap

1. Start AMS first without a replication peer.

```sh
KANIDM_REPL_ENABLED=true
KANIDM_REPL_ORIGIN=repl://kanidm-ams.nessie-monster.ts.net:8444
KANIDM_REPL_BINDADDRESS=127.0.0.1:8444
KANIDM_REPL_PEER_URL=
KANIDM_REPL_PEER_CERT_B64=
OPS_ADMIN_TOKEN=<long-random-token>
```

2. Show the AMS replication certificate from a tailnet admin machine.

```sh
curl http://kanidm-ams.nessie-monster.ts.net:9080/replication/certificate
```

3. Start SG with the AMS certificate and automatic refresh enabled.

```sh
KANIDM_REPL_ENABLED=true
KANIDM_REPL_ORIGIN=repl://kanidm-sg.nessie-monster.ts.net:8444
KANIDM_REPL_BINDADDRESS=127.0.0.1:8444
KANIDM_REPL_PEER_URL=repl://127.0.0.1:18444
KANIDM_REPL_PEER_CERT_B64=<base64-of-ams-replication-cert-value>
KANIDM_REPL_AUTOMATIC_REFRESH=true
OPS_ADMIN_TOKEN=<long-random-token>
```

`KANIDM_REPL_PEER_CERT` must contain only the certificate string value, not the full `certificate: "..."` output line. `KANIDM_REPL_PEER_CERT_B64` must be base64 of only that certificate string value.

The peer URL currently points to the local forwarder: `repl://127.0.0.1:18444`. Kanidm examples describe peer stanzas using the partner node origin, such as `repl://origin_of_A:port`; this local-forwarder URL is the main remaining runtime validation point. It may work because `partner_cert` validates the remote node reached through socat. If Kanidm requires the URL to match the partner origin, the fallback is to bind socat on a loopback alias, for example `127.0.0.2:8444`, resolve `kanidm-ams.nessie-monster.ts.net` locally to `127.0.0.2` inside the Kanidm container, and keep the peer URL as `repl://kanidm-ams.nessie-monster.ts.net:8444`.

4. Show the SG replication certificate.

```sh
curl http://kanidm-sg.nessie-monster.ts.net:9080/replication/certificate
```

5. Update AMS with the SG certificate and no automatic refresh.

```sh
KANIDM_REPL_PEER_URL=repl://127.0.0.1:18444
KANIDM_REPL_PEER_CERT_B64=<base64-of-sg-replication-cert-value>
```

Leave `KANIDM_REPL_AUTOMATIC_REFRESH` unset or false on the primary. The config generator only writes `automatic_refresh = true` when `KANIDM_REPL_AUTOMATIC_REFRESH=true`; it omits the key otherwise.

6. If SG does not automatically refresh from AMS, call the refresh endpoint.

```sh
curl -X POST \
  -H "Authorization: Bearer ${OPS_ADMIN_TOKEN}" \
  http://kanidm-sg.nessie-monster.ts.net:9080/replication/refresh-consumer
```

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
