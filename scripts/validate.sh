#!/bin/sh
set -eu

failures=0

log() {
  printf '[validate] %s\n' "$*"
}

fail() {
  printf '[validate] ERROR: %s\n' "$*" >&2
  failures=$((failures + 1))
}

run_sh_syntax() {
  log "Checking shell syntax"
  for script in \
    images/kanidm-bunny/rootfs/usr/local/bin/generate-kanidm-config \
    images/kanidm-bunny/rootfs/usr/local/bin/run-kanidm-config \
    images/kanidm-bunny/rootfs/usr/local/bin/run-kanidm-server \
    images/kanidm-bunny/rootfs/usr/local/bin/run-kanidm-ops-api \
    images/kanidm-bunny/rootfs/usr/local/bin/finish-kanidm-server \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-config/up \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-server/run \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-server/finish \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-ops-api/run \
    images/tailscale-sidecar/entrypoint.sh \
    images/socat-forwarder/entrypoint.sh \
    scripts/build-all.sh \
    scripts/validate.sh
  do
    sh -n "$script" || fail "sh -n failed for $script"
  done
}

run_shellcheck() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    log "Skipping shellcheck; command not found"
    return 0
  fi

  log "Running shellcheck"
  shellcheck \
    images/kanidm-bunny/rootfs/usr/local/bin/generate-kanidm-config \
    images/kanidm-bunny/rootfs/usr/local/bin/run-kanidm-config \
    images/kanidm-bunny/rootfs/usr/local/bin/run-kanidm-server \
    images/kanidm-bunny/rootfs/usr/local/bin/run-kanidm-ops-api \
    images/kanidm-bunny/rootfs/usr/local/bin/finish-kanidm-server \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-config/up \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-server/run \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-server/finish \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-ops-api/run \
    images/tailscale-sidecar/entrypoint.sh \
    images/socat-forwarder/entrypoint.sh \
    scripts/build-all.sh \
    scripts/validate.sh || fail "shellcheck reported issues"
}

validate_renovate_json() {
  if command -v python3 >/dev/null 2>&1; then
    log "Parsing renovate.json with python3"
    python3 -m json.tool renovate.json >/dev/null || fail "python3 could not parse renovate.json"
    return 0
  fi

  if command -v jq >/dev/null 2>&1; then
    log "Parsing renovate.json with jq"
    jq empty renovate.json || fail "jq could not parse renovate.json"
    return 0
  fi

  log "Skipping renovate.json parse; python3 and jq are not available"
}

validate_github_actions_yaml() {
  if ! command -v python3 >/dev/null 2>&1; then
    log "Skipping GitHub Actions YAML parse; python3 is not available"
    return 0
  fi

  if ! python3 -c 'import yaml' >/dev/null 2>&1; then
    log "Skipping GitHub Actions YAML parse; python yaml module is not available"
    return 0
  fi

  log "Parsing GitHub Actions YAML with python yaml"
  python3 -c 'import pathlib, yaml; [yaml.safe_load(path.read_text()) for path in pathlib.Path(".github/workflows").glob("*.yml")]' \
    || fail "python yaml could not parse GitHub Actions workflows"
}

run_go_tests() {
  if ! command -v go >/dev/null 2>&1; then
    log "Skipping Go tests; go command not found"
    return 0
  fi

  log "Running Go tests for kanidm ops API"
  (cd images/kanidm-bunny/ops-api && GOCACHE="${GOCACHE:-/tmp/bunny-kanidm-go-cache}" go test ./...) \
    || fail "go test failed for kanidm ops API"
}

validate_s6_layout() {
  log "Checking s6 service layout"

  for path in \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-config/type \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-config/up \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-server/type \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-server/run \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-server/finish \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-server/dependencies.d/kanidm-config \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-ops-api/type \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-ops-api/run \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-ops-api/dependencies.d/kanidm-config \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/kanidm-config \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/kanidm-server \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/kanidm-ops-api
  do
    [ -e "$path" ] || fail "missing s6 file $path"
  done

  for path in \
    images/kanidm-bunny/rootfs/usr/local/bin/generate-kanidm-config \
    images/kanidm-bunny/rootfs/usr/local/bin/run-kanidm-config \
    images/kanidm-bunny/rootfs/usr/local/bin/run-kanidm-server \
    images/kanidm-bunny/rootfs/usr/local/bin/run-kanidm-ops-api \
    images/kanidm-bunny/rootfs/usr/local/bin/finish-kanidm-server \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-config/up \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-server/run \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-server/finish \
    images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-ops-api/run
  do
    [ -x "$path" ] || fail "not executable: $path"
  done

  grep -qx 'oneshot' images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-config/type \
    || fail "kanidm-config must be oneshot"
  grep -qx 'longrun' images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-server/type \
    || fail "kanidm-server must be longrun"
  grep -qx 'longrun' images/kanidm-bunny/rootfs/etc/s6-overlay/s6-rc.d/kanidm-ops-api/type \
    || fail "kanidm-ops-api must be longrun"
}

run_sh_syntax
run_shellcheck
validate_renovate_json
validate_github_actions_yaml
run_go_tests
validate_s6_layout

if [ "$failures" -ne 0 ]; then
  fail "$failures validation check(s) failed"
  exit 1
fi

log "Validation completed"
