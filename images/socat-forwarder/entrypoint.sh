#!/bin/sh
set -eu

log() {
  printf '[socat-forwarder] %s\n' "$*"
}

die() {
  printf '[socat-forwarder] ERROR: %s\n' "$*" >&2
  exit 1
}

wait_for_tcp() {
  host="$1"
  port="$2"
  timeout_seconds="$3"
  label="$4"
  i=0

  log "Waiting for ${label} at ${host}:${port}"
  while ! nc -z "$host" "$port" >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -le "$timeout_seconds" ] || die "${label} was not reachable after ${timeout_seconds}s"
    sleep 1
  done
}

REGION_RAW="${BUNNYNET_MC_REGION:-unknown}"
REGION="$(printf '%s' "$REGION_RAW" | tr '[:upper:]' '[:lower:]')"

: "${SOCKS5_PROXY_HOST:=127.0.0.1}"
: "${SOCKS5_PROXY_PORT:=1055}"
: "${FORWARD_LISTEN_HOST:=127.0.0.1}"
: "${FORWARD_LISTEN_PORT:=18444}"
: "${FORWARD_TARGET_PORT:=8444}"
: "${TAILNET_DNS_NAME:=nessie-monster.ts.net}"
: "${FORWARD_START_DELAY_SECONDS:=0}"
: "${SOCKS_WAIT_SECONDS:=60}"

case "$REGION" in
  sg)
    DEFAULT_PEER="kanidm-ams.${TAILNET_DNS_NAME}"
    ;;
  ams|se)
    DEFAULT_PEER="kanidm-sg.${TAILNET_DNS_NAME}"
    ;;
  *)
    DEFAULT_PEER=""
    ;;
esac

FORWARD_TARGET_HOST="${FORWARD_TARGET_HOST:-$DEFAULT_PEER}"
[ -n "$FORWARD_TARGET_HOST" ] || die "Cannot derive FORWARD_TARGET_HOST from BUNNYNET_MC_REGION=${REGION_RAW}; set FORWARD_TARGET_HOST explicitly"

if [ "$FORWARD_START_DELAY_SECONDS" -gt 0 ]; then
  log "Delaying start for ${FORWARD_START_DELAY_SECONDS}s"
  sleep "$FORWARD_START_DELAY_SECONDS"
fi

wait_for_tcp "$SOCKS5_PROXY_HOST" "$SOCKS5_PROXY_PORT" "$SOCKS_WAIT_SECONDS" "SOCKS5 proxy"

log "Starting socat Tailscale SOCKS5 forwarder"
log "region=${REGION_RAW}"
log "listen=${FORWARD_LISTEN_HOST}:${FORWARD_LISTEN_PORT}"
log "socks5=${SOCKS5_PROXY_HOST}:${SOCKS5_PROXY_PORT}"
log "target=${FORWARD_TARGET_HOST}:${FORWARD_TARGET_PORT}"

exec socat -d -d \
  "TCP-LISTEN:${FORWARD_LISTEN_PORT},bind=${FORWARD_LISTEN_HOST},reuseaddr,fork" \
  "SOCKS5-CONNECT:${SOCKS5_PROXY_HOST}:${SOCKS5_PROXY_PORT}:${FORWARD_TARGET_HOST}:${FORWARD_TARGET_PORT}"
