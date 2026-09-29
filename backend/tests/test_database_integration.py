"""
Async Database Integration Test Suite.

================================================================================
TEST STRATEGY & DIALECT LIMITATIONS NOTICE:
================================================================================
PostgreSQL is the production database engine (as codified in
`backend/migrations/20260830_phase11_production_schema.sql` with native PostgreSQL
UUIDs, custom ENUMs, JSONB, and Supabase `auth.users` foreign keys).

In environments where an external PostgreSQL daemon or Docker container is not
provisioned, these integration tests execute against an asynchronous SQLite engine
(`sqlite+aiosqlite:///:memory:`) via SQLAlchemy's unified async session interface.

WHAT THESE TESTS VALIDATE:
1. Real async database session lifecycle (engine creation, connection pooling, commit, rollback).
2. Actual SQL execution of CRUD operations on User, Entitlement, Subscription,
   SubscriptionEvent, ScanUsage, ScanHistory, CollectionItem, Feedback, and UserLegalConsent.
3. Transaction rollback semantics on errors and integrity conflicts.
4. Multi-tenant account isolation and foreign key cascading.
5. Persistent quota counting and date-boundary uniqueness.
6. Webhook event idempotency and database persistence.
7. Account deletion cascading across all user-owned tables.

WHAT THESE TESTS DO NOT VALIDATE (PostgreSQL/Supabase-specific features):
1. Supabase server-side Row Level Security (RLS) policies (`auth.uid() = user_id`).
2. PostgreSQL-internal binary representation for `subscription_tier_enum` and `subscription_status_enum`.
3. Cross-schema foreign key enforcement to Supabase's internal `auth.users(id)` table.
================================================================================
"""

import uuid
import time
from datetime import datetime, date, timezone
import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy import select, delete
from sqlalchemy.exc import IntegrityError

from backend.app.config import settings
import backend.app.db.session as session_module
from backend.app.db.models import (
    Base,
    User,
    Entitlement,
    Subscription,
    SubscriptionEvent,
    ScanUsage,
    ScanHistory,
    CollectionItem,
    Feedback,
    UserLegalConsent,
)
from backend.app.security.rate_limit import SubscriptionTier
from backend.app.api.account import account_store
from backend.app.api.webhooks import webhook_state
from backend.app.security.quota_service import quota_engine


TEST_DB_URL = "sqlite+aiosqlite:///:memory:"


@pytest_asyncio.fixture(autouse=True)
async def db_integration_engine():
    """Sets up an in-memory async SQLite engine with schema for integration testing."""
    orig_env = settings.app_env
    orig_db_url = settings.database_url
    orig_engine = session_module._engine
    orig_factory = session_module._session_factory

    settings.app_env = "production"
    settings.database_url = TEST_DB_URL

    test_engine = create_async_engine(TEST_DB_URL, echo=False)
    test_session_factory = async_sessionmaker(
        bind=test_engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )

    # Create all tables in memory
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    # Patch global session module
    session_module._engine = test_engine
    session_module._session_factory = test_session_factory

    yield test_session_factory

    # Teardown
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await test_engine.dispose()

    session_module._engine = orig_engine
    session_module._session_factory = orig_factory
    settings.app_env = orig_env
    settings.database_url = orig_db_url
    account_store.reset_for_test()
    webhook_state.reset_for_test()


