#!/bin/sh
set -eu

log() {
  printf '[socat-forwarder] %s\n' "$*"
}

die() {
  printf '[socat-forwarder] ERROR: %s\n' "$*" >&2
  exit 1
}

env_is_set() {
  eval "[ \"\${$1+x}\" = x ]"
}

env_get() {
  eval "RESOLVED_VALUE=\${$1-}"
}

resolve_env() {
  base="$1"
  default="$2"

  RESOLVED_SOURCE=""
  for candidate in "${base}_${REGION_UPPER}" "${base}_${REGION_LOWER}" "$base"; do
    if env_is_set "$candidate"; then
      env_get "$candidate"
      RESOLVED_SOURCE="$candidate"
      log "${base}: selected ${candidate}"
      return 0
    fi
  done

  RESOLVED_VALUE="$default"
  log "${base}: no region/global override selected; using default"
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
REGION_LOWER="$(printf '%s' "$REGION_RAW" | tr '[:upper:]' '[:lower:]')"
REGION_UPPER="$(printf '%s' "$REGION_RAW" | tr '[:lower:]' '[:upper:]')"

: "${TAILNET_DNS_NAME:=nessie-monster.ts.net}"
: "${FORWARD_START_DELAY_SECONDS:=0}"
: "${SOCKS_WAIT_SECONDS:=60}"

resolve_env SOCKS5_PROXY_HOST "127.0.0.1"
SOCKS5_PROXY_HOST="$RESOLVED_VALUE"
resolve_env SOCKS5_PROXY_PORT "1055"
SOCKS5_PROXY_PORT="$RESOLVED_VALUE"
resolve_env FORWARD_LISTEN_HOST "127.0.0.1"
FORWARD_LISTEN_HOST="$RESOLVED_VALUE"
resolve_env FORWARD_LISTEN_PORT "18444"
FORWARD_LISTEN_PORT="$RESOLVED_VALUE"
resolve_env FORWARD_TARGET_PORT "8444"
FORWARD_TARGET_PORT="$RESOLVED_VALUE"
resolve_env FORWARD_TARGET_HOST ""
FORWARD_TARGET_HOST="$RESOLVED_VALUE"
FORWARD_TARGET_HOST_SOURCE="$RESOLVED_SOURCE"

case "$REGION_LOWER" in
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

if [ -z "$FORWARD_TARGET_HOST_SOURCE" ]; then
  FORWARD_TARGET_HOST="$DEFAULT_PEER"
fi
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
