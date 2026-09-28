#!/usr/bin/env bash
###############################################################################
# PocketHost stack supervisor.
#
# Starts mothership -> edge daemon -> dashboard + a routing sidecar, then exits
# (killing the children) if any one of them dies, so the container's restart
# policy brings the whole stack back in a known order.
###############################################################################
set -Eeuo pipefail

# The edge daemon keeps a realtime (SSE) subscription to the mothership and the
# PocketBase JS SDK needs a global EventSource, which Node only exposes behind
# this flag (without it the mirror never syncs and instances never start).
export NODE_OPTIONS="${NODE_OPTIONS:-} --experimental-eventsource"

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

# The settings layer validates SSL_KEY/SSL_CERT at startup even when the in-stack
# TLS terminator is not used (Coolify's proxy terminates TLS here). Provide a
# wildcard self-signed pair so the paths resolve.
if [ ! -f "$PH_HOME_DIR/ssl/tls.key" ] || [ ! -f "$PH_HOME_DIR/ssl/tls.cert" ]; then
  APEX_FOR_CERT="${APEX_DOMAIN:-pockethost.local}"
  if openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
      -keyout "$PH_HOME_DIR/ssl/tls.key" -out "$PH_HOME_DIR/ssl/tls.cert" \
      -subj "/CN=*.${APEX_FOR_CERT}" \
      -addext "subjectAltName=DNS:*.${APEX_FOR_CERT},DNS:${APEX_FOR_CERT}" >/dev/null 2>&1; then
    log "generated self-signed certificate for *.${APEX_FOR_CERT}"
  else
    log "WARN: could not generate the self-signed certificate"
  fi
fi

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

# The mothership runs on a real PocketBase binary that is resolved from the
# local release cache, so the cache must be populated before anything starts.
# `pocketbase update` downloads the latest patch of each allowed minor version;
# its follow-up catalogue sync fails until the mothership and its admin exist,
# which is harmless here and repeated once the stack is up.
if [ "${PH_PREFETCH_VERSIONS:-true}" = "true" ]; then
  log "prefetching PocketBase releases (${PH_ALLOWED_POCKETBASE_SEMVER:-default range})"
  $NODE_BIN pocketbase update || log "WARN: PocketBase prefetch failed"
fi

# Apply the mothership schema before the first boot. PocketBase triggers
# onBootstrap BEFORE running migrations, and the mothership's own onBootstrap
# hook queries its collections — a fresh database therefore boot-fails
# ("no such table: instances") unless the schema exists first. `migrate up` is
# idempotent; --hooksDir points at an empty dir so no hooks run during this step.
MOTHERSHIP_DB_DIR="${DATA_ROOT:-$PH_HOME_DIR/data}/mothership/pb_data"
PB_BIN="$(ls -1 "$PH_HOME_DIR"/pocketbase/*/linux_amd64/pocketbase 2>/dev/null | sort -V | tail -1)"
if [ -n "${PB_BIN:-}" ]; then
  mkdir -p "$MOTHERSHIP_DB_DIR" /tmp/empty-hooks

  # First pass: creates the database and applies PocketBase's built-in
  # migrations. It stops at the schema snapshot migration because a brand-new
  # PocketBase database already contains a default non-system `users`
  # collection, and the snapshot creates its own customized `users`.
  "$PB_BIN" migrate up \
    --dir "$MOTHERSHIP_DB_DIR" \
    --migrationsDir "$PKG_DIR/src/mothership-app/pb_migrations" \
    --hooksDir /tmp/empty-hooks >"$PH_HOME_DIR/migrate1.log" 2>&1 || true

  DB_FILE="$MOTHERSHIP_DB_DIR/data.db"
  if [ -f "$DB_FILE" ]; then
    SNAPSHOT_APPLIED="$(sqlite3 "$DB_FILE" "select count(*) from _migrations where file like '%collections_snapshot%'" 2>/dev/null || echo 0)"
    if [ "${SNAPSHOT_APPLIED:-0}" = "0" ]; then
      USERS_ROWS="$(sqlite3 "$DB_FILE" "select count(*) from users" 2>/dev/null || echo 0)"
      if [ "${USERS_ROWS:-0}" = "0" ]; then
        sqlite3 "$DB_FILE" "delete from _collections where name='users' and system=0;" >/dev/null 2>&1 || true
        sqlite3 "$DB_FILE" "drop table if exists users;" >/dev/null 2>&1 || true
        log "removed PocketBase's default empty users collection (schema snapshot recreates it)"
      fi
    fi
  fi

  if "$PB_BIN" migrate up \
      --dir "$MOTHERSHIP_DB_DIR" \
      --migrationsDir "$PKG_DIR/src/mothership-app/pb_migrations" \
      --hooksDir /tmp/empty-hooks >"$PH_HOME_DIR/migrate2.log" 2>&1; then
    log "mothership schema up to date"
  else
    log "WARN: mothership migrate failed:"
    tail -5 "$PH_HOME_DIR/migrate2.log" | sed 's/^/  /'
  fi
else
  log "WARN: no PocketBase binary cached, skipping schema migration"
fi

# The mothership admin is a PocketBase superuser of the central database, and
# the edge daemon authenticates with exactly these credentials, so it has to
# exist before the first boot. `superuser upsert` is idempotent.
if [ -n "${PB_BIN:-}" ] && [ -n "${MOTHERSHIP_ADMIN_USERNAME:-}" ] && [ -n "${MOTHERSHIP_ADMIN_PASSWORD:-}" ]; then
  if "$PB_BIN" superuser upsert "$MOTHERSHIP_ADMIN_USERNAME" "$MOTHERSHIP_ADMIN_PASSWORD" \
      --dir "$MOTHERSHIP_DB_DIR" >"$PH_HOME_DIR/superuser.log" 2>&1; then
    log "mothership superuser ready: $MOTHERSHIP_ADMIN_USERNAME"
  else
    log "WARN: could not create the mothership superuser:"
    tail -3 "$PH_HOME_DIR/superuser.log" | sed 's/^/  /'
  fi
fi

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

# Supervise: exit (and let the container restart policy bring the stack back in
# a known order) as soon as any *supervised* process dies. A plain `wait -n`
# would also return for short-lived helper jobs such as the prefetch below.
while true; do
  for p in "${pids[@]}"; do
    if ! kill -0 "$p" 2>/dev/null; then
      log "supervised process $p exited; restarting container"
      exit 0
    fi
  done
  sleep 3
done
