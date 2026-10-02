"""Shared test fixtures."""

import os

# APP_ENV defaults to production (hardened). The suite runs as "test", which
# enables the development aids the tests rely on; tests that check hardened
# behaviour switch settings.app_env themselves. Set before any backend import.
os.environ["APP_ENV"] = "test"
# Never let a shell-level DATABASE_URL point the test suite at a real database.
# PostgreSQL integration tests use TEST_POSTGRES_URL explicitly.
os.environ.pop("DATABASE_URL", None)

import pytest  # noqa: E402

from backend.app.security.guest_quota import guest_allowance  # noqa: E402
from backend.app.security.jwt_auth import signing_keys  # noqa: E402


@pytest.fixture(autouse=True)
def _fresh_guest_allowance():
    """Each test starts with an unused guest allowance (in-memory store).

    Guests are limited to a few scans per day, and most API tests call the scan
    endpoint as a guest from the same test client address.
    """
    guest_allowance.store.reset_for_test()
    yield
    guest_allowance.store.reset_for_test()


@pytest.fixture(autouse=True)
def _fresh_signing_keys():
    """No Supabase signing keys are cached between tests."""
    signing_keys.reset_for_test()
    yield
    signing_keys.reset_for_test()
