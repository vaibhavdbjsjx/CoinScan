"""
Database module for CoinScan backend.
Provides async SQLAlchemy engine, session management, and models.
"""

from backend.app.db.session import (
    get_db,
    init_db,
    close_db,
    get_async_engine,
    get_session_factory,
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
    GuestScanUsage,
)

__all__ = [
    "get_db",
    "init_db",
    "close_db",
    "get_async_engine",
    "get_session_factory",
    "Base",
    "User",
    "Entitlement",
    "Subscription",
    "SubscriptionEvent",
    "ScanUsage",
    "ScanHistory",
    "CollectionItem",
    "ApiKey",
    "ApiKeyUsage",
    "Feedback",
    "SecurityEvent",
    "UserLegalConsent",
    "GuestScanUsage",
]
