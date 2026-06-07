# Kanidm Bootstrap

Bunny has no reliable `docker exec` style operational path for Magic Containers. The `kanidm-bunny` image has helper modes so one-off Kanidm commands can be run by changing environment variables and restarting/redeploying the container.

Recovery passwords and some Kanidm command outputs can appear in logs. Treat Bunny logs and log forwarding destinations as sensitive during bootstrap and recovery.

Helper modes generate `/data/server.toml` and run Kanidm commands against that config. In `kanidm/server:1.10.3`, these forms were verified inside the built `kanidm-bunny` image:

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
```

2. Show the AMS replication certificate.

```sh
KANIDM_MODE=show-replication-certificate
```

3. Start SG with the AMS certificate and automatic refresh enabled.

```sh
KANIDM_REPL_ENABLED=true
KANIDM_REPL_ORIGIN=repl://kanidm-sg.nessie-monster.ts.net:8444
KANIDM_REPL_BINDADDRESS=127.0.0.1:8444
KANIDM_REPL_PEER_URL=repl://127.0.0.1:18444
KANIDM_REPL_PEER_CERT_B64=<base64-of-ams-replication-cert-value>
KANIDM_REPL_AUTOMATIC_REFRESH=true
```

`KANIDM_REPL_PEER_CERT` must contain only the certificate string value, not the full `certificate: "..."` output line. `KANIDM_REPL_PEER_CERT_B64` must be base64 of only that certificate string value.

The peer URL currently points to the local forwarder: `repl://127.0.0.1:18444`. Kanidm examples describe peer stanzas using the partner node origin, such as `repl://origin_of_A:port`; this local-forwarder URL is the main remaining runtime validation point. It may work because `partner_cert` validates the remote node reached through socat. If Kanidm requires the URL to match the partner origin, the fallback is to bind socat on a loopback alias, for example `127.0.0.2:8444`, resolve `kanidm-ams.nessie-monster.ts.net` locally to `127.0.0.2` inside the Kanidm container, and keep the peer URL as `repl://kanidm-ams.nessie-monster.ts.net:8444`.

4. Show the SG replication certificate.

```sh
KANIDM_MODE=show-replication-certificate
```

5. Update AMS with the SG certificate and no automatic refresh.

```sh
KANIDM_REPL_PEER_URL=repl://127.0.0.1:18444
KANIDM_REPL_PEER_CERT_B64=<base64-of-sg-replication-cert-value>
```

Leave `KANIDM_REPL_AUTOMATIC_REFRESH` unset or false on the primary. The wrapper only writes `automatic_refresh = true` when `KANIDM_REPL_AUTOMATIC_REFRESH=true`; it omits the key otherwise.

6. Restart both regions in `server` mode.

```sh
KANIDM_MODE=server
```

7. If SG does not automatically refresh from AMS, temporarily run:

```sh
KANIDM_MODE=refresh-replication-consumer
```

Then return to:

```sh
KANIDM_MODE=server
```

## Account Recovery

Use only when needed. The generated recovery password will appear in logs.

```sh
KANIDM_MODE=recover-account
KANIDM_RECOVER_ACCOUNT=admin
```

or:

```sh
KANIDM_MODE=recover-account
KANIDM_RECOVER_ACCOUNT=idm_admin
```

Return to `KANIDM_MODE=server` immediately after recovery.
