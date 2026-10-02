import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'recognition_models.dart';

/// Exception thrown when an image fails fundamental file or decoding checks.
class ImageProcessingException implements Exception {
  final String message;
  const ImageProcessingException(this.message);

  @override
  String toString() => message;
}

/// Result of normalizing and inspecting a coin photograph.
class PreprocessedCoinImage {
  final CapturedCoinImage image;
  final ImageQualityReport qualityReport;
  final Uint8List normalizedBytes;

  const PreprocessedCoinImage({
    required this.image,
    required this.qualityReport,
    required this.normalizedBytes,
  });
}

/// Unified, production-grade image normalization and deterministic quality engine.
///
/// Ensures both camera captures and gallery imports:
/// 1. Validate file readability and non-empty byte payloads.
/// 2. Gracefully handle corrupt or unsupported image formats.
/// 3. Bake EXIF orientation so pixels are correctly physically oriented.
/// 4. Constrain maximum dimensions to 1920px (preserving high numismatic fidelity while reducing memory/bandwidth).
/// 5. Compress to standard high-quality JPEG (quality 88).
/// 6. Perform multi-factor quality inspection (blur, glare, exposure, resolution) giving actionable feedback.
class ImagePreprocessingService {
  ImagePreprocessingService._();
  static final ImagePreprocessingService instance = ImagePreprocessingService._();

  static const int minAcceptableDimension = 240;
  static const int maxNormalizedDimension = 1920;
  static const int maxFileSizeBytes = 25 * 1024 * 1024; // 25 MB ceiling

  /// Normalizes an [XFile] into a standardized, EXIF-baked JPEG and inspects quality.
  Future<PreprocessedCoinImage> normalizeAndInspect({
    required XFile file,
    required CaptureSide side,
    required CaptureSource source,
    Directory? overrideTempDir,
  }) async {
    final size = await file.length();
    if (size == 0) {
      throw const ImageProcessingException('The image file is empty (0 bytes).');
    }
    if (size > maxFileSizeBytes) {
      throw const ImageProcessingException(
        'The image file exceeds 25MB. Please choose or capture a smaller photograph.',
      );
    }

    final Uint8List rawBytes;
    try {
      rawBytes = await file.readAsBytes();
    } catch (e) {
      throw ImageProcessingException('Could not read image data: $e');
    }

    // Decode image safely
    img.Image? decoded;
    try {
      decoded = img.decodeImage(rawBytes);
    } catch (_) {
      throw const ImageProcessingException(
        'The selected file could not be decoded as an image. Please provide a valid JPEG, PNG, or HEIC photo.',
      );
    }

    if (decoded == null) {
      throw const ImageProcessingException(
        'The selected file could not be decoded. The file may be corrupted or in an unsupported format.',
      );
    }

    // 1. Bake EXIF orientation so pixels are physically rotated as taken
    decoded = img.bakeOrientation(decoded);

    // 2. Perform Image Quality Inspection before downscaling to measure true capture fidelity
    final qualityReport = inspectQuality(decoded);

    // If resolution is too low, reject early
    if (decoded.width < minAcceptableDimension ||
        decoded.height < minAcceptableDimension) {
      throw const ImageProcessingException(
        'Photo resolution is too low to distinguish coin inscriptions and details. Try taking a closer, sharper photograph.',
      );
    }

    // 3. Downscale if image exceeds maximum dimension (maintains aspect ratio)
    final origW = decoded.width;
    final origH = decoded.height;
    if (origW > maxNormalizedDimension || origH > maxNormalizedDimension) {
      final double ratio = origW >= origH
          ? maxNormalizedDimension / origW
          : maxNormalizedDimension / origH;
      final newW = (origW * ratio).round();
      final newH = (origH * ratio).round();
      decoded = img.copyResize(
        decoded,
        width: newW,
        height: newH,
        interpolation: img.Interpolation.linear,
      );
    }

    // 4. Encode to standard high-quality JPEG
    final Uint8List normalizedJpg = Uint8List.fromList(
      img.encodeJpg(decoded, quality: 88),
    );

    // 5. Persist to a temporary cache file (mobile/desktop). Browsers have no
    // file system: there the normalized bytes are kept in memory only.
    String path = file.path;
    if (!kIsWeb) {
      final tempDir = overrideTempDir ?? await _resolveTempDirectory();
      final fileName = 'coinscan_norm_${side.name}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final targetFile = File('${tempDir.path}/$fileName');
      await targetFile.writeAsBytes(normalizedJpg, flush: true);
      path = targetFile.path;
    }

    final capturedImage = CapturedCoinImage(
      path: path,
      source: source,
      side: side,
      capturedAt: DateTime.now(),
      width: decoded.width,
      height: decoded.height,
      fileSizeBytes: normalizedJpg.length,
      mimeType: 'image/jpeg',
      bytes: normalizedJpg,
    );

    return PreprocessedCoinImage(
      image: capturedImage,
      qualityReport: qualityReport,
      normalizedBytes: normalizedJpg,
    );
  }

