# bunny-kanidm

Production-oriented container images for running Kanidm on Bunny.net Magic Containers.

This repository builds three linux/amd64 images that are intended to run together in one Bunny Magic Containers app with multiple regions, for example AMS and SG:

- `kanidm-bunny`: s6-overlay supervised Kanidm server that generates `/data/server.toml`, runs configtest before startup, and exposes a localhost-only ops API on `127.0.0.1:9080`.
- `tailscale-sidecar`: Tailscale userspace sidecar with SOCKS5 and `tailscale serve` for replication traffic.
- `socat-forwarder`: Local TCP listener that forwards Kanidm replication through the Tailscale SOCKS5 proxy.

## Architecture

Public HTTPS/OIDC traffic uses the Bunny HTTP endpoint to reach Kanidm on `0.0.0.0:8443`.

Replication does not depend on Bunny Anycast IPs. It uses Tailscale userspace networking and a local socat hop:

```text
Kanidm -> localhost:18444 -> socat -> Tailscale SOCKS5 127.0.0.1:1055 -> peer MagicDNS:8444 -> tailscale serve --tcp=8444 -> peer localhost:8444
```

Optional LDAPS can later be exposed privately with `tailscale serve` to `127.0.0.1:3636`. Public LDAPS would require raw TCP exposure unless clients are on Tailscale or behind another TCP proxy.

Kanidm operations use the built-in ops API through Tailscale Serve only. Do not expose `127.0.0.1:9080` through Bunny public HTTP/CDN endpoints.

Kanidm `domain` and `origin` must remain the public identity domain, for example `idm.svee.eu` and `https://idm.svee.eu`. Do not set them to Tailscale names. Replication has its own `repl://kanidm-sg.nessie-monster.ts.net:8444` style origin.

Use one Bunny app for the public `idm.svee.eu` endpoint so Bunny CDN routing and load balancing stay on one surface, and so per-region persistent volumes and Tailscale node identities are created in the final topology from day one. Bunny provides `BUNNYNET_MC_REGION` at runtime; `kanidm-bunny` and `socat-forwarder` use it to resolve region-specific env vars such as `KANIDM_REPL_ORIGIN_AMS` or `FORWARD_TARGET_HOST_SG`, falling back to the global variable name for single-region deployments.

## Local Builds

```sh
make build-images
```

or:

```sh
scripts/build-all.sh
```

## Published Images

GitHub Actions publishes on `push` to `main` and `workflow_dispatch`, but not on pull requests.

Expected GHCR images:

```text
ghcr.io/<owner>/bunny-kanidm-kanidm
ghcr.io/<owner>/bunny-kanidm-tailscale-sidecar
ghcr.io/<owner>/bunny-kanidm-socat-forwarder
```

## Updates

Renovate opens PRs for Dockerfile base image updates and GitHub Actions updates. After review and merge, the build workflow publishes updated GHCR images. There is no blind scheduled publish workflow.

## Docs

- [Bunny deployment](docs/bunny-deployment.md)
- [Kanidm bootstrap](docs/kanidm-bootstrap.md)
- [Tailscale ACLs](docs/tailscale-acl.md)
- [Operations](docs/operations.md)
