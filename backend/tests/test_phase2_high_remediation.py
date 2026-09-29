"""
Regression tests for Phase 2 High-Severity production remediations.
"""

import pytest
import pytest_asyncio
import uuid
from pydantic import ValidationError
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy import select

from backend.app.config import settings
import backend.app.db.session as session_module
from backend.app.models.requests import JsonRecognitionRequest
from backend.app.security.quota_service import QuotaEngine
from backend.app.security.rate_limit import SubscriptionTier
from backend.app.services.valuation.valuation_service import ValuationEngine
from backend.app.services.valuation.metal_price_provider import MetalSpotPriceProvider
from backend.app.db.models import Base, User, ScanUsage


TEST_DB_URL = "sqlite+aiosqlite:///:memory:"


@pytest_asyncio.fixture
async def test_db():
    orig_env = settings.app_env
    orig_db_url = settings.database_url
    orig_engine = session_module._engine
    orig_factory = session_module._session_factory

    settings.app_env = "production"
    settings.database_url = TEST_DB_URL

    test_engine = create_async_engine(TEST_DB_URL, echo=False)
    session_factory = async_sessionmaker(
        bind=test_engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    session_module._engine = test_engine
    session_module._session_factory = session_factory

    yield session_factory

    session_module._engine = orig_engine
    session_module._session_factory = orig_factory
    settings.app_env = orig_env
    settings.database_url = orig_db_url
    await test_engine.dispose()


@pytest.fixture
def fresh_quota_engine():
    engine = QuotaEngine()
    engine.reset_usage_for_test()
    return engine


@pytest.mark.asyncio
async def test_issue_conc_01_quota_db_synchronization(fresh_quota_engine, test_db):
    """
    Verifies that QuotaEngine.reserve_slot and commit write to ScanUsage in the database,
    preventing multi-worker or restart quota loss.
    """
    engine = fresh_quota_engine
    user_id = str(uuid.uuid4())

    async with test_db() as db:
        # Pre-create user in database
        db_user = User(
            id=user_id,
            email=f"{user_id}@coinscan.app",
        )
        db.add(db_user)
        await db.commit()

    # Reserve slot with QuotaEngine (automatically uses configured session_factory)
    reservation = await engine.reserve_slot(
        user_id, tier=SubscriptionTier.FREE
    )
    assert reservation is not None
    assert reservation.committed is False
    assert reservation.released is False

    # Commit reservation
    await reservation.commit()
    assert reservation.committed is True

    # Check database directly for persisted ScanUsage
    async with test_db() as verify_db:
        res = await verify_db.execute(select(ScanUsage).where(ScanUsage.user_id == user_id))
        usage_record = res.scalars().first()
        assert usage_record is not None
        assert usage_record.scan_count >= 1


def test_issue_api_01_image_base64_length_bounds():
    """
    Verifies that JsonRecognitionRequest enforces min_length=100 and max_length=28_000_000
    on frontImageBase64, reverseImageBase64, and edgeImageBase64 to prevent payload bomb and empty DoS.
    """
    # 1. Reject too short payload (< 100 chars)
    with pytest.raises(ValidationError) as exc_info:
        JsonRecognitionRequest(frontImageBase64="data:image/jpeg;base64,too_short")
    errors = exc_info.value.errors()
    assert any("front" in str(e["loc"]).lower() for e in errors)

    # 2. Accept valid length payload (>= 100 chars and <= 28MB)
    valid_base64 = "A" * 150
    valid_req = JsonRecognitionRequest(
        frontImageBase64=valid_base64,
        reverseImageBase64=valid_base64,
    )
    assert valid_req.frontImageBase64 == valid_base64
    assert valid_req.reverseImageBase64 == valid_base64

    # 3. Reject oversized payload (> 28MB)
    with pytest.raises(ValidationError) as exc_info:
        JsonRecognitionRequest(frontImageBase64="A" * 28_000_001)
    errors = exc_info.value.errors()
    assert any("front" in str(e["loc"]).lower() for e in errors)


def test_issue_val_02_metal_spot_price_provider_settings_injection(monkeypatch):
    """
    Verifies that ValuationEngine automatically injects settings.metals_api_key
    and settings.metals_api_base_url into MetalSpotPriceProvider.
    """
    monkeypatch.setattr(settings, "metals_api_key", "test_secret_metals_api_key_123")
    monkeypatch.setattr(settings, "metals_api_base_url", "https://metals.test.provider/v1")

    engine = ValuationEngine()
    assert engine.metal_provider is not None
    assert isinstance(engine.metal_provider, MetalSpotPriceProvider)
    assert engine.metal_provider.api_key == "test_secret_metals_api_key_123"
    assert engine.metal_provider.base_url == "https://metals.test.provider/v1"
