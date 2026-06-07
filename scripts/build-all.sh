#!/bin/sh
set -eu

docker buildx build --platform linux/amd64 -t bunny-kanidm-kanidm:local images/kanidm-bunny
docker buildx build --platform linux/amd64 -t bunny-kanidm-tailscale-sidecar:local images/tailscale-sidecar
docker buildx build --platform linux/amd64 -t bunny-kanidm-socat-forwarder:local images/socat-forwarder
