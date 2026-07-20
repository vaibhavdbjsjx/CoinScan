import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/premium_widgets.dart';
import '../onboarding/login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  final List<OnboardingPageData> _pages = [
    OnboardingPageData(
      title: 'Discover History.',
      subtitle: 'Scan any coin instantly and uncover its origin, mint details, and composition.',
      painterType: OnboardingPainterType.goldCoin,
    ),
    OnboardingPageData(
      title: 'Know Its Story.',
      subtitle: 'Our AI engine acts like a master numismatist, detailing the historical context of each strike.',
      painterType: OnboardingPainterType.ancientCoin,
    ),
    OnboardingPageData(
      title: 'Build Your Collection.',
      subtitle: 'Track storage locations, invoices, certificates, and ownership records securely.',
      painterType: OnboardingPainterType.vault,
    ),
    OnboardingPageData(
      title: 'Know Your Value.',
      subtitle: 'Access real-time price evaluations, historical auction archives, and volatility charts.',
      painterType: OnboardingPainterType.analytics,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              key: const ValueKey('bg_glow_1'),
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withOpacity(0.08),
              ),
            ),
          ).animate().fadeIn(duration: 800.ms),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              key: const ValueKey('bg_glow_2'),
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.goldDark.withOpacity(0.04),
              ),
            ),
          ),

          // Main Page Content
          SafeArea(
            child: Column(
              children: [
                // Top Header logo
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.layers_outlined, color: AppColors.goldDark, size: 28),
                          const SizedBox(width: 8),
                          Text(
                            'COINVAULT AI',
                            style: AppTypography.goldLabel.copyWith(
                              letterSpacing: 2,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: Text(
                          'Skip',
                          style: AppTypography.bodyMuted.copyWith(
                            color: AppColors.goldDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Expanded Carousel Illustration & Info
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _pages.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentIndex = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final page = _pages[index];
                      return SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Vector Graphic Container
                            SizedBox(
                              height: 200,
                              width: 200,
                              child: CustomPaint(
                                painter: OnboardingVectorPainter(type: page.painterType),
                              ),
                            )
                                .animate(key: ValueKey('graphic_$index'))
                                .scale(duration: 600.ms, curve: Curves.easeOutBack)
                                .fadeIn(duration: 400.ms),
                            const SizedBox(height: 24),

                            // Text Content
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 40),
                              child: Column(
                                children: [
                                  Text(
                                    page.title,
                                    style: AppTypography.heroTitle,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    page.subtitle,
                                    style: AppTypography.bodyMuted,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                                .animate(key: ValueKey('text_$index'))
                                .slideY(begin: 0.1, end: 0, duration: 400.ms)
                                .fadeIn(duration: 400.ms),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Bottom Action Panel
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      // Page Indicators
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_pages.length, (index) {
                          final isSelected = _currentIndex == index;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 6,
                            width: isSelected ? 24 : 6,
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.gold : AppColors.border,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 32),

                      // Continue Button
                      SizedBox(
                        width: double.infinity,
                        child: GoldButton(
                          text: _currentIndex == _pages.length - 1 ? 'Get Started' : 'Continue',
                          onPressed: () {
                            if (_currentIndex < _pages.length - 1) {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeInOutCubic,
                              );
                            } else {
                              context.go('/login');
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingPageData {
  final String title;
  final String subtitle;
  final OnboardingPainterType painterType;

  OnboardingPageData({
    required this.title,
    required this.subtitle,
    required this.painterType,
  });
}

enum OnboardingPainterType { goldCoin, ancientCoin, vault, analytics }

class OnboardingVectorPainter extends CustomPainter {
  final OnboardingPainterType type;

  OnboardingVectorPainter({required this.type});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..isAntiAlias = true;

    if (type == OnboardingPainterType.goldCoin) {
      // Draw shiny gold coin
      // Outer ring
      paint.color = AppColors.gold.withOpacity(0.2);
      canvas.drawCircle(center, 110, paint);

      // Gold base
      final coinGrad = RadialGradient(
        colors: [AppColors.goldLight, AppColors.gold, AppColors.goldDark],
        stops: const [0.1, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: 90));
      paint.shader = coinGrad;
      canvas.drawCircle(center, 90, paint);

      // Embossed eagle outline
      paint.shader = null;
      paint.color = Colors.white.withOpacity(0.3);
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 3;
      canvas.drawCircle(center, 80, paint);

      // Star markings
      paint.style = PaintingStyle.fill;
      paint.color = AppColors.goldLight.withOpacity(0.7);
      for (int i = 0; i < 8; i++) {
        final angle = i * pi / 4;
        final starCenter = Offset(
          center.dx + 65 * cos(angle),
          center.dy + 65 * sin(angle),
        );
        canvas.drawCircle(starCenter, 4, paint);
      }

      // Shine effect line
      final path = Path()
        ..moveTo(center.dx - 90, center.dy)
        ..quadraticBezierTo(center.dx, center.dy - 30, center.dx + 90, center.dy - 90)
        ..quadraticBezierTo(center.dx, center.dy - 10, center.dx - 90, center.dy);
      paint.color = Colors.white.withOpacity(0.25);
      canvas.drawPath(path, paint);

    } else if (type == OnboardingPainterType.ancientCoin) {
      // Draw ancient rough silver coin
      paint.color = AppColors.borderLight;
      canvas.drawCircle(center, 100, paint);

      // Silver metal base (irregular shape)
      final coinPath = Path();
      const numPoints = 12;
      for (int i = 0; i < numPoints; i++) {
        final angle = i * 2 * pi / numPoints;
        final r = 80.0 + (i % 2 == 0 ? 5.0 : -3.0);
        final x = center.dx + r * cos(angle);
        final y = center.dy + r * sin(angle);
        if (i == 0) coinPath.moveTo(x, y);
        else coinPath.lineTo(x, y);
      }
      coinPath.close();

      final silverGrad = RadialGradient(
        colors: [Colors.white, AppColors.border, AppColors.textSecondary],
        stops: const [0.2, 0.8, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: 85));
      paint.shader = silverGrad;
      canvas.drawPath(coinPath, paint);

      // Draw Athenian Owl outline inside
      paint.shader = null;
      paint.color = AppColors.textPrimary.withOpacity(0.4);
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 4;
      paint.strokeCap = StrokeCap.round;

      // Owl eyes
      canvas.drawCircle(Offset(center.dx - 18, center.dy - 15), 10, paint);
      canvas.drawCircle(Offset(center.dx + 18, center.dy - 15), 10, paint);
      
      // Owl beak
      final beak = Path()
        ..moveTo(center.dx, center.dy - 8)
        ..lineTo(center.dx - 4, center.dy)
        ..lineTo(center.dx + 4, center.dy)
        ..close();
      paint.style = PaintingStyle.fill;
      canvas.drawPath(beak, paint);

      // Owl body
      paint.style = PaintingStyle.stroke;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(center.dx, center.dy + 15), width: 35, height: 40),
        paint,
      );

      // Olive branch sprig
      paint.strokeWidth = 2;
      canvas.drawLine(Offset(center.dx - 45, center.dy - 40), Offset(center.dx - 35, center.dy - 30), paint);
      canvas.drawCircle(Offset(center.dx - 48, center.dy - 43), 3, paint);

    } else if (type == OnboardingPainterType.vault) {
      // Draw vault / premium lock
      paint.color = AppColors.borderLight;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: 160, height: 160),
          const Radius.circular(32),
        ),
        paint,
      );

      // Gold vault outer border
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 5;
      paint.color = AppColors.gold;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: 140, height: 140),
          const Radius.circular(24),
        ),
        paint,
      );

      // Safe wheel spin
      paint.style = PaintingStyle.fill;
      paint.color = Colors.white;
      canvas.drawCircle(center, 40, paint);

      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 6;
      paint.color = AppColors.textPrimary.withOpacity(0.8);
      canvas.drawCircle(center, 30, paint);

      // Wheel handles
      paint.strokeWidth = 8;
      for (int i = 0; i < 4; i++) {
        final angle = i * pi / 2;
        canvas.drawLine(
          Offset(center.dx + 15 * cos(angle), center.dy + 15 * sin(angle)),
          Offset(center.dx + 45 * cos(angle), center.dy + 45 * sin(angle)),
          paint,
        );
      }

    } else if (type == OnboardingPainterType.analytics) {
      // Draw luxury investment growth line and cards
      paint.color = AppColors.gold.withOpacity(0.1);
      final fillPath = Path()
        ..moveTo(center.dx - 100, center.dy + 60)
        ..quadraticBezierTo(center.dx - 30, center.dy - 10, center.dx + 30, center.dy + 20)
        ..quadraticBezierTo(center.dx + 80, center.dy - 70, center.dx + 100, center.dy - 60)
        ..lineTo(center.dx + 100, center.dy + 80)
        ..lineTo(center.dx - 100, center.dy + 80)
        ..close();
      canvas.drawPath(fillPath, paint);

      // Draw gridlines
      paint.color = AppColors.borderLight;
      paint.strokeWidth = 1.5;
      for (int i = -3; i <= 3; i++) {
        canvas.drawLine(
          Offset(center.dx - 100, center.dy + i * 25),
          Offset(center.dx + 100, center.dy + i * 25),
          paint,
        );
      }

      // Draw main gold trend line
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 5;
      paint.color = AppColors.gold;
      paint.strokeCap = StrokeCap.round;
      final linePath = Path()
        ..moveTo(center.dx - 100, center.dy + 60)
        ..quadraticBezierTo(center.dx - 30, center.dy - 10, center.dx + 30, center.dy + 20)
        ..quadraticBezierTo(center.dx + 80, center.dy - 70, center.dx + 100, center.dy - 60);
      canvas.drawPath(linePath, paint);

      // Nodes
      paint.style = PaintingStyle.fill;
      paint.color = AppColors.goldDark;
      canvas.drawCircle(Offset(center.dx - 100, center.dy + 60), 7, paint);
      canvas.drawCircle(Offset(center.dx + 100, center.dy - 60), 7, paint);

      // Outer rings of final node (pulse representation)
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;
      paint.color = AppColors.gold.withOpacity(0.5);
      canvas.drawCircle(Offset(center.dx + 100, center.dy - 60), 15, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
