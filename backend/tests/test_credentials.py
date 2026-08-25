"""
Credential resolution — the security property this project is built around.

backend/db.py resolves database credentials from, in strict order:

    1. a CSI-mounted secret file   (EKS, via IRSA + Secrets Store CSI Driver)
    2. a direct Secrets Manager fetch, if DB_SECRET_NAME is set
    3. DATABASE_URL                (local docker-compose ONLY)
    4. nothing -> raise

Step 4 is the one that matters. There is no default connection string, so the
service can never silently connect to the wrong database, and a hardcoded
credential cannot creep back in unnoticed. These tests hold that line.
"""

import json

import pytest

import db

VALID_SECRET = {
    "username": "jollofadmin",
    "password": "s3cret",
    "engine": "postgres",
    "host": "db.internal",
    "port": 5432,
    "dbname": "jollofrun",
}


# =============================================================================
# The CSI mount — the production path
# =============================================================================


def test_reads_credentials_from_csi_mount(csi_secret):
    csi_secret(json.dumps(VALID_SECRET))

    url = db.resolve_database_url()

    assert url.startswith("postgresql+psycopg2://")
    assert "jollofadmin" in url
    assert "db.internal:5432" in url
    assert url.endswith("/jollofrun")


def test_csi_mount_wins_over_database_url(csi_secret, monkeypatch):
    """
    Priority is not cosmetic.

    If DATABASE_URL could override the mounted secret, anyone able to set an
    environment variable on the Deployment could redirect the backend at a
    database of their choosing. The mount must always win.
    """
    csi_secret(json.dumps(VALID_SECRET))
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg2://evil:evil@attacker/db")

    url = db.resolve_database_url()

    assert "db.internal" in url
    assert "attacker" not in url


def test_missing_key_in_secret_is_reported_clearly(csi_secret):
    incomplete = {k: v for k, v in VALID_SECRET.items() if k != "password"}
    csi_secret(json.dumps(incomplete))

    with pytest.raises(RuntimeError, match="missing required key"):
        db.resolve_database_url()


def test_malformed_json_names_the_likely_cause(csi_secret):
    """
    The realistic failure is a jmesPath in the SecretProviderClass splitting the
    secret into single-value files. The error should point at that, not at a
    json module traceback.
    """
    csi_secret("not json at all")

    with pytest.raises(RuntimeError, match="secretproviderclass"):
        db.resolve_database_url()


# =============================================================================
# Refusing to guess
# =============================================================================


def test_raises_when_no_credentials_are_available(monkeypatch, tmp_path):
    """
    THE MOST IMPORTANT TEST IN THIS FILE.

    With no mount, no DB_SECRET_NAME and no DATABASE_URL, db.py must raise
    rather than fall back to something like
    postgresql://postgres:postgres@localhost/postgres.

    A default would mean a misconfigured pod starts successfully and talks to
    the wrong database. Crash-looping with a readable error is the correct
    behaviour.
    """
    monkeypatch.setattr(db, "CSI_SECRET_PATH", tmp_path / "does-not-exist")
    monkeypatch.delenv("DB_SECRET_NAME", raising=False)
    monkeypatch.delenv("DATABASE_URL", raising=False)

    with pytest.raises(RuntimeError) as excinfo:
        db.resolve_database_url()

    message = str(excinfo.value)
    assert "No database credentials found" in message
    # The error must be actionable — it should list every source it tried.
    assert "/mnt/secrets-store" in message or "CSI" in message.upper()
    assert "DB_SECRET_NAME" in message
    assert "DATABASE_URL" in message


def test_local_database_url_is_used_when_nothing_else_exists(monkeypatch, tmp_path):
    monkeypatch.setattr(db, "CSI_SECRET_PATH", tmp_path / "does-not-exist")
    monkeypatch.delenv("DB_SECRET_NAME", raising=False)
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg2://u:p@localhost/testdb")

    assert db.resolve_database_url() == "postgresql+psycopg2://u:p@localhost/testdb"


# =============================================================================
# URL encoding
# =============================================================================


@pytest.mark.parametrize(
    "password",
    [
        "p@ssw0rd",  # @ would otherwise terminate the userinfo section
        "pa/ss",  # / would start the path
        "pa:ss",  # : would split user from password
        "pa#ss",  # # would start a fragment
        "a@b:c/d#e?f",  # all of them at once
    ],
)
def test_special_characters_in_password_are_percent_encoded(csi_secret, password):
    """
    terraform/secrets.tf generates passwords from a character set that includes
    every symbol above.

    Without quote_plus the URL is corrupted and SQLAlchemy fails with something
    that looks like a DNS problem — "could not translate host name" — sending
    you to debug networking when the real fault is string handling. Roughly one
    deploy in ten, entirely at random.
    """
    csi_secret(json.dumps({**VALID_SECRET, "password": password}))

    url = db.resolve_database_url()

    # The raw password must not appear; its encoded form must.
    assert f":{password}@" not in url
    # The host is still parsed as the host, which is what actually breaks.
    assert "@db.internal:5432/jollofrun" in url


def test_special_characters_in_username_are_encoded_too(csi_secret):
    csi_secret(json.dumps({**VALID_SECRET, "username": "user@corp"}))

    url = db.resolve_database_url()

    assert "user%40corp" in url
