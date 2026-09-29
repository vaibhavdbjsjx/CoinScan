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
                detail="Front and reverse motifs correspond consistently to the same catalogue type.",
                strength=SignalStrength.STRONG,
                score=0.95,
                source="Joint Multi-Side Analysis",
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

    # Derive Confidence Tier
    if overall_score >= 0.85 and contradiction_penalty == 0:
        conf_level = ConfidenceLevel.HIGH
        explanation = (
            f"High certainty match for {catalog_match.title}. Visual features, date, and denomination agree across both sides."
            if reverse_captured
            else f"High certainty match for {catalog_match.title} from the front side only; photograph the reverse to confirm."
        )
    elif overall_score >= 0.60:
        conf_level = ConfidenceLevel.MEDIUM
        explanation = f"Probable match for {catalog_match.title}. Coin type confirmed, but sub-variety details require visual inspection."
    elif overall_score >= 0.35:
        conf_level = ConfidenceLevel.LOW
        explanation = "Possible match with partial evidence. Multiple candidate varieties exist."
    else:
        conf_level = ConfidenceLevel.INDETERMINATE
        explanation = "Insufficient evidence to distinguish this coin with certainty."

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
