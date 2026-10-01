#!/usr/bin/env bash
set -Eeuo pipefail

cd /home/container

expected_startup='/opt/spz-grafana/start.sh'
configured_startup="${STARTUP:-$expected_startup}"
if [[ "$configured_startup" != "$expected_startup" ]]; then
  printf '[spz-grafana] ERROR: Egg STARTUP must be %s (received an unsupported command).\n' "$expected_startup" >&2
  exit 1
fi

if [[ ! "${SERVER_PORT:-}" =~ ^[0-9]+$ ]] || (( 10#${SERVER_PORT:-0} < 1 || 10#${SERVER_PORT:-0} > 65535 )); then
  printf '[spz-grafana] ERROR: Pterodactyl must provide SERVER_PORT for the primary allocation.\n' >&2
  exit 1
fi

export GF_SERVER_HTTP_ADDR="${GF_SERVER_HTTP_ADDR:-0.0.0.0}"
export GF_SERVER_HTTP_PORT="${SERVER_PORT}"
printf '[spz-grafana] Pterodactyl allocation: %s:%s\n' "$GF_SERVER_HTTP_ADDR" "$GF_SERVER_HTTP_PORT"
exec /bin/bash "$expected_startup"
