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
    images/kanidm-bunny/entrypoint.sh \
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
    images/kanidm-bunny/entrypoint.sh \
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

run_sh_syntax
run_shellcheck
validate_renovate_json
validate_github_actions_yaml

if [ "$failures" -ne 0 ]; then
  fail "$failures validation check(s) failed"
  exit 1
fi

log "Validation completed"
