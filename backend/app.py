"""
app.py — the Jollof Run API.

A deliberately small FastAPI service. Its job in this project is to be the
thing that proves the infrastructure works:

  - it reaches RDS, using credentials it never had baked in
  - it is reachable ONLY through the frontend's nginx, never from the internet
  - it is the target of the WAF SQL-injection test in Phase 9

Endpoints:
    GET /health              liveness  — no database access
    GET /health/ready        readiness — checks the database
    GET /restaurants         list, with optional ?search=
    GET /restaurants/{id}    one restaurant, with its menu
    GET /foods               list, with optional ?restaurant_id= / ?category=
    GET /categories          distinct food categories
"""

from __future__ import annotations

import logging
import os
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

import db

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
# Log to STDOUT, not to a file.
#
# This is the twelve-factor rule and it matters concretely here: the Container
# Insights agent collects each container's stdout/stderr and ships it to the
# CloudWatch log group /aws/containerinsights/jollof-run/application. A log
# file inside the container is invisible to that pipeline and dies with the pod.
# -----------------------------------------------------------------------------

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)-8s %(name)s %(message)s",
)
log = logging.getLogger("jollof.api")


# -----------------------------------------------------------------------------
# Startup / shutdown
# -----------------------------------------------------------------------------


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Runs once when the process starts, and again on shutdown.

    Schema initialisation is retried because on a cold `terraform apply` the
    pods can be Running before RDS has finished becoming available. Without the
    retry the pod crash-loops for a few minutes and looks broken when it is
    merely early.

    Note that we do NOT swallow a permanent failure. If the database is still
    unreachable after all attempts, the exception propagates, the process dies,
    and Kubernetes restarts it — which is exactly the right behaviour. A pod
    that starts successfully but cannot serve requests is worse than one that
    visibly fails.
    """
    attempts = 10
    for attempt in range(1, attempts + 1):
        try:
            db.init_schema()
            log.info("Database ready")
            break
        except Exception as exc:  # broad by design: any startup failure should retry
            if attempt == attempts:
                log.error("Database unreachable after %d attempts", attempts)
                raise
            wait = min(2**attempt, 30)  # exponential backoff, capped
            log.warning(
                "Database not ready (attempt %d/%d): %s — retrying in %ds",
                attempt,
                attempts,
                exc,
                wait,
            )
            time.sleep(wait)

    yield

    log.info("Shutting down")


app = FastAPI(
    title="Jollof Run API",
    description="Restaurant and food discovery for the Jollof Run platform.",
    version="1.0.0",
    lifespan=lifespan,
)


# -----------------------------------------------------------------------------
# CORS
# -----------------------------------------------------------------------------
# In the deployed architecture the browser NEVER calls this service directly —
# nginx in the frontend pod proxies /api/* to backend-service, so every request
# the browser makes is same-origin and CORS never comes into play.
#
# It is enabled here purely for local development, where Vite serves on :5173
# and this runs on :8000, which ARE different origins.
#
# CORS_ORIGINS defaults to the Vite dev server. It is NOT "*" — a wildcard here
# would be a habit worth not forming, even on a service with no auth.
# -----------------------------------------------------------------------------

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv(
        "CORS_ORIGINS", "http://localhost:5173,http://localhost:3000"
    ).split(","),
    allow_credentials=False,
    allow_methods=["GET"],
    allow_headers=["*"],
)


# -----------------------------------------------------------------------------
# Request logging
# -----------------------------------------------------------------------------


@app.middleware("http")
async def log_requests(request: Request, call_next):
    """One structured line per request, for CloudWatch Logs Insights."""
    started = time.perf_counter()
    response = await call_next(request)
    duration_ms = (time.perf_counter() - started) * 1000

    log.info(
        "method=%s path=%s status=%d duration_ms=%.1f client=%s",
        request.method,
        request.url.path,
        response.status_code,
        duration_ms,
        request.client.host if request.client else "-",
    )
    return response


# -----------------------------------------------------------------------------
# Error handling
# -----------------------------------------------------------------------------


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    """
    Log the real error; return a generic one.

    Database errors are especially dangerous to return verbatim — a psycopg2
    error message can contain table names, column names, and fragments of the
    query. That is free reconnaissance for anyone probing the service. The full
    detail goes to CloudWatch where an operator can read it; the client gets a
    sentence.
    """
    log.exception("Unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"},
    )


# =============================================================================
# HEALTH
# =============================================================================
#
# TWO probes, because they answer different questions and Kubernetes uses them
# differently:
#
#   LIVENESS  "is this process wedged?"        failure -> RESTART the container
#   READINESS "can it serve traffic right now?" failure -> REMOVE from Service
#                                                          endpoints, keep it
#                                                          running
#
# THE CLASSIC MISTAKE is checking the database in the LIVENESS probe. If RDS
# has a brief hiccup, every backend pod fails liveness simultaneously and
# Kubernetes restarts all of them — turning a 30-second database blip into a
# full outage plus a thundering herd of reconnects. Liveness must only test the
# process itself.
# =============================================================================


@app.get("/health", tags=["health"])
def health():
    """Liveness. Deliberately touches nothing external."""
    return {"status": "healthy", "service": "jollof-run-api"}


@app.get("/health/ready", tags=["health"])
def health_ready():
    """Readiness. Confirms the database is actually reachable."""
    if db.check_connection():
        return {"status": "ready", "database": "connected"}

    # 503, not 500: this is "not ready yet", not "broken".
    raise HTTPException(status_code=503, detail="Database not reachable")


# =============================================================================
# RESTAURANTS
# =============================================================================


@app.get("/restaurants", tags=["restaurants"])
def get_restaurants(
    search: str | None = Query(
        None,
        max_length=100,
        description="Filter by restaurant name or cuisine",
    ),
    limit: int = Query(50, ge=1, le=100),
):
    """
    List restaurants.

    THE PHASE 9 / PHASE 12 TEST TARGET.

    `search` is the most attacker-reachable input in the whole application, so
    it is the one we point the SQL-injection test at. Three independent things
    protect it, and it is worth being able to name all three in order:

      1. AWS WAF, at the edge. AWSManagedRulesSQLiRuleSet inspects the query
         string and returns 403 before the request reaches the ALB. Outermost,
         and the weakest — it is pattern matching and can be evaded.

      2. FastAPI validation, here. max_length=100 caps the input. Most useful
         SQLi payloads are longer than that. Cheap, and not a real control.

      3. Parameterized SQL, in db.list_restaurants(). The value is bound, never
         parsed as SQL. THIS is the control. Delete rules 1 and 2 and the
         application is still not injectable.

    Get the ordering right in an interview: WAF is defence in depth. Layer 3 is
    the fix.
    """
    return {"restaurants": db.list_restaurants(search=search, limit=limit)}


@app.get("/restaurants/{restaurant_id}", tags=["restaurants"])
def get_restaurant(restaurant_id: int):
    """
    One restaurant, with its full menu.

    Note the type annotation: `restaurant_id: int`. FastAPI coerces and
    validates before this function body runs, so a request to
    /restaurants/1;DROP TABLE foods returns 422 Unprocessable Entity from the
    framework — the handler is never called and no string ever reaches SQL.

    Type annotations are not documentation here. They are input validation.
    """
    restaurant = db.get_restaurant(restaurant_id)

    if restaurant is None:
        raise HTTPException(
            status_code=404, detail=f"Restaurant {restaurant_id} not found"
        )

    return restaurant


# =============================================================================
# FOODS
# =============================================================================


@app.get("/foods", tags=["foods"])
def get_foods(
    restaurant_id: int | None = Query(None, ge=1),
    category: str | None = Query(None, max_length=50),
    limit: int = Query(100, ge=1, le=200),
):
    """List dishes across all restaurants, optionally filtered."""
    return {
        "foods": db.list_foods(
            restaurant_id=restaurant_id,
            category=category,
            limit=limit,
        )
    }


@app.get("/categories", tags=["foods"])
def get_categories():
    """Distinct food categories with item counts, for the homepage rail."""
    return {"categories": db.list_categories()}


# =============================================================================
# ROOT
# =============================================================================


@app.get("/", tags=["meta"])
def root():
    """Service description. Handy for confirming which pod answered."""
    return {
        "service": "Jollof Run API",
        "version": "1.0.0",
        "pod": os.getenv("HOSTNAME", "unknown"),  # Kubernetes sets HOSTNAME
        "endpoints": [
            "/health",
            "/health/ready",
            "/restaurants",
            "/restaurants/{id}",
            "/foods",
            "/categories",
        ],
    }