  /// Inspects decoded image pixels for blur, glare, exposure, and resolution defects.
  ImageQualityReport inspectQuality(img.Image image) {
    final issues = <ImageQualityIssue>[];
    final warnings = <String>[];
    final actions = <String>[];
    double score = 1.0;

    final width = image.width;
    final height = image.height;

    // 1. Resolution Check
    if (width < minAcceptableDimension || height < minAcceptableDimension) {
      issues.add(ImageQualityIssue.resolutionTooLow);
      warnings.add('Image resolution (${width}x$height) is below minimum recommended ${minAcceptableDimension}x${minAcceptableDimension}px.');
      actions.add('Hold camera closer or choose a higher-resolution photograph.');
      score -= 0.50;
    }

    // Sub-sample to a fast analysis grid (max 120x120) for near-instant metric computation (<15ms)
    const sampleDim = 120;
    final sampleImg = (width > sampleDim || height > sampleDim)
        ? img.copyResize(image, width: sampleDim, height: sampleDim, interpolation: img.Interpolation.nearest)
        : image;

    final sampleW = sampleImg.width;
    final sampleH = sampleImg.height;
    final totalPixels = sampleW * sampleH;

    double totalLuminance = 0.0;
    int glarePixelCount = 0;

    // Extract grayscale luminance grid for discrete Laplacian variance computation
    final lumGrid = List.generate(
      sampleH,
      (_) => List<double>.filled(sampleW, 0.0),
    );

    for (int y = 0; y < sampleH; y++) {
      for (int x = 0; x < sampleW; x++) {
        final pixel = sampleImg.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();

        // Standard ITU-R BT.601 luminance
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;
        lumGrid[y][x] = lum;
        totalLuminance += lum;

        // Glare: near-saturated highlight pixels
        if (r > 248 && g > 248 && b > 248) {
          glarePixelCount++;
        }
      }
    }

    // 2. Exposure / Darkness Check
    final meanLuminanceNorm = totalLuminance / (totalPixels * 255.0); // 0.0 to 1.0
    if (meanLuminanceNorm < 0.18) {
      issues.add(ImageQualityIssue.tooDark);
      warnings.add('Lighting is very dark; coin surface details and legends may be obscured.');
      actions.add('Capture under direct, even lighting without heavy shadows.');
      score -= 0.35;
    } else if (meanLuminanceNorm > 0.90) {
      warnings.add('Lighting is overexposed; coin highlights are washed out.');
      actions.add('Reduce direct harsh lighting to reveal coin relief.');
      score -= 0.25;
    }

    // 3. Glare Check
    final glareFraction = glarePixelCount / totalPixels.toDouble();
    if (glareFraction > 0.12) {
      issues.add(ImageQualityIssue.excessiveGlare);
      warnings.add('High specular reflection or flash glare detected on coin face.');
      actions.add('Angle lighting or diffuse reflection to eliminate glare spots.');
      score -= 0.25;
    }

    // 4. Blur Check (Discrete Laplacian Variance)
    if (sampleW > 8 && sampleH > 8) {
      double lapSum = 0.0;
      double lapSqSum = 0.0;
      int lapCount = 0;

      for (int y = 1; y < sampleH - 1; y++) {
        for (int x = 1; x < sampleW - 1; x++) {
          final center = lumGrid[y][x];
          final top = lumGrid[y - 1][x];
          final bottom = lumGrid[y + 1][x];
          final left = lumGrid[y][x - 1];
          final right = lumGrid[y][x + 1];

          final lapVal = (top + bottom + left + right) - (4.0 * center);
          lapSum += lapVal;
          lapSqSum += lapVal * lapVal;
          lapCount++;
        }
      }

      if (lapCount > 0) {
        final mean = lapSum / lapCount;
        final variance = (lapSqSum / lapCount) - (mean * mean);

        if (variance < 28.0) {
          issues.add(ImageQualityIssue.tooBlurry);
          warnings.add('Image appears out of focus or motion-blurred.');
          actions.add('Hold the camera steady and tap to focus on coin relief.');
          score -= 0.40;
        }
      }
    }

    final clampedScore = math.max(0.0, math.min(1.0, score));
    final isAcceptable = clampedScore >= 0.45 &&
        !issues.contains(ImageQualityIssue.resolutionTooLow);

    return ImageQualityReport(
      isAcceptable: isAcceptable,
      overallScore: double.parse(clampedScore.toStringAsFixed(2)),
      issues: issues,
      warnings: warnings,
      recommendedActions: actions,
    );
  }

  Future<Directory> _resolveTempDirectory() async {
    if (!kIsWeb) {
      try {
        return await getTemporaryDirectory();
      } catch (_) {}
    }
    return Directory.systemTemp;
  }
}
