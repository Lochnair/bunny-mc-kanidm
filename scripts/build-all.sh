#!/bin/sh
set -eu

DOCKER_BUILD_NETWORK="${DOCKER_BUILD_NETWORK:-host}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"

docker buildx build --network="$DOCKER_BUILD_NETWORK" --platform "$DOCKER_PLATFORM" -t bunny-kanidm-kanidm:local images/kanidm-bunny
docker buildx build --network="$DOCKER_BUILD_NETWORK" --platform "$DOCKER_PLATFORM" -t bunny-kanidm-tailscale-sidecar:local images/tailscale-sidecar
docker buildx build --network="$DOCKER_BUILD_NETWORK" --platform "$DOCKER_PLATFORM" -t bunny-kanidm-socat-forwarder:local images/socat-forwarder
