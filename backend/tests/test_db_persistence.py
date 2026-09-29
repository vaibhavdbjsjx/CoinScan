"""
Tests for Phase 4: Database Integration, Production Fail-Closed Behavior,
SQLAlchemy Models, and Account Isolation.
"""

import pytest
from fastapi import HTTPException
from sqlalchemy import inspect as sa_inspect

from backend.app.config import settings
from backend.app.db.session import (
    is_db_configured,
    ensure_db_readiness,
    get_async_engine,
    get_session_factory,
    get_db,
    init_db,
    close_db,
)
from backend.app.db.models import (
    Base,
    User,
    Entitlement,
    Subscription,
    SubscriptionEvent,
    ScanUsage,
    ScanHistory,
    CollectionItem,
    ApiKey,
    ApiKeyUsage,
    Feedback,
    SecurityEvent,
    UserLegalConsent,
)
from backend.app.api.account import account_store
from backend.app.api.webhooks import webhook_state
from backend.app.security.quota_service import quota_engine
from backend.app.api.feedback import feedback_store


@pytest.fixture(autouse=True)
def restore_env_and_db():
    orig_env = settings.app_env
    orig_db = settings.database_url
    yield
    settings.app_env = orig_env
    settings.database_url = orig_db


class TestDatabaseFailClosedProduction:
    """Production must strictly fail closed if DATABASE_URL is missing or unconfigured."""

    def test_production_startup_fails_without_database_url(self):
        settings.app_env = "production"
        settings.database_url = None

        with pytest.raises(RuntimeError) as exc_info:
            ensure_db_readiness()
        assert "DATABASE_URL is not configured in production" in str(exc_info.value)

    def test_production_account_store_fails_closed(self):
        settings.app_env = "production"
        settings.database_url = None

        with pytest.raises(HTTPException) as exc:
            account_store.get_or_create_profile("usr_test_fail")
        assert exc.value.status_code == 500
        assert "Database persistence unconfigured" in exc.value.detail

        with pytest.raises(HTTPException) as exc2:
            account_store.record_consent("usr_test_fail", "1.0.0", "1.0.0")
        assert exc2.value.status_code == 500

    def test_production_webhook_state_fails_closed(self):
        settings.app_env = "production"
        settings.database_url = None

        with pytest.raises(HTTPException) as exc:
            webhook_state.is_processed("evt_rc_any")
        assert exc.value.status_code == 500

        with pytest.raises(HTTPException) as exc2:
            webhook_state.set_user_tier("usr_any", None)
        assert exc2.value.status_code == 500

    @pytest.mark.asyncio
    async def test_production_quota_engine_fails_closed(self):
        settings.app_env = "production"
        settings.database_url = None

        with pytest.raises(HTTPException) as exc:
            await quota_engine.check_quota_available("usr_any")
        assert exc.value.status_code == 500

        with pytest.raises(HTTPException) as exc2:
            await quota_engine.check_and_consume_quota("usr_any")
        assert exc2.value.status_code == 500

    def test_production_feedback_store_fails_closed(self):
        settings.app_env = "production"
        settings.database_url = None

        from backend.app.api.feedback import FeedbackSubmission, FeedbackCategory
        from backend.app.security.auth import AuthenticatedUser

        sub = FeedbackSubmission(
            category=FeedbackCategory.OTHER,
            title="Production Test",
            description="Testing fail closed",
        )
        user = AuthenticatedUser(user_id="usr_prod")

        with pytest.raises(HTTPException) as exc:
            feedback_store.submit_feedback(sub, user, "127.0.0.1")
        assert exc.value.status_code == 500

    @pytest.mark.asyncio
    async def test_production_get_db_fails_closed(self):
        settings.app_env = "production"
        settings.database_url = None

        gen = get_db()
        with pytest.raises(HTTPException) as exc:
            await gen.__anext__()
        assert exc.value.status_code == 500


class TestSqlAlchemyModelDefinitions:
    """Verifies that ORM models strictly reflect the production schema migrations."""

    def test_users_table_schema(self):
        assert User.__tablename__ == "users"
        cols = {c.name for c in User.__table__.columns}
        expected = {
            "id", "email", "display_name", "avatar_url",
            "preferred_currency", "locale", "created_at", "updated_at",
        }
        assert expected.issubset(cols)

    def test_entitlements_table_schema(self):
        assert Entitlement.__tablename__ == "entitlements"
        cols = {c.name for c in Entitlement.__table__.columns}
        expected = {
            "user_id", "tier", "status", "daily_scan_limit",
            "active_subscription_id", "expires_at", "updated_at",
        }
        assert expected.issubset(cols)
        # Foreign key to users.id
        fks = list(Entitlement.__table__.columns["user_id"].foreign_keys)
        assert len(fks) == 1
        assert fks[0].target_fullname == "users.id"
        assert fks[0].ondelete == "CASCADE"

    def test_subscription_events_table_schema(self):
        assert SubscriptionEvent.__tablename__ == "subscription_events"
        cols = {c.name for c in SubscriptionEvent.__table__.columns}
        expected = {
            "id", "event_id", "app_user_id", "event_type",
            "product_id", "store", "environment", "raw_payload", "received_at",
        }
        assert expected.issubset(cols)
        assert SubscriptionEvent.__table__.columns["event_id"].unique is True

    def test_scan_usage_table_schema_and_unique_constraint(self):
        assert ScanUsage.__tablename__ == "scan_usage"
        cols = {c.name for c in ScanUsage.__table__.columns}
        assert {"id", "user_id", "scan_date", "scan_count"}.issubset(cols)
        # Unique constraint on (user_id, scan_date)
        constraint_names = [c.name for c in ScanUsage.__table__.constraints]
        assert "uq_user_scan_date" in constraint_names

    def test_collection_items_table_schema(self):
        assert CollectionItem.__tablename__ == "collection_items"
        cols = {c.name for c in CollectionItem.__table__.columns}
        expected = {
            "id", "user_id", "coin_name", "country", "denomination",
            "year", "mint_mark", "composition", "grade", "numista_id",
            "purchase_price", "purchase_date", "currency_code",
            "initial_valuation_snapshot", "current_estimated_value",
            "notes", "front_image_url", "reverse_image_url", "is_favorite",
            "created_at", "updated_at",
        }
        assert expected.issubset(cols)

    def test_user_legal_consents_table_schema(self):
        assert UserLegalConsent.__tablename__ == "user_legal_consents"
        cols = {c.name for c in UserLegalConsent.__table__.columns}
        expected = {"user_id", "terms_version", "privacy_version", "accepted_at", "updated_at"}
        assert expected.issubset(cols)
        fks = list(UserLegalConsent.__table__.columns["user_id"].foreign_keys)
        assert len(fks) == 1
        assert fks[0].ondelete == "CASCADE"


class TestDevelopmentFallbackBehavior:
    """In development mode when DATABASE_URL is not set, stores fall back gracefully to in-memory."""

    def test_development_account_store_fallback(self):
        settings.app_env = "development"
        settings.database_url = None

        profile = account_store.get_or_create_profile("usr_dev_1")
        assert profile["id"] == "usr_dev_1"

        consent = account_store.record_consent("usr_dev_1", "1.0.0", "1.0.0")
        assert consent["terms_version"] == "1.0.0"
        assert account_store.get_consent("usr_dev_1")["terms_version"] == "1.0.0"

    def test_development_webhook_state_fallback(self):
        settings.app_env = "development"
        settings.database_url = None

        assert webhook_state.is_processed("evt_dev_123") is False
        webhook_state.mark_processed("evt_dev_123")
        assert webhook_state.is_processed("evt_dev_123") is True
