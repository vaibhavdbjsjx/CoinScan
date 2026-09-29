"""
Image quality inspection and deterministic validation.
Detects corruption, low resolution, extreme blur, excessive darkness, and glare.
"""

import io
from typing import Tuple, List, Optional
from PIL import Image, ImageOps
import numpy as np

from backend.app.models.domain import ImageQualityReport, ImageQualityIssue

# Protect against memory exhaustion from decompression bombs (e.g. 100k x 100k pixel bombs)
Image.MAX_IMAGE_PIXELS = 25_000_000


def inspect_image_quality(
    image_bytes: bytes,
    min_dimension: int = 240,
    max_dimension: int = 4096,
) -> Tuple[ImageQualityReport, Optional[Image.Image]]:
    """
    Decodes and inspects an image for quality defects.
    Returns the ImageQualityReport and the decoded PIL Image (or None if corrupt).
    """
    if not image_bytes:
        return ImageQualityReport(
            isAcceptable=False,
            overallScore=0.0,
            issues=[ImageQualityIssue.RESOLUTION_TOO_LOW],
            warnings=["Image file is empty (0 bytes)."],
            recommendedActions=["Retake photo ensuring camera captures correctly."],
        ), None

    try:
        img = Image.open(io.BytesIO(image_bytes))
        img.verify()  # Check for corruption
        # Re-open for actual processing after verify()
        img = Image.open(io.BytesIO(image_bytes))
        img = ImageOps.exif_transpose(img)  # Correct orientation
        img = img.convert("RGB")
    except Exception as e:
        return ImageQualityReport(
            isAcceptable=False,
            overallScore=0.0,
            issues=[ImageQualityIssue.NON_COIN_DETECTED],
            warnings=[f"Image data is corrupted or unreadable: {str(e)}"],
            recommendedActions=["Provide a valid JPEG, PNG, or HEIC image."],
        ), None

    width, height = img.size
    issues: List[ImageQualityIssue] = []
    warnings: List[str] = []
    recommended_actions: List[str] = []
    score = 1.0

    # 1. Resolution Check
    if width < min_dimension or height < min_dimension:
        issues.append(ImageQualityIssue.RESOLUTION_TOO_LOW)
        warnings.append(f"Image resolution ({width}x{height}) is below minimum {min_dimension}x{min_dimension}px.")
        recommended_actions.append("Hold camera closer or select a higher-resolution photograph.")
        score -= 0.5

    # 2. NumPy analysis on grayscale array
    gray_arr = np.array(img.convert("L"), dtype=np.float32)

    # 3. Brightness & Exposure Check
    mean_brightness = float(np.mean(gray_arr)) / 255.0  # 0.0 to 1.0
    if mean_brightness < 0.18:
        issues.append(ImageQualityIssue.TOO_DARK)
        warnings.append("Lighting is very dark; coin surface details and legends may be obscured.")
        recommended_actions.append("Capture under direct, even lighting without heavy shadows.")
        score -= 0.35

    # 4. Glare Check (fraction of saturated pixels)
    glare_fraction = float(np.sum(gray_arr > 250)) / gray_arr.size
    if glare_fraction > 0.12:
        issues.append(ImageQualityIssue.EXCESSIVE_GLARE)
        warnings.append("High specular reflection / glare detected on coin face.")
        recommended_actions.append("Angle lighting or diffuse direct light to eliminate blinding reflections.")
        score -= 0.25

    # 5. Blur Check (variance of discrete Laplacian)
    if gray_arr.shape[0] > 8 and gray_arr.shape[1] > 8:
        # Compute fast Laplacian kernel via numpy slicing
        laplacian = (
            gray_arr[:-2, 1:-1]
            + gray_arr[2:, 1:-1]
            + gray_arr[1:-1, :-2]
            + gray_arr[1:-1, 2:]
            - 4 * gray_arr[1:-1, 1:-1]
        )
        blur_variance = float(np.var(laplacian))
        if blur_variance < 35.0:
            issues.append(ImageQualityIssue.TOO_BLURRY)
            warnings.append("Image appears out of focus or motion-blurred.")
            recommended_actions.append("Hold the camera steady and tap the screen to ensure sharp focus on coin relief.")
            score -= 0.40

    clamped_score = max(0.0, min(1.0, score))
    is_acceptable = clamped_score >= 0.45 and (ImageQualityIssue.RESOLUTION_TOO_LOW not in issues)

    return ImageQualityReport(
        isAcceptable=is_acceptable,
        overallScore=round(clamped_score, 2),
        issues=issues,
        warnings=warnings,
        recommendedActions=recommended_actions,
    ), img
