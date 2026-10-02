"""
Image quality inspection and deterministic validation.
Detects corruption, low resolution, extreme blur, excessive darkness, and glare.

Untrusted uploads are checked from the image header first: only JPEG, PNG and
WebP are decoded, and images above the dimension / pixel limits are refused
before any pixel data is decoded (decoding cost grows with pixel count, not
file size).
"""

import io
from typing import Tuple, List, Optional
from PIL import Image, ImageOps
import numpy as np

from backend.app.models.domain import ImageQualityReport, ImageQualityIssue

# Backstop for Pillow's own decompression-bomb guard; the explicit header checks
# below refuse oversized images long before this is reached.
Image.MAX_IMAGE_PIXELS = 25_000_000

# MPO is the multi-picture JPEG variant many phone cameras write.
ALLOWED_FORMATS = {"JPEG", "MPO", "PNG", "WEBP"}
DEFAULT_MAX_PIXELS = 12_000_000
SUPPORTED_FORMATS_HINT = "Please upload a JPEG, PNG or WebP photo."

_HEIF_BRANDS = (b"heic", b"heix", b"hevc", b"hevx", b"heim", b"heis", b"mif1", b"msf1", b"avif")


class ImageTooLargeError(ValueError):
    """The image's declared size exceeds the processing limits."""

    def __init__(self, width: Optional[int], height: Optional[int], max_dimension: int, max_pixels: int):
        self.width, self.height = width, height
        self.max_dimension, self.max_pixels = max_dimension, max_pixels
        limits = f"the maximum is {max_dimension} px per side and {max_pixels / 1_000_000:g} megapixels."
        if width and height:
            super().__init__(f"Image is {width}x{height} px; {limits}")
        else:
            super().__init__(f"Image dimensions are far too large; {limits}")


class UnsupportedImageError(ValueError):
    """The upload is not a readable image in a supported format."""


def _is_heif(image_bytes: bytes) -> bool:
    return len(image_bytes) >= 12 and image_bytes[4:8] == b"ftyp" and image_bytes[8:12] in _HEIF_BRANDS


def probe_image(
    image_bytes: bytes,
    max_dimension: int = 4096,
    max_pixels: int = DEFAULT_MAX_PIXELS,
) -> Tuple[str, int, int]:
    """Reads only the image header and returns (format, width, height).

    Raises UnsupportedImageError for unreadable data or unsupported formats and
    ImageTooLargeError when the declared dimensions exceed the limits.
    """
    if _is_heif(image_bytes):
        raise UnsupportedImageError(f"HEIC/HEIF photos are not supported. {SUPPORTED_FORMATS_HINT}")
    try:
        with Image.open(io.BytesIO(image_bytes)) as img:
            image_format = (img.format or "").upper()
            width, height = img.size
    except Image.DecompressionBombError:
        # Pillow's own guard fired while reading the header.
        raise ImageTooLargeError(None, None, max_dimension, max_pixels) from None
    except Exception:
        raise UnsupportedImageError("Image data is corrupted or unreadable.") from None
    if image_format not in ALLOWED_FORMATS:
        raise UnsupportedImageError(f"{image_format or 'This'} images are not supported. {SUPPORTED_FORMATS_HINT}")
    if width > max_dimension or height > max_dimension or width * height > max_pixels:
        raise ImageTooLargeError(width, height, max_dimension, max_pixels)
    return image_format, width, height


def _unreadable_report(message: str) -> ImageQualityReport:
    return ImageQualityReport(
        isAcceptable=False,
        overallScore=0.0,
        issues=[ImageQualityIssue.NON_COIN_DETECTED],
        warnings=[message],
        recommendedActions=[SUPPORTED_FORMATS_HINT],
    )


def inspect_image_quality(
    image_bytes: bytes,
    min_dimension: int = 240,
    max_dimension: int = 4096,
    max_pixels: int = DEFAULT_MAX_PIXELS,
) -> Tuple[ImageQualityReport, Optional[Image.Image]]:
    """
    Decodes and inspects an image for quality defects.
    Returns the ImageQualityReport and the decoded PIL Image (or None if corrupt
    or unsupported). Raises ImageTooLargeError, before decoding, when the image
    exceeds max_dimension per side or max_pixels in total.
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
        probe_image(image_bytes, max_dimension=max_dimension, max_pixels=max_pixels)
    except UnsupportedImageError as e:
        return _unreadable_report(str(e)), None

    try:
        img = Image.open(io.BytesIO(image_bytes))
        img.verify()  # Check for corruption
        # Re-open for actual processing after verify()
        img = Image.open(io.BytesIO(image_bytes))
        img = ImageOps.exif_transpose(img)  # Correct orientation
        img = img.convert("RGB")
    except Exception:
        return _unreadable_report("Image data is corrupted or unreadable."), None

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
