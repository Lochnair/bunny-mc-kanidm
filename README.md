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

## Origin TLS Files On Bunny

Kanidm requires `tls_chain` and `tls_key` files before `kanidmd configtest` can pass. In the intended Bunny deployment, public clients connect to Bunny for `https://idm.svee.eu` and see Bunny's public certificate. The Kanidm origin certificate is only used behind Bunny, so `kanidm-bunny` auto-generates a self-signed origin certificate and key by default at `/data/chain.pem` and `/data/key.pem`.

Minimal Bunny env vars:

```sh
KANIDM_TLS_CHAIN=/data/chain.pem
KANIDM_TLS_KEY=/data/key.pem
```

The generated files are stored in `/data`, so they persist across restarts. Startup reuses an existing certificate when it is valid and not expiring within the configured threshold. It regenerates both files when either file is missing, the certificate is expired, unparsable, or expiring soon.

Optional self-signed settings:

```sh
KANIDM_TLS_SELF_SIGNED_ENABLED=true
KANIDM_TLS_SELF_SIGNED_CN=idm.svee.eu
KANIDM_TLS_SELF_SIGNED_SAN=idm.svee.eu
```

If Bunny endpoint origin SSL validation rejects self-signed origin certificates, provide a publicly trusted origin certificate instead or configure Bunny origin validation appropriately. Manual TLS env provisioning remains supported and overrides self-signed generation:

```sh
KANIDM_TLS_CHAIN_PEM_B64=<base64-fullchain-pem>
KANIDM_TLS_KEY_PEM_B64=<base64-private-key-pem>
```

Raw PEM values are also supported as `KANIDM_TLS_CHAIN_PEM` and `KANIDM_TLS_KEY_PEM`; do not set both raw and base64 variants for the same file.

Create one-line values locally:

```sh
# Linux GNU coreutils
base64 -w0 fullchain.pem
base64 -w0 privkey.pem

# macOS/BSD
base64 -i fullchain.pem
base64 -i privkey.pem
```

The decoded files are written to `/data/chain.pem` mode `0644` and `/data/key.pem` mode `0600` by default before configtest. The private key env var is a secret; treat Bunny env access and logs accordingly. Leaving real certificate env vars set rewrites the files on every container start, which is acceptable for rotation when the Bunny env values are updated.

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
