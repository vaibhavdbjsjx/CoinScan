"""
Vision AI Provider abstractions and implementations for Gemini and OpenAI.
Extracts structured numismatic observations from multi-sided coin captures.
"""

from abc import ABC, abstractmethod
from typing import Optional, List, Dict, Any
import json
import re
import httpx
from pydantic import BaseModel, Field


class RawVisionObservation(BaseModel):
    """Structured observation extracted by the vision AI from joint images."""
    country: Optional[str] = None
    issuer: Optional[str] = None
    denomination: Optional[str] = None
    year: Optional[int] = None
    mint_mark: Optional[str] = None
    composition: Optional[str] = None
    obverse_description: Optional[str] = None
    reverse_description: Optional[str] = None
    edge_description: Optional[str] = None
    visible_inscriptions: List[str] = Field(default_factory=list)
    km_number_guess: Optional[str] = None
    numista_id_guess: Optional[int] = None
    obverse_reverse_consistent: bool = True
    contradiction_notes: Optional[str] = None
    candidate_varieties: List[str] = Field(default_factory=list)
    confidence_reasoning: str = ""
    # The vision model's SELF-reported similarity; uncalibrated. Neutral when omitted.
    visual_similarity_score: float = Field(default=0.5, ge=0.0, le=1.0)


class VisionProviderError(Exception):
    """Sanitized provider failure.

    The message is safe to log and never contains request URLs, headers or
    credentials. Callers must still not return it verbatim to clients.
    """

    def __init__(self, provider: str, reason: str, status_code: Optional[int] = None):
        self.provider = provider
        self.reason = reason
        self.status_code = status_code
        detail = f"{provider} vision request failed: {reason}"
        if status_code is not None:
            detail += f" (HTTP {status_code})"
        super().__init__(detail)


async def _post_to_provider(
    provider: str,
    url: str,
    payload: Dict[str, Any],
    headers: Dict[str, str],
    timeout: float,
) -> Dict[str, Any]:
    """POSTs to a vision provider and converts every failure into a VisionProviderError.

    httpx exception messages include the full request URL, so they are never
    propagated; only the status code / exception class name is kept.
    """
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.post(url, json=payload, headers=headers)
    except httpx.TimeoutException:
        raise VisionProviderError(provider, "timeout") from None
    except httpx.HTTPError as exc:
        raise VisionProviderError(provider, f"transport error ({type(exc).__name__})") from None

    if resp.status_code >= 400:
        raise VisionProviderError(provider, "provider returned an error", resp.status_code)

    try:
        return resp.json()
    except ValueError:
        raise VisionProviderError(provider, "response was not valid JSON") from None


def safe_parse_vision_response(text: str) -> RawVisionObservation:
    """
    Defensively parses and validates unstructured AI vision responses.
    
    Guarantees:
    - Strips markdown code fences (```json ... ```)
    - Isolates outer JSON object if model generates conversational preamble/postscript
    - Sanitizes and coerces year fields (rejects unparsable strings, validates realistic era)
    - Clamps visual_similarity_score to [0.0, 1.0]
    - Fallback defaults for missing non-critical attributes
    """
    cleaned = text.strip()
    if cleaned.startswith("```"):
        first_newline = cleaned.find("\n")
        if first_newline != -1:
            cleaned = cleaned[first_newline + 1:]
        if cleaned.endswith("```"):
            cleaned = cleaned[:-3].strip()

    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start != -1 and end != -1 and end > start:
        cleaned = cleaned[start : end + 1]

    try:
        raw_dict = json.loads(cleaned)
        if not isinstance(raw_dict, dict):
            raw_dict = {}
    except (json.JSONDecodeError, ValueError):
        return RawVisionObservation(
            confidence_reasoning="Model returned malformed unparsable response.",
            visual_similarity_score=0.1,
            obverse_reverse_consistent=False,
        )

    # Sanitize year
    raw_year = raw_dict.get("year")
    if raw_year is not None:
        if isinstance(raw_year, str):
            match = re.search(r"-?\d{1,4}", raw_year)
            if match:
                try:
                    val = int(match.group(0))
                    raw_dict["year"] = val if -1000 <= val <= 2100 else None
                except ValueError:
                    raw_dict["year"] = None
            else:
                raw_dict["year"] = None
        elif isinstance(raw_year, (int, float)):
            val = int(raw_year)
            raw_dict["year"] = val if -1000 <= val <= 2100 else None
        else:
            raw_dict["year"] = None

    # Sanitize numista_id_guess
    raw_numista = raw_dict.get("numista_id_guess")
    if raw_numista is not None:
        try:
            n_val = int(raw_numista)
            raw_dict["numista_id_guess"] = n_val if n_val > 0 else None
        except (ValueError, TypeError):
            raw_dict["numista_id_guess"] = None

    # Sanitize lists
    if not isinstance(raw_dict.get("visible_inscriptions"), list):
        raw_dict["visible_inscriptions"] = []
    else:
        raw_dict["visible_inscriptions"] = [str(x) for x in raw_dict["visible_inscriptions"] if x is not None]

    if not isinstance(raw_dict.get("candidate_varieties"), list):
        raw_dict["candidate_varieties"] = []
    else:
        raw_dict["candidate_varieties"] = [str(x) for x in raw_dict["candidate_varieties"] if x is not None]

    # Clamp visual similarity score
    raw_score = raw_dict.get("visual_similarity_score")
    if raw_score is not None:
        try:
            score_f = float(raw_score)
            raw_dict["visual_similarity_score"] = max(0.0, min(1.0, score_f))
        except (ValueError, TypeError):
            raw_dict["visual_similarity_score"] = 0.5
    else:
        raw_dict["visual_similarity_score"] = 0.5  # omitted by the model: neutral, never optimistic

    valid_fields = RawVisionObservation.model_fields.keys()
    filtered_dict = {k: v for k, v in raw_dict.items() if k in valid_fields}

    return RawVisionObservation(**filtered_dict)


