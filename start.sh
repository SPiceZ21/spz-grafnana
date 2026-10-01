  #!/usr/bin/env bash
  set -Eeuo pipefail

  APP_DIR="${SPZ_GRAFANA_APP_DIR:-/home/container}"
  CONTAINER_DIR="${PTERODACTYL_CONTAINER_DIR:-/home/container}"
  GRAFANA_USER="${GRAFANA_USER:-container}"
  DATA_DIR="${GF_PATHS_DATA:-${CONTAINER_DIR}/data}"
  PROVISIONING_DIR="${GF_PATHS_PROVISIONING:-${APP_DIR}/provisioning}"
  MAP_ENABLED="${TRACK_MAP_ENABLED:-true}"
  CHILD_PIDS=()
  declare -A CHILD_NAMES=()

  log() { printf '[spz-grafana] %s\n' "$*"; }
  fail() { log "ERROR: $*" >&2; exit 1; }
  require_value() { [[ -n "${!1:-}" ]] || fail "Required environment variable $1 is empty or unset"; }
  valid_port() { [[ "$2" =~ ^[0-9]+$ ]] && (( 10#$2 >= 1 && 10#$2 <= 65535 )) || fail "$1 must be a TCP port from 1 to 65535"; }

  GF_SERVER_HTTP_ADDR="${GF_SERVER_HTTP_ADDR:-0.0.0.0}"
  GF_SERVER_HTTP_PORT="${GF_SERVER_HTTP_PORT:-${SERVER_PORT:-}}"
  require_value GF_SERVER_HTTP_PORT
  valid_port GF_SERVER_HTTP_PORT "$GF_SERVER_HTTP_PORT"
  export GF_SERVER_HTTP_ADDR GF_SERVER_HTTP_PORT

  for key in SPZ_DB_HOST SPZ_DB_NAME SPZ_DB_USER SPZ_DB_PASSWORD GF_SECURITY_ADMIN_PASSWORD FIVEM_HOST; do require_value "$key"; done
  FIVEM_PORT="${FIVEM_PORT:-30120}"
  HEALTH_POLL_SECONDS="${HEALTH_POLL_SECONDS:-30}"
  valid_port FIVEM_PORT "$FIVEM_PORT"
  [[ "$HEALTH_POLL_SECONDS" =~ ^[0-9]+$ ]] && (( 10#$HEALTH_POLL_SECONDS >= 5 && 10#$HEALTH_POLL_SECONDS <= 86400 )) || fail 'HEALTH_POLL_SECONDS must be an integer from 5 to 86400'

  # The monitor uses HEALTH_DB_*; the datasource uses GF_DATABASE_HEALTH_*.
  # Each side can have separate users, while either family can supply defaults.
  HEALTH_DB_NAME="${HEALTH_DB_NAME:-${GF_DATABASE_HEALTH_NAME:-}}"
  HEALTH_DB_USER="${HEALTH_DB_USER:-${GF_DATABASE_HEALTH_USER:-}}"
  HEALTH_DB_PASSWORD="${HEALTH_DB_PASSWORD:-${GF_DATABASE_HEALTH_PASSWORD:-}}"
  HEALTH_DB_ADDRESS="${HEALTH_DB_HOST:-${GF_DATABASE_HEALTH_HOST:-}}"
  HEALTH_DB_PORT_EXPLICIT="${HEALTH_DB_PORT:+1}"
  require_value HEALTH_DB_NAME
  require_value HEALTH_DB_USER
  require_value HEALTH_DB_PASSWORD
  require_value HEALTH_DB_ADDRESS
  HEALTH_DB_PORT="${HEALTH_DB_PORT:-3306}"
  if [[ "$HEALTH_DB_ADDRESS" =~ ^\[([^]]+)\]:([0-9]+)$ ]]; then
    HEALTH_DB_HOST="${BASH_REMATCH[1]}"
    [[ -n "${HEALTH_DB_PORT_EXPLICIT:-}" ]] || HEALTH_DB_PORT="${BASH_REMATCH[2]}"
  elif [[ "$HEALTH_DB_ADDRESS" =~ ^([^:]+):([0-9]+)$ ]]; then
    HEALTH_DB_HOST="${BASH_REMATCH[1]}"
    [[ -n "${HEALTH_DB_PORT_EXPLICIT:-}" ]] || HEALTH_DB_PORT="${BASH_REMATCH[2]}"
  else
    HEALTH_DB_HOST="$HEALTH_DB_ADDRESS"
  fi
  valid_port HEALTH_DB_PORT "$HEALTH_DB_PORT"

  GF_DATABASE_HEALTH_HOST="${GF_DATABASE_HEALTH_HOST:-${HEALTH_DB_HOST}:${HEALTH_DB_PORT}}"
  GF_DATABASE_HEALTH_NAME="${GF_DATABASE_HEALTH_NAME:-$HEALTH_DB_NAME}"
  GF_DATABASE_HEALTH_USER="${GF_DATABASE_HEALTH_USER:-$HEALTH_DB_USER}"
  GF_DATABASE_HEALTH_PASSWORD="${GF_DATABASE_HEALTH_PASSWORD:-$HEALTH_DB_PASSWORD}"
  GF_SECURITY_ADMIN_USER="${GF_SECURITY_ADMIN_USER:-admin}"
  export FIVEM_PORT HEALTH_POLL_SECONDS HEALTH_DB_HOST HEALTH_DB_PORT HEALTH_DB_NAME HEALTH_DB_USER HEALTH_DB_PASSWORD
  export GF_DATABASE_HEALTH_HOST GF_DATABASE_HEALTH_NAME GF_DATABASE_HEALTH_USER GF_DATABASE_HEALTH_PASSWORD GF_SECURITY_ADMIN_USER
  GF_USERS_ALLOW_SIGN_UP="${GF_USERS_ALLOW_SIGN_UP:-false}"
  export GF_USERS_ALLOW_SIGN_UP
  export GF_PATHS_HOME="${GF_PATHS_HOME:-${APP_DIR}/grafana}" GF_PATHS_DATA="$DATA_DIR" GF_PATHS_PROVISIONING="$PROVISIONING_DIR"

  cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM
    log 'Stopping child processes'
    local pid
    for pid in "${CHILD_PIDS[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        if ! kill -TERM "$pid"; then log "ERROR: Failed to send SIGTERM to ${CHILD_NAMES[$pid]} (pid $pid)" >&2; exit_code=1; fi
      fi
    done
    for pid in "${CHILD_PIDS[@]}"; do
      if wait "$pid"; then :; else
        local child_status=$?
        if (( child_status != 143 && child_status != 130 )); then log "${CHILD_NAMES[$pid]} exited with status ${child_status}"; fi
      fi
    done
    log "Shutdown complete (exit ${exit_code})"
    exit "$exit_code"
  }
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  [[ -f "${APP_DIR}/tools/server-monitor.mjs" ]] || fail "Server monitor is missing from ${APP_DIR}/tools"
  [[ -f "${APP_DIR}/provisioning/dashboards/spz-race-analytics.json" ]] || fail 'Provisioned race dashboard JSON is missing'
  [[ -d "${APP_DIR}/public" ]] || fail 'Track-map public/ directory is missing'
  id "$GRAFANA_USER" >/dev/null 2>&1 || fail "Grafana runtime user '$GRAFANA_USER' does not exist in the image"

  mkdir -p "${DATA_DIR}/dashboards"
  chmod 0755 "$DATA_DIR" "${DATA_DIR}/dashboards"

  if [[ "$MAP_ENABLED" == 'true' ]]; then
    TRACK_MAP_PORT="${TRACK_MAP_PORT:-}"
    require_value TRACK_MAP_PORT
    valid_port TRACK_MAP_PORT "$TRACK_MAP_PORT"
    TRACK_MAP_PUBLIC_URL="${TRACK_MAP_PUBLIC_URL:-}"
    require_value TRACK_MAP_PUBLIC_URL
    export TRACK_MAP_PORT TRACK_MAP_ROOT="${APP_DIR}/public"
    log "Starting track map on 0.0.0.0:${TRACK_MAP_PORT} (${TRACK_MAP_PUBLIC_URL})"
    node "${APP_DIR}/tools/track-map-server.mjs" &
    map_pid=$!
    CHILD_PIDS+=("$map_pid")
    CHILD_NAMES["$map_pid"]='track-map'
    sleep 1
    kill -0 "$map_pid" 2>/dev/null || fail 'Track-map service exited during startup; inspect its [spz-track-map] log'
  elif [[ "$MAP_ENABLED" != 'false' ]]; then
    fail 'TRACK_MAP_ENABLED must be true or false'
  else
    TRACK_MAP_PUBLIC_URL="${TRACK_MAP_PUBLIC_URL:-http://localhost}"
    log 'Track map is disabled (TRACK_MAP_ENABLED=false)'
  fi

  dashboard_output="${DATA_DIR}/dashboards/spz-race-analytics.json"
  node "${APP_DIR}/tools/prepare-dashboard.mjs" \
    "${APP_DIR}/provisioning/dashboards/spz-race-analytics.json" \
    "$dashboard_output" "$TRACK_MAP_PUBLIC_URL" || fail 'Could not prepare the dashboard for this Pterodactyl server'
  chmod 0644 "$dashboard_output"

  log "Starting FiveM health monitor for ${FIVEM_HOST}:${FIVEM_PORT} (poll interval ${HEALTH_POLL_SECONDS}s)"
  node "${APP_DIR}/tools/server-monitor.mjs" &
  monitor_pid=$!
  CHILD_PIDS+=("$monitor_pid")
  CHILD_NAMES["$monitor_pid"]='server-monitor'
  sleep 1
  kill -0 "$monitor_pid" 2>/dev/null || fail 'FiveM server monitor exited during startup; inspect its [spz-server-monitor] log'

  export GF_SERVER_HTTP_ADDR GF_SERVER_HTTP_PORT
  log "Starting Grafana on ${GF_SERVER_HTTP_ADDR}:${GF_SERVER_HTTP_PORT}; dashboard directory ${DATA_DIR}/dashboards"

  if command -v grafana >/dev/null 2>&1; then
    grafana_bin="$(command -v grafana)"
  elif command -v grafana-server >/dev/null 2>&1; then
    grafana_bin="$(command -v grafana-server)"
  else
    fail 'Neither grafana nor grafana-server is available in PATH'
  fi

  if [[ "${grafana_bin##*/}" == 'grafana' ]]; then
    "$grafana_bin" server \
      --homepath="$GF_PATHS_HOME" --config="${GF_PATHS_CONFIG:-${GRAFANA_DIR}/conf/defaults.ini}" --packaging=docker &
  else
    "$grafana_bin" \
      --homepath="$GF_PATHS_HOME" --config="${GF_PATHS_CONFIG:-${GRAFANA_DIR}/conf/defaults.ini}" --packaging=docker &
  fi
  grafana_pid=$!
  CHILD_PIDS+=("$grafana_pid")
  CHILD_NAMES["$grafana_pid"]='grafana'

  set +e
  wait -n -p exited_pid "${CHILD_PIDS[@]}"
  process_status=$?
  set -e
  process_name="${CHILD_NAMES[$exited_pid]:-unknown process}"
  if [[ "$exited_pid" == "$grafana_pid" ]]; then
    log "Grafana exited with status ${process_status}"
    exit "$process_status"
  fi
  log "ERROR: ${process_name} exited unexpectedly with status ${process_status}; stopping the server"
  exit 1
