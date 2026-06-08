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
    images/kanidm-bunny/rootfs/usr/local/lib/kanidm-env-files.sh \
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
    images/kanidm-bunny/rootfs/usr/local/lib/kanidm-env-files.sh \
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

  log "Running Go tests for kanidm cert helper"
  (cd images/kanidm-bunny/cert-helper && GOCACHE="${GOCACHE:-/tmp/bunny-kanidm-go-cache}" go test ./...) \
    || fail "go test failed for kanidm cert helper"
}

cert_helper_binary() {
  if ! command -v go >/dev/null 2>&1; then
    return 1
  fi

  helper_dir="${TMPDIR:-/tmp}/bunny-kanidm-cert-helper"
  helper_path="${helper_dir}/kanidm-cert-helper"
  mkdir -p "$helper_dir"
  if [ ! -x "$helper_path" ]; then
    (cd images/kanidm-bunny/cert-helper && GOCACHE="${GOCACHE:-/tmp/bunny-kanidm-go-cache}" go build -trimpath -o "$helper_path" .) \
      || return 1
  fi
  printf '%s' "$helper_path"
}

stat_mode() {
  if mode=$(stat -c '%a' "$1" 2>/dev/null); then
    printf '%s' "$mode"
    return 0
  fi
  if mode=$(stat -f '%Lp' "$1" 2>/dev/null); then
    printf '%s' "$mode"
    return 0
  fi
  return 1
}

base64_one_line() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

run_tls_env_file_test() {
  log "Testing TLS env file writer"

  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/bunny-kanidm-validate.XXXXXX")
  chain_path="${tmp_dir}/nested/chain.pem"
  key_path="${tmp_dir}/nested/key.pem"
  chain_value='-----BEGIN CERTIFICATE-----
dummy-chain
-----END CERTIFICATE-----
'
  key_value='-----BEGIN PRIVATE KEY-----
dummy-key
-----END PRIVATE KEY-----
'
  chain_b64=$(base64_one_line "$chain_value")
  key_b64=$(base64_one_line "$key_value")
  expected_chain_path="${tmp_dir}/expected-chain.pem"
  expected_key_path="${tmp_dir}/expected-key.pem"
  printf '%s' "$chain_value" > "$expected_chain_path"
  printf '%s' "$key_value" > "$expected_key_path"
  output=$(
    KANIDM_TLS_CHAIN_PEM_B64="$chain_b64"
    KANIDM_TLS_KEY_PEM_B64="$key_b64"
    export KANIDM_TLS_CHAIN_PEM_B64 KANIDM_TLS_KEY_PEM_B64
    . images/kanidm-bunny/rootfs/usr/local/lib/kanidm-env-files.sh
    write_env_file "TLS chain file" KANIDM_TLS_CHAIN_PEM KANIDM_TLS_CHAIN_PEM_B64 "$chain_path" 0644
    write_env_file "TLS key file" KANIDM_TLS_KEY_PEM KANIDM_TLS_KEY_PEM_B64 "$key_path" 0600
  ) || fail "TLS env file writer failed"

  [ -f "$chain_path" ] || fail "TLS chain file was not created"
  [ -f "$key_path" ] || fail "TLS key file was not created"
  cmp -s "$chain_path" "$expected_chain_path" || fail "TLS chain file content did not match"
  cmp -s "$key_path" "$expected_key_path" || fail "TLS key file content did not match"

  chain_mode=$(stat_mode "$chain_path" || true)
  key_mode=$(stat_mode "$key_path" || true)
  if [ -n "$chain_mode" ] && [ "$chain_mode" != 644 ]; then
    fail "TLS chain file mode is $chain_mode, expected 644"
  fi
  if [ -n "$key_mode" ] && [ "$key_mode" != 600 ]; then
    fail "TLS key file mode is $key_mode, expected 600"
  fi

  case "$output" in
    *dummy-chain*|*dummy-key*|*"BEGIN CERTIFICATE"*|*"BEGIN PRIVATE KEY"*|*"$chain_b64"*|*"$key_b64"*)
      fail "TLS env file writer printed secret material"
      ;;
  esac

  if (
    KANIDM_TLS_CHAIN_PEM="$chain_value"
    KANIDM_TLS_CHAIN_PEM_B64="$chain_b64"
    export KANIDM_TLS_CHAIN_PEM KANIDM_TLS_CHAIN_PEM_B64
    . images/kanidm-bunny/rootfs/usr/local/lib/kanidm-env-files.sh
    write_env_file "TLS chain file" KANIDM_TLS_CHAIN_PEM KANIDM_TLS_CHAIN_PEM_B64 "$chain_path" 0644
  ) >/dev/null 2>&1; then
    fail "TLS env file writer allowed raw and base64 values together"
  fi

  if (
    KANIDM_TLS_CHAIN_PEM_B64='not-base64!!'
    export KANIDM_TLS_CHAIN_PEM_B64
    . images/kanidm-bunny/rootfs/usr/local/lib/kanidm-env-files.sh
    write_env_file "TLS chain file" KANIDM_TLS_CHAIN_PEM KANIDM_TLS_CHAIN_PEM_B64 "$chain_path" 0644
  ) >/dev/null 2>&1; then
    fail "TLS env file writer accepted invalid base64"
  fi

  rm -rf "$tmp_dir"
}

