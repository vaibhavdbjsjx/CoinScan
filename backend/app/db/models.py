"""
SQLAlchemy ORM models strictly matching the production PostgreSQL / Supabase schema migrations:
- 20260830_phase11_production_schema.sql
- 20260925_user_legal_consents.sql

Guarantees:
1. Native PostgreSQL UUID primary and foreign keys (with dialect-agnostic GUID TypeDecorator).
2. Native PostgreSQL custom ENUMs: subscription_tier_enum, subscription_status_enum, feedback_category_enum.
3. Native PostgreSQL JSONB storage for payloads and result structures.
4. Strict multi-tenant cascading deletes matching migration schema.
"""

import uuid
from datetime import datetime, date
from typing import Optional, Any
from sqlalchemy import (
    Column,
    String,
    Integer,
    Numeric,
    Boolean,
    Date,
    DateTime,
    Text,
    ForeignKey,
    UniqueConstraint,
    JSON,
    Enum as SAEnum,
    func,
)
from sqlalchemy.types import TypeDecorator, CHAR
from sqlalchemy.dialects.postgresql import UUID as PG_UUID, JSONB
from sqlalchemy.orm import DeclarativeBase, relationship


class GUID(TypeDecorator):
    """Platform-independent GUID type.
    Uses PostgreSQL's native UUID type, otherwise uses CHAR(36).
    """
    impl = CHAR
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == "postgresql":
            return dialect.type_descriptor(PG_UUID(as_uuid=False))
        else:
            return dialect.type_descriptor(CHAR(36))

    def process_bind_param(self, value, dialect):
        if value is None:
            return value
        if isinstance(value, uuid.UUID):
            return str(value)
        return str(value)

    def process_result_value(self, value, dialect):
        if value is None:
            return value
        return str(value)


# Custom PostgreSQL Enum definitions matching migrations
subscription_tier_enum = SAEnum(
    "free", "plus", "pro", "enterprise",
    name="subscription_tier_enum",
    create_type=False,
)

subscription_status_enum = SAEnum(
    "none", "trial", "active", "grace", "billing_retry", "cancelled", "expired", "revoked",
    name="subscription_status_enum",
    create_type=False,
)

feedback_category_enum = SAEnum(
    "recognition_incorrect", "valuation_incorrect", "camera_problem", "gallery_problem",
    "subscription_problem", "app_crash", "performance", "feature_request", "other",
    name="feedback_category_enum",
    create_type=False,
)

json_variant = JSON().with_variant(JSONB, "postgresql")


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    # UUID primary key referencing Supabase auth.users(id) in PostgreSQL migration
    id = Column(GUID, primary_key=True, default=lambda: str(uuid.uuid4()))
    email = Column(String(255), nullable=False, index=True)
    display_name = Column(String(255), nullable=True)
    avatar_url = Column(Text, nullable=True)
    preferred_currency = Column(String(10), nullable=False, default="USD")
    locale = Column(String(20), nullable=False, default="en-US")
    created_at = Column(DateTime(timezone=True), nullable=False, default=func.now())
    updated_at = Column(DateTime(timezone=True), nullable=False, default=func.now(), onupdate=func.now())

    # Relationships with strict cascade deletion matching migration constraints
    entitlement = relationship("Entitlement", back_populates="user", uselist=False, cascade="all, delete-orphan")
    legal_consent = relationship("UserLegalConsent", back_populates="user", uselist=False, cascade="all, delete-orphan")
    collection_items = relationship("CollectionItem", back_populates="user", cascade="all, delete-orphan")
    scan_history = relationship("ScanHistory", back_populates="user", cascade="all, delete-orphan")
    scan_usage = relationship("ScanUsage", back_populates="user", cascade="all, delete-orphan")
    api_keys = relationship("ApiKey", back_populates="user", cascade="all, delete-orphan")


class Entitlement(Base):
    __tablename__ = "entitlements"

    user_id = Column(GUID, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    tier = Column(subscription_tier_enum, nullable=False, default="free", index=True)
    status = Column(subscription_status_enum, nullable=False, default="none")
    daily_scan_limit = Column(Integer, nullable=False, default=3)
    active_subscription_id = Column(GUID, nullable=True)
    expires_at = Column(DateTime(timezone=True), nullable=True)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="entitlement")


