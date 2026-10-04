#!/usr/bin/env bash
# Start Grafana. The only configuration is the race database (SPZ_DB_*) and
# the admin login; everything else comes from /etc/grafana/provisioning.
set -Eeuo pipefail

log()  { printf '[spz-grafana] %s
' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

for key in SPZ_DB_HOST SPZ_DB_NAME SPZ_DB_USER SPZ_DB_PASSWORD GF_SECURITY_ADMIN_PASSWORD; do
  [[ -n "${!key:-}" ]] || fail "Required environment variable $key is empty or unset"
done
export GF_SECURITY_ADMIN_USER="${GF_SECURITY_ADMIN_USER:-admin}"
export GF_USERS_ALLOW_SIGN_UP="${GF_USERS_ALLOW_SIGN_UP:-false}"
export GF_SERVER_HTTP_ADDR="${GF_SERVER_HTTP_ADDR:-0.0.0.0}"
export GF_SERVER_HTTP_PORT="${GF_SERVER_HTTP_PORT:-${SERVER_PORT:-3000}}"
export GF_PATHS_DATA="${GF_PATHS_DATA:-/home/container/data}"
export GF_PATHS_PROVISIONING="${GF_PATHS_PROVISIONING:-/etc/grafana/provisioning}"
mkdir -p "$GF_PATHS_DATA"

[[ -f "${GF_PATHS_PROVISIONING}/dashboards/spz-race-analytics.json" ]] || fail 'Dashboard JSON is missing from provisioning'

GF_HOME="${GF_PATHS_HOME:-/usr/share/grafana}"
GF_CONFIG="${GF_PATHS_CONFIG:-/etc/grafana/grafana.ini}"
log "Starting Grafana on ${GF_SERVER_HTTP_ADDR}:${GF_SERVER_HTTP_PORT}"
if command -v grafana >/dev/null 2>&1; then
  exec grafana server --homepath="$GF_HOME" --config="$GF_CONFIG" --packaging=docker
fi
exec grafana-server --homepath="$GF_HOME" --config="$GF_CONFIG" --packaging=docker