run_self_signed_tls_test() {
  helper_path=$(cert_helper_binary || true)
  if [ -z "$helper_path" ]; then
    log "Skipping self-signed TLS validation; go command not found or helper build failed"
    return 0
  fi

  log "Testing self-signed TLS generation"

  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/bunny-kanidm-self-signed.XXXXXX")
  chain_path="${tmp_dir}/tls/chain.pem"
  key_path="${tmp_dir}/tls/key.pem"
  config_path="${tmp_dir}/server.toml"
  backup_path="${tmp_dir}/backups"
  generator="images/kanidm-bunny/rootfs/usr/local/bin/generate-kanidm-config"
  env_lib="images/kanidm-bunny/rootfs/usr/local/lib/kanidm-env-files.sh"

  output=$(
    CONFIG_PATH="$config_path"
    KANIDM_ENV_FILES_LIB="$env_lib"
    KANIDM_DOMAIN="idm.svee.eu"
    KANIDM_ORIGIN="https://idm.svee.eu"
    KANIDM_DB_PATH="${tmp_dir}/kanidm.db"
    KANIDM_TLS_CHAIN="$chain_path"
    KANIDM_TLS_KEY="$key_path"
    KANIDM_TLS_SELF_SIGNED_CN="idm.svee.eu"
    KANIDM_TLS_SELF_SIGNED_SAN="idm.svee.eu,login.svee.eu"
    KANIDM_ONLINE_BACKUP_PATH="$backup_path"
    KANIDM_CERT_HELPER="$helper_path"
    export CONFIG_PATH KANIDM_ENV_FILES_LIB KANIDM_DOMAIN KANIDM_ORIGIN KANIDM_DB_PATH
    export KANIDM_TLS_CHAIN KANIDM_TLS_KEY KANIDM_TLS_SELF_SIGNED_CN KANIDM_TLS_SELF_SIGNED_SAN
    export KANIDM_ONLINE_BACKUP_PATH KANIDM_CERT_HELPER
    "$generator"
  ) || fail "self-signed TLS generation failed for missing files"

  [ -f "$chain_path" ] || fail "self-signed TLS chain file was not created"
  [ -f "$key_path" ] || fail "self-signed TLS key file was not created"
  "$helper_path" check \
    --chain "$chain_path" \
    --key "$key_path" \
    --cn idm.svee.eu \
    --san idm.svee.eu,login.svee.eu \
    --renew-within-days 30 >/dev/null 2>&1 \
    || fail "self-signed TLS certificate is not valid beyond default threshold"

  chain_mode=$(stat_mode "$chain_path" || true)
  key_mode=$(stat_mode "$key_path" || true)
  if [ -n "$chain_mode" ] && [ "$chain_mode" != 644 ]; then
    fail "self-signed TLS chain file mode is $chain_mode, expected 644"
  fi
  if [ -n "$key_mode" ] && [ "$key_mode" != 600 ]; then
    fail "self-signed TLS key file mode is $key_mode, expected 600"
  fi

  first_cert_copy="${tmp_dir}/first-chain.pem"
  cp "$chain_path" "$first_cert_copy"
  (
    CONFIG_PATH="$config_path"
    KANIDM_ENV_FILES_LIB="$env_lib"
    KANIDM_DOMAIN="idm.svee.eu"
    KANIDM_ORIGIN="https://idm.svee.eu"
    KANIDM_DB_PATH="${tmp_dir}/kanidm.db"
    KANIDM_TLS_CHAIN="$chain_path"
    KANIDM_TLS_KEY="$key_path"
    KANIDM_TLS_SELF_SIGNED_CN="idm.svee.eu"
    KANIDM_TLS_SELF_SIGNED_SAN="idm.svee.eu,login.svee.eu"
    KANIDM_ONLINE_BACKUP_PATH="$backup_path"
    KANIDM_CERT_HELPER="$helper_path"
    export CONFIG_PATH KANIDM_ENV_FILES_LIB KANIDM_DOMAIN KANIDM_ORIGIN KANIDM_DB_PATH
    export KANIDM_TLS_CHAIN KANIDM_TLS_KEY KANIDM_TLS_SELF_SIGNED_CN KANIDM_TLS_SELF_SIGNED_SAN
    export KANIDM_ONLINE_BACKUP_PATH KANIDM_CERT_HELPER
    "$generator"
  ) >/dev/null || fail "self-signed TLS second run failed"
  if ! cmp -s "$chain_path" "$first_cert_copy"; then
    fail "self-signed TLS second run did not reuse non-expiring certificate"
  fi

  printf '%s\n' "not a certificate" > "$chain_path"
  (
    CONFIG_PATH="$config_path"
    KANIDM_ENV_FILES_LIB="$env_lib"
    KANIDM_DOMAIN="idm.svee.eu"
    KANIDM_ORIGIN="https://idm.svee.eu"
    KANIDM_DB_PATH="${tmp_dir}/kanidm.db"
    KANIDM_TLS_CHAIN="$chain_path"
    KANIDM_TLS_KEY="$key_path"
    KANIDM_TLS_SELF_SIGNED_CN="idm.svee.eu"
    KANIDM_TLS_SELF_SIGNED_SAN="idm.svee.eu,login.svee.eu"
    KANIDM_ONLINE_BACKUP_PATH="$backup_path"
    KANIDM_CERT_HELPER="$helper_path"
    export CONFIG_PATH KANIDM_ENV_FILES_LIB KANIDM_DOMAIN KANIDM_ORIGIN KANIDM_DB_PATH
    export KANIDM_TLS_CHAIN KANIDM_TLS_KEY KANIDM_TLS_SELF_SIGNED_CN KANIDM_TLS_SELF_SIGNED_SAN
    export KANIDM_ONLINE_BACKUP_PATH KANIDM_CERT_HELPER
    "$generator"
  ) >/dev/null || fail "self-signed TLS regeneration failed for unparsable cert"
  "$helper_path" check \
    --chain "$chain_path" \
    --key "$key_path" \
    --cn idm.svee.eu \
    --san idm.svee.eu,login.svee.eu \
    --renew-within-days 30 >/dev/null 2>&1 \
    || fail "self-signed TLS regeneration did not replace unparsable cert"

  case "$output" in
    *"BEGIN PRIVATE KEY"*|*"BEGIN EC PRIVATE KEY"*|*"BEGIN RSA PRIVATE KEY"*)
      fail "self-signed TLS generation printed private key material"
      ;;
  esac

  rm -rf "$tmp_dir"
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
    images/kanidm-bunny/rootfs/usr/local/lib/kanidm-env-files.sh \
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
run_tls_env_file_test
run_self_signed_tls_test
validate_s6_layout

if [ "$failures" -ne 0 ]; then
  fail "$failures validation check(s) failed"
  exit 1
fi

log "Validation completed"
