"""
Shared pytest fixtures.

TWO CLASSES OF TEST LIVE IN THIS SUITE:

  pure unit    credential resolution, URL building. No database. Always run.
  integration  real SQL against a real PostgreSQL. Marked `integration`,
               skipped automatically when DATABASE_URL is unset.

The integration tests deliberately do NOT use SQLite. backend/db.py relies on
ILIKE and CAST(:x AS TEXT), both PostgreSQL-specific — a SQLite run would pass
while testing something that is not what ships. CI provides a
postgres:16-alpine service container; locally, `docker compose up -d postgres`
is enough.
"""

import os

import pytest

import db

# CI sets this to the service container. Locally it points at docker-compose.
DATABASE_URL = os.getenv("DATABASE_URL")

# Applied to every test in test_queries.py / test_api.py via their own marks.
requires_db = pytest.mark.skipif(
    not DATABASE_URL,
    reason="DATABASE_URL not set — start PostgreSQL or run this in CI",
)


@pytest.fixture(autouse=True)
def _reset_engine_between_tests():
    """
    db.py memoises its engine in a module-level `_engine` global.

    Without resetting it, the first test to build an engine pins the connection
    string for the whole session — so a later test that monkeypatches the
    credential source would silently keep using the earlier one and pass for the
    wrong reason. Disposing the pool also stops connections leaking across
    tests.
    """
    yield

    if db._engine is not None:
        db._engine.dispose()
        db._engine = None


@pytest.fixture(scope="session")
def seeded_db():
    """
    Apply schema + seed data once for the whole session.

    seed.sql is written to be idempotent (CREATE TABLE IF NOT EXISTS,
    ON CONFLICT DO NOTHING), so running it against an already-populated database
    is safe. That property is worth exercising here — it is the same property
    that lets two backend pods start simultaneously without racing each other.
    """
    if not DATABASE_URL:
        pytest.skip("DATABASE_URL not set")

    db.init_schema()
    yield

    if db._engine is not None:
        db._engine.dispose()
        db._engine = None


@pytest.fixture
def csi_secret(tmp_path, monkeypatch):
    """
    Write a fake CSI-mounted secret and point db.py at it.

    Mirrors what the Secrets Store CSI Driver does at pod start: drop a JSON
    document on a tmpfs path. Returns the path so a test can rewrite it.
    """

    def _write(payload: str):
        secret_file = tmp_path / "db-credentials"
        secret_file.write_text(payload, encoding="utf-8")
        monkeypatch.setattr(db, "CSI_SECRET_PATH", secret_file)
        return secret_file

    return _write
