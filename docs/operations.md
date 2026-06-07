# Operations

## Rotate TS_AUTHKEY

Create a new reusable or ephemeral auth key with `tag:kanidm` permissions in Tailscale. Update Bunny environment variables only for regions that need a fresh login, then restart the Tailscale sidecar.

If the region already has a valid `/var/lib/tailscale` persistent volume, the sidecar first runs `tailscale up` without `TS_AUTHKEY`. Remove `TS_AUTHKEY` after confirming the node remains logged in across restarts.

## Image Updates

Renovate opens PRs for upstream Docker image tags and GitHub Actions. Review the PR, merge it, and let `.github/workflows/build-images.yml` publish updated GHCR images.

To publish manually, run the `Build images` workflow with `workflow_dispatch`.

## Logs

Bunny Magic Containers should be operated through Bunny logs, log forwarding, or syslog. Do not assume interactive shell access. Treat logs as sensitive during recovery modes because Kanidm can print recovery passwords.

Check that config generation did not print secrets by searching logs for placeholder markers and known secret prefixes. The wrappers print whether values are set, not their contents. Replication certificates are less sensitive than passwords, but recovery account output is sensitive.

## Temporary LDAPS Through Tailscale

Enable Kanidm LDAPS:

```sh
KANIDM_LDAP_ENABLED=true
KANIDM_LDAP_BINDADDRESS=127.0.0.1:3636
```

Enable Tailscale serve for LDAPS:

```sh
TS_LDAP_SERVE_PORT=3636
TS_LDAP_SERVE_TARGET=127.0.0.1:3636
```

Allow `tag:kanidm` or client tags to reach TCP `3636` in Tailscale policy. This is useful for Jellyfin or similar clients that can reach the tailnet.

## Rollback

In Bunny, change each container image back to a previous GHCR tag or digest and redeploy. Prefer immutable SHA tags or digests for rollback notes.

## Health Checks From Logs

Tailscale sidecar signs of health:

```text
[tailscale-sidecar] Tailscale up succeeded without TS_AUTHKEY
[tailscale-sidecar] Bunny Tailscale sidecar ready
```

It should also print `tailscale status` and `tailscale serve status`.

socat signs of health:

```text
[socat-forwarder] SOCKS5 proxy at 127.0.0.1:1055
[socat-forwarder] target=kanidm-ams.nessie-monster.ts.net:8444
```

Kanidm signs of health:

```text
[kanidm-bunny] Running kanidmd configtest
[kanidm-bunny] Starting kanidmd server
```

## Test The Forwarding Path

Use the existing proof scripts outside Bunny when possible. Inside Bunny, rely on logs:

- Tailscale must reach running state.
- SOCKS5 listener must become reachable.
- `tailscale serve status` must show TCP `8444`.
- socat must start after the SOCKS5 wait succeeds.
- Kanidm configtest must pass before server start.

## Accidental Tailscale State Clones

If a Tailscale state volume was copied between regions, the nodes can appear as the same machine. Stop the affected region, remove or replace only that region's `/var/lib/tailscale` volume, provide a fresh `TS_AUTHKEY`, and restart. Confirm the node appears with the expected `kanidm-<region>` hostname, then remove `TS_AUTHKEY`.
