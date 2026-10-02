"""
User Collection & Vault Management API.

Allows users to organize, track, and manage their physical coin collection.
Enforces strict IDOR ownership checks: Users can NEVER access or mutate another user's collection.
Maintains historical acquisition valuation snapshots alongside current market valuations.
"""

import time
import uuid
import logging
from typing import Dict, Any, List, Optional
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, HTTPException, status

from backend.app.security.auth import get_current_user, verify_terms_accepted, AuthenticatedUser
from backend.app.api.account import account_store


logger = logging.getLogger("coinscan.collection")
router = APIRouter(prefix="/v1/collection", tags=["Collection Vault"])


import math
from pydantic import field_validator

class CollectionItemCreate(BaseModel):
    id: Optional[str] = None
    coin_name: str = Field(..., min_length=2, max_length=200)
    country: str = Field(..., min_length=1, max_length=100)
    denomination: str = Field(..., min_length=1, max_length=100)
    year: Optional[int] = Field(None, ge=-2000, le=2100)
    mint_mark: Optional[str] = Field(None, max_length=50)
    composition: Optional[str] = Field(None, max_length=150)
    grade: Optional[str] = Field(None, max_length=50)  # e.g. "MS65", "VF30"
    numista_id: Optional[int] = Field(None, ge=1)
    purchase_price: Optional[float] = Field(None, ge=0.0, le=100_000_000.0)
    purchase_date: Optional[str] = Field(None, max_length=50)  # YYYY-MM-DD
    notes: Optional[str] = Field(None, max_length=5000)
    currency_code: str = Field("USD", min_length=3, max_length=5, pattern=r"^[A-Za-z]{3,5}$")
    initial_valuation_snapshot: Optional[float] = Field(None, ge=0.0, le=100_000_000.0)
    front_image_url: Optional[str] = Field(None, max_length=1000)
    reverse_image_url: Optional[str] = Field(None, max_length=1000)
    is_favorite: Optional[bool] = False

    @field_validator("purchase_price", "initial_valuation_snapshot", mode="after")
    @classmethod
    def validate_finite_floats(cls, v: Optional[float]) -> Optional[float]:
        if v is not None and (math.isnan(v) or math.isinf(v)):
            raise ValueError("Numeric valuation must be a finite number.")
        return v


class CollectionItemResponse(BaseModel):
    id: str
    user_id: str
    coin_name: str
    country: str
    denomination: str
    year: Optional[int] = None
    mint_mark: Optional[str] = None
    composition: Optional[str] = None
    grade: Optional[str] = None
    numista_id: Optional[int] = None
    purchase_price: Optional[float] = None
    purchase_date: Optional[str] = None
    notes: Optional[str] = None
    currency_code: str
    initial_valuation_snapshot: Optional[float] = None
    current_estimated_value: Optional[float] = None
    front_image_url: Optional[str] = None
    reverse_image_url: Optional[str] = None
    is_favorite: Optional[bool] = False
    created_at: float
    updated_at: float


def _client_item_id(value: Optional[str]) -> Optional[str]:
    """A client-chosen item id is kept only if it is a real UUID (the column type)."""
    if not value:
        return None
    try:
        return str(uuid.UUID(value))
    except (ValueError, TypeError, AttributeError):
        return None


@router.post("", response_model=CollectionItemResponse)
async def add_collection_item(
    item_in: CollectionItemCreate,
    current_user: AuthenticatedUser = Depends(verify_terms_accepted),
):
    """
    Adds a verified coin item to the user's permanent Collection Vault.
    """
    if not current_user.is_authenticated:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required to save coins to your vault.",
        )

    now = time.time()
    item_id = _client_item_id(item_in.id) or str(uuid.uuid4())

    item_dict = {
        "id": item_id,
        "user_id": current_user.user_id,
        "coin_name": item_in.coin_name,
        "country": item_in.country,
        "denomination": item_in.denomination,
        "year": item_in.year,
        "mint_mark": item_in.mint_mark,
        "composition": item_in.composition,
        "grade": item_in.grade,
        "numista_id": item_in.numista_id,
        "purchase_price": item_in.purchase_price,
        "purchase_date": item_in.purchase_date,
        "notes": item_in.notes,
        "currency_code": item_in.currency_code,
        "initial_valuation_snapshot": item_in.initial_valuation_snapshot or item_in.purchase_price,
        "current_estimated_value": item_in.initial_valuation_snapshot or item_in.purchase_price,
        "front_image_url": item_in.front_image_url,
        "reverse_image_url": item_in.reverse_image_url,
        "is_favorite": item_in.is_favorite or False,
        "created_at": now,
        "updated_at": now,
    }

    await account_store.add_collection_item_async(current_user.user_id, item_dict)
    logger.info(f"Collection item added: id={item_id} user={current_user.user_id} coin='{item_in.coin_name}'")
    return CollectionItemResponse(**item_dict)


@router.get("", response_model=List[CollectionItemResponse])
async def list_collection_items(
    current_user: AuthenticatedUser = Depends(verify_terms_accepted),
):
    """
    Lists all collection vault items owned exclusively by the authenticated user.
    """
    if not current_user.is_authenticated:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required to view your collection.",
        )

    items = await account_store.get_collection_items_async(current_user.user_id)
    return [CollectionItemResponse(**i) for i in items]


@router.delete("/{item_id}")
async def delete_collection_item(
    item_id: str,
    current_user: AuthenticatedUser = Depends(verify_terms_accepted),
):
    """
    Removes a coin item from the user's Collection Vault.
    Guarantees that a user cannot delete another user's coin item (IDOR protection).
    """
    if not current_user.is_authenticated:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required.",
        )

    deleted = await account_store.delete_collection_item_async(current_user.user_id, item_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Collection item not found or you do not have permission to delete it.",
        )

    return {"status": "success", "message": "Item removed from collection vault.", "item_id": item_id}
