#!/bin/sh

env_file_log() {
  printf '[kanidm-config] %s\n' "$*"
}

env_file_die() {
  printf '[kanidm-config] ERROR: %s\n' "$*" >&2
  exit 1
}

env_file_is_set() {
  eval "[ \"\${$1+x}\" = x ]"
}

env_file_get() {
  eval "ENV_FILE_VALUE=\${$1-}"
}

decode_base64_to_file() {
  value="$1"
  dest="$2"
  clean_value=$(printf '%s' "$value" | tr -d '[:space:]')

  case "$clean_value" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=]*)
      return 1
      ;;
  esac

  if ! command -v base64 >/dev/null 2>&1; then
    env_file_die "base64 command is required to decode TLS material"
  fi

  if printf '%s' "$clean_value" | base64 -d > "$dest" 2>/dev/null; then
    return 0
  fi

  if printf '%s' "$clean_value" | base64 -D > "$dest" 2>/dev/null; then
    return 0
  fi

  return 1
}

write_env_file() {
  logical_name="$1"
  raw_env_name="$2"
  b64_env_name="$3"
  dest_path="$4"
  mode="$5"

  raw_is_set=false
  b64_is_set=false
  if env_file_is_set "$raw_env_name"; then
    raw_is_set=true
  fi
  if env_file_is_set "$b64_env_name"; then
    b64_is_set=true
  fi

  if [ "$raw_is_set" = true ] && [ "$b64_is_set" = true ]; then
    env_file_die "Set only one of ${raw_env_name} or ${b64_env_name}"
  fi
  if [ "$raw_is_set" != true ] && [ "$b64_is_set" != true ]; then
    return 0
  fi

  dest_dir=$(dirname "$dest_path")
  dest_base=$(basename "$dest_path")
  mkdir -p "$dest_dir"

  tmp_path="${dest_dir}/.${dest_base}.tmp.$$"
  rm -f "$tmp_path"

  if [ "$raw_is_set" = true ]; then
    env_file_get "$raw_env_name"
    if ! printf '%s' "$ENV_FILE_VALUE" > "$tmp_path"; then
      rm -f "$tmp_path"
      env_file_die "Failed to write ${logical_name} from ${raw_env_name}"
    fi
  else
    env_file_get "$b64_env_name"
    if ! decode_base64_to_file "$ENV_FILE_VALUE" "$tmp_path"; then
      rm -f "$tmp_path"
      env_file_die "Failed to decode ${b64_env_name}"
    fi
  fi

  if ! chmod "$mode" "$tmp_path"; then
    rm -f "$tmp_path"
    env_file_die "Failed to chmod ${logical_name} temporary file"
  fi
  if ! mv "$tmp_path" "$dest_path"; then
    rm -f "$tmp_path"
    env_file_die "Failed to install ${logical_name} at ${dest_path}"
  fi

  env_file_log "Wrote ${logical_name} from environment to ${dest_path}"
}
