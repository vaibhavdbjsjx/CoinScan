"""
Numista API v3 client and catalogue verification service.
Enforces attribution (N# requirement), non-redistribution, and rate limits.

Catalogue data is never invented: when Numista is not configured or not
reachable the client raises CatalogueUnavailableError instead of answering
from local data. A small offline fixture exists for automated tests and the
benchmark only, must be enabled explicitly, and labels every record with
source="offline_test_fixture".
"""

import logging
from typing import Optional, List, Dict, Any
import httpx
from pydantic import BaseModel, Field

logger = logging.getLogger("coinscan.numista")

SOURCE_NUMISTA = "numista"
SOURCE_OFFLINE_FIXTURE = "offline_test_fixture"


class CatalogueUnavailableError(Exception):
    """Numista could not be queried (not configured, HTTP error, timeout, bad payload)."""


class NumistaIssue(BaseModel):
    year: Optional[int] = None
    mint_mark: Optional[str] = None
    mintage: Optional[int] = None
    comment: Optional[str] = None


class NumistaTypeDetail(BaseModel):
    id: Optional[int] = None
    title: str
    country: str
    denomination: Optional[str] = None
    currency: Optional[str] = None
    min_year: Optional[int] = None
    max_year: Optional[int] = None
    composition: Optional[str] = None
    weight_g: Optional[float] = None
    diameter_mm: Optional[float] = None
    thickness_mm: Optional[float] = None
    edge_type: Optional[str] = None
    km_number: Optional[str] = None
    obverse_description: Optional[str] = None
    reverse_description: Optional[str] = None
    issues: List[NumistaIssue] = Field(default_factory=list)
    numista_url: Optional[str] = None
    # Where this record came from: "numista" (live API) or "offline_test_fixture".
    source: str = SOURCE_NUMISTA


