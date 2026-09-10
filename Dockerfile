# syntax=docker/dockerfile:1
#
# Build context is this directory (bxThreads/). Build with:
#
#   docker build -t bxthreads .

# --- Static assets -----------------------------------------------------------
# Minified once here rather than at container start — app.bxs's own asset-manifest detection
# (see its app.locals.assets block) just falls back to the unminified files if this stage's
# output isn't present, so this stage existing at all is what makes production actually serve
# the minified/bundled CSS+JS instead of the raw dev files.
FROM node:20-alpine AS assets
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY public ./public
COPY scripts ./scripts
RUN npm run build

# --- BoxLang module dependencies ----------------------------------------------
# CommandBox's `box install`, not BVM's install-bx-module — confirmed directly (2026-09-10) that
# install-bx-module fails inside ortussolutions/boxlang:cli with "Helper scripts not found",
# the same error this project's own dev machine hits calling it directly; `box install` has no
# such problem and is what setup.bxs itself already uses as its fallback path.
#
# boxlang-express is ForgeBox-published as of 2026-09-10 (confirmed directly: `box install`
# fetches 0.2.9, matching box.json, with the real STOMP onSend hook and cluster support present —
# not a stale version) — installed like every other dependency here, no special-casing needed.
FROM ortussolutions/commandbox:latest AS deps
WORKDIR /app
COPY box.json ./
RUN box install --production

# --- Runtime image -------------------------------------------------------------
FROM ortussolutions/boxlang:cli
WORKDIR /app

COPY --from=deps /app/boxlang_modules ./boxlang_modules
COPY . .
COPY --from=assets /app/public ./public

# .cache/img-thumbs (models/services/ImageProxyService.bx) is a per-instance, rebuildable
# thumbnail cache with its own daily prune job (app.bxs) — created here so the app never needs to
# create its own top-level directory at runtime. k8s/deployment.yaml mounts an emptyDir over it
# rather than letting it grow inside the container's writable layer.
RUN mkdir -p .cache/img-thumbs

RUN chmod +x docker/entrypoint.sh

ENV APP_ENV=production
EXPOSE 3000

ENTRYPOINT [ "docker/entrypoint.sh" ]
