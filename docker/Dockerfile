# syntax=docker/dockerfile:1
###############################################################################
# PocketHost — self-hosted single-service stack
#
# Runs the whole open-source PocketHost stack in one container, the way Coolify
# expects a deployable unit:
#
#   mothership   PocketBase control plane (:8090)  — holds users + instances
#   edge daemon  spawns one PocketBase container per instance and proxies to it
#                (:3000), talking to the HOST docker socket
#   dashboard    static SvelteKit control panel (:8080)
#
# The container mounts /var/run/docker.sock because PocketBase instances are
# real sibling containers on the host daemon, and /data/pockethost because
# instance data directories and the instance-app templates must exist at the
# SAME absolute path on the host (the host daemon resolves those bind mounts).
###############################################################################

FROM node:24-bookworm AS build

RUN corepack enable
WORKDIR /app

COPY . .
RUN pnpm install --frozen-lockfile

# The dashboard is a static SvelteKit build whose PUBLIC_* values are baked in
# at build time (see packages/dashboard/src/lib/appEnv.ts).
ARG PUBLIC_APEX_DOMAIN=pockethost.lvh.me
ARG PUBLIC_APP_URL=
ARG PUBLIC_MOTHERSHIP_URL=
ARG PUBLIC_HTTP_PROTOCOL=https:
ARG PUBLIC_DEBUG=false

RUN printf 'PUBLIC_APEX_DOMAIN=%s\nPUBLIC_APP_URL=%s\nPUBLIC_MOTHERSHIP_URL=%s\nPUBLIC_HTTP_PROTOCOL=%s\nPUBLIC_DEBUG=%s\n' \
      "$PUBLIC_APEX_DOMAIN" "$PUBLIC_APP_URL" "$PUBLIC_MOTHERSHIP_URL" "$PUBLIC_HTTP_PROTOCOL" "$PUBLIC_DEBUG" \
      > packages/dashboard/.env \
 && pnpm --filter @pockethost/dashboard build

FROM node:24-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl bash tini procps unzip openssl \
 && rm -rf /var/lib/apt/lists/*

# Docker CLI: the edge daemon also shells out to `docker` (container cleanup,
# watchdog) in addition to using the socket through dockerode.
COPY --from=docker:cli /usr/local/bin/docker /usr/local/bin/docker

WORKDIR /app
COPY --from=build /app /app
RUN corepack enable && chmod +x /app/docker/entrypoint.sh

ENV NODE_ENV=production \
    PH_HOME=/data/pockethost \
    DATA_ROOT=/data/pockethost/data \
    DASHBOARD_PORT=8080 \
    MOTHERSHIP_PORT=8090 \
    DAEMON_PORT=3000

EXPOSE 8090 3000 8080

ENTRYPOINT ["/usr/bin/tini", "--", "/app/docker/entrypoint.sh"]
