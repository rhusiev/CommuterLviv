# The built UI, and the one process in front of everything. Caddy serves the
# files and passes `/api` and `/ws` back to the service, so the browser sees a
# single origin and the `__Host-` cookies work without any cross-origin rules.
#
# The build context is the repository root, because the Caddyfile lives beside
# this file and the app lives in `web/`.
FROM node:22-alpine AS build

WORKDIR /app
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web ./
RUN npm run build

FROM caddy:2-alpine

COPY deploy/Caddyfile /etc/caddy/Caddyfile
COPY --from=build /app/dist /srv
