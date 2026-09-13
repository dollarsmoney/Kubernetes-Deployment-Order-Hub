# =============================================================================
# backend/Dockerfile — FastAPI on Python 3.12
# =============================================================================
# Single-stage: Python needs its interpreter and site-packages at runtime, so
# there is much less to gain from a multi-stage build than there is for the
# frontend (where the Node toolchain is thrown away entirely).
#
# Build:  docker build -t jollof-backend:local ./backend
# Run:    docker run -p 8000:8000 -e DATABASE_URL=... jollof-backend:local
# =============================================================================

FROM python:3.12-slim-bookworm

# -----------------------------------------------------------------------------
# Why -slim and not :latest or :alpine
# -----------------------------------------------------------------------------
#   python:3.12         ~1 GB   full Debian, build tools, docs
#   python:3.12-slim    ~150 MB Debian minus the extras          <- this
#   python:3.12-alpine  ~50 MB  musl libc
#
# Alpine looks tempting and is usually the wrong choice for Python: musl breaks
# manylinux wheels, so pip compiles from source instead of downloading a
# prebuilt binary. Builds go from 20 seconds to several minutes, and psycopg2
# then needs gcc and libpq-dev in the image.
#
# `latest` is never pinned. A rebuild six months from now would silently pull
# a different Python.
#
# -----------------------------------------------------------------------------
# WHY THE EXPLICIT -bookworm SUFFIX
# -----------------------------------------------------------------------------
# Bare `python:3.12-slim` follows whatever Debian release upstream currently
# considers default, which moved to trixie (13). That image ships perl-base
# 5.40.1-6, which carries a CRITICAL with a fix already published
# (5.40.1-6+deb13u1) that the published image has not been rebuilt against
# yet — so the Trivy image gate fails on a CVE we cannot fix from here.
#
# Pinning the codename keeps Python at 3.12 and puts the OS on Debian 12,
# which scans clean today. It also stops the base OS from changing underneath
# a rebuild, which the paragraph above already argues for on the Python side.
#
# If the trixie image is rebuilt with the fix, dropping the suffix again is a
# one-word change. The alternative — `apt-get upgrade` at build time — was not
# taken: it makes builds non-reproducible and trips hadolint DL3005.
# -----------------------------------------------------------------------------

# PYTHONDONTWRITEBYTECODE  no .pyc files — pointless in an immutable container
# PYTHONUNBUFFERED         flush stdout immediately, so logs reach CloudWatch
#                          in real time instead of sitting in a 4KB buffer.
#                          Without this, `kubectl logs` looks empty on a
#                          low-traffic service and you chase a phantom bug.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# -----------------------------------------------------------------------------
# LAYER CACHING — copy requirements BEFORE the source
# -----------------------------------------------------------------------------
# Docker caches each instruction and invalidates every layer after the first
# change. Requirements change rarely; app.py changes constantly.
#
# Copying them separately means editing app.py reuses the cached pip install
# and rebuilds in about a second. Copying everything at once would reinstall
# every dependency on every source edit.
#
# This ordering is the single highest-value Dockerfile habit there is.
# -----------------------------------------------------------------------------
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py db.py seed.sql ./

# -----------------------------------------------------------------------------
# RUN AS A NON-ROOT USER
# -----------------------------------------------------------------------------
# Containers run as root by DEFAULT. Root in a container is not root on the
# host, but it removes one whole layer of protection: a container escape, or a
# writable host mount, becomes far more damaging.
#
# UID 1000 is arbitrary but conventional. The matching runAsUser: 1000 in
# backend-deployment.yaml enforces this at the Kubernetes level too — belt and
# braces, since a deployment can override the image's USER.
# -----------------------------------------------------------------------------
RUN useradd --create-home --uid 1000 --shell /bin/false appuser \
    && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

# -----------------------------------------------------------------------------
# HEALTHCHECK
# -----------------------------------------------------------------------------
# Used by `docker run` and docker-compose. KUBERNETES IGNORES THIS ENTIRELY —
# it uses the livenessProbe/readinessProbe in the Deployment instead. Both are
# defined so the image behaves sensibly in either environment.
#
# urllib rather than curl, because curl is not in the slim image and adding it
# for a health check is 10 MB of attack surface for no reason.
# -----------------------------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/health', timeout=2).status == 200 else 1)"

# -----------------------------------------------------------------------------
# EXEC FORM, not shell form.
#
#   CMD ["uvicorn", ...]      -> uvicorn is PID 1, receives SIGTERM directly
#   CMD uvicorn ...           -> /bin/sh is PID 1 and does NOT forward signals
#
# With the shell form, `kubectl delete pod` sends SIGTERM, sh ignores it,
# nothing shuts down, and 30 seconds later Kubernetes SIGKILLs the container.
# Every rolling update then drops in-flight requests. This one bracket pair is
# the difference between graceful shutdown and not.
#
# --workers 1: one uvicorn worker per container. Scale with more PODS, not more
# processes inside a pod — that is what Kubernetes is for, and it keeps the
# connection-pool maths in db.py predictable.
# -----------------------------------------------------------------------------
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
