# =============================================================================
# frontend/Dockerfile — MULTI-STAGE build
# =============================================================================
#
#   STAGE 1 "build"    node:20-alpine
#                      npm ci, vite build  ->  /app/dist  (static files)
#                      ~400 MB of Node, npm, and 300 packages
#                              |
#                              |  ONLY /app/dist is copied forward
#                              v
#   STAGE 2 "runtime"  nginx-unprivileged:alpine
#                      serves those files    ->  ~45 MB final image
#
# The Node toolchain never reaches production. That is a ~90% size reduction,
# and more importantly it removes npm, the package cache, and every build
# dependency from the running container's attack surface.
#
# Build:  docker build -t jollof-frontend:local ./frontend
# Run:    docker run -p 8080:8080 jollof-frontend:local
# =============================================================================


# =============================================================================
# STAGE 1 — build
# =============================================================================
FROM node:20-alpine AS build

WORKDIR /app

# -----------------------------------------------------------------------------
# Dependencies first, source second — the layer-caching rule again.
# Editing a component reuses the cached npm install and rebuilds in seconds.
# -----------------------------------------------------------------------------
COPY package.json package-lock.json* ./

# -----------------------------------------------------------------------------
# `npm ci` vs `npm install`:
#
#   npm install  may UPDATE package-lock.json to satisfy ranges in package.json.
#                Two builds a week apart can install different versions.
#   npm ci       installs EXACTLY what the lockfile says, deletes node_modules
#                first, and fails outright if the lockfile disagrees with
#                package.json. Reproducible, and faster.
#
# Always npm ci in a Dockerfile.
#
# The `||` fallback exists only because package-lock.json is generated on the
# first `npm install` and may not be committed yet. Once it is committed, the
# fallback never runs. Remove it if you want the build to fail loudly instead.
# -----------------------------------------------------------------------------
RUN npm ci --no-audit --no-fund || npm install --no-audit --no-fund

COPY . .

# Vite compiles JSX, bundles, minifies, and writes hashed filenames to /app/dist
RUN npm run build


# =============================================================================
# STAGE 2 — runtime
# =============================================================================
# nginx-unprivileged rather than the standard nginx image:
#   - runs as UID 101, not root
#   - listens on 8080 by default (a non-root process cannot bind port 80)
#   - writes its pid and temp files to paths a non-root user owns
#
# Doing this by hand on the standard nginx image means overriding the pid path,
# four temp paths, and chowning the cache directories. Using the image that is
# already built for it is simply less to get wrong.
# =============================================================================
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime

# Copy our server config over the default one.
COPY nginx.conf /etc/nginx/conf.d/default.conf

# The security-header snippet, included by every location block in nginx.conf.
# It lives OUTSIDE conf.d/ on purpose: nginx's main config does
# `include /etc/nginx/conf.d/*.conf` into the http block, so a file placed
# there would be loaded as a top-level config as well as being included —
# applying the headers twice and duplicating every one of them.
COPY security-headers.conf /etc/nginx/security-headers.conf

# -----------------------------------------------------------------------------
# THE ONLY THING CARRIED FORWARD FROM STAGE 1.
# /app/node_modules, the npm cache, and Node itself are all left behind.
# -----------------------------------------------------------------------------
COPY --from=build /app/dist /usr/share/nginx/html

# Documentation only — EXPOSE does not publish anything. The Kubernetes Service
# maps port 80 to this targetPort 8080.
EXPOSE 8080

# Kubernetes ignores this and uses the probes in frontend-deployment.yaml, but
# it makes `docker run` and docker-compose behave sensibly.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:8080/healthz || exit 1

# Exec form so nginx is PID 1 and receives SIGTERM directly. `daemon off;`
# keeps it in the foreground — a container whose main process daemonises exits
# immediately, and the pod CrashLoopBackOffs with no error message at all.
CMD ["nginx", "-g", "daemon off;"]
