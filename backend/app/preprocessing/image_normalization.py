"""
Image normalization routines for resizing, detail preservation, and payload formatting.
"""

import io
import base64
from typing import Tuple
from PIL import Image


def normalize_image_for_analysis(
    image: Image.Image,
    max_dimension: int = 1536,
    jpeg_quality: int = 90,
) -> Tuple[bytes, str]:
    """
    Normalizes a PIL Image by resizing to max_dimension if needed and encoding as JPEG.
    Returns (jpeg_bytes, base64_encoded_string).
    """
    width, height = image.size

    # Downscale maintaining aspect ratio if larger than max_dimension
    if width > max_dimension or height > max_dimension:
        if width >= height:
            new_w = max_dimension
            new_h = int(height * (max_dimension / width))
        else:
            new_h = max_dimension
            new_w = int(width * (max_dimension / height))
        image = image.resize((new_w, new_h), Image.Resampling.LANCZOS)

    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=jpeg_quality, optimize=True)
    jpeg_bytes = buffer.getvalue()
    b64_str = base64.b64encode(jpeg_bytes).decode("utf-8")

    return jpeg_bytes, b64_str
