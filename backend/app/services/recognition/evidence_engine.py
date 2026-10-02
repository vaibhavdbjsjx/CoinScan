"""
Deterministic evidence aggregation and candidate ranking engine.
Calculates multi-signal confidence scores and builds transparent evidentiary proofs.
"""

from typing import List, Tuple, Optional
from backend.app.models.domain import (
    RecognitionCandidate,
    CoinIdentity,
    RecognitionConfidence,
    ConfidenceLevel,
    RecognitionEvidence,
    RecognitionEvidenceType,
    SignalStrength,
)
from backend.app.services.recognition.vision_provider import RawVisionObservation
from backend.app.services.recognition.ocr_service import ExtractedOcrSignals
from backend.app.services.numista.client import NumistaTypeDetail, SOURCE_OFFLINE_FIXTURE


def _catalogue_label(catalog_match: NumistaTypeDetail) -> str:
    """Human-readable provenance of a catalogue record. Fixture data is never called Numista."""
    if catalog_match.source == SOURCE_OFFLINE_FIXTURE:
        return "Offline test fixture (not Numista)"
    return "Numista catalogue"


_LEVEL_ORDER = [
    ConfidenceLevel.INDETERMINATE,
    ConfidenceLevel.LOW,
    ConfidenceLevel.MEDIUM,
    ConfidenceLevel.HIGH,
]
# Highest score a capped level may report, so the number never contradicts the label.
_LEVEL_SCORE_CEILING = {
    ConfidenceLevel.LOW: 0.59,
    ConfidenceLevel.MEDIUM: 0.84,
}


def _gate_confidence(
    level: ConfidenceLevel,
    score: float,
    corroborations: int,
    reverse_captured: bool,
    has_contradiction: bool,
) -> Tuple[ConfidenceLevel, float]:
    """Caps the confidence level by independent catalogue corroboration.

    Every identity field comes from a single vision-model reading of the photo, and
    the catalogue record was found by searching with that same reading, so the
    weighted score alone can look strong without any independent confirmation.
    - 0 cross-checks passed: at most LOW.
    - 1 cross-check passed: at most MEDIUM.
    - HIGH additionally requires the reverse side and no contradiction.
    """
    if corroborations <= 0:
        ceiling = ConfidenceLevel.LOW
    elif corroborations == 1 or not reverse_captured or has_contradiction:
        ceiling = ConfidenceLevel.MEDIUM
    else:
        ceiling = ConfidenceLevel.HIGH

    if _LEVEL_ORDER.index(level) > _LEVEL_ORDER.index(ceiling):
        level = ceiling
    # Keep the (rounded) number inside the band of the final level in every case.
    if level in _LEVEL_SCORE_CEILING:
        score = min(score, _LEVEL_SCORE_CEILING[level])
    return level, score


def _explain(level: ConfidenceLevel, title: str, corroborations: int, reverse_captured: bool) -> str:
    checks = (
        "1 detail read from the photo agrees"
        if corroborations == 1
        else f"{corroborations} details read from the photo agree"
    )
    if level == ConfidenceLevel.HIGH:
        return (
            f"Strong match for {title}: {checks} with the catalogue record and both sides "
            "were photographed. This identifies the coin type only; it does not authenticate the coin."
        )
    if level == ConfidenceLevel.MEDIUM:
        follow_up = (
            "Photograph the reverse to confirm."
            if not reverse_captured
            else "Variety and mint details still need visual confirmation."
        )
        return f"Probable match for {title}: {checks} with the catalogue record. {follow_up}"
    if level == ConfidenceLevel.LOW:
        if corroborations == 0:
            return (
                f"Possible match for {title}. This rests only on the AI's reading of the photo; "
                "no detail could be cross-checked against the catalogue record."
            )
        return f"Possible match for {title} with partial evidence. Several candidate types remain plausible."
    return "Insufficient evidence to identify this coin."


