"""
Request models for the CoinScan backend API.
"""

from typing import Optional, List
from pydantic import BaseModel, Field


class ClientMetadata(BaseModel):
    appVersion: Optional[str] = Field(default=None, alias="app_version")
    deviceModel: Optional[str] = Field(default=None, alias="device_model")
    detectedYearHint: Optional[int] = Field(default=None, alias="detected_year_hint")
    detectedTextHints: List[str] = Field(default_factory=list, alias="detected_text_hints")


class JsonRecognitionRequest(BaseModel):
    """Base64/JSON payload alternative to multipart/form-data."""
    model_config = {"populate_by_name": True}

    frontImageBase64: str = Field(alias="front_image_base64", min_length=100, max_length=28_000_000)
    reverseImageBase64: Optional[str] = Field(default=None, alias="reverse_image_base64", max_length=28_000_000)
    edgeImageBase64: Optional[str] = Field(default=None, alias="edge_image_base64", max_length=28_000_000)
    preferredCurrency: str = Field(default="USD", min_length=3, max_length=5, alias="preferred_currency")
    locale: str = Field(default="en-US", max_length=20)
    clientMetadata: Optional[ClientMetadata] = Field(default=None, alias="client_metadata")