@pytest.mark.asyncio
class TestDatabaseIntegration:

    async def test_user_and_profile_persistence(self, db_integration_engine):
        """Verifies real SQL insert, query, and field persistence for User."""
        user_uuid = str(uuid.uuid4())
        factory = db_integration_engine

        async with factory() as session:
            user = User(
                id=user_uuid,
                email="alice@coinscan.app",
                display_name="Alice Collector",
                preferred_currency="USD",
                locale="en-US",
            )
            session.add(user)
            await session.commit()

        # Query back in a clean session
        async with factory() as session:
            stmt = select(User).where(User.id == user_uuid)
            res = await session.execute(stmt)
            fetched = res.scalar_one_or_none()

            assert fetched is not None
            assert fetched.id == user_uuid
            assert fetched.email == "alice@coinscan.app"
            assert fetched.display_name == "Alice Collector"
            assert fetched.preferred_currency == "USD"

    async def test_entitlement_persistence_and_update(self, db_integration_engine):
        """Verifies entitlement row creation, tier change, and foreign key linkage."""
        user_uuid = str(uuid.uuid4())
        factory = db_integration_engine

        async with factory() as session:
            user = User(id=user_uuid, email="bob@coinscan.app")
            entitlement = Entitlement(
                user_id=user_uuid,
                tier="free",
                status="none",
                daily_scan_limit=3,
            )
            session.add(user)
            session.add(entitlement)
            await session.commit()

        # Update tier via webhook state async
        updated = await webhook_state.set_user_tier_async(
            user_id=user_uuid,
            tier=SubscriptionTier.PRO,
            status_val="active",
        )
        assert updated is True

        # Verify DB reflects pro tier
        async with factory() as session:
            fetched_ent = await session.get(Entitlement, user_uuid)
            assert fetched_ent is not None
            assert fetched_ent.tier == "pro"
            assert fetched_ent.status == "active"

    async def test_webhook_idempotency_and_event_persistence(self, db_integration_engine):
        """Verifies SubscriptionEvent persistence and unique event_id idempotency."""
        user_uuid = str(uuid.uuid4())
        event_id = f"evt_test_{uuid.uuid4()}"
        factory = db_integration_engine

        # Mark processed async
        await webhook_state.mark_processed_async(
            event_id=event_id,
            app_user_id=user_uuid,
            event_type="INITIAL_PURCHASE",
            product_id="com.coinscan.pro.monthly",
            store="revenuecat",
            raw_payload={"test": True, "event_id": event_id},
        )

        # Check DB presence
        assert await webhook_state.is_processed_async(event_id) is True

        # Verify duplicate insertion on unique event_id is rejected by DB
        async with factory() as session:
            dup_event = SubscriptionEvent(
                id=str(uuid.uuid4()),
                event_id=event_id,
                app_user_id=user_uuid,
                event_type="INITIAL_PURCHASE",
                raw_payload={},
            )
            session.add(dup_event)
            with pytest.raises(IntegrityError):
                await session.commit()

    async def test_daily_scan_quota_persistence_and_boundaries(self, db_integration_engine):
        """Verifies ScanUsage SQL counting and unique constraint on (user_id, scan_date)."""
        user_uuid = str(uuid.uuid4())
        today = date.today()
        factory = db_integration_engine

        async with factory() as session:
            user = User(id=user_uuid, email="charlie@coinscan.app")
            usage = ScanUsage(
                id=str(uuid.uuid4()),
                user_id=user_uuid,
                scan_date=today,
                scan_count=1,
            )
            session.add(user)
            session.add(usage)
            await session.commit()

        # Duplicate scan_date for same user must violate unique constraint
        async with factory() as session:
            dup_usage = ScanUsage(
                id=str(uuid.uuid4()),
                user_id=user_uuid,
                scan_date=today,
                scan_count=1,
            )
            session.add(dup_usage)
            with pytest.raises(IntegrityError):
                await session.commit()

        # Increment count
        async with factory() as session:
            stmt = select(ScanUsage).where(
                ScanUsage.user_id == user_uuid,
                ScanUsage.scan_date == today,
            )
            res = await session.execute(stmt)
            row = res.scalar_one()
            row.scan_count += 1
            await session.commit()

        async with factory() as session:
            row = await session.get(ScanUsage, row.id)
            assert row.scan_count == 2

    async def test_collection_crud_and_account_isolation(self, db_integration_engine):
        """Verifies multi-tenant collection isolation between User A and User B."""
        user_a = str(uuid.uuid4())
        user_b = str(uuid.uuid4())
        item_a1_id = str(uuid.uuid4())
        item_a2_id = str(uuid.uuid4())
        item_b1_id = str(uuid.uuid4())

        # Add items for User A
        await account_store.add_collection_item_async(
            user_a,
            {
                "id": item_a1_id,
                "coin_name": "1882-CC Morgan Dollar",
                "country": "United States",
                "denomination": "1 Dollar",
                "year": 1882,
                "purchase_price": 410.0,
            },
        )
        await account_store.add_collection_item_async(
            user_a,
            {
                "id": item_a2_id,
                "coin_name": "1907 Saint-Gaudens Double Eagle",
                "country": "United States",
                "denomination": "$20",
                "year": 1907,
                "purchase_price": 28000.0,
            },
        )

        # Add items for User B
        await account_store.add_collection_item_async(
            user_b,
            {
                "id": item_b1_id,
                "coin_name": "Athenian Owl Tetradrachm",
                "country": "Ancient Greece",
                "denomination": "Tetradrachm",
                "year": -440,
                "purchase_price": 850.0,
            },
        )

        # Verify User A sees ONLY their 2 items
        items_a = await account_store.get_collection_items_async(user_a)
        assert len(items_a) == 2
        assert {i["id"] for i in items_a} == {item_a1_id, item_a2_id}

        # Verify User B sees ONLY their 1 item
        items_b = await account_store.get_collection_items_async(user_b)
        assert len(items_b) == 1
        assert items_b[0]["id"] == item_b1_id

        # Verify User A CANNOT delete User B's item
        deleted = await account_store.delete_collection_item_async(user_a, item_b1_id)
        assert deleted is False

        # Verify User B's item still exists
        items_b_after = await account_store.get_collection_items_async(user_b)
        assert len(items_b_after) == 1

        # Delete User A's item
        deleted_a = await account_store.delete_collection_item_async(user_a, item_a1_id)
        assert deleted_a is True
        items_a_remaining = await account_store.get_collection_items_async(user_a)
        assert len(items_a_remaining) == 1
        assert items_a_remaining[0]["id"] == item_a2_id

    async def test_feedback_persistence(self, db_integration_engine):
        """Verifies Feedback record insertion and retrieval."""
        user_uuid = str(uuid.uuid4())
        feedback_uuid = str(uuid.uuid4())
        factory = db_integration_engine

        async with factory() as session:
            user = User(id=user_uuid, email="reporter@coinscan.app")
            fb = Feedback(
                id=feedback_uuid,
                user_id=user_uuid,
                category="recognition_incorrect",
                title="Wrong date on Morgan Dollar",
                description="Scan returned 1881 instead of 1882",
                app_version="1.0.0",
                platform="ios",
                client_ip="192.168.1.10",
            )
            session.add(user)
            session.add(fb)
            await session.commit()

        async with factory() as session:
            saved_fb = await session.get(Feedback, feedback_uuid)
            assert saved_fb is not None
            assert saved_fb.category == "recognition_incorrect"
            assert saved_fb.user_id == user_uuid
            assert saved_fb.title == "Wrong date on Morgan Dollar"

    async def test_cascading_account_deletion(self, db_integration_engine):
        """Verifies that permanent account deletion cascades across all required user tables."""
        user_uuid = str(uuid.uuid4())
        item_uuid = str(uuid.uuid4())
        factory = db_integration_engine

        # Populate user, entitlement, collection item, scan usage, legal consent
        async with factory() as session:
            user = User(id=user_uuid, email="delete_me@coinscan.app")
            ent = Entitlement(user_id=user_uuid, tier="plus", status="active")
            col = CollectionItem(
                id=item_uuid,
                user_id=user_uuid,
                coin_name="Test Coin",
                country="US",
                denomination="1C",
            )
            usage = ScanUsage(
                id=str(uuid.uuid4()),
                user_id=user_uuid,
                scan_date=date.today(),
                scan_count=3,
            )
            consent = UserLegalConsent(
                user_id=user_uuid,
                terms_version="1.0.0",
                privacy_version="1.0.0",
            )
            session.add_all([user, ent, col, usage, consent])
            await session.commit()

        # Verify records exist before deletion
        async with factory() as session:
            assert await session.get(User, user_uuid) is not None
            assert await session.get(Entitlement, user_uuid) is not None
            assert await session.get(CollectionItem, item_uuid) is not None
            assert await session.get(UserLegalConsent, user_uuid) is not None

        # Execute full account deletion
        purged = await account_store.delete_account_async(user_uuid)
        assert isinstance(purged, dict)

        # Verify all user-owned rows are permanently purged from database
        async with factory() as session:
            assert await session.get(User, user_uuid) is None
            assert await session.get(Entitlement, user_uuid) is None
            assert await session.get(CollectionItem, item_uuid) is None
            assert await session.get(UserLegalConsent, user_uuid) is None

            usage_stmt = select(ScanUsage).where(ScanUsage.user_id == user_uuid)
            usage_res = await session.execute(usage_stmt)
            assert usage_res.scalar_one_or_none() is None

    async def test_transaction_rollback_on_unhandled_error(self, db_integration_engine):
        """Verifies that an exception during multi-statement operations rolls back cleanly."""
        user_uuid = str(uuid.uuid4())
        factory = db_integration_engine

        try:
            async with factory() as session:
                user = User(id=user_uuid, email="rollback@coinscan.app")
                session.add(user)
                await session.flush()

                # Simulate mid-transaction unhandled fault
                raise RuntimeError("Simulated database failure during transaction")
        except RuntimeError:
            pass

        # Verify user was NOT saved
        async with factory() as session:
            check_user = await session.get(User, user_uuid)
            assert check_user is None

    @pytest.mark.asyncio
    async def test_delete_supabase_auth_user_invokes_admin_api(self, monkeypatch):
        from backend.app.api.account import delete_supabase_auth_user
        from backend.app.config import settings

        settings.supabase_url = "https://mockproject.supabase.co"
        settings.supabase_service_role_key = "mock-service-role-key-123"

        called_url = None
        called_headers = None

        class MockAsyncClient:
            def __init__(self, *args, **kwargs):
                pass
            async def __aenter__(self):
                return self
            async def __aexit__(self, *args):
                pass
            async def delete(self, url, headers=None):
                nonlocal called_url, called_headers
                called_url = url
                called_headers = headers
                class MockResponse:
                    status_code = 200
                    text = "OK"
                return MockResponse()

        import httpx
        monkeypatch.setattr(httpx, "AsyncClient", MockAsyncClient)

        target_uuid = "12345678-1234-1234-1234-123456789abc"
        success = await delete_supabase_auth_user(target_uuid)
        assert success is True
        assert called_url == f"https://mockproject.supabase.co/auth/v1/admin/users/{target_uuid}"
        assert called_headers["Authorization"] == "Bearer mock-service-role-key-123"
        assert called_headers["apikey"] == "mock-service-role-key-123"

        # Restore
        settings.supabase_url = None
        settings.supabase_service_role_key = None