class VisionProvider(ABC):
    """Abstract interface for multi-image vision analysis."""

    @abstractmethod
    async def analyze_coin_images(
        self,
        front_b64: str,
        reverse_b64: Optional[str] = None,
        edge_b64: Optional[str] = None,
        detected_text_hints: Optional[List[str]] = None,
    ) -> RawVisionObservation:
        pass


SYSTEM_PROMPT = """
You are an expert numismatist and computer vision specialist.
Analyze the provided coin photograph(s) (Front, and optionally Reverse and Edge).
Your goal is to extract accurate, structured numismatic observations.

CRITICAL INSTRUCTIONS:
1. Examine both Front and Reverse together. Verify if both sides correspond to the same coin issue (obverse_reverse_consistent).
2. Look for clear date numerals (Gregorian or transliterated historical era), mint marks (e.g. CC, O, S, D, A, mint letters), denomination, and inscriptions.
3. If an attribute is worn, illegible, or uncertain, state null rather than inventing a number.
4. Provide candidate varieties or KM# / Numista type identifiers if known.
5. Return strictly valid JSON conforming to the requested schema.
"""

JSON_SCHEMA_PROMPT = """
Return JSON matching this exact structure:
{
  "country": "Country/Issuer name",
  "issuer": "Issuing authority or monarch if applicable",
  "denomination": "Denomination (e.g. 1 Dollar, 1 Rupee, 50 Cents)",
  "year": 1882,
  "mint_mark": "CC or None",
  "composition": "e.g. 90% Silver, 10% Copper or Bronze",
  "obverse_description": "Detailed description of front motif",
  "reverse_description": "Detailed description of reverse motif",
  "edge_description": "Reeded, lettered, or plain if visible",
  "visible_inscriptions": ["List of read text tokens"],
  "km_number_guess": "KM# 110 if recognized",
  "numista_id_guess": null,
  "obverse_reverse_consistent": true,
  "contradiction_notes": null,
  "candidate_varieties": ["List of possible varieties"],
  "confidence_reasoning": "Clear factual explanation of visual match",
  "visual_similarity_score": 0.90
}
"""


