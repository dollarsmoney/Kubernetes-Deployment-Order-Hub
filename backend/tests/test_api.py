"""
API-layer tests via FastAPI's TestClient.

Covers the HTTP contract the frontend depends on, plus the framework-level
validation that runs BEFORE any handler executes — which is a real defence
layer, not documentation.
"""

import pytest
from fastapi.testclient import TestClient

from tests.conftest import requires_db

pytestmark = [requires_db, pytest.mark.integration]


@pytest.fixture(scope="module")
def client():
    """
    TestClient as a context manager runs the app's lifespan, so init_schema()
    executes exactly as it does in a real pod. Constructing TestClient without
    `with` skips startup entirely and the database is never seeded.
    """
    from app import app

    with TestClient(app) as c:
        yield c


# =============================================================================
# Health
# =============================================================================


def test_liveness_does_not_touch_the_database(client):
    """
    /health must stay independent of the database.

    Pointing the livenessProbe at something that checks RDS means a 30-second
    database blip fails liveness on every replica at once, Kubernetes restarts
    all of them, and a brief hiccup becomes a full outage plus a reconnect
    stampede. Readiness is where the DB check belongs.
    """
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_readiness_reports_the_database(client):
    response = client.get("/health/ready")

    assert response.status_code == 200
    assert response.json()["database"] == "connected"


def test_root_lists_endpoints(client):
    body = client.get("/").json()

    assert body["service"] == "Jollof Run API"
    assert "/restaurants" in body["endpoints"]


# =============================================================================
# Restaurants
# =============================================================================


def test_list_restaurants(client):
    body = client.get("/restaurants").json()

    assert len(body["restaurants"]) == 8
    assert {"id", "name", "rating", "cuisine"} <= set(body["restaurants"][0])


def test_get_one_restaurant_includes_its_menu(client):
    body = client.get("/restaurants/2").json()

    assert body["name"] == "Mama Nkechi Kitchen"
    assert len(body["foods"]) == 4


def test_missing_restaurant_is_404(client):
    response = client.get("/restaurants/9999")

    assert response.status_code == 404
    assert "not found" in response.json()["detail"].lower()


def test_non_integer_id_is_rejected_before_the_handler_runs(client):
    """
    `restaurant_id: int` is input validation, not a type hint.

    FastAPI coerces and validates the path parameter first, so this returns 422
    from the framework and the handler is never called — the string never gets
    anywhere near SQL. Type annotations are doing security work here.
    """
    assert client.get("/restaurants/not-an-integer").status_code == 422
    assert client.get("/restaurants/1;DROP TABLE foods").status_code == 422


def test_limit_bounds_are_enforced(client):
    assert client.get("/restaurants?limit=0").status_code == 422
    assert client.get("/restaurants?limit=500").status_code == 422
    assert client.get("/restaurants?limit=5").status_code == 200


def test_overlong_search_is_rejected(client):
    """max_length=100 caps the input. Cheap, and not the real control."""
    assert client.get("/restaurants?search=" + "a" * 101).status_code == 422


# =============================================================================
# Foods
# =============================================================================


def test_list_foods(client):
    body = client.get("/foods").json()

    assert len(body["foods"]) == 30
    assert "restaurant_name" in body["foods"][0]


def test_foods_filtered_by_restaurant(client):
    body = client.get("/foods?restaurant_id=8").json()

    assert all(f["restaurant_id"] == 8 for f in body["foods"])


def test_categories(client):
    body = client.get("/categories").json()

    assert {c["category"] for c in body["categories"]} >= {"Rice", "Grill", "Soup"}


# =============================================================================
# Injection, through the full HTTP path
# =============================================================================


@pytest.mark.parametrize(
    "payload",
    ["' OR 1=1--", "' UNION SELECT NULL--", "1; DROP TABLE foods--"],
)
def test_injection_over_http_returns_an_empty_result_not_an_error(client, payload):
    """
    Note the expected status is 200, not 500.

    A parameterised query does not fail on hostile input — it searches for the
    literal text and finds nothing. A 500 here would suggest the value reached
    the SQL parser and blew up, which would be its own kind of bad.

    In production AWS WAF returns 403 before this request ever reaches a pod.
    That is defence in depth; this test proves the layer underneath holds on
    its own.
    """
    response = client.get("/restaurants", params={"search": payload})

    assert response.status_code == 200
    assert response.json()["restaurants"] == []

    # And the data is still there.
    assert len(client.get("/foods").json()["foods"]) == 30
