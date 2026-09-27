#!/usr/bin/env bash
###############################################################################
# PocketHost stack supervisor.
#
# Starts mothership -> edge daemon -> dashboard + a routing sidecar, then exits
# (killing the children) if any one of them dies, so the container's restart
# policy brings the whole stack back in a known order.
###############################################################################
set -Eeuo pipefail

APP_DIR=/app
PH_HOME_DIR="${PH_HOME:-/data/pockethost}"
PKG_DIR="$APP_DIR/packages/pockethost"
INSTANCE_APP_SRC="$PKG_DIR/src/instance-app"

log() { printf '[entrypoint] %s\n' "$*"; }

pids=()
cleanup() {
  log "shutting down"
  for p in "${pids[@]:-}"; do
    kill "$p" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

###############################################################################
# 1. Shared data root.
#    Everything below lives in the host bind mount because the HOST docker
#    daemon resolves these paths when it starts an instance container.
###############################################################################
mkdir -p "$PH_HOME_DIR" "$PH_HOME_DIR/data" "$PH_HOME_DIR/ssl"

if [ -d "$INSTANCE_APP_SRC" ]; then
  rm -rf "$PH_HOME_DIR/instance-app.new"
  mkdir -p "$PH_HOME_DIR/instance-app.new"
  cp -a "$INSTANCE_APP_SRC/." "$PH_HOME_DIR/instance-app.new/"
  rm -rf "$PH_HOME_DIR/instance-app"
  mv "$PH_HOME_DIR/instance-app.new" "$PH_HOME_DIR/instance-app"
  log "instance templates staged at $PH_HOME_DIR/instance-app"
fi

###############################################################################
# 2. Processes
###############################################################################
cd "$PKG_DIR"
NODE_BIN="node --import tsx ./src/cli/index.ts"

log "mothership -> :${MOTHERSHIP_PORT:-8090}"
$NODE_BIN mothership serve &
MOTHERSHIP_PID=$!
pids+=("$MOTHERSHIP_PID")

for _ in $(seq 1 150); do
  if curl -fsS "http://127.0.0.1:${MOTHERSHIP_PORT:-8090}/api/health" >/dev/null 2>&1; then
    log "mothership healthy"
    break
  fi
  if ! kill -0 "$MOTHERSHIP_PID" 2>/dev/null; then
    log "ERROR: mothership exited during startup"
    exit 1
  fi
  sleep 2
done

log "edge daemon -> :${DAEMON_PORT:-3000}"
$NODE_BIN edge daemon serve &
pids+=("$!")

log "dashboard  -> :${DASHBOARD_PORT:-8080}"
node "$APP_DIR/docker/serve-static.mjs" &
pids+=("$!")

if [ "${PH_TRAEFIK_SYNC:-true}" = "true" ] && [ -d "${TRAEFIK_DYNAMIC_DIR:-/traefik-dynamic}" ]; then
  log "traefik route publisher -> ${TRAEFIK_DYNAMIC_DIR:-/traefik-dynamic}"
  node "$APP_DIR/docker/traefik-sync.mjs" &
  pids+=("$!")
else
  log "traefik route publisher disabled"
fi

# PocketBase release prefetch: populates the version catalog the dashboard
# offers when creating an instance. Runs in the background; instance creation
# falls back to an on-demand download if it has not finished yet.
if [ "${PH_PREFETCH_VERSIONS:-true}" = "true" ]; then
  ( sleep 15; $NODE_BIN pocketbase update || log "WARN: PocketBase version prefetch failed" ) &
fi

set +e
wait -n
log "a supervised process exited; restarting container"
exit 0
