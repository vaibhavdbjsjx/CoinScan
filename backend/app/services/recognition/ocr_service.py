"""
OCR extraction and text normalization service for coin legends, dates, and mint marks.
"""

import re
from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field


class ExtractedOcrSignals(BaseModel):
    detected_years: List[int] = Field(default_factory=list)
    detected_denominations: List[str] = Field(default_factory=list)
    detected_country_tokens: List[str] = Field(default_factory=list)
    detected_mint_marks: List[str] = Field(default_factory=list)
    raw_tokens: List[str] = Field(default_factory=list)


# Common numismatic date regex (Gregorian 4-digit years between 1500 and 2026)
YEAR_PATTERN = re.compile(r"\b(1[5-9]\d{2}|20[0-2]\d)\b")

# Common denomination terms across multiple currencies
DENOMINATION_PATTERNS = [
    re.compile(r"\b(ONE|TWO|FIVE|TEN|TWENTY|FIFTY|QUARTER|HALF)\s+(DOLLAR|DOLLARS|CENT|CENTS)\b", re.IGNORECASE),
    re.compile(r"\b(\d+)\s*(DOLLAR|DOLLARS|CENT|CENTS|PENNY|PENCE|SHILLING|SHILLINGS|CROWN|POUND|POUNDS|FRANC|FRANCS|RUPEE|RUPEES|PESO|PESOS|MARK|MARKS|PFENNIG|YEN|YUAN|DINAR|DIRHAM)\b", re.IGNORECASE),
    re.compile(r"\b(1/2|1/4|1/12|1/24)\s*(DOLLAR|RUPEE|CROWN|ANNA)\b", re.IGNORECASE),
]

# Standard country / issuer tokens
COUNTRY_PATTERNS = [
    re.compile(r"\b(UNITED\s+STATES(\s+OF\s+AMERICA)?|GREAT\s+BRITAIN|BRITISH\s+INDIA|CANADA|AUSTRALIA|FRANCE|GERMANY|DEUTSCHES\s+REICH|ITALIA|ESPAÑA|MEXICO|SWITZERLAND|HELVETIA|RUSSIA|INDIA|JAPAN|CHINA)\b", re.IGNORECASE),
]

# Common isolated mint marks
MINT_MARK_PATTERNS = [
    re.compile(r"\b(CC|O|S|D|W|P|A|B|C|E|F|G|H|J)\b"),
]


def extract_ocr_signals(text_tokens: List[str]) -> ExtractedOcrSignals:
    """
    Extracts structured numismatic signals (years, denominations, countries, mint marks)
    from a list of raw OCR text tokens.
    """
    detected_years: List[int] = []
    detected_denominations: List[str] = []
    detected_country_tokens: List[str] = []
    detected_mint_marks: List[str] = []

    combined_text = " ".join(text_tokens)

    # 1. Year extraction
    for match in YEAR_PATTERN.finditer(combined_text):
        try:
            year = int(match.group(1))
            if 1500 <= year <= 2030 and year not in detected_years:
                detected_years.append(year)
        except ValueError:
            continue

    # 2. Denomination extraction
    for pattern in DENOMINATION_PATTERNS:
        for match in pattern.finditer(combined_text):
            denom = match.group(0).strip().upper()
            if denom not in detected_denominations:
                detected_denominations.append(denom)

    # 3. Country / issuer extraction
    for pattern in COUNTRY_PATTERNS:
        for match in pattern.finditer(combined_text):
            country = match.group(0).strip().upper()
            if country not in detected_country_tokens:
                detected_country_tokens.append(country)

    return ExtractedOcrSignals(
        detected_years=detected_years,
        detected_denominations=detected_denominations,
        detected_country_tokens=detected_country_tokens,
        detected_mint_marks=detected_mint_marks,
        raw_tokens=text_tokens,
    )
