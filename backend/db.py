"""
db.py — credential resolution and database access for Jollof Run.

TWO THINGS HAPPEN IN THIS FILE, and both are the point of the project:

  1. CREDENTIALS ARE NEVER HARDCODED.
     They are resolved at startup, in a strict priority order, from sources
     that live outside the image and outside Git.

  2. EVERY QUERY IS PARAMETERIZED.
     Not because WAF might miss something, but because parameterization is the
     only thing that actually makes SQL injection impossible. WAF is a second
     line of defence for a problem this file has already solved.
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

log = logging.getLogger("jollof.db")

# Where the Secrets Store CSI Driver mounts the secret. This path is set by
# `volumeMounts.mountPath` in backend-deployment.yaml plus the `objectName`
# in secretproviderclass.yaml. Change one, change all three.
CSI_SECRET_PATH = Path(os.getenv("DB_SECRET_FILE", "/mnt/secrets-store/db-credentials"))


# =============================================================================
# CREDENTIAL RESOLUTION
# =============================================================================


def _from_csi_mount() -> dict[str, Any] | None:
    """
    PRIMARY PATH — production / EKS.

    The Secrets Store CSI Driver has already done all the work by the time this
    runs. The full chain:

        Pod starts with a `secrets-store.csi.k8s.io` volume
              |
        kubelet asks the CSI driver to mount it
              |
        CSI driver + AWS provider read the pod's PROJECTED SERVICE ACCOUNT
        TOKEN -- a short-lived JWT signed by the cluster, mounted by kubelet
        at /var/run/secrets/eks.amazonaws.com/serviceaccount/token
              |
        sts:AssumeRoleWithWebIdentity, presenting that JWT
              |
        STS validates the signature against the cluster's registered OIDC
        provider, then checks the role's trust policy conditions:
              sub == system:serviceaccount:jollof-run:backend-sa
              aud == sts.amazonaws.com
              |
        temporary IAM credentials for jollof-run-backend-irsa (~1 hour)
              |
        secretsmanager:GetSecretValue on ONE secret ARN
        kms:Decrypt on ONE key ARN
              |
        plaintext JSON written into the pod's tmpfs at CSI_SECRET_PATH

    By the time Python opens the file, there is nothing left to authenticate.
    The application code contains no AWS SDK call, no region, no role ARN, and
    no password. It reads a file.

    tmpfs matters: the mount is in memory, never written to the node's disk.
    """
    if not CSI_SECRET_PATH.exists():
        return None

    log.info("Reading database credentials from CSI mount: %s", CSI_SECRET_PATH)
    raw = CSI_SECRET_PATH.read_text(encoding="utf-8").strip()

    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        # A common cause: secretproviderclass.yaml used jmesPath to split the
        # secret into separate files, so this file holds a bare value rather
        # than the whole JSON document. Say so, rather than dying on a
        # stack trace that names neither file.
        raise RuntimeError(
            f"{CSI_SECRET_PATH} is not valid JSON. Check the objects: block in "
            f"kubernetes/secretproviderclass.yaml — it should mount the whole "
            f"secret, not a jmesPath fragment."
        ) from exc


def _from_secrets_manager_api() -> dict[str, Any] | None:
    """
    ALTERNATIVE PATH — direct boto3 fetch, no CSI driver.

    Set DB_SECRET_NAME to enable. Same IRSA identity, same IAM policy, same
    STS exchange; the only difference is that the application makes the API
    call itself instead of the kubelet doing it at mount time.

    Trade-offs, which are worth being able to argue either side of:

      CSI mount                          boto3 in-process
      ---------------------------------  --------------------------------
      + no AWS SDK in the image          + no CSI driver to install
      + no AWS code in the app           + refresh/rotation is your choice
      + secret ready before app starts   + works outside Kubernetes too
      - another cluster component        - couples app code to AWS
      - rotation needs a pod restart       (harder to run locally/test)
        or the rotation sidecar

    We use the CSI mount as primary because "the application contains no
    cloud-provider code" is a genuinely better property.
    """
    secret_name = os.getenv("DB_SECRET_NAME")
    if not secret_name:
        return None

    import boto3  # imported lazily so the primary path needs no SDK

    region = os.getenv("AWS_REGION", "us-east-1")
    log.info("Fetching database credentials from Secrets Manager: %s", secret_name)

    client = boto3.client("secretsmanager", region_name=region)
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response["SecretString"])


def _from_database_url() -> str | None:
    """
    LOCAL DEVELOPMENT ONLY — docker-compose.

    docker-compose.yml sets DATABASE_URL to point at a throwaway local
    Postgres container. That connection string contains a password, which is
    exactly why this path must never be used in EKS: it would mean a
    credential in a manifest.

    The local password is `localdev`. It protects a container that is deleted
    when you stop composing and is not reachable from outside your laptop.
    Treating it as a secret would be theatre.
    """
    return os.getenv("DATABASE_URL")


def resolve_database_url() -> str:
    """
    Try each source in priority order and build a SQLAlchemy URL.

    Note the last line: if nothing resolves, we RAISE. We do not fall back to
    a default like 'postgresql://postgres:postgres@localhost/postgres'.

    A default connection string is how a service ends up silently talking to
    the wrong database, or how a hardcoded credential creeps back into a
    codebase that was supposed to have none. Failing loudly at startup is the
    correct behaviour: the pod crash-loops, `kubectl logs` says exactly what is
    missing, and you fix the configuration.
    """
    creds = _from_csi_mount() or _from_secrets_manager_api()

    if creds:
        required = ("username", "password", "host", "port", "dbname")
        missing = [k for k in required if k not in creds]
        if missing:
            raise RuntimeError(
                f"Secret is missing required key(s): {', '.join(missing)}. "
                f"Expected JSON with: {', '.join(required)}"
            )

        # quote_plus so a password containing '@', '/', ':' or '#' does not
        # corrupt the URL. random_password in secrets.tf can generate all of
        # these — without quoting, roughly one deploy in ten fails with a
        # baffling "could not translate host name" error.
        from urllib.parse import quote_plus

        return (
            f"postgresql+psycopg2://{quote_plus(str(creds['username']))}:"
            f"{quote_plus(str(creds['password']))}@"
            f"{creds['host']}:{creds['port']}/{creds['dbname']}"
        )

    local_url = _from_database_url()
    if local_url:
        log.warning(
            "Using DATABASE_URL from the environment. This is the LOCAL "
            "development path and must never be how a deployed pod gets its "
            "credentials."
        )
        return local_url

    raise RuntimeError(
        "No database credentials found. Expected one of:\n"
        f"  1. a CSI-mounted secret at {CSI_SECRET_PATH}  (EKS, preferred)\n"
        "  2. DB_SECRET_NAME set, for a direct Secrets Manager fetch\n"
        "  3. DATABASE_URL set, for local docker-compose only\n"
        "Refusing to start with a guessed default."
    )


# =============================================================================
# ENGINE
# =============================================================================

_engine: Engine | None = None


def get_engine() -> Engine:
    """Lazily create one connection pool for the process lifetime."""
    global _engine

    if _engine is None:
        _engine = create_engine(
            resolve_database_url(),
            # POOL SIZING MATTERS ON db.t3.micro.
            # Its max_connections is about 85. With 2 backend pods and a pool
            # of 5 (+10 overflow), worst case is 2 * 15 = 30 connections —
            # comfortably under the limit, and under the 40 that the
            # rds-connections-high alarm watches for.
            pool_size=5,
            max_overflow=10,
            # Recycle connections after 5 minutes. RDS, NAT Gateways, and
            # security-group changes can all silently drop an idle TCP
            # connection; without recycling, the first query after an idle
            # period fails with "server closed the connection unexpectedly".
            pool_recycle=300,
            # Cheap liveness check before handing a connection to the caller.
            # Turns a hard error into a transparent reconnect.
            pool_pre_ping=True,
            # NEVER set echo=True outside local debugging. It logs every
            # statement WITH ITS BOUND PARAMETERS, which is how credentials and
            # personal data end up in CloudWatch Logs.
            echo=False,
        )
        log.info("Database engine initialised")

    return _engine


def check_connection() -> bool:
    """Used by /health/ready. Cheapest possible round-trip to the database."""
    try:
        with get_engine().connect() as conn:
            conn.execute(text("SELECT 1"))
        return True
    except Exception as exc:  # broad by design: a health check must never raise
        log.error("Database health check failed: %s", exc)
        return False


# =============================================================================
# QUERIES
# =============================================================================
#
# EVERY query below uses BOUND PARAMETERS: :name placeholders, with values
# passed separately. The driver sends the SQL and the values over the wire as
# distinct things, so a value can never be parsed as SQL. It is not escaping —
# escaping can be defeated. The value never enters the parser at all.
#
# WHAT WE NEVER WRITE:
#
#     # BROKEN — do not do this, ever
#     conn.execute(text(f"SELECT * FROM restaurants WHERE id = {rid}"))
#     conn.execute(text("SELECT * FROM restaurants WHERE id = " + rid))
#     conn.execute(text("SELECT * FROM restaurants WHERE id = %s" % rid))
#
# With any of those, rid = "1 OR 1=1" returns every row and
# rid = "1; DROP TABLE foods--" does what it says. AWS WAF would probably
# catch the second one. It should never get the chance.
# =============================================================================


def list_restaurants(search: str | None = None, limit: int = 50) -> list[dict]:
    """
    All restaurants, newest-rated first, with an optional name/cuisine search.

    The `search` parameter is the deliberate demonstration target for Phase 9:
    it is the most attacker-reachable input in the application, and it is
    parameterized. When you send it a SQL-injection payload in Phase 12, two
    independent things happen:

      1. WAF sees the payload in the query string and returns 403 at the edge.
      2. Even if WAF were disabled, ILIKE would search for a restaurant whose
         name literally contains "' OR 1=1--" and return zero rows.

    Layer 1 is defence in depth. Layer 2 is the actual fix.
    """
    # TWO SUBTLETIES, both of which bite people writing "correct" parameterized
    # SQL for the first time:
    #
    # 1. The LIKE wildcards live in the VALUE, not in the SQL string.
    #    Writing  ILIKE '%' || :search || '%'  also works, but a literal % in a
    #    text() construct interacts with psycopg2's pyformat paramstyle and
    #    whether it needs doubling depends on the SQLAlchemy version. Building
    #    the pattern in Python sidesteps the question entirely and is still
    #    fully parameterized — the wildcards are part of the bound value.
    #
    # 2. CAST(:search AS TEXT) IS NULL, not :search IS NULL.
    #    PostgreSQL cannot infer a type for a bare parameter used only in an
    #    IS NULL test, and fails with:
    #       could not determine data type of parameter $1
    #    An explicit cast tells the planner what it is looking at.
    pattern = f"%{search}%" if search else None

    sql = """
        SELECT id, name, description, image_url, rating, location, cuisine,
               delivery_time_mins, delivery_fee
        FROM restaurants
        WHERE (CAST(:search AS TEXT) IS NULL
               OR name    ILIKE :pattern
               OR cuisine ILIKE :pattern)
        ORDER BY rating DESC, name ASC
        LIMIT :limit
    """
    with get_engine().connect() as conn:
        rows = conn.execute(
            text(sql),
            {"search": search, "pattern": pattern, "limit": limit},
        )
        return [dict(r._mapping) for r in rows]


def get_restaurant(restaurant_id: int) -> dict | None:
    """One restaurant with its menu nested inside."""
    restaurant_sql = """
        SELECT id, name, description, image_url, rating, location, cuisine,
               delivery_time_mins, delivery_fee
        FROM restaurants
        WHERE id = :id
    """
    foods_sql = """
        SELECT id, restaurant_id, name, description, price, image_url, category
        FROM foods
        WHERE restaurant_id = :id
        ORDER BY category, name
    """
    with get_engine().connect() as conn:
        row = conn.execute(text(restaurant_sql), {"id": restaurant_id}).first()
        if row is None:
            return None

        restaurant = dict(row._mapping)
        foods = conn.execute(text(foods_sql), {"id": restaurant_id})
        restaurant["foods"] = [dict(f._mapping) for f in foods]
        return restaurant


def list_foods(
    restaurant_id: int | None = None,
    category: str | None = None,
    limit: int = 100,
) -> list[dict]:
    """
    All dishes, optionally filtered.

    Note how the optional filters are handled: `:param IS NULL OR <condition>`
    inside the SQL, rather than building the WHERE clause with Python string
    concatenation. One static query string, values bound separately. Dynamic
    SQL assembly is where injection bugs are born even in codebases that
    "use parameters".
    """
    sql = """
        SELECT f.id, f.restaurant_id, f.name, f.description, f.price,
               f.image_url, f.category, r.name AS restaurant_name,
               r.rating AS restaurant_rating
        FROM foods f
        JOIN restaurants r ON r.id = f.restaurant_id
        WHERE (CAST(:restaurant_id AS INTEGER) IS NULL
               OR f.restaurant_id = :restaurant_id)
          AND (CAST(:category AS TEXT) IS NULL
               OR f.category = :category)
        ORDER BY f.category, f.name
        LIMIT :limit
    """
    with get_engine().connect() as conn:
        rows = conn.execute(
            text(sql),
            {
                "restaurant_id": restaurant_id,
                "category": category,
                "limit": limit,
            },
        )
        return [dict(r._mapping) for r in rows]


def list_categories() -> list[dict]:
    """Distinct food categories with a count, for the homepage category rail."""
    sql = """
        SELECT category, COUNT(*) AS item_count
        FROM foods
        GROUP BY category
        ORDER BY item_count DESC
    """
    with get_engine().connect() as conn:
        return [dict(r._mapping) for r in conn.execute(text(sql))]


# =============================================================================
# SCHEMA + SEED
# =============================================================================


def init_schema() -> None:
    """
    Create tables and seed data if the database is empty.

    Running DDL from the application at startup is fine for a project of this
    size and makes the whole stack self-bootstrapping. It is NOT what you would
    do in production: two pods starting at once race each other, and there is
    no migration history. A real service uses Alembic and a Kubernetes Job or
    initContainer that runs migrations exactly once before the app starts.

    IF NOT EXISTS and ON CONFLICT DO NOTHING make this safe to run repeatedly,
    which is what saves us from the race in practice.
    """
    seed_path = Path(__file__).parent / "seed.sql"
    if not seed_path.exists():
        log.warning("seed.sql not found; skipping schema initialisation")
        return

    log.info("Applying schema and seed data")
    with get_engine().begin() as conn:  # begin() = transaction, auto-commit
        # exec_driver_sql, not text(): this file contains multiple statements
        # and literal ':' characters inside strings, which SQLAlchemy's text()
        # would try to interpret as bind parameters.
        conn.exec_driver_sql(seed_path.read_text(encoding="utf-8"))
    log.info("Schema ready")