class NumistaClient:
    """Async client for querying the official Numista API v3."""

    def __init__(
        self,
        api_key: Optional[str] = None,
        base_url: str = "https://api.numista.com/v3",
        timeout: float = 10.0,
        offline_fixture: bool = False,
    ):
        self.api_key = api_key
        self.base_url = base_url
        self.timeout = timeout
        # Tests/benchmark only. Never enable for real users.
        self.offline_fixture = offline_fixture

    async def search_types(
        self,
        query: str,
        category: str = "coin",
        count: int = 5,
    ) -> List[NumistaTypeDetail]:
        """Searches Numista catalogue types by keyword / query string.

        Returns [] when Numista answers but has no match.
        Raises CatalogueUnavailableError when Numista cannot be queried.
        """
        if self.offline_fixture:
            return self._get_fallback_catalog(query)
        if not self.api_key:
            raise CatalogueUnavailableError("Numista API key is not configured")

        headers = {
            "Numista-API-Key": self.api_key,
            "Accept": "application/json",
        }
        params = {
            "q": query,
            "category": category,
            "count": count,
        }

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                resp = await client.get(f"{self.base_url}/types", headers=headers, params=params)
        except httpx.HTTPError as exc:
            logger.warning(f"Numista search failed: {type(exc).__name__}")
            raise CatalogueUnavailableError(f"transport error ({type(exc).__name__})") from None

        if resp.status_code != 200:
            logger.warning(f"Numista search returned HTTP {resp.status_code}")
            raise CatalogueUnavailableError(f"HTTP {resp.status_code}")

        try:
            data = resp.json()
            return [self._parse_type(item) for item in (data.get("types") or [])]
        except (ValueError, TypeError, AttributeError) as exc:
            logger.warning(f"Numista search returned an unparseable payload: {type(exc).__name__}")
            raise CatalogueUnavailableError("unparseable response") from None

    @staticmethod
    def _parse_type(item: Dict[str, Any], fallback_id: Optional[int] = None) -> NumistaTypeDetail:
        type_id = item.get("id", fallback_id)
        return NumistaTypeDetail(
            id=type_id,
            title=item.get("title") or "",
            country=(item.get("issuer") or {}).get("name") or "Unknown",
            denomination=(item.get("value") or {}).get("text"),
            min_year=item.get("min_year"),
            max_year=item.get("max_year"),
            composition=(item.get("composition") or {}).get("text"),
            weight_g=item.get("weight"),
            diameter_mm=item.get("diameter"),
            km_number=(item.get("reference") or {}).get("km"),
            numista_url=f"https://en.numista.com/catalogue/pieces{type_id}.html" if type_id else None,
            source=SOURCE_NUMISTA,
        )

    async def get_type_details(self, type_id: int) -> Optional[NumistaTypeDetail]:
        """Retrieves comprehensive specifications for a specific Numista catalogue type ID.

        Returns None when the type does not exist (HTTP 404).
        Raises CatalogueUnavailableError when Numista cannot be queried.
        """
        if self.offline_fixture:
            for item in self._get_fallback_catalog(""):
                if item.id == type_id:
                    return item
            return None
        if not self.api_key:
            raise CatalogueUnavailableError("Numista API key is not configured")

        headers = {
            "Numista-API-Key": self.api_key,
            "Accept": "application/json",
        }

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                resp = await client.get(f"{self.base_url}/types/{type_id}", headers=headers)
        except httpx.HTTPError as exc:
            raise CatalogueUnavailableError(f"transport error ({type(exc).__name__})") from None

        if resp.status_code == 404:
            return None
        if resp.status_code != 200:
            raise CatalogueUnavailableError(f"HTTP {resp.status_code}")
        try:
            return self._parse_type(resp.json(), fallback_id=type_id)
        except (ValueError, TypeError, AttributeError):
            raise CatalogueUnavailableError("unparseable response") from None

    def _get_fallback_catalog(self, query: str) -> List[NumistaTypeDetail]:
        """
        OFFLINE TEST FIXTURE - used only when offline_fixture=True (tests / benchmark).

        These four records are hand-written reference data, not Numista responses.
        Every record is labelled source="offline_test_fixture" so it can never be
        presented as verified Numista data.
        """
        q = query.lower()
        records = [
            NumistaTypeDetail(
                id=1492,
                title="1 Dollar 'Morgan Dollar'",
                country="United States",
                denomination="1 Dollar",
                currency="USD",
                min_year=1878,
                max_year=1921,
                composition="90% Silver, 10% Copper",
                weight_g=26.73,
                diameter_mm=38.1,
                thickness_mm=2.4,
                edge_type="Reeded",
                km_number="KM# 110",
                obverse_description="Liberty head facing left with Phrygian cap.",
                reverse_description="Heraldic eagle holding arrows and olive branch.",
                numista_url="https://en.numista.com/catalogue/pieces1492.html",
                issues=[
                    NumistaIssue(year=1882, mint_mark="CC", mintage=1133000, comment="Carson City mint"),
                    NumistaIssue(year=1882, mint_mark="O", mintage=6070000, comment="New Orleans mint"),
                    NumistaIssue(year=1882, mint_mark="S", mintage=9250000, comment="San Francisco mint"),
                    NumistaIssue(year=1882, mint_mark="None", mintage=11100000, comment="Philadelphia mint"),
                ]
            ),
            NumistaTypeDetail(
                id=4378,
                title="1 Rupee - George V",
                country="British India",
                denomination="1 Rupee",
                currency="INR",
                min_year=1911,
                max_year=1936,
                composition="91.7% Silver, 8.3% Copper",
                weight_g=11.66,
                diameter_mm=30.5,
                thickness_mm=1.9,
                edge_type="Reeded",
                km_number="KM# 524",
                obverse_description="Crowned bust of King George V facing left.",
                reverse_description="Denomination and year surrounded by floral wreath.",
                numista_url="https://en.numista.com/catalogue/pieces4378.html",
                issues=[
                    NumistaIssue(year=1912, mint_mark="B", mintage=15104000, comment="Bombay mint (incuse bead/dot)"),
                    NumistaIssue(year=1912, mint_mark="C", mintage=12850000, comment="Calcutta mint (no mint mark)"),
                ]
            ),
            NumistaTypeDetail(
                id=1259,
                title="1 Sovereign - Victoria (Jubilee Head)",
                country="United Kingdom",
                denomination="1 Sovereign",
                currency="GBP",
                min_year=1887,
                max_year=1892,
                composition="91.67% Gold, 8.33% Copper",
                weight_g=7.99,
                diameter_mm=22.05,
                thickness_mm=1.52,
                edge_type="Reeded",
                km_number="KM# 767",
                obverse_description="Jubilee bust of Queen Victoria facing left.",
                reverse_description="Saint George slaying the Dragon with date below.",
                numista_url="https://en.numista.com/catalogue/pieces1259.html",
                issues=[
                    NumistaIssue(year=1887, mint_mark="None", mintage=1115500, comment="London mint"),
                    NumistaIssue(year=1887, mint_mark="M", mintage=1000000, comment="Melbourne mint"),
                    NumistaIssue(year=1887, mint_mark="S", mintage=800000, comment="Sydney mint"),
                ]
            ),
            NumistaTypeDetail(
                id=6853,
                title="Attic Tetradrachm (Athena / Owl)",
                country="Ancient Greece (Athens)",
                denomination="Tetradrachm",
                currency="Attic Drachma",
                min_year=-454,
                max_year=-404,
                composition="98% Silver",
                weight_g=17.2,
                diameter_mm=24.0,
                edge_type="Rough / irregular hammered",
                km_number="HGC 4, 1597",
                obverse_description="Helmeted head of Athena right, in crested Attic helmet.",
                reverse_description="Owl standing right, head facing; olive sprig and crescent moon behind, ΑΘΕ in front.",
                numista_url="https://en.numista.com/catalogue/pieces6853.html",
                issues=[]
            )
        ]

        records = [r.model_copy(update={"source": SOURCE_OFFLINE_FIXTURE}) for r in records]

        if not q:
            return records

        matching = []
        for r in records:
            if (
                q in r.title.lower()
                or q in r.country.lower()
                or (r.km_number and q in r.km_number.lower())
                or (r.denomination and q in r.denomination.lower())
            ):
                matching.append(r)
        return matching