def build_candidate_from_evidence(
    vision: RawVisionObservation,
    ocr: ExtractedOcrSignals,
    catalog_match: NumistaTypeDetail,
    rank: int = 1,
    reverse_captured: bool = True,
) -> RecognitionCandidate:
    """
    Synthesizes vision observations, OCR tokens, and catalogue ground-truth
    into a ranked RecognitionCandidate with discrete evidence signals.

    Evidence sources state honestly where each signal came from: values read
    from the photo by the vision model are labelled as AI-read, and only facts
    present in the catalogue record are labelled as catalogue data.
    reverse_captured must be False when only the front image was analysed, so
    no two-sided agreement is claimed.
    """
    catalogue_label = _catalogue_label(catalog_match)
    evidence_list: List[RecognitionEvidence] = []
    visual_score = vision.visual_similarity_score
    ocr_score = 0.5
    metadata_score = 0.5
    contradiction_penalty = 0.0
    # Independent catalogue cross-checks passed (see _gate_confidence).
    corroborations = 0

    # 1. Visual Similarity Evidence
    evidence_list.append(
        RecognitionEvidence(
            type=RecognitionEvidenceType.VISUAL_SIMILARITY,
            label="AI Visual Assessment",
            detail=vision.confidence_reasoning or "The vision model's own assessment of the photographed coin.",
            strength=SignalStrength.STRONG if visual_score >= 0.8 else SignalStrength.MODERATE,
            score=visual_score,
            source="Vision AI model (self-assessed; not compared against catalogue images)",
        )
    )

    # 2. Year & Date Evaluation
    matched_year: Optional[int] = None
    year_read_by = "Vision AI (read from photo)"
    if vision.year:
        matched_year = vision.year
    elif ocr.detected_years:
        matched_year = ocr.detected_years[0]
        year_read_by = "Text read from photo"

    catalogue_has_year_range = catalog_match.min_year is not None or catalog_match.max_year is not None
    range_text = (
        f"{catalog_match.min_year if catalog_match.min_year is not None else '?'}"
        f"–{catalog_match.max_year if catalog_match.max_year is not None else '?'}"
    )

    if matched_year and not catalogue_has_year_range:
        # The catalogue record has no year range, so the year cannot be verified.
        # Report it as AI-read only and do not award verification credit.
        evidence_list.append(
            RecognitionEvidence(
                type=RecognitionEvidenceType.YEAR,
                label=f"Date {matched_year} (unverified)",
                detail=f"Year {matched_year} was read from the photo, but the catalogue record has no year range to verify it against.",
                strength=SignalStrength.MODERATE,
                score=0.60,
                source=year_read_by,
            )
        )
    elif matched_year:
        in_range = True
        if catalog_match.min_year and matched_year < catalog_match.min_year:
            in_range = False
        if catalog_match.max_year and matched_year > catalog_match.max_year:
            in_range = False

        if in_range:
            ocr_score = max(ocr_score, 0.92)
            corroborations += 1
            evidence_list.append(
                RecognitionEvidence(
                    type=RecognitionEvidenceType.YEAR,
                    label=f"Date {matched_year}",
                    detail=f"Year {matched_year} read from the photo falls within the catalogue issue range ({range_text}).",
                    strength=SignalStrength.STRONG,
                    score=0.95,
                    source=f"{year_read_by}, checked against {catalogue_label}",
                )
            )
        else:
            contradiction_penalty += 0.25
            evidence_list.append(
                RecognitionEvidence(
                    type=RecognitionEvidenceType.YEAR,
                    label=f"Year Discrepancy ({matched_year})",
                    detail=f"Year {matched_year} read from the photo is outside the catalogue issue range ({range_text}).",
                    strength=SignalStrength.INCONSISTENT,
                    score=0.20,
                    source=f"{year_read_by}, checked against {catalogue_label}",
                )
            )

    # 3. Mint Mark Verification
    if vision.mint_mark and catalog_match.issues:
        known_mints = [iss.mint_mark for iss in catalog_match.issues if iss.mint_mark]
        if vision.mint_mark in known_mints:
            metadata_score = max(metadata_score, 0.90)
            corroborations += 1
            evidence_list.append(
                RecognitionEvidence(
                    type=RecognitionEvidenceType.MINT_MARK,
                    label=f"Mint Mark '{vision.mint_mark}'",
                    detail=f"Mint mark '{vision.mint_mark}' read from the photo is listed among this type's catalogue issues.",
                    strength=SignalStrength.STRONG,
                    score=0.92,
                    source=f"Vision AI (read from photo), checked against {catalogue_label} issues",
                )
            )

    # 4. Denomination & Inscription Match
    if catalog_match.denomination:
        denom_upper = catalog_match.denomination.upper()
        if any(d in denom_upper or denom_upper in d for d in ocr.detected_denominations):
            ocr_score = max(ocr_score, 0.90)
            corroborations += 1
            evidence_list.append(
                RecognitionEvidence(
                    type=RecognitionEvidenceType.DENOMINATION,
                    label="Denomination Inscription",
                    detail=f"Legend text read from the photo matches the catalogue denomination '{catalog_match.denomination}'.",
                    strength=SignalStrength.STRONG,
                    score=0.90,
                    source=f"Text read from photo, checked against {catalogue_label}",
                )
            )

    # 5. Obverse / Reverse Agreement Check
    if not vision.obverse_reverse_consistent:
        contradiction_penalty += 0.40
        evidence_list.append(
            RecognitionEvidence(
                type=RecognitionEvidenceType.OBVERSE_REVERSE_AGREEMENT,
                label="Obverse / Reverse Mismatch",
                detail=vision.contradiction_notes or "Reverse face characteristics do not match the expected obverse die type.",
                strength=SignalStrength.INCONSISTENT,
                score=0.10,
                source="Joint Multi-Side Analysis",
            )
        )
    elif not reverse_captured:
        evidence_list.append(
            RecognitionEvidence(
                type=RecognitionEvidenceType.OBVERSE_REVERSE_AGREEMENT,
                label="Reverse Not Captured",
                detail="Only one side was photographed, so the two sides could not be cross-checked.",
                strength=SignalStrength.WEAK,
                score=None,
                source="Capture metadata",
            )
        )
    else:
        evidence_list.append(
            RecognitionEvidence(
                type=RecognitionEvidenceType.OBVERSE_REVERSE_AGREEMENT,
                label="Two-Sided Agreement",
                detail="The vision model judged the front and reverse photos to belong to the same coin issue.",
                strength=SignalStrength.MODERATE,
                score=0.95,
                source="Vision AI (both photos; model's own judgement)",
            )
        )

    # 6. Physical Specifications (Composition & Edge)
    if catalog_match.composition:
        evidence_list.append(
            RecognitionEvidence(
                type=RecognitionEvidenceType.COMPOSITION,
                label="Metal Composition",
                detail=f"Catalogue alloy for this type: {catalog_match.composition}. Not measured from the photo.",
                strength=SignalStrength.MODERATE,
                score=0.85,
                source=catalogue_label,
            )
        )

    # Compute Final Weighted Composite Score
    raw_composite = (visual_score * 0.45) + (ocr_score * 0.30) + (metadata_score * 0.25) - contradiction_penalty
    overall_score = max(0.0, min(1.0, raw_composite))

    # Derive Confidence Tier from the score, then cap it by corroboration.
    if overall_score >= 0.85 and contradiction_penalty == 0:
        conf_level = ConfidenceLevel.HIGH
    elif overall_score >= 0.60:
        conf_level = ConfidenceLevel.MEDIUM
    elif overall_score >= 0.35:
        conf_level = ConfidenceLevel.LOW
    else:
        conf_level = ConfidenceLevel.INDETERMINATE

    conf_level, overall_score = _gate_confidence(
        conf_level,
        overall_score,
        corroborations=corroborations,
        reverse_captured=reverse_captured,
        has_contradiction=contradiction_penalty > 0,
    )
    explanation = _explain(conf_level, catalog_match.title, corroborations, reverse_captured)

    identity = CoinIdentity(
        country=catalog_match.country or vision.country or "Unknown",
        denomination=catalog_match.denomination or vision.denomination or "Coin",
        currency=catalog_match.currency,
        year=matched_year,
        mint=vision.mint_mark,
        composition=catalog_match.composition or vision.composition,
        weightG=catalog_match.weight_g,
        diameterMm=catalog_match.diameter_mm,
        thicknessMm=catalog_match.thickness_mm,
        edgeType=catalog_match.edge_type or vision.edge_description,
        kmNumber=catalog_match.km_number or vision.km_number_guess,
        numistaId=catalog_match.id,
    )

    confidence = RecognitionConfidence(
        level=conf_level,
        overallScore=round(overall_score, 2),
        visualScore=round(visual_score, 2),
        ocrScore=round(ocr_score, 2),
        metadataScore=round(metadata_score, 2),
        explanation=explanation,
        corroboratingChecks=corroborations,
    )

    coin_id = f"numista_{catalog_match.id}" if catalog_match.id else "coin_unverified"

    return RecognitionCandidate(
        coinId=coin_id,
        identity=identity,
        providerName="CoinScan Hybrid Engine",
        confidence=confidence,
        evidence=evidence_list,
        rank=rank,
    )
