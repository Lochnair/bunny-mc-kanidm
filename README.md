# bunny-kanidm

Production-oriented container images for running Kanidm on Bunny.net Magic Containers.

This repository builds three linux/amd64 images:

- `kanidm-bunny`: Kanidm server wrapper that generates `/data/server.toml` from environment variables and uses `/data` as the persistent volume.
- `tailscale-sidecar`: Tailscale userspace sidecar with SOCKS5 and `tailscale serve` for replication traffic.
- `socat-forwarder`: Local TCP listener that forwards Kanidm replication through the Tailscale SOCKS5 proxy.

## Architecture

Public HTTPS/OIDC traffic uses the Bunny HTTP endpoint to reach Kanidm on `0.0.0.0:8443`.

Replication does not depend on Bunny Anycast IPs. It uses Tailscale userspace networking and a local socat hop:

```text
Kanidm -> localhost:18444 -> socat -> Tailscale SOCKS5 127.0.0.1:1055 -> peer MagicDNS:8444 -> tailscale serve --tcp=8444 -> peer localhost:8444
```

Optional LDAPS can later be exposed privately with `tailscale serve` to `127.0.0.1:3636`. Public LDAPS would require raw TCP exposure unless clients are on Tailscale or behind another TCP proxy.

Kanidm `domain` and `origin` must remain the public identity domain, for example `idm.svee.eu` and `https://idm.svee.eu`. Do not set them to Tailscale names. Replication has its own `repl://kanidm-sg.nessie-monster.ts.net:8444` style origin.

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
