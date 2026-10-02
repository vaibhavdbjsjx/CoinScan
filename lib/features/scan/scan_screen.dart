import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/auth/auth_service.dart';
import '../../core/recognition/recognition_models.dart';
import '../../core/recognition/image_preprocessing_service.dart';
import '../../core/reports/coin_report_service.dart';
import '../../core/storage/collection_storage_service.dart';
import '../../core/storage/scan_history_service.dart';
import '../../core/subscriptions/entitlement_models.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../main.dart';
import '../collection/collection_detail_screen.dart';
import '../onboarding/account_prompt.dart';
import '../subscription/paywall_screen.dart';
import 'widgets/coin_report_sheet.dart';
import 'widgets/evidence_result_widgets.dart';

enum _CaptureStep { front, reverse, edge, analyzing }

enum _CameraStatus { initializing, ready, permissionDenied, unavailable, error }

typedef TestImageFactory =
    Future<CapturedCoinImage?> Function(CaptureSide side, CaptureSource source);
typedef TestPreviewLoader = Future<Uint8List> Function(CapturedCoinImage image);

class ScanScreen extends StatefulWidget {
  final RecognitionService? recognitionService;
  final TestImageFactory? testImageFactory;
  final TestPreviewLoader? testPreviewLoader;

  const ScanScreen({
    super.key,
    this.recognitionService,
    this.testImageFactory,
    this.testPreviewLoader,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final ImagePicker _imagePicker = ImagePicker();
  static const double _galleryMaxDimension = 4096;
  final Map<CaptureSide, _CapturedImageData> _captures = {};

  late final RecognitionService _recognitionService =
      widget.recognitionService ??
      (widget.testImageFactory != null
          ? const UnavailableRecognitionService()
          : HttpRecognitionService());
  late final AnimationController _rotationController;

  CameraController? _cameraController;
  Future<void>? _cameraInitialization;

  bool _isProcessing = false;
  bool _isCapturing = false;
  bool _isFlashOn = false;
  bool _isMacroOn = true;
  bool _isPermissionPermanentlyBlocked = false;
  _CaptureStep _captureStep = _CaptureStep.front;
  _CameraStatus _cameraStatus = _CameraStatus.initializing;
  String? _cameraMessage;
  Offset? _focusPoint;
  RecognitionResult? _recognitionResult;
  _CapturedImageData? _reviewImage;

  int _analysisStageIndex = 0;
  Timer? _analysisStageTimer;
  static const List<String> _analysisStages = [
    'Preparing images for numismatic analysis...',
    'Examining portrait, motifs, and die characteristics...',
    'Reading date, mint mark, and inscriptions...',
    'Comparing against numismatic catalogue records...',
    'Checking die concordance across sides...',
    'Preparing transparent valuation breakdown...',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rotationController.dispose();
    _analysisStageTimer?.cancel();
    _disposeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (_reviewImage == null && !_isProcessing && _recognitionResult == null) {
        _initializeCamera();
      }
    }
  }

  CaptureSide get _currentSide => switch (_captureStep) {
    _CaptureStep.front => CaptureSide.front,
    _CaptureStep.reverse => CaptureSide.reverse,
    _CaptureStep.edge => CaptureSide.edge,
    _CaptureStep.analyzing => CaptureSide.front,
  };

  String get _stepTitle => switch (_captureStep) {
    _CaptureStep.front => 'Scan the front',
    _CaptureStep.reverse => 'Now scan the reverse',
    _CaptureStep.edge => 'Optional edge scan',
    _CaptureStep.analyzing => 'Preparing images',
  };

  String get _stepBody => switch (_captureStep) {
    _CaptureStep.front =>
      'Fill the ring with the coin face. Use steady light and avoid glare.',
    _CaptureStep.reverse =>
      'Flip the same coin over. Reverse evidence reduces confident wrong matches.',
    _CaptureStep.edge =>
      'Capture the rim only if it has lettering, reeding or unusual patterns.',
    _CaptureStep.analyzing =>
      'Sending local image references into the recognition boundary.',
  };

  String get _primaryAction => switch (_captureStep) {
    _CaptureStep.front => 'Capture front',
    _CaptureStep.reverse => 'Capture reverse',
    _CaptureStep.edge => 'Capture edge',
    _CaptureStep.analyzing => 'Preparing',
  };

  Future<void> _initializeCamera() async {
    if (widget.testImageFactory != null) {
      if (mounted) {
        setState(() {
          _cameraStatus = _CameraStatus.ready;
          _cameraMessage = null;
        });
      }
      return;
    }

    await _disposeCamera();
    if (!mounted) return;

    setState(() {
      _cameraStatus = _CameraStatus.initializing;
      _cameraMessage = null;
    });

    final PermissionStatus permission;
    if (kIsWeb) {
      // Browsers ask for camera access when the camera is opened below (a
      // refusal arrives as a CameraException). Their Permissions API does not
      // support a "camera" query everywhere, so it is not consulted.
      permission = PermissionStatus.granted;
    } else {
      final currentStatus = await Permission.camera.status;
      permission = currentStatus.isGranted
          ? currentStatus
          : await Permission.camera.request();
    }
    if (!mounted) return;

    if (permission.isPermanentlyDenied || permission.isRestricted) {
      setState(() {
        _cameraStatus = _CameraStatus.permissionDenied;
        _isPermissionPermanentlyBlocked = true;
        _cameraMessage =
            'Camera access is blocked. Enable camera access in Settings to scan coins.';
      });
      return;
    }

    if (!permission.isGranted) {
      setState(() {
        _cameraStatus = _CameraStatus.permissionDenied;
        _isPermissionPermanentlyBlocked = false;
        _cameraMessage =
            'CoinScan needs camera access to photograph coins for identification. Tap below to grant permission.';
      });
      return;
    }

    try {
      final cameras = await availableCameras();
      if (!mounted) return;

      if (cameras.isEmpty) {
        setState(() {
          _cameraStatus = _CameraStatus.unavailable;
          _cameraMessage = 'No camera is available on this device.';
        });
        return;
      }

      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _cameraController = controller;
      _cameraInitialization = controller.initialize();
      await _cameraInitialization;

      if (!mounted || _cameraController != controller) {
        await controller.dispose();
        return;
      }

      // Browsers expose neither torch nor focus control (the web camera
      // plugin throws for both), so this tuning is mobile-only.
      if (!kIsWeb) {
        await controller.setFlashMode(FlashMode.off);
        await controller.setFocusMode(FocusMode.auto);
      }

      if (!mounted || _cameraController != controller) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraStatus = _CameraStatus.ready;
        _cameraMessage = null;
      });
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraStatus = _CameraStatus.error;
        _cameraMessage = error.description ?? 'Camera could not be opened.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cameraStatus = _CameraStatus.error;
        _cameraMessage = 'Camera could not be opened on this device.';
      });
    }
  }

  Future<void> _disposeCamera() async {
    final controller = _cameraController;
    _cameraController = null;
    _cameraInitialization = null;
    await controller?.dispose();
  }

  Future<void> _handleCapture() async {
    if (_isProcessing || _reviewImage != null || _isCapturing) return;
    _isCapturing = true;

    if (widget.testImageFactory != null) {
      try {
        await _captureFromTestFactory(CaptureSource.camera);
      } finally {
        _isCapturing = false;
      }
      return;
    }

    final controller = _cameraController;
    if (controller == null ||
        _cameraStatus != _CameraStatus.ready ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      _isCapturing = false;
      return;
    }

    try {
      final file = await controller.takePicture();
      final preprocessed = await ImagePreprocessingService.instance.normalizeAndInspect(
        file: file,
        side: _currentSide,
        source: CaptureSource.camera,
      );
      if (!mounted) return;
      setState(
        () => _reviewImage = _CapturedImageData(
          image: preprocessed.image,
          file: file,
          qualityReport: preprocessed.qualityReport,
        ),
      );
    } on ImageProcessingException catch (error) {
      _showCaptureProblem(error.message);
    } on CameraException catch (error) {
      _showCaptureProblem(error.description ?? 'The camera could not capture.');
    } catch (_) {
      _showCaptureProblem('The captured photograph could not be processed.');
    } finally {
      _isCapturing = false;
    }
  }

  Future<void> _chooseFromPhotos() async {
    if (_isProcessing || _reviewImage != null || _isCapturing) return;
    _isCapturing = true;

    if (widget.testImageFactory != null) {
      try {
        await _captureFromTestFactory(CaptureSource.gallery);
      } finally {
        _isCapturing = false;
      }
      return;
    }

    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: true,
        // A size limit makes Android re-encode the picked photo (HEIC/HEIF
        // included) to JPEG/PNG, which the image decoder can read; without one
        // the original file is returned. iOS already converts HEIC to JPEG.
        // 4096 px matches the server's maximum accepted dimension.
        maxWidth: _galleryMaxDimension,
        maxHeight: _galleryMaxDimension,
      );
      if (file == null) return;

      final preprocessed = await ImagePreprocessingService.instance.normalizeAndInspect(
        file: file,
        side: _currentSide,
        source: CaptureSource.gallery,
      );
      if (!mounted) return;
      setState(
        () => _reviewImage = _CapturedImageData(
          image: preprocessed.image,
          file: file,
          qualityReport: preprocessed.qualityReport,
        ),
      );
    } on ImageProcessingException catch (error) {
      _showCaptureProblem(error.message);
    } catch (_) {
      _showCaptureProblem('That photo could not be opened or processed.');
    } finally {
      _isCapturing = false;
    }
  }

  Future<void> _captureFromTestFactory(CaptureSource source) async {
    final image = await widget.testImageFactory!(_currentSide, source);
    if (image != null && mounted) {
      setState(() => _reviewImage = _CapturedImageData(image: image));
    }
  }



  void _showCaptureProblem(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _acceptReview() {
    final review = _reviewImage;
    if (review == null) return;
    final reviewedSide = review.image.side;

    setState(() {
      _captures[reviewedSide] = review;
      _reviewImage = null;
      if (reviewedSide == CaptureSide.front) {
        _captureStep = _CaptureStep.reverse;
      } else if (reviewedSide == CaptureSide.reverse) {
        _captureStep = _CaptureStep.edge;
      }
    });

    if (reviewedSide == CaptureSide.edge) {
      _triggerAnalysis();
    }
  }

  void _analyzeFrontOnly() {
    final review = _reviewImage;
    if (review == null) return;
    setState(() {
      _captures[CaptureSide.front] = review;
      _reviewImage = null;
    });
    _triggerAnalysis();
  }

  void _retakeReview() {
    setState(() => _reviewImage = null);
  }

  void _skipEdgeAndAnalyze() {
    if (_captureStep == _CaptureStep.edge && !_isProcessing) {
      _triggerAnalysis();
    }
  }

  Future<void> _triggerAnalysis() async {
    if (_isProcessing) return;
    final stepBeforeAnalysis = _captureStep;
    setState(() {
      _isProcessing = true;
      _captureStep = _CaptureStep.analyzing;
      _recognitionResult = null;
    });

    final front = _captures[CaptureSide.front]?.image;
    if (front == null) {
      if (mounted) setState(() => _isProcessing = false);
      _showCaptureProblem('Capture the front of the coin before analysis.');
      return;
    }

    // Check scan quota before proceeding
    final subService = SubscriptionProvider.maybeOf(context);
    if (!AuthService.instance.currentState.isAuthenticated) {
      // Guests: the server's guest allowance decides. The local count only
      // skips a request that would certainly be refused. Guests cannot buy a
      // plan, so the way forward is a free account, not the paywall.
      final used = (await subService?.currentEntitlement())?.scansUsedToday ?? 0;
      if (used >= TierQuota.guestDaily) {
        if (!mounted) return;
        setState(() {
          _isProcessing = false;
          _captureStep = stepBeforeAnalysis;
        });
        await _promptGuestLimit();
        return;
      }
    } else if (subService != null) {
      final entitlement = await subService.currentEntitlement();
      if (!entitlement.canScan) {
        if (!mounted) return;
        final upgraded = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => PaywallScreen(subscriptionService: subService),
          ),
        );
        if (upgraded != true || !mounted) {
          if (mounted) setState(() => _isProcessing = false);
          return;
        }
        // Re-check after potential upgrade
        final refreshed = await subService.currentEntitlement();
        if (!refreshed.canScan) {
          if (mounted) setState(() => _isProcessing = false);
          return;
        }
      }
    }

    _analysisStageIndex = 0;
    _analysisStageTimer?.cancel();
    _analysisStageTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (mounted && _isProcessing) {
        setState(() {
          _analysisStageIndex = (_analysisStageIndex + 1) % _analysisStages.length;
        });
      }
    });

    _rotationController.repeat();

    try {
      final result = await _recognitionService.recognize(
        CoinScanInput(
          frontImage: front,
          reverseImage: _captures[CaptureSide.reverse]?.image,
          edgeImage: _captures[CaptureSide.edge]?.image,
        ),
      );

      _analysisStageTimer?.cancel();
      if (!mounted) return;
      _rotationController.stop();
      setState(() {
        _isProcessing = false;
        _recognitionResult = result;
      });
      if (result.guestLimitReached) {
        unawaited(_promptGuestLimit(result.message));
        return;
      }

      // Record scan usage against quota ONLY upon successful identification
      final isRecognitionSuccessful = result.candidates.isNotEmpty &&
          result.status != RecognitionStatus.unavailable &&
          result.status != RecognitionStatus.error &&
          result.status != RecognitionStatus.insufficientQuality &&
          result.status != RecognitionStatus.unknown;

      if (isRecognitionSuccessful) {
        subService?.recordScanUsage();
      }

      // Record scan history persistence
      try {
        final record = ScanRecord.fromRecognitionResult(
          id: 'scan_${DateTime.now().millisecondsSinceEpoch}',
          result: result,
          frontImagePath: front.path,
          reverseImagePath: _captures[CaptureSide.reverse]?.image.path,
        );
        ScanHistoryService.instance.addRecord(record).catchError((e) {
          debugPrint('Failed to save to scan history: $e');
        });
      } catch (e) {
        debugPrint('Failed to save to scan history: $e');
      }
    } catch (e) {
      // Recognition failed (network error, server 500, timeout, etc.)
      // Clean up UI state — do NOT deduct quota on failure.
      _analysisStageTimer?.cancel();
      if (!mounted) return;
      _rotationController.stop();
      setState(() {
        _isProcessing = false;
        _recognitionResult = null;
      });
      _showCaptureProblem('Recognition failed. Please check your connection and try again.');
      debugPrint('Recognition error: $e');
    }
  }

  Future<void> _promptGuestLimit([String? message]) {
    return promptForAccount(
      context,
      title: 'You’ve used today’s free scans',
      message: message ??
          'Guests can identify ${TierQuota.guestDaily} coins a day. Create a free '
              'account to keep scanning and save coins to your vault.',
    );
  }

  void _continueToReverseFromResults() {
    setState(() {
      _recognitionResult = null;
      _reviewImage = null;
      _captureStep = _CaptureStep.reverse;
    });
  }

  void _showCaptureGuide() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _CaptureGuideSheet(),
    );
  }

  void _restartScan() {
    _analysisStageTimer?.cancel();
    setState(() {
      _analysisStageIndex = 0;
      _captureStep = _CaptureStep.front;
      _recognitionResult = null;
      _reviewImage = null;
      _isProcessing = false;
      _focusPoint = null;
      _captures.clear();
    });
  }

  Future<void> _toggleFlash() async {
    final controller = _cameraController;
    if (controller == null || _cameraStatus != _CameraStatus.ready) return;
    final next = !_isFlashOn;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _isFlashOn = next);
    } catch (_) {
      _showCaptureProblem('Flash is not available on this camera.');
    }
  }

  Future<void> _toggleFocusMode() async {
    final controller = _cameraController;
    if (controller == null || _cameraStatus != _CameraStatus.ready) return;
    final next = !_isMacroOn;
    try {
      await controller.setFocusMode(next ? FocusMode.auto : FocusMode.locked);
      if (mounted) setState(() => _isMacroOn = next);
    } catch (_) {
      _showCaptureProblem('Focus control is not available on this camera.');
    }
  }

  void _handleFocusTap(TapUpDetails details) {
    if (_isProcessing || _reviewImage != null) return;
    setState(() => _focusPoint = details.localPosition);
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _focusPoint = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_reviewImage == null &&
              !_isProcessing &&
              _recognitionResult == null)
            _buildCameraSurface(),
          if (_reviewImage != null)
            _ReviewCapturedImage(
              data: _reviewImage!,
              previewLoader: widget.testPreviewLoader,
              onRetake: _retakeReview,
              onContinue: _acceptReview,
              onAnalyzeFrontOnly: _analyzeFrontOnly,
            ),
          if (_recognitionResult != null)
            _RecognitionResultView(
              result: _recognitionResult!,
              frontImagePath: _captures[CaptureSide.front]?.image.path,
              reverseImagePath: _captures[CaptureSide.reverse]?.image.path,
              onRetake: _restartScan,
              onClose: () => Navigator.of(context).pop(),
              onScanReverse: _captures.containsKey(CaptureSide.front) &&
                      !_captures.containsKey(CaptureSide.reverse)
                  ? _continueToReverseFromResults
                  : null,
            ),
          if (_isProcessing) _buildProcessingState(),
          if (_reviewImage == null &&
              !_isProcessing &&
              _recognitionResult == null)
            _buildTopControls(),
          if (_reviewImage == null &&
              !_isProcessing &&
              _recognitionResult == null)
            _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildCameraSurface() {
    return GestureDetector(
      onTapUp: _handleFocusTap,
      child: Stack(
        children: [
          Positioned.fill(
            child: _CameraPreviewSurface(
              status: _cameraStatus,
              message: _cameraMessage,
              initialization: _cameraInitialization,
              controller: _cameraController,
              isPermanentlyBlocked: _isPermissionPermanentlyBlocked,
              onRetry: _initializeCamera,
            ),
          ),
          Opacity(
            opacity: 0.12,
            child: CustomPaint(
              painter: CameraGridPainter(),
              child: Container(),
            ),
          ),
          Center(child: _CaptureReticle(step: _captureStep)),
          // Real-time Framing & Environment Guidance Chip
          Positioned(
            top: 72,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: AppRadius.allPill,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tips_and_updates_outlined, size: 14, color: AppColors.gold),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _captureStep == _CaptureStep.edge
                            ? 'Align rim horizontally inside guide • Good lighting'
                            : 'Center coin inside gold ring • Flat dark surface • Avoid glare',
                        style: AppTypography.captionSmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_focusPoint != null)
            Positioned(
              left: _focusPoint!.dx - 24,
              top: _focusPoint!.dy - 24,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.gold, width: 1.5),
                ),
              ).animate().scale(duration: 200.ms).fadeOut(delay: 800.ms),
            ),
        ],
      ),
    );
  }

  Widget _buildProcessingState() {
    final currentStage = _analysisStages[_analysisStageIndex];
    return ColoredBox(
      color: AppColors.ink,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RotationTransition(
                  turns: _rotationController,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.gold.withValues(alpha: 0.12),
                      border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                    ),
                    child: const Icon(
                      Icons.sync_rounded,
                      color: AppColors.gold,
                      size: 38,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Analyzing Coin...',
                  style: AppTypography.sectionHeader.copyWith(
                    color: Colors.white,
                    fontSize: 24,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    currentStage,
                    key: ValueKey('stage_$_analysisStageIndex'),
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.gold,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                // Progress dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_analysisStages.length, (i) {
                    final active = i <= _analysisStageIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active ? AppColors.gold : Colors.white24,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Cross-referencing mintage records, die varieties & live bullion spot.',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textOnInkMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopControls() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Row(
            children: [
              // Left: cancel button (fixed width)
              IconButton(
                tooltip: 'Cancel scan',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              // Centre: step pills, take all remaining space and never overflow
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.xs,
                  children: [
                    _StepPill(
                      label: 'Front',
                      done: _captures.containsKey(CaptureSide.front),
                      active: _captureStep == _CaptureStep.front,
                    ),
                    _StepPill(
                      label: 'Reverse',
                      done: _captures.containsKey(CaptureSide.reverse),
                      active: _captureStep == _CaptureStep.reverse,
                    ),
                    _StepPill(
                      label: 'Edge',
                      done: _captures.containsKey(CaptureSide.edge),
                      active: _captureStep == _CaptureStep.edge,
                    ),
                  ],
                ),
              ),
              // Right: camera controls (fixed width)
              IconButton(
                tooltip: _isFlashOn ? 'Turn flash off' : 'Turn flash on',
                icon: Icon(
                  _isFlashOn ? Icons.flash_on : Icons.flash_off,
                  color: Colors.white,
                ),
                onPressed: _cameraStatus == _CameraStatus.ready
                    ? _toggleFlash
                    : null,
              ),
              IconButton(
                tooltip: 'Toggle focus lock',
                icon: Icon(
                  _isMacroOn
                      ? Icons.center_focus_strong
                      : Icons.center_focus_weak,
                  color: _isMacroOn ? AppColors.gold : Colors.white,
                ),
                onPressed: _cameraStatus == _CameraStatus.ready
                    ? _toggleFocusMode
                    : null,
              ),
            ],
          ),
        ),

      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xD9000000), Colors.transparent],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CaptureInstruction(
                title: _stepTitle,
                body: _stepBody,
                showSkip: _captureStep == _CaptureStep.edge,
                onSkip: _skipEdgeAndAnalyze,
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _RoundToolButton(
                    key: const ValueKey('scan_gallery'),
                    tooltip: 'Choose from Photos',
                    icon: Icons.photo_library_outlined,
                    label: 'Photos',
                    onPressed: _chooseFromPhotos,
                  ),
                  Semantics(
                    button: true,
                    label: _primaryAction,
                    child: GestureDetector(
                      key: const ValueKey('scan_shutter'),
                      onTap: _cameraStatus == _CameraStatus.ready
                          ? _handleCapture
                          : null,
                      child: AnimatedOpacity(
                        opacity: _cameraStatus == _CameraStatus.ready
                            ? 1
                            : 0.42,
                        duration: AppDuration.fast,
                        child: Container(
                          height: 82,
                          width: 82,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          padding: const EdgeInsets.all(5),
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _RoundToolButton(
                    key: const ValueKey('scan_guide'),
                    tooltip: 'Framing & Lighting Guide',
                    icon: Icons.lightbulb_outline,
                    label: 'Guide',
                    onPressed: _showCaptureGuide,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CapturedImageData {
  final CapturedCoinImage image;
  final XFile? file;
  final ImageQualityReport? qualityReport;

  const _CapturedImageData({
    required this.image,
    this.file,
    this.qualityReport,
  });
}

class _CameraPreviewSurface extends StatelessWidget {
  final _CameraStatus status;
  final String? message;
  final Future<void>? initialization;
  final CameraController? controller;
  final bool isPermanentlyBlocked;
  final VoidCallback onRetry;

  const _CameraPreviewSurface({
    required this.status,
    required this.message,
    required this.initialization,
    required this.controller,
    this.isPermanentlyBlocked = false,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cameraController = controller;
    if (status == _CameraStatus.ready &&
        cameraController != null &&
        initialization != null) {
      return FutureBuilder<void>(
        future: initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _CameraMessage(
              icon: Icons.camera_alt_outlined,
              title: 'Opening camera',
              message: 'Preparing the rear camera.',
            );
          }

          final previewSize = cameraController.value.previewSize;
          final double previewW;
          final double previewH;
          if (previewSize != null) {
            final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
            if (isPortrait) {
              previewW = math.min(previewSize.width, previewSize.height);
              previewH = math.max(previewSize.width, previewSize.height);
            } else {
              previewW = math.max(previewSize.width, previewSize.height);
              previewH = math.min(previewSize.width, previewSize.height);
            }
          } else {
            previewW = 1;
            previewH = 1;
          }

          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: previewW,
                  height: previewH,
                  child: CameraPreview(cameraController),
                ),
              ),
            ),
          );
        },
      );
    }

    final isPermission = status == _CameraStatus.permissionDenied;
    return _CameraMessage(
      icon: isPermission ? Icons.no_photography_outlined : Icons.videocam_off,
      title: switch (status) {
        _CameraStatus.initializing => 'Opening camera',
        _CameraStatus.permissionDenied => isPermanentlyBlocked ? 'Camera access blocked' : 'Camera access needed',
        _CameraStatus.unavailable => 'Camera unavailable',
        _CameraStatus.error => 'Camera could not open',
        _CameraStatus.ready => 'Camera ready',
      },
      message: message ?? 'Preparing the camera.',
      actionLabel: isPermission
          ? (isPermanentlyBlocked ? 'Open Settings' : 'Allow Camera')
          : 'Retry',
      onAction: (isPermission && isPermanentlyBlocked) ? openAppSettings : onRetry,
    );
  }
}

class _CameraMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CameraMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0B0B0C),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Semantics(
              liveRegion: true,
              label: '$title. $message',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: AppColors.gold, size: 44),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    title,
                    style: AppTypography.sectionHeader.copyWith(
                      color: Colors.white,
                      fontSize: 24,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    message,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textOnInkMuted,
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: AppSpacing.xl),
                    FilledButton.icon(
                      onPressed: onAction,
                      icon: const Icon(Icons.settings_outlined),
                      label: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewCapturedImage extends StatelessWidget {
  final _CapturedImageData data;
  final TestPreviewLoader? previewLoader;
  final VoidCallback onRetake;
  final VoidCallback onContinue;
  final VoidCallback? onAnalyzeFrontOnly;

  const _ReviewCapturedImage({
    required this.data,
    required this.previewLoader,
    required this.onRetake,
    required this.onContinue,
    this.onAnalyzeFrontOnly,
  });

  @override
  Widget build(BuildContext context) {
    final side = _sideLabel(data.image.side);
    final previewFuture = previewLoader?.call(data.image) ??
        data.file?.readAsBytes() ??
        Future<Uint8List>.value(Uint8List(0));

    return ColoredBox(
      color: AppColors.ink,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Text(
                    'Review $side',
                    style: AppTypography.sectionHeader.copyWith(
                      color: Colors.white,
                      fontSize: 22,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Retake $side',
                    icon: const Icon(Icons.refresh_rounded),
                    color: Colors.white,
                    onPressed: onRetake,
                  ),
                ],
              ),
            ),
            if (data.qualityReport != null && data.qualityReport!.warnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.15),
                    borderRadius: AppRadius.allMd,
                    border: Border.all(color: AppColors.amber.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.amber, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              data.qualityReport!.warnings.first,
                              style: AppTypography.captionSmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (data.qualityReport!.recommendedActions.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                data.qualityReport!.recommendedActions.first,
                                style: AppTypography.captionSmall.copyWith(
                                  color: AppColors.textOnInkMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                child: ClipRRect(
                  borderRadius: AppRadius.allLg,
                  child: FutureBuilder<Uint8List>(
                    future: previewFuture,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const ColoredBox(
                          color: Color(0xFF111113),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.gold,
                            ),
                          ),
                        );
                      }
                      if (snapshot.data!.isEmpty) {
                        return const _CameraMessage(
                          icon: Icons.image_not_supported_outlined,
                          title: 'Preview unavailable',
                          message: 'The image reference is ready for analysis.',
                        );
                      }
                      return Image.memory(
                        snapshot.data!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                      );
                    },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  Text(
                    '${data.image.width} x ${data.image.height} px',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textOnInkMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onRetake,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retake'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.24),
                            ),
                            minimumSize: const Size.fromHeight(54),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onContinue,
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text('Continue'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            foregroundColor: AppColors.ink,
                            minimumSize: const Size.fromHeight(54),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (data.image.side == CaptureSide.front && onAnalyzeFrontOnly != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    TextButton.icon(
                      onPressed: onAnalyzeFrontOnly,
                      icon: const Icon(Icons.bolt_rounded, color: AppColors.gold, size: 18),
                      label: Text(
                        'Analyze Front Only (Skip Reverse)',
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecognitionResultView extends StatefulWidget {
  final RecognitionResult result;
  final String? frontImagePath;
  final String? reverseImagePath;
  final VoidCallback onRetake;
  final VoidCallback onClose;
  final VoidCallback? onScanReverse;

  const _RecognitionResultView({
    required this.result,
    this.frontImagePath,
    this.reverseImagePath,
    required this.onRetake,
    required this.onClose,
    this.onScanReverse,
  });

  @override
  State<_RecognitionResultView> createState() => _RecognitionResultViewState();
}

class _RecognitionResultViewState extends State<_RecognitionResultView> {
  List<VaultCoinItem> _duplicateMatches = [];
  bool _isSaved = false;
  bool _isSaving = false;
  VaultCoinItem? _savedItem;

  @override
  void initState() {
    super.initState();
    _checkForDuplicates();
  }

  Future<void> _checkForDuplicates() async {
    final candidate = widget.result.primaryCandidate;
    if (candidate == null) return;
    try {
      await CollectionStorageService.instance.loadCollection();
      final duplicates = CollectionStorageService.instance.findDuplicates(
        country: candidate.identity.country,
        denomination: candidate.identity.denomination,
        year: candidate.identity.year,
        mintMark: candidate.identity.mint,
      );
      if (mounted) {
        setState(() {
          _duplicateMatches = duplicates;
        });
      }
    } catch (_) {
      // Safe fallback
    }
  }

  Future<void> _saveToCollection() async {
    final candidate = widget.result.primaryCandidate;
    if (candidate == null || _isSaved || _isSaving) return;

    // The vault lives in the user's account. A guest signs in first and then
    // taps Save again: nothing is saved (or moved into the account) silently.
    if (!AuthService.instance.currentState.isAuthenticated) {
      final signedIn = await promptForAccount(
        context,
        title: 'Sign in to save coins',
        message:
            'Your vault is kept in your CoinScan account, so it’s backed up and '
            'on your other devices. Sign in or create a free account, then tap '
            'Save to Vault again.',
      );
      if (!signedIn || !mounted) return;
      unawaited(_checkForDuplicates());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: ValueKey('signed_in_tap_save_again'),
          content: Text('You’re signed in. Tap Save to Vault to add this coin.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final id = candidate.identity;
      final valuation = widget.result.valuation;
      // A value range is stored only when a real collector/market estimate
      // exists. Melt value is stored separately, and a missing valuation is
      // never saved as "$0–$0".
      final collectorEst = valuation?.collectorEstimate;
      final valRange =
          (collectorEst?.low != null && collectorEst?.high != null)
              ? '${collectorEst!.low!.toStringAsFixed(0)}–${collectorEst.high!.toStringAsFixed(0)} ${valuation!.currencyCode}'
              : null;
      final meltVal = valuation?.meltValue;
      final catVal = valuation?.catalogueValue;
      final confScore = candidate.confidence?.overallScore;
      // Use the service's corroboration-gated level, never a local re-derivation.
      final confLevel = candidate.confidence != null
          ? CoinReportData.levelLabel(candidate.confidence!.level)
          : null;

      final valHigh = valuation?.marketHigh;
      final valLow = valuation?.marketLow;
      final estValue = valuation?.catalogueValue ??
          (valHigh != null && valLow != null
              ? (valHigh + valLow) / 2.0
              : valHigh ?? valLow ?? valuation?.meltValue);

      final keyEvidence = candidate.evidence
          .map(
            (e) => [
              e.label,
              if (e.detail.isNotEmpty) e.detail,
              if (e.source != null && e.source!.isNotEmpty) 'Source: ${e.source}',
            ].join(' — '),
          )
          .toList();

      final newItem = VaultCoinItem(
        id: 'vault_${DateTime.now().millisecondsSinceEpoch}',
        coinName: candidate.formattedTitle,
        country: id.country,
        denomination: id.denomination,
        year: id.year,
        mintMark: id.mint,
        variety: id.variety,
        composition: id.composition,
        weightG: id.weightG,
        diameterMm: id.diameterMm,
        kmNumber: id.kmNumber,
        numistaId: id.numistaId,
        conditionEstimate: candidate.conditionGrade,
        currentEstimatedValue: estValue,
        initialValuationSnapshot: estValue,
        valuationRange: valRange,
        meltValue: meltVal,
        catalogueValue: catVal,
        confidenceScore: confScore,
        confidenceLevel: confLevel,
        keyEvidence: keyEvidence,
        frontImagePath: widget.frontImagePath,
        reverseImagePath: widget.reverseImagePath,
        dateAdded: DateTime.now(),
      );

      await CollectionStorageService.instance.addItem(newItem);

      if (mounted) {
        setState(() {
          _isSaved = true;
          _isSaving = false;
          _savedItem = newItem;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved "${newItem.name}" to your collection vault.'),
            backgroundColor: AppColors.emerald,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save to collection: $e'),
            backgroundColor: AppColors.crimson,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _shareReport() {
    final candidate = widget.result.primaryCandidate;
    if (candidate == null) return;
    final report = CoinReportData.fromCandidate(
      candidate,
      valuation: widget.result.valuation,
      frontPath: widget.frontImagePath,
      reversePath: widget.reverseImagePath,
    );
    CoinReportSheet.show(context, report);
  }

  Widget _buildScanReversePromptCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.1),
        borderRadius: AppRadius.allLg,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.flip_camera_android_rounded,
              color: AppColors.gold,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Want higher confidence?',
                  style: AppTypography.captionSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Scan reverse side to verify mint mark and date.',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textOnInkMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed: widget.onScanReverse,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.ink,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 34),
            ),
            child: const Text(
              'Scan Reverse',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasCandidates => widget.result.candidates.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.ink,
      child: SafeArea(
        child: Column(
          children: [
            // Top App Bar
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Close scanner',
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: widget.onClose,
                  ),
                  _buildStatusBadge(widget.result.status),
                  const SizedBox(width: 48), // Balancing spacer
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                children: [
                  if (_hasCandidates) ...[
                    _buildHeroCandidateCard(widget.result.primaryCandidate!),
                    const SizedBox(height: AppSpacing.md),

                    // Prompt to scan reverse side if user only captured front
                    if (widget.frontImagePath != null &&
                        widget.reverseImagePath == null &&
                        widget.onScanReverse != null) ...[
                      _buildScanReversePromptCard(),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Duplicate Detection Warning
                    if (_duplicateMatches.isNotEmpty) ...[
                      DuplicateWarningCard(
                        duplicates: _duplicateMatches,
                        onAddAnyway: () {
                          setState(() => _duplicateMatches = []);
                        },
                        onViewExisting: () {
                          if (_duplicateMatches.isNotEmpty) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CollectionDetailScreen(
                                  vaultItem: _duplicateMatches.first,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Honest Confidence
                    if (widget.result.primaryCandidate!.confidence != null) ...[
                      HonestConfidenceCard(
                        confidence: widget.result.primaryCandidate!.confidence!,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Collector Insight: Worth a Closer Look
                    WorthACloserLookCard(
                      candidate: widget.result.primaryCandidate!,
                      valuation: widget.result.valuation,
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Why We Think This Is Your Coin (8 Factual Evidence Cards)
                    WhyWeThinkThisIsYourCoinWidget(
                      candidate: widget.result.primaryCandidate!,
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Transparent Valuation (Face, Melt, Catalogue, Market Range)
                    TransparentValuationCard(
                      valuation: widget.result.valuation,
                      candidate: widget.result.primaryCandidate!,
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Condition / Grade Estimate (only shown if genuine grade available)
                    if (widget.result.primaryCandidate!.conditionGrade != null &&
                        widget.result.primaryCandidate!.conditionGrade!.isNotEmpty) ...[
                      ConditionEstimateCard(
                        conditionGrade: widget.result.primaryCandidate!.conditionGrade,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Should I Consider Professional Grading?
                    ShouldIGetThisGradedCard(
                      candidate: widget.result.primaryCandidate!,
                      valuation: widget.result.valuation,
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Alternative Candidates (if any)
                    if (widget.result.candidates.length > 1) ...[
                      _buildAlternativeCandidatesSection(
                        widget.result.candidates.sublist(1),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Warnings (if any)
                    if (widget.result.warnings.isNotEmpty) ...[
                      _buildWarningsCard(widget.result.warnings),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Wrong Identification Feedback Loop (Thumb Up / Down)
                    WrongIdentificationFeedbackWidget(
                      candidate: widget.result.primaryCandidate!,
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Collector Vault & Sharing Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            key: const ValueKey('save_to_vault'),
                            onPressed: _isSaved ? null : _saveToCollection,
                            icon: Icon(
                              _isSaved
                                  ? Icons.check_circle_rounded
                                  : Icons.bookmark_add_outlined,
                              size: 18,
                            ),
                            label: Text(
                              _isSaved ? 'Saved to Vault' : 'Save to Vault',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.gold,
                              foregroundColor: AppColors.ink,
                              minimumSize: const Size.fromHeight(50),
                              disabledBackgroundColor:
                                  AppColors.gold.withValues(alpha: 0.3),
                              disabledForegroundColor: Colors.white60,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _shareReport,
                            icon: const Icon(Icons.share_outlined, size: 18),
                            label: const Text('Share Report'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.28),
                              ),
                              minimumSize: const Size.fromHeight(50),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_isSaved && _savedItem != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CollectionDetailScreen(
                                vaultItem: _savedItem!,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: AppColors.gold,
                        ),
                        label: const Text('View Coin in Vault'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.gold,
                          side: const BorderSide(color: AppColors.gold),
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ],
                  ] else ...[
                    _buildUnidentifiedState(),
                  ],
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),

            // Bottom Action Bar
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Close'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.24),
                        ),
                        minimumSize: const Size.fromHeight(54),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.onRetake,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('New scan'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.ink,
                        minimumSize: const Size.fromHeight(54),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(RecognitionStatus status) {
    final (label, color) = switch (status) {
      RecognitionStatus.identified => ('Identified', AppColors.emerald),
      RecognitionStatus.candidate => ('Probable Match', AppColors.gold),
      RecognitionStatus.lowConfidence => ('Possible Match', AppColors.amber),
      RecognitionStatus.insufficientQuality => ('Poor Quality', AppColors.amber),
      RecognitionStatus.unknown => ('Unidentified', Colors.white60),
      RecognitionStatus.unavailable => ('Service Unavailable', Colors.white60),
      RecognitionStatus.error => ('Scan Error', AppColors.crimson),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: AppRadius.allPill,
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: AppTypography.captionSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildHeroCandidateCard(RecognitionCandidate candidate) {
    final id = candidate.identity;
    final title = candidate.formattedTitle;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.inkElevated,
        borderRadius: AppRadius.allXl,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!kIsWeb &&
                  widget.frontImagePath != null &&
                  File(widget.frontImagePath!).existsSync())
                ClipRRect(
                  borderRadius: AppRadius.allMd,
                  child: Image.file(
                    File(widget.frontImagePath!),
                    width: 54,
                    height: 54,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 54,
                      height: 54,
                      color: AppColors.inkElevated,
                      child: const Icon(Icons.monetization_on_rounded, color: AppColors.gold, size: 28),
                    ),
                  ),
                )
              else
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.gold.withValues(alpha: 0.15),
                  ),
                  child: const Icon(
                    Icons.monetization_on_rounded,
                    color: AppColors.gold,
                    size: 28,
                  ),
                ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.sectionHeader.copyWith(
                        color: Colors.white,
                        fontSize: 22,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      candidate.providerName,
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textOnInkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!kIsWeb &&
              widget.reverseImagePath != null &&
              File(widget.reverseImagePath!).existsSync()) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: AppRadius.allMd,
              ),
              child: Row(
                children: [
                  Text(
                    'Captured Photos:',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textOnInkMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!kIsWeb &&
                      widget.frontImagePath != null &&
                      File(widget.frontImagePath!).existsSync()) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.file(
                        File(widget.frontImagePath!),
                        width: 24,
                        height: 24,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Obverse',
                      style: AppTypography.captionSmall.copyWith(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.file(
                      File(widget.reverseImagePath!),
                      width: 24,
                      height: 24,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Reverse',
                    style: AppTypography.captionSmall.copyWith(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const Divider(color: Colors.white12),
          const SizedBox(height: AppSpacing.md),

          // Key Coin Specifications Grid
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              if (id.year != null) _buildSpecItem('Year', '${id.year}'),
              if (id.mint != null) _buildSpecItem('Mint Mark', id.mint!),
              if (id.composition != null) _buildSpecItem('Composition', id.composition!),
              if (id.weightG != null) _buildSpecItem('Weight', '${id.weightG} g'),
              if (id.diameterMm != null) _buildSpecItem('Diameter', '${id.diameterMm} mm'),
              if (id.kmNumber != null) _buildSpecItem('KM Reference', id.kmNumber!),
            ],
          ),

          // Numista Attribution Badge
          if (id.numistaId != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: AppRadius.allMd,
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_outlined, size: 14, color: AppColors.gold),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Numista N# ${id.numistaId} • Catalogue record',
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textOnInkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpecItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.captionSmall.copyWith(color: AppColors.textOnInkMuted),
        ),
        Text(
          value,
          style: AppTypography.bodyMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildAlternativeCandidatesSection(List<RecognitionCandidate> alternatives) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Alternative Candidate Varieties',
          style: AppTypography.titleSmall.copyWith(color: Colors.white),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...alternatives.map(
          (c) => Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.inkElevated,
              borderRadius: AppRadius.allMd,
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white12,
                  ),
                  child: Center(
                    child: Text(
                      '#${c.rank}',
                      style: AppTypography.captionSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.formattedTitle,
                        style: AppTypography.bodyMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (c.identity.mint != null)
                        Text(
                          'Mint: ${c.identity.mint}',
                          style: AppTypography.captionSmall.copyWith(
                            color: AppColors.textOnInkMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWarningsCard(List<String> warnings) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.12),
        borderRadius: AppRadius.allMd,
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: warnings
            .map(
              (w) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        w,
                        style: AppTypography.captionSmall.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildUnidentifiedState() {
    final isQuality = widget.result.status == RecognitionStatus.insufficientQuality;
    final icon = isQuality ? Icons.blur_on_rounded : Icons.search_off_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gold.withValues(alpha: 0.14),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.32)),
            ),
            child: Icon(icon, color: AppColors.gold, size: 34),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            widget.result.message,
            style: AppTypography.sectionHeader.copyWith(
              color: Colors.white,
              fontSize: 24,
              height: 1.15,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          if (widget.result.qualityReport != null &&
              widget.result.qualityReport!.recommendedActions.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.lg),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.inkElevated,
                borderRadius: AppRadius.allLg,
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tips for Better Identification',
                    style: AppTypography.titleSmall.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ...widget.result.qualityReport!.recommendedActions.map(
                    (action) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.arrow_right_rounded, size: 18, color: AppColors.gold),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              action,
                              style: AppTypography.captionSmall.copyWith(
                                color: AppColors.textOnInkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoundToolButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _RoundToolButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 62,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            tooltip: tooltip,
            icon: Icon(icon, color: Colors.white),
            onPressed: onPressed,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              minimumSize: const Size(50, 50),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTypography.captionSmall.copyWith(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _CaptureInstruction extends StatelessWidget {
  final String title;
  final String body;
  final bool showSkip;
  final VoidCallback onSkip;

  const _CaptureInstruction({
    required this.title,
    required this.body,
    required this.showSkip,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: AppRadius.allLg,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.sectionHeader.copyWith(
                    color: Colors.white,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textOnInkMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (showSkip) ...[
            const SizedBox(width: AppSpacing.md),
            TextButton(
              onPressed: onSkip,
              child: Text(
                'Skip',
                style: AppTypography.titleSmall.copyWith(color: AppColors.gold),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CaptureReticle extends StatelessWidget {
  final _CaptureStep step;

  const _CaptureReticle({required this.step});

  @override
  Widget build(BuildContext context) {
    final isEdge = step == _CaptureStep.edge;
    return AnimatedContainer(
      duration: AppDuration.base,
      curve: AppCurves.standard,
      width: isEdge ? 290 : 264,
      height: isEdge ? 88 : 264,
      decoration: BoxDecoration(
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.48),
          width: 2,
        ),
        borderRadius: BorderRadius.circular(isEdge ? AppRadius.xxl : 132),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: isEdge ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: isEdge ? AppRadius.allXxl : null,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(painter: _ReticleTickPainter(isEdge: isEdge)),
          ),
          Center(
            child: Icon(
              isEdge ? Icons.drag_handle_rounded : Icons.circle_outlined,
              color: Colors.white.withValues(alpha: 0.28),
              size: isEdge ? 38 : 86,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepPill extends StatelessWidget {
  final String label;
  final bool done;
  final bool active;

  const _StepPill({
    required this.label,
    required this.done,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = done || active ? AppColors.gold : Colors.white54;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: done ? 0.22 : 0.08),
        borderRadius: AppRadius.allPill,
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_rounded : Icons.radio_button_unchecked_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.captionSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class CameraGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(size.width / 3, 0),
      Offset(size.width / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(2 * size.width / 3, 0),
      Offset(2 * size.width / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      paint,
    );
    canvas.drawLine(
      Offset(0, 2 * size.height / 3),
      Offset(size.width, 2 * size.height / 3),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ReticleTickPainter extends CustomPainter {
  final bool isEdge;

  const _ReticleTickPainter({required this.isEdge});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.gold.withValues(alpha: 0.72)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    if (isEdge) {
      for (var x = 28.0; x < size.width - 28; x += 22) {
        canvas.drawLine(Offset(x, 14), Offset(x, 24), paint);
        canvas.drawLine(
          Offset(x, size.height - 14),
          Offset(x, size.height - 24),
          paint,
        );
      }
      return;
    }

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 7;
    for (var i = 0; i < 32; i++) {
      final angle = i * math.pi * 2 / 32;
      final outer = Offset(
        center.dx + radius * math.sin(angle),
        center.dy - radius * math.cos(angle),
      );
      final inner = Offset(
        center.dx + (radius - (i % 4 == 0 ? 16 : 9)) * math.sin(angle),
        center.dy - (radius - (i % 4 == 0 ? 16 : 9)) * math.cos(angle),
      );
      canvas.drawLine(inner, outer, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ReticleTickPainter oldDelegate) =>
      oldDelegate.isEdge != isEdge;
}

String _sideLabel(CaptureSide side) => switch (side) {
  CaptureSide.front => 'front',
  CaptureSide.reverse => 'reverse',
  CaptureSide.edge => 'edge',
};

class _CaptureGuideSheet extends StatelessWidget {
  const _CaptureGuideSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: const BoxDecoration(
        color: AppColors.inkElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(
                  Icons.tips_and_updates_outlined,
                  color: AppColors.gold,
                  size: 24,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Coin Scanning Guide',
                  style: AppTypography.sectionHeader.copyWith(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _buildTip(
              icon: Icons.light_mode_outlined,
              title: 'Soft, Diffuse Lighting',
              desc:
                  'Use indirect lighting. Direct harsh flash creates blinding specular glare on silver and lustrous coins.',
            ),
            const SizedBox(height: AppSpacing.md),
            _buildTip(
              icon: Icons.crop_free_rounded,
              title: 'Fill 70–85% of Reticle',
              desc:
                  'Hold your camera directly parallel to the coin surface so edge lettering, mint marks, and date numerals stay sharp.',
            ),
            const SizedBox(height: AppSpacing.md),
            _buildTip(
              icon: Icons.flip_camera_android_rounded,
              title: 'Capture Both Sides',
              desc:
                  'Obverse and reverse sides provide independent proof (date + mint mark), achieving highest recognition accuracy.',
            ),
            const SizedBox(height: AppSpacing.md),
            _buildTip(
              icon: Icons.contrast_rounded,
              title: 'Matte, Dark Background',
              desc:
                  'Place coin on a dark sheet of paper or non-reflective cloth to avoid distracting patterns and edge confusion.',
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.ink,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text(
                  'Got It',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTip({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.gold, size: 20),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textOnInkMuted,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