class Subscription(Base):
    __tablename__ = "subscriptions"

    id = Column(GUID, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(GUID, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    original_transaction_id = Column(String(255), nullable=False, index=True)
    product_id = Column(String(255), nullable=False)
    store = Column(String(50), nullable=False)  # 'apple_app_store', 'google_play', 'stripe'
    status = Column(subscription_status_enum, nullable=False, default="active")
    starts_at = Column(DateTime(timezone=True), nullable=False, default=func.now())
    current_period_start = Column(DateTime(timezone=True), nullable=False, default=func.now())
    current_period_end = Column(DateTime(timezone=True), nullable=False)
    cancel_at_period_end = Column(Boolean, nullable=False, default=False)
    is_sandbox = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=func.now())
    updated_at = Column(DateTime(timezone=True), nullable=False, default=func.now(), onupdate=func.now())

    user = relationship("User")


class SubscriptionEvent(Base):
    __tablename__ = "subscription_events"

    id = Column(GUID, primary_key=True, default=lambda: str(uuid.uuid4()))
    event_id = Column(String(255), nullable=False, unique=True, index=True)
    app_user_id = Column(String(255), nullable=False, index=True)
    event_type = Column(String(100), nullable=False)
    product_id = Column(String(255), nullable=True)
    store = Column(String(50), nullable=True)
    environment = Column(String(50), nullable=False, default="PRODUCTION")
    raw_payload = Column(json_variant, nullable=False)
    received_at = Column(DateTime(timezone=True), nullable=False, default=func.now())


class ScanUsage(Base):
    __tablename__ = "scan_usage"

    id = Column(GUID, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(GUID, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    scan_date = Column(Date, nullable=False)
    scan_count = Column(Integer, nullable=False, default=1)
    created_at = Column(DateTime(timezone=True), nullable=False, default=func.now())
    updated_at = Column(DateTime(timezone=True), nullable=False, default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint("user_id", "scan_date", name="uq_user_scan_date"),
    )

    user = relationship("User", back_populates="scan_usage")


class ScanHistory(Base):
    __tablename__ = "scan_history"

    id = Column(GUID, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(GUID, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    scanned_at = Column(DateTime(timezone=True), nullable=False, default=func.now())
    coin_name = Column(String(255), nullable=True)
    country = Column(String(100), nullable=True)
    denomination = Column(String(100), nullable=True)
    year = Column(String(20), nullable=True)
    mint_mark = Column(String(50), nullable=True)
    grade = Column(String(50), nullable=True)
    confidence_score = Column(Numeric(5, 4), nullable=True)
    numista_id = Column(Integer, nullable=True)
    status_label = Column(String(50), nullable=False)
    front_image_url = Column(Text, nullable=True)
    reverse_image_url = Column(Text, nullable=True)
    result_json = Column(json_variant, nullable=True)

    user = relationship("User", back_populates="scan_history")


class CollectionItem(Base):
    __tablename__ = "collection_items"

    id = Column(GUID, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(GUID, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    coin_name = Column(String(255), nullable=False)
    country = Column(String(100), nullable=False)
    denomination = Column(String(100), nullable=False)
    year = Column(Integer, nullable=True)
    mint_mark = Column(String(50), nullable=True)
    composition = Column(String(150), nullable=True)
    grade = Column(String(50), nullable=True)
    numista_id = Column(Integer, nullable=True)
    purchase_price = Column(Numeric(12, 2), nullable=True)
    purchase_date = Column(Date, nullable=True)
    currency_code = Column(String(10), nullable=False, default="USD")
    initial_valuation_snapshot = Column(Numeric(12, 2), nullable=True)
    current_estimated_value = Column(Numeric(12, 2), nullable=True)
    notes = Column(Text, nullable=True)
    front_image_url = Column(Text, nullable=True)
    reverse_image_url = Column(Text, nullable=True)
    is_favorite = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=func.now())
    updated_at = Column(DateTime(timezone=True), nullable=False, default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="collection_items")


class ApiKey(Base):
    __tablename__ = "api_keys"

    id = Column(GUID, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(GUID, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    key_prefix = Column(String(32), nullable=False)
    key_hash = Column(String(128), nullable=False, unique=True, index=True)
    name = Column(String(255), nullable=False)
    tier = Column(subscription_tier_enum, nullable=False, default="free")
    monthly_limit = Column(Integer, nullable=False, default=500)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=func.now())
    last_used_at = Column(DateTime(timezone=True), nullable=True)

    user = relationship("User", back_populates="api_keys")


class ApiKeyUsage(Base):
    __tablename__ = "api_key_usage"

    id = Column(GUID, primary_key=True, default=lambda: str(uuid.uuid4()))
    api_key_id = Column(GUID, ForeignKey("api_keys.id", ondelete="CASCADE"), nullable=False)
    usage_month = Column(Date, nullable=False)
    request_count = Column(Integer, nullable=False, default=0)
    success_count = Column(Integer, nullable=False, default=0)
    rate_limit_hits = Column(Integer, nullable=False, default=0)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint("api_key_id", "usage_month", name="uq_key_usage_month"),
    )


class Feedback(Base):
    __tablename__ = "feedback"

    id = Column(GUID, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(GUID, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    category = Column(feedback_category_enum, nullable=False)
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=False)
    app_version = Column(String(50), nullable=False)
    platform = Column(String(50), nullable=False)
    request_id = Column(String(100), nullable=True)
    client_ip = Column(String(50), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=func.now())

    user = relationship("User")


class SecurityEvent(Base):
    __tablename__ = "security_events"

    id = Column(GUID, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(GUID, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    event_type = Column(String(100), nullable=False, index=True)
    ip_address = Column(String(50), nullable=True)
    user_agent = Column(Text, nullable=True)
    details = Column(json_variant, nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=func.now())

    user = relationship("User")


class UserLegalConsent(Base):
    __tablename__ = "user_legal_consents"

    user_id = Column(GUID, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    terms_version = Column(String(50), nullable=False)
    privacy_version = Column(String(50), nullable=False)
    accepted_at = Column(DateTime(timezone=True), nullable=False, default=func.now())
    updated_at = Column(DateTime(timezone=True), nullable=False, default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="legal_consent")
