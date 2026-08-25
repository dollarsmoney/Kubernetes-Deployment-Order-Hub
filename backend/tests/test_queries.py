"""
Query-layer tests against a REAL PostgreSQL.

These assert the claim the whole project rests on: SQL injection is prevented by
BOUND PARAMETERS in db.py, not by the WAF sitting in front of the ALB. WAF is a
pattern matcher and the outer layer; this is the control.

Not run against SQLite on purpose. db.py uses ILIKE and CAST(:x AS TEXT), which
SQLite does not have — passing there would prove nothing about production.
"""

import pytest

import db
from tests.conftest import requires_db

pytestmark = [requires_db, pytest.mark.integration]


# =============================================================================
# Seeding
# =============================================================================


def test_seed_data_loaded(seeded_db):
    restaurants = db.list_restaurants()

    assert len(restaurants) == 8
    assert {r["name"] for r in restaurants} >= {"Suya Republic", "Calabar Kitchen"}


def test_seed_is_idempotent(seeded_db):
    """
    Two backend pods start at the same time and both run init_schema().

    seed.sql relies on CREATE TABLE IF NOT EXISTS and ON CONFLICT DO NOTHING to
    make that safe. If it were not idempotent, a second run would raise a
    duplicate-key error and one of the two pods would crash-loop.
    """
    before = len(db.list_restaurants())
    db.init_schema()
    db.init_schema()

    assert len(db.list_restaurants()) == before


def test_ordering_is_rating_desc(seeded_db):
    ratings = [float(r["rating"]) for r in db.list_restaurants()]

    assert ratings == sorted(ratings, reverse=True)


# =============================================================================
# Filtering
# =============================================================================


def test_search_matches_name_case_insensitively(seeded_db):
    assert [r["name"] for r in db.list_restaurants(search="suya")] == ["Suya Republic"]
    assert [r["name"] for r in db.list_restaurants(search="SUYA")] == ["Suya Republic"]


def test_search_matches_cuisine(seeded_db):
    results = db.list_restaurants(search="Efik")

    assert [r["name"] for r in results] == ["Calabar Kitchen"]


def test_search_is_a_substring_match(seeded_db):
    """The % wildcards live in the bound VALUE, not in the SQL string."""
    assert len(db.list_restaurants(search="Kitchen")) >= 2


def test_no_search_returns_everything(seeded_db):
    """
    Exercises the `CAST(:search AS TEXT) IS NULL` branch.

    Without the explicit cast PostgreSQL cannot infer a type for a parameter
    used only in an IS NULL test and fails with
    "could not determine data type of parameter $1".
    """
    assert len(db.list_restaurants(search=None)) == 8


def test_limit_is_respected(seeded_db):
    assert len(db.list_restaurants(limit=3)) == 3


def test_foods_filter_by_restaurant(seeded_db):
    foods = db.list_foods(restaurant_id=3)

    assert len(foods) == 4
    assert all(f["restaurant_id"] == 3 for f in foods)
    assert all(f["restaurant_name"] == "Suya Republic" for f in foods)


def test_foods_filter_by_category(seeded_db):
    foods = db.list_foods(category="Drinks")

    assert [f["name"] for f in foods] == ["Chapman"]


def test_foods_filters_combine(seeded_db):
    assert db.list_foods(restaurant_id=3, category="Drinks") == []
    assert len(db.list_foods(restaurant_id=3, category="Grill")) == 4


def test_get_restaurant_nests_its_menu(seeded_db):
    restaurant = db.get_restaurant(1)

    assert restaurant["name"] == "Iya Basira Buka"
    assert len(restaurant["foods"]) == 4
    assert "Party Jollof Rice" in {f["name"] for f in restaurant["foods"]}


def test_get_missing_restaurant_returns_none(seeded_db):
    assert db.get_restaurant(9999) is None


def test_categories_are_counted(seeded_db):
    categories = {c["category"]: c["item_count"] for c in db.list_categories()}

    assert categories["Grill"] == 6
    assert categories["Drinks"] == 1
    assert sum(categories.values()) == 30


# =============================================================================
# SQL INJECTION — the actual control
# =============================================================================


@pytest.mark.parametrize(
    "payload",
    [
        "' OR 1=1--",
        "' OR '1'='1",
        "' UNION SELECT NULL,NULL--",
        "1; DROP TABLE foods--",
        "' AND SLEEP(5)--",
        "' UNION SELECT table_name FROM information_schema.tables--",
        "'/**/OR/**/1=1--",
        "admin'--",
    ],
)
def test_injection_payloads_are_treated_as_literal_text(seeded_db, payload):
    """
    Each payload is searched for as a LITERAL STRING.

    No restaurant is named "' OR 1=1--", so the correct result is zero rows.

    Note what is NOT asserted: that an error is raised. A parameterised query
    does not error on hostile input — it simply looks for it and finds nothing.
    The value never reaches the SQL parser at all, so there is nothing to fail.

    If any of these returned all 8 restaurants, the tautology would have been
    evaluated as SQL and the application would be injectable.
    """
    results = db.list_restaurants(search=payload)

    assert results == [], f"{payload!r} returned rows — it was parsed as SQL"


def test_drop_table_payload_leaves_the_schema_intact(seeded_db):
    """The one that would be unrecoverable if parameterisation failed."""
    db.list_restaurants(search="1; DROP TABLE foods--")
    db.list_foods(category="Grill'; DROP TABLE restaurants;--")

    assert len(db.list_foods()) == 30
    assert len(db.list_restaurants()) == 8


def test_injection_via_category_filter_is_inert(seeded_db):
    """
    `category` uses equality rather than ILIKE, and is bound the same way.
    Every user-controlled parameter is covered, not just the obvious one.
    """
    assert db.list_foods(category="Grill' OR '1'='1") == []


def test_connection_check(seeded_db):
    assert db.check_connection() is True
