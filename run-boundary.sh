#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN_FILE="${SCRIPT_DIR}/apha-integration-bridge-boundary.jmx"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/environments/dev.properties"

env_var_is_set() {
  local key="$1"
  env | LC_ALL=C grep -q "^${key}="
}

parse_env_file() {
  local env_file="$1"
  local line=""

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"

    [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue

    if [[ "${line}" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      local key="${BASH_REMATCH[2]}"
      local value="${BASH_REMATCH[3]}"

      if [[ "${value}" =~ ^\".*\"$ ]] || [[ "${value}" =~ ^\'.*\'$ ]]; then
        value="${value:1:${#value}-2}"
      fi

      if ! env_var_is_set "${key}"; then
        export "${key}=${value}"
      fi
    fi
  done < "${env_file}"
}

load_local_env_files() {
  local env_file=""
  local env_files=(
    "${SCRIPT_DIR}/secrets.env"
    "${SCRIPT_DIR}/.env"
    "${SCRIPT_DIR}/.env.local"
    "${SCRIPT_DIR}/.envrc"
  )

  for env_file in "${env_files[@]}"; do
    if [[ -f "${env_file}" ]]; then
      parse_env_file "${env_file}"
    fi
  done
}

java_major_version() {
  java -version 2>&1 | awk -F '"' '/version/ {print $2}' | awk -F. '{print $1}'
}

auto_select_compatible_java() {
  local current_major=""
  if command -v java >/dev/null 2>&1; then
    current_major="$(java_major_version)"
    if [[ -n "${current_major}" ]] && (( current_major <= 21 )); then
      return 0
    fi
  fi

  if [[ -x /usr/libexec/java_home ]]; then
    local candidate_home=""
    for version in 21 17; do
      candidate_home="$(
        /usr/libexec/java_home -v "${version}" 2>/dev/null || true
      )"
      if [[ -n "${candidate_home}" ]]; then
        export JAVA_HOME="${candidate_home}"
        export PATH="${JAVA_HOME}/bin:${PATH}"
        return 0
      fi
    done
  fi
}

maybe_install_compatible_java() {
  if [[ "${BRIDGE_PERF_AUTO_INSTALL_JAVA:-0}" != "1" ]]; then
    return 0
  fi

  if [[ -x /usr/libexec/java_home ]]; then
    if /usr/libexec/java_home -v 21 >/dev/null 2>&1 || /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
      return 0
    fi
  fi

  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required to auto-install Java but was not found on PATH." >&2
    exit 1
  fi

  echo "No compatible Java 21/17 found. Installing Temurin 21 with Homebrew..." >&2
  brew install --cask temurin@21
}

require_java_compatible() {
  if ! command -v java >/dev/null 2>&1; then
    echo "java is not installed or not on PATH" >&2
    exit 1
  fi

  local major
  major="$(java_major_version)"

  if [[ -z "${major}" ]]; then
    echo "Could not determine Java version. Set JAVA_HOME to Java 21 or 17." >&2
    exit 1
  fi

  if (( major > 21 )); then
    echo "Java ${major} detected. JMeter 5.6.3 in this repo should be run with Java 21 or 17." >&2
    echo "Install one of those versions, then rerun the command." >&2
    echo "Tip: BRIDGE_PERF_AUTO_INSTALL_JAVA=1 ./run-boundary.sh ..." >&2
    exit 1
  fi
}

has_explicit_auth_client_secret() {
  local arg=""

  for arg in "$@"; do
    case "${arg}" in
      -Jauth.client_secret=*)
        return 0
        ;;
    esac
  done

  return 1
}

env_name_for_file() {
  local env_file="$1"
  local env_name=""

  env_name="$(basename "${env_file}")"
  env_name="${env_name%.properties}"
  printf '%s\n' "${env_name}"
}

secret_value_for_env() {
  local env_name="$1"

  case "${env_name}" in
    dev)
      printf '%s\n' "${DEV_SECRET-}"
      ;;
    test)
      printf '%s\n' "${TEST_SECRET-}"
      ;;
    perf-test)
      printf '%s\n' "${PERF_SECRET-}"
      ;;
    preprod)
      if env_var_is_set PREPROD_SECRET; then
        printf '%s\n' "${PREPROD_SECRET-}"
      elif env_var_is_set PROD_SECRET; then
        printf '%s\n' "${PROD_SECRET-}"
      fi
      ;;
  esac
}

secret_arg_for_env() {
  local env_name="$1"
  shift
  local secret_value=""

  if has_explicit_auth_client_secret "$@"; then
    return 0
  fi

  secret_value="$(secret_value_for_env "${env_name}")"
  if [[ -n "${secret_value}" ]]; then
    printf '%s\n' "-Jauth.client_secret=${secret_value}"
  fi
}

if ! command -v jmeter >/dev/null 2>&1; then
  echo "jmeter is not installed or not on PATH" >&2
  exit 1
fi

load_local_env_files
maybe_install_compatible_java
auto_select_compatible_java
require_java_compatible

ENV_FILE="${1:-$DEFAULT_ENV_FILE}"
shift || true

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Environment properties file not found: ${ENV_FILE}" >&2
  exit 1
fi

mkdir -p "${SCRIPT_DIR}/results"

ENV_NAME="$(env_name_for_file "${ENV_FILE}")"
SECRET_ARG="$(secret_arg_for_env "${ENV_NAME}" "$@" || true)"

ARGS=()
if [[ -n "${SECRET_ARG}" ]]; then
  ARGS+=("${SECRET_ARG}")
fi
ARGS+=("$@")

exec jmeter -n -t "${PLAN_FILE}" -q "${ENV_FILE}" "${ARGS[@]}"
