#!/bin/sh
set -eu

log() {
  printf '[tailscale-sidecar] %s\n' "$*"
}

die() {
  printf '[tailscale-sidecar] ERROR: %s\n' "$*" >&2
  exit 1
}

redact_state() {
  if [ -n "${1:-}" ]; then
    printf '<set:%s chars>' "$(printf '%s' "$1" | wc -c | tr -d ' ')"
  else
    printf '<unset>'
  fi
}

wait_for_socket() {
  socket_path="$1"
  timeout_seconds="$2"
  i=0

  log "Waiting for LocalAPI socket ${socket_path}"
  while [ ! -S "$socket_path" ]; do
    i=$((i + 1))
    [ "$i" -le "$timeout_seconds" ] || die "LocalAPI socket did not appear after ${timeout_seconds}s"
    sleep 1
  done
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

serve_tcp() {
  port="$1"
  target="$2"
  label="$3"

  [ -n "$port" ] || return 0
  log "Configuring Tailscale Serve ${label}: tcp/${port} -> tcp://${target}"
  tailscale --socket="$TS_SOCKET" serve --bg --tcp="$port" "tcp://${target}"
}

REGION_RAW="${BUNNYNET_MC_REGION:-unknown}"
REGION="$(printf '%s' "$REGION_RAW" | tr '[:upper:]' '[:lower:]')"

: "${TS_STATE_DIR:=/var/lib/tailscale}"
: "${TS_SOCKET:=/tmp/tailscaled.sock}"
: "${TS_SOCKS5_SERVER:=127.0.0.1:1055}"
: "${TS_WAIT_TIMEOUT:=60s}"
: "${TS_SOCKET_WAIT_SECONDS:=30}"
: "${TS_SOCKS_WAIT_SECONDS:=30}"
: "${TS_EXTRA_ARGS:=--accept-dns=true}"
: "${TS_HOSTNAME:=kanidm-${REGION}}"
: "${TS_SERVE_PORT:=8444}"
: "${TS_SERVE_TARGET:=127.0.0.1:8444}"
: "${TS_LDAP_SERVE_PORT:=}"

if [ -n "$TS_LDAP_SERVE_PORT" ]; then
  : "${TS_LDAP_SERVE_TARGET:=127.0.0.1:3636}"
else
  : "${TS_LDAP_SERVE_TARGET:=}"
fi

SOCKS_HOST="${TS_SOCKS5_SERVER%:*}"
SOCKS_PORT="${TS_SOCKS5_SERVER##*:}"

log "Starting Bunny Tailscale sidecar"
log "region=${REGION_RAW}"
log "hostname=${TS_HOSTNAME}"
log "state_dir=${TS_STATE_DIR}"
log "socket=${TS_SOCKET}"
log "socks5=${TS_SOCKS5_SERVER}"
log "serve_replication=${TS_SERVE_PORT:-disabled} -> ${TS_SERVE_TARGET:-disabled}"
log "serve_ldaps=${TS_LDAP_SERVE_PORT:-disabled} -> ${TS_LDAP_SERVE_TARGET:-disabled}"
log "authkey=$(redact_state "${TS_AUTHKEY:-}")"
log "extra_args=${TS_EXTRA_ARGS}"

mkdir -p "$TS_STATE_DIR"
rm -f "$TS_SOCKET"

tailscaled \
  --tun=userspace-networking \
  --statedir="$TS_STATE_DIR" \
  --socket="$TS_SOCKET" \
  --socks5-server="$TS_SOCKS5_SERVER" &

TAILSCALED_PID="$!"

cleanup() {
  log "Stopping tailscaled"
  kill "$TAILSCALED_PID" >/dev/null 2>&1 || true
  wait "$TAILSCALED_PID" >/dev/null 2>&1 || true
}

trap cleanup INT TERM

wait_for_socket "$TS_SOCKET" "$TS_SOCKET_WAIT_SECONDS"

log "Trying tailscale up with persisted state"
# shellcheck disable=SC2086
if tailscale --socket="$TS_SOCKET" up --hostname="$TS_HOSTNAME" $TS_EXTRA_ARGS; then
  log "Tailscale up succeeded without TS_AUTHKEY"
elif [ -n "${TS_AUTHKEY:-}" ]; then
  log "Persisted-state tailscale up failed; retrying with TS_AUTHKEY"
  # shellcheck disable=SC2086
  tailscale --socket="$TS_SOCKET" up --auth-key="$TS_AUTHKEY" --hostname="$TS_HOSTNAME" $TS_EXTRA_ARGS || {
    tailscale --socket="$TS_SOCKET" status || true
    die "tailscale up failed with persisted state and TS_AUTHKEY"
  }
else
  tailscale --socket="$TS_SOCKET" status || true
  die "tailscale up failed with persisted state and TS_AUTHKEY is unset"
fi

log "Waiting for Tailscale running state"
tailscale --socket="$TS_SOCKET" wait --timeout="$TS_WAIT_TIMEOUT"

wait_for_tcp "$SOCKS_HOST" "$SOCKS_PORT" "$TS_SOCKS_WAIT_SECONDS" "SOCKS5 listener"

serve_tcp "$TS_SERVE_PORT" "$TS_SERVE_TARGET" "replication"
serve_tcp "$TS_LDAP_SERVE_PORT" "$TS_LDAP_SERVE_TARGET" "ldaps"

log "Tailscale status:"
tailscale --socket="$TS_SOCKET" status || true

log "Tailscale Serve status:"
tailscale --socket="$TS_SOCKET" serve status || true

log "Bunny Tailscale sidecar ready"
wait "$TAILSCALED_PID"
