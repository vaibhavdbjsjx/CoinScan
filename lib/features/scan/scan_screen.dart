import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/network/mock_api.dart';
import '../collection/collection_detail_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({Key? key}) : super(key: key);

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with TickerProviderStateMixin {
  bool _isProcessing = false;
  bool _isFlashOn = false;
  bool _isMacroOn = true;
  String _currentMode = 'Single'; // Single, Multi, Live
  
  // Animation controllers
  late AnimationController _laserController;
  late AnimationController _rotationController;
  
  // Loading Trivia Fact State
  int _triviaIndex = 0;
  Timer? _triviaTimer;
  final List<String> _triviaFacts = [
    "Did you know? The 1907 Double Eagle was designed by Augustus Saint-Gaudens at the request of Theodore Roosevelt.",
    "This scanner measures metal composition and weight by calculating optical density and diameter ratios.",
    "Numismatic Tip: Cleaning a rare coin can reduce its collector value by up to 80%! Never scrub surfaces.",
    "Only 25,000 examples of the Carson City Silver Dollar were minted in the year 1882.",
    "AI is analyzing microprint sharpness, serial alignment, watermarks, and edge reeding patterns."
  ];

  Offset? _focusPoint;
  
  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
  }

  @override
  void dispose() {
    _laserController.dispose();
    _rotationController.dispose();
    _triviaTimer?.cancel();
    super.dispose();
  }

  Widget _buildFloatingScanMarker(String label, String confidence, String material) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.circle_outlined, color: AppColors.goldAccent, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.caption.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(confidence, style: AppTypography.caption.copyWith(color: AppColors.emerald, fontSize: 10)),
          Text('Material: $material', style: AppTypography.caption.copyWith(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  void _triggerScan() {
    setState(() {
      _isProcessing = true;
      _triviaIndex = 0;
    });

    _laserController.repeat(reverse: true);
    _rotationController.repeat();

    // Rotate trivia facts every 2 seconds
    _triviaTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          _triviaIndex = (_triviaIndex + 1) % _triviaFacts.length;
        });
      }
    });

    // Simulate AI Identification Pipeline
    Future.delayed(const Duration(milliseconds: 6000), () {
      if (mounted) {
        _triviaTimer?.cancel();
        setState(() {
          _isProcessing = false;
        });
        
        // Pushes the identified Saint-Gaudens or random coin details
        final mockCoin = MockApi.collectibles[0]; // Saint-Gaudens
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => CollectionDetailScreen(collectible: mockCoin),
          ),
        );
      }
    });
  }

  void _handleFocusTap(TapUpDetails details) {
    if (_isProcessing) return;
    setState(() {
      _focusPoint = details.localPosition;
    });
    // Remove focus square after 1 second
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() {
          _focusPoint = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Simulated Camera Frame View
          if (!_isProcessing)
            GestureDetector(
              onTapUp: _focusPoint == null ? _handleFocusTap : null,
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.grey[900], // dark camera backdrop
                  ),
                  
                  // Camera abstract grid
                  Opacity(
                    opacity: 0.15,
                    child: CustomPaint(
                      painter: CameraGridPainter(),
                      child: Container(),
                    ),
                  ),

                  // Edge detection bracket reticle overlay
                  Center(
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.gold.withOpacity(0.4),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Stack(
                        children: [
                          // Custom corner markers
                          Positioned(
                            top: 10, left: 10,
                            child: Icon(Icons.crop_free, color: AppColors.gold, size: 24),
                          ),
                          Positioned(
                            top: 10, right: 10,
                            child: Icon(Icons.crop_free, color: AppColors.gold, size: 24),
                          ),
                          Positioned(
                            bottom: 10, left: 10,
                            child: Icon(Icons.crop_free, color: AppColors.gold, size: 24),
                          ),
                          Positioned(
                            bottom: 10, right: 10,
                            child: Icon(Icons.crop_free, color: AppColors.gold, size: 24),
                          ),
                          
                          // Focus/Macro Ring
                          Center(
                            child: Container(
                              width: 180,
                              height: 180,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
                                  width: 1,
                                  style: BorderStyle.solid,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Batch mode: show floating target coins
                  if (_currentMode != 'Single') ...[
                    // Floating target coin 1
                    Positioned(
                      top: 140,
                      left: 60,
                      child: _buildFloatingScanMarker('Coin A', '94% Confidence', 'Silver'),
                    ).animate().fadeIn(duration: 400.ms),
                    
                    // Floating target coin 2
                    Positioned(
                      bottom: 220,
                      right: 50,
                      child: _buildFloatingScanMarker('Coin B', '88% Confidence', 'Gold'),
                    ).animate().fadeIn(duration: 400.ms),
                  ],

                  // Interactive Tap Focus Square
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
            ),

          // 2. Cinematic AI Processing Engine Overlay
          if (_isProcessing)
            Container(
              color: AppColors.textPrimary, // dark premium charcoal
              width: double.infinity,
              height: double.infinity,
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'AI RECOGNITION ENGINE',
                      style: AppTypography.goldLabel.copyWith(
                        letterSpacing: 3,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Analyzing Collectible...',
                      style: AppTypography.sectionHeader.copyWith(
                        color: Colors.white,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Rotating 3D Coin Model and Laser Sweep Animation
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // Core 3D metallic glowing circle
                        AnimatedBuilder(
                          animation: _rotationController,
                          builder: (context, child) {
                            return Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.002) // perspective
                                ..rotateY(_rotationController.value * 2 * 3.1415),
                              child: Container(
                                height: 180,
                                width: 180,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      AppColors.goldLight.withOpacity(0.8),
                                      AppColors.gold,
                                      AppColors.goldDark,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.gold.withOpacity(0.5),
                                      blurRadius: 40,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.insights,
                                    color: Colors.white.withOpacity(0.4),
                                    size: 64,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        // Glowing Scanning Rings
                        Container(
                          height: 240,
                          width: 240,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.gold.withOpacity(0.2),
                              width: 1.5,
                            ),
                          ),
                        ),

                        // Green/Gold Scanning Laser Sweeper Line
                        AnimatedBuilder(
                          animation: _laserController,
                          builder: (context, child) {
                            final double topOffset = 240 * _laserController.value;
                            return Positioned(
                              top: topOffset - 120 + 120, // Center relative
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  color: AppColors.gold,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.gold.withOpacity(0.8),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 60),

                    // Educational Trivia facts while waiting
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.history_edu, color: AppColors.gold, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'NUMISMATIC HISTORY',
                                  style: AppTypography.goldLabel.copyWith(fontSize: 10),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 60,
                              child: Text(
                                _triviaFacts[_triviaIndex],
                                style: AppTypography.bodyMedium.copyWith(
                                  color: Colors.white.withOpacity(0.8),
                                  height: 1.4,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ).animate(key: ValueKey('trivia_$_triviaIndex')).fadeIn().slideY(begin: 0.05, end: 0),
                  ],
                ),
              ),
            ),

          // 3. Camera Control Overlays (Top bar)
          if (!_isProcessing)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.only(top: 48, left: 16, right: 16, bottom: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            _isFlashOn ? Icons.flash_on : Icons.flash_off,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            setState(() {
                              _isFlashOn = !_isFlashOn;
                            });
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            _isMacroOn ? Icons.center_focus_strong : Icons.center_focus_weak,
                            color: _isMacroOn ? AppColors.gold : Colors.white,
                          ),
                          onPressed: () {
                            setState(() {
                              _isMacroOn = !_isMacroOn;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // 4. Camera Control Overlays (Bottom bar)
          if (!_isProcessing)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 48),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xD9000000), Colors.transparent],
                  ),
                ),
                child: Column(
                  children: [
                    // Mode Selectors (Single, Multi, Live)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: ['Single', 'Multi', 'Live'].map((mode) {
                        final isSel = _currentMode == mode;
                        return GestureDetector(
                          onTap: () => setState(() => _currentMode = mode),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSel ? AppColors.gold.withOpacity(0.2) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSel ? AppColors.gold : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              mode.toUpperCase(),
                              style: AppTypography.caption.copyWith(
                                color: isSel ? AppColors.gold : Colors.white60,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 28),

                    // Trigger button row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Import from gallery
                        IconButton(
                          icon: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 28),
                          onPressed: _triggerScan, // simulate scan from gallery
                        ),
                        
                        // Shutter trigger button
                        GestureDetector(
                          onTap: _triggerScan,
                          child: Container(
                            height: 80,
                            width: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Container(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),

                        // Fake toggle camera facing (rear/front)
                        IconButton(
                          icon: const Icon(Icons.flip_camera_ios_outlined, color: Colors.white, size: 28),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ],
                ),
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

    // Vertical grid lines
    canvas.drawLine(Offset(size.width / 3, 0), Offset(size.width / 3, size.height), paint);
    canvas.drawLine(Offset(2 * size.width / 3, 0), Offset(2 * size.width / 3, size.height), paint);

    // Horizontal grid lines
    canvas.drawLine(Offset(0, size.height / 3), Offset(size.width, size.height / 3), paint);
    canvas.drawLine(Offset(0, 2 * size.height / 3), Offset(size.width, 2 * size.height / 3), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