class GeminiVisionProvider(VisionProvider):
    """Google Gemini 2.0 / 1.5 Flash Vision Provider."""

    def __init__(self, api_key: str, model: str = "gemini-2.0-flash", timeout: float = 15.0):
        self.api_key = api_key
        self.model = model
        self.timeout = timeout
        # The key is sent in the x-goog-api-key header, never in the URL, so it
        # cannot leak through error messages, proxies or access logs.
        self.endpoint = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"

    async def analyze_coin_images(
        self,
        front_b64: str,
        reverse_b64: Optional[str] = None,
        edge_b64: Optional[str] = None,
        detected_text_hints: Optional[List[str]] = None,
    ) -> RawVisionObservation:
        parts: List[Dict[str, Any]] = [
            {"text": f"{SYSTEM_PROMPT}\n{JSON_SCHEMA_PROMPT}"}
        ]

        if detected_text_hints:
            parts.append({"text": f"Client OCR detected text hints: {', '.join(detected_text_hints)}"})

        parts.append({"text": "FRONT / OBVERSE IMAGE:"})
        parts.append({
            "inline_data": {
                "mime_type": "image/jpeg",
                "data": front_b64,
            }
        })

        if reverse_b64:
            parts.append({"text": "REVERSE IMAGE:"})
            parts.append({
                "inline_data": {
                    "mime_type": "image/jpeg",
                    "data": reverse_b64,
                }
            })

        if edge_b64:
            parts.append({"text": "EDGE IMAGE:"})
            parts.append({
                "inline_data": {
                    "mime_type": "image/jpeg",
                    "data": edge_b64,
                }
            })

        payload = {
            "contents": [{"parts": parts}],
            "generationConfig": {
                "response_mime_type": "application/json",
                "temperature": 0.1,
            }
        }

        data = await _post_to_provider(
            "Gemini",
            self.endpoint,
            payload,
            headers={"x-goog-api-key": self.api_key},
            timeout=self.timeout,
        )

        # Parse output defensively from candidates (safety blocks return no parts)
        try:
            text = data["candidates"][0]["content"]["parts"][0]["text"]
        except (KeyError, IndexError, TypeError):
            raise VisionProviderError("Gemini", "response contained no text candidate") from None
        return safe_parse_vision_response(text)


OPENAI_MAX_COMPLETION_TOKENS = 1500


class OpenAIVisionProvider(VisionProvider):
    """OpenAI GPT-4o-mini Vision Provider."""

    def __init__(self, api_key: str, model: str = "gpt-4o-mini", timeout: float = 15.0):
        self.api_key = api_key
        self.model = model
        self.timeout = timeout
        self.endpoint = "https://api.openai.com/v1/chat/completions"

    async def analyze_coin_images(
        self,
        front_b64: str,
        reverse_b64: Optional[str] = None,
        edge_b64: Optional[str] = None,
        detected_text_hints: Optional[List[str]] = None,
    ) -> RawVisionObservation:
        content: List[Dict[str, Any]] = [
            {"type": "text", "text": f"{SYSTEM_PROMPT}\n{JSON_SCHEMA_PROMPT}"},
            {
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{front_b64}", "detail": "high"}
            }
        ]

        if reverse_b64:
            content.append({
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{reverse_b64}", "detail": "high"}
            })

        if edge_b64:
            content.append({
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{edge_b64}", "detail": "high"}
            })

        payload = {
            "model": self.model,
            "messages": [{"role": "user", "content": content}],
            "response_format": {"type": "json_object"},
            "temperature": 0.1,
            # Cost and latency ceiling. The expected JSON is a few hundred tokens;
            # without a cap, JSON mode can run on (e.g. emitting whitespace) until
            # the model's maximum, which the 15 s timeout would cut off anyway.
            "max_completion_tokens": OPENAI_MAX_COMPLETION_TOKENS,
        }

        headers = {"Authorization": f"Bearer {self.api_key}"}

        data = await _post_to_provider(
            "OpenAI", self.endpoint, payload, headers=headers, timeout=self.timeout
        )

        try:
            text = data["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError):
            raise VisionProviderError("OpenAI", "response contained no message content") from None
        return safe_parse_vision_response(text)


class MockVisionProvider(VisionProvider):
    """Deterministic Mock Vision Provider for automated unit & integration testing."""

    def __init__(self, observation: Optional[RawVisionObservation] = None):
        self.observation = observation or RawVisionObservation(
            country="United States",
            issuer="United States Mint",
            denomination="$1",
            year=1882,
            mint_mark="CC",
            composition="90% Silver, 10% Copper",
            obverse_description="Head of Liberty facing left, hair in Phrygian cap with LIBERTY band.",
            reverse_description="Heraldic eagle holding arrows and olive branch, CC mint mark below wreath.",
            edge_description="Reeded edge.",
            visible_inscriptions=["E PLURIBUS UNUM", "LIBERTY", "1882", "UNITED STATES OF AMERICA", "ONE DOLLAR", "IN GOD WE TRUST"],
            km_number_guess="KM# 110",
            numista_id_guess=1492,
            obverse_reverse_consistent=True,
            candidate_varieties=["1882-CC Regular Strike", "1882-CC GSA Hoard"],
            confidence_reasoning="Clear Carson City (CC) mint mark and sharp 1882 date matching standard dies.",
            visual_similarity_score=0.94,
        )

    async def analyze_coin_images(
        self,
        front_b64: str,
        reverse_b64: Optional[str] = None,
        edge_b64: Optional[str] = None,
        detected_text_hints: Optional[List[str]] = None,
    ) -> RawVisionObservation:
        return self.observation
