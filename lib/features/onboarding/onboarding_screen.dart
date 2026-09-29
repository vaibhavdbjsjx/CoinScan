import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/premium_widgets.dart';

/// The product's first impression.
///
/// Design notes:
/// * The canvas is ink rather than white. Gold reaches 8.1:1 against ink but
///   only 2.1:1 against white, so the immersive treatment is both the more
///   striking *and* the more legible option.
/// * A single [PageController] drives everything — illustration parallax, the
///   ambient aura, the progress rail — so swiping feels like moving one
///   continuous scene rather than flipping through four separate screens.
/// * Layout is proportional to the available height, so the composition stays
///   balanced from a 4" phone up to a tablet without dead space.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();

  /// Continuous scroll position (e.g. 1.42 while dragging between pages).
  double _page = 0;
  int _index = 0;

  static const List<_OnboardingPage> _pages = [
    _OnboardingPage(
      eyebrow: 'Identify',
      title: 'Every coin\nhas an origin.',
      body:
          'Point your camera at any coin or note. CoinScan reads the mint, the metal and the strike in seconds.',
      art: _ArtType.coin,
    ),
    _OnboardingPage(
      eyebrow: 'Understand',
      title: 'And a story\nworth knowing.',
      body:
          'A master numismatist in your pocket — historical context, die varieties and grading rationale for every find.',
      art: _ArtType.provenance,
    ),
    _OnboardingPage(
      eyebrow: 'Curate',
      title: 'Build a vault,\nnot a shoebox.',
      body:
          'Track provenance, storage, certificates and invoices. Your collection, documented to auction-house standard.',
      art: _ArtType.vault,
    ),
    _OnboardingPage(
      eyebrow: 'Value',
      title: 'Know exactly\nwhat it\'s worth.',
      body:
          'Live valuations, auction archives and trend analysis — so you always know when to hold and when to sell.',
      art: _ArtType.market,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_pageController.hasClients) return;
    final page = _pageController.page ?? 0;
    if (page != _page) setState(() => _page = page);
  }

  @override
  void dispose() {
    _pageController.removeListener(_onScroll);
    _pageController.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _pages.length - 1;

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _pageController.nextPage(
        duration: AppDuration.page,
        curve: AppCurves.emphasized,
      );
    }
  }

  void _finish() {
    HapticFeedback.lightImpact();
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;

    // Proportional composition: art takes the upper half, copy the lower.
    // Clamped so it stays sane on very short and very tall canvases.
    final artSize = (size.height * 0.34).clamp(180.0, 320.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.inkOverlay,
      child: Scaffold(
        backgroundColor: AppColors.ink,
        body: Stack(
          children: [
            // Ambient backdrop — drifts opposite the swipe for depth.
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: _AuroraPainter(page: _page)),
              ),
            ),

            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppBreakpoints.maxContentWidth,
                  ),
                  child: Column(
                    children: [
                      _buildTopBar(),
                      Expanded(
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: _pages.length,
                          onPageChanged: (i) {
                            HapticFeedback.selectionClick();
                            setState(() => _index = i);
                          },
                          itemBuilder: (context, i) => _buildPage(i, artSize),
                        ),
                      ),
                      _buildFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.base,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          // Scales down rather than overflowing on very narrow canvases (and
          // during Flutter's first layout pass, before the view is sized).
          const Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: _Wordmark(),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _finish,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textOnInkMuted,
              overlayColor: Colors.white,
            ),
            child: Text(
              'Skip',
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.textOnInkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(int i, double artSize) {
    final page = _pages[i];

    // How far this page is from the viewport centre, in pages.
    final delta = (_page - i).clamp(-1.0, 1.0);
    final reduceMotion = !Motion.allowed(context);
    final shift = reduceMotion ? 0.0 : delta;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Art layer moves slowest — furthest "away" from the viewer.
                Transform.translate(
                  offset: Offset(-shift * 46, 0),
                  child: Opacity(
                    opacity: (1 - delta.abs() * 0.85).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 1 - delta.abs() * 0.12,
                      child: SizedBox(
                        height: artSize,
                        width: artSize,
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _OnboardingArtPainter(type: page.art),
                            isComplex: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                // Copy layer moves fastest — closest to the viewer.
                Transform.translate(
                  offset: Offset(-shift * 110, 0),
                  child: Opacity(
                    opacity: (1 - delta.abs() * 1.6).clamp(0.0, 1.0),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: Column(
                        children: [
                          _EyebrowRail(
                            index: i,
                            total: _pages.length,
                            label: page.eyebrow,
                          ),
                          const SizedBox(height: AppSpacing.base),
                          Text(
                            page.title,
                            textAlign: TextAlign.center,
                            style: AppTypography.heroTitle.copyWith(
                              color: Colors.white,
                              fontSize: 34,
                              height: 1.1,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            page.body,
                            textAlign: TextAlign.center,
                            style: AppTypography.subtitle.copyWith(
                              color: AppColors.textOnInkMuted,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.base,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: Column(
        children: [
          _ProgressRail(page: _page, count: _pages.length),
          const SizedBox(height: AppSpacing.xl),
          GoldButton(
            text: _isLast ? 'Create your vault' : 'Continue',
            icon: _isLast ? Icons.arrow_forward_rounded : null,
            onPressed: _next,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 36,
            child: AnimatedOpacity(
              opacity: _isLast ? 1 : 0,
              duration: AppDuration.base,
              child: IgnorePointer(
                ignoring: !_isLast,
                child: TextButton(
                  onPressed: _finish,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textOnInkMuted,
                    overlayColor: Colors.white,
                  ),
                  child: Text(
                    'I already have an account',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textOnInkMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage {
  final String eyebrow;
  final String title;
  final String body;
  final _ArtType art;

  const _OnboardingPage({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.art,
  });
}

enum _ArtType { coin, provenance, vault, market }

// ---------------------------------------------------------------------------
// Chrome
// ---------------------------------------------------------------------------

/// Monogram + wordmark. The mark is a struck-coin "V" rather than a stock icon.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'CoinScan',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 28,
              width: 28,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.goldGradient,
              ),
              child: const Center(
                child: Text(
                  'C',
                  style: TextStyle(
                    color: AppColors.onGold,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm + 2),
            Text(
              'COINSCAN',
              style: AppTypography.goldLabel.copyWith(
                color: Colors.white,
                fontSize: 12,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "01 — IDENTIFY" numbered eyebrow.
class _EyebrowRail extends StatelessWidget {
  final int index;
  final int total;
  final String label;

  const _EyebrowRail({
    required this.index,
    required this.total,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${(index + 1).toString().padLeft(2, '0')} / ${total.toString().padLeft(2, '0')}',
            style: AppTypography.goldLabel.copyWith(
              color: AppColors.gold.withValues(alpha: 0.75),
            ),
          ),
          Container(
            width: 18,
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            color: AppColors.gold.withValues(alpha: 0.4),
          ),
          Text(
            label.toUpperCase(),
            style: AppTypography.goldLabel.copyWith(color: AppColors.gold),
          ),
        ],
      ),
    );
  }
}

/// Continuous progress rail. The active segment slides with the drag rather
/// than snapping between pages.
class _ProgressRail extends StatelessWidget {
  final double page;
  final int count;

  const _ProgressRail({required this.page, required this.count});

  @override
  Widget build(BuildContext context) {
    const segmentWidth = 26.0;
    const gap = 6.0;

    return Semantics(
      label: 'Page ${page.round() + 1} of $count',
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            height: 3,
            width: count * segmentWidth + (count - 1) * gap,
            child: Stack(
              children: [
                Row(
                  children: List.generate(count, (i) {
                    return Container(
                      width: segmentWidth,
                      height: 3,
                      margin: EdgeInsets.only(right: i == count - 1 ? 0 : gap),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                ),
                Positioned(
                  left: page.clamp(0, count - 1) * (segmentWidth + gap),
                  child: Container(
                    width: segmentWidth,
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: AppColors.goldGradient,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

/// Ambient gold aura behind the content, offset by scroll position.
class _AuroraPainter extends CustomPainter {
  final double page;

  _AuroraPainter({required this.page});

  @override
  void paint(Canvas canvas, Size size) {
    // Base ink wash.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = AppColors.inkGradient.createShader(Offset.zero & size),
    );

    final drift = page * 40;

    // Warm halo behind the artwork.
    canvas.drawCircle(
      Offset(size.width * 0.5 - drift, size.height * 0.32),
      size.width * 0.62,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                AppColors.gold.withValues(alpha: 0.16),
                AppColors.gold.withValues(alpha: 0.03),
                Colors.transparent,
              ],
              stops: const [0.0, 0.45, 1.0],
            ).createShader(
              Rect.fromCircle(
                center: Offset(size.width * 0.5 - drift, size.height * 0.32),
                radius: size.width * 0.62,
              ),
            ),
    );

    // Cool counter-glow keeps the ink from going muddy.
    canvas.drawCircle(
      Offset(size.width * 0.1 + drift * 0.6, size.height * 0.86),
      size.width * 0.5,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xFF3A3A46).withValues(alpha: 0.5),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromCircle(
                center: Offset(
                  size.width * 0.1 + drift * 0.6,
                  size.height * 0.86,
                ),
                radius: size.width * 0.5,
              ),
            ),
    );

    // Fine constellation of dust motes — static, so it costs nothing to keep.
    final dust = Paint()..color = AppColors.gold.withValues(alpha: 0.16);
    final rnd = math.Random(7);
    for (var i = 0; i < 40; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      canvas.drawCircle(
        Offset((x - drift * 0.35) % size.width, y),
        rnd.nextDouble() * 1.3 + 0.4,
        dust,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => old.page != page;
}

/// The four hero illustrations. Drawn rather than imported so they inherit the
/// palette exactly and stay crisp at any density.
class _OnboardingArtPainter extends CustomPainter {
  final _ArtType type;

  _OnboardingArtPainter({required this.type});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;

    switch (type) {
      case _ArtType.coin:
        _drawScanningCoin(canvas, c, r);
      case _ArtType.provenance:
        _drawProvenance(canvas, c, r);
      case _ArtType.vault:
        _drawVault(canvas, c, r);
      case _ArtType.market:
        _drawMarket(canvas, c, r);
    }
  }

  // A gold coin inside camera framing brackets.
  void _drawScanningCoin(Canvas canvas, Offset c, double r) {
    _drawCoinBody(canvas, c, r * 0.62);

    // Framing reticle.
    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = AppColors.gold.withValues(alpha: 0.85);
    const arm = 26.0;
    final box = r * 0.86;
    for (final sx in [-1.0, 1.0]) {
      for (final sy in [-1.0, 1.0]) {
        final corner = c + Offset(sx * box, sy * box);
        canvas.drawPath(
          Path()
            ..moveTo(corner.dx - sx * arm, corner.dy)
            ..lineTo(corner.dx, corner.dy)
            ..lineTo(corner.dx, corner.dy - sy * arm),
          bracket,
        );
      }
    }

    // Scan line sweeping the field.
    canvas.drawRect(
      Rect.fromLTRB(c.dx - box, c.dy - 1.5, c.dx + box, c.dy + 1.5),
      Paint()
        ..shader =
            LinearGradient(
              colors: [
                Colors.transparent,
                AppColors.goldAccent.withValues(alpha: 0.9),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromLTRB(c.dx - box, c.dy - 2, c.dx + box, c.dy + 2),
            ),
    );

    // Readout ticks along the right bracket.
    final tick = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = AppColors.gold.withValues(alpha: 0.4);
    for (var i = 0; i < 5; i++) {
      final y = c.dy - box * 0.4 + i * box * 0.2;
      canvas.drawLine(
        Offset(c.dx + box + 12, y),
        Offset(c.dx + box + 12 + (i.isEven ? 14 : 8), y),
        tick,
      );
    }
  }

  // A coin with a provenance timeline threading through it.
  void _drawProvenance(Canvas canvas, Offset c, double r) {
    // Timeline spine.
    final spine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.gold.withValues(alpha: 0.3);
    canvas.drawLine(
      Offset(c.dx - r * 0.9, c.dy + r * 0.72),
      Offset(c.dx + r * 0.9, c.dy + r * 0.72),
      spine,
    );
    for (var i = 0; i < 5; i++) {
      final x = c.dx - r * 0.9 + i * r * 0.45;
      final active = i == 2;
      canvas.drawCircle(
        Offset(x, c.dy + r * 0.72),
        active ? 5 : 3,
        Paint()
          ..color = active
              ? AppColors.gold
              : AppColors.gold.withValues(alpha: 0.35),
      );
      if (active) {
        canvas.drawCircle(
          Offset(x, c.dy + r * 0.72),
          11,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = AppColors.gold.withValues(alpha: 0.5),
        );
      }
    }

    _drawCoinBody(canvas, c.translate(0, -r * 0.14), r * 0.56);

    // Annotation leaders pointing at the coin — the "AI reading it" motif.
    final leader = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = AppColors.gold.withValues(alpha: 0.45);
    // Extents are expressed as fractions of the radius so the leaders always
    // terminate inside the illustration's own box rather than bleeding across
    // the screen (CustomPaint does not clip by default).
    const labels = [
      (Offset(-1.0, -0.62), 0.94),
      (Offset(1.0, -0.3), 0.96),
      (Offset(-0.95, 0.1), 0.86),
    ];
    for (final (dir, extent) in labels) {
      final anchor = c.translate(dir.dx * r * 0.5, dir.dy * r * 0.5 - r * 0.14);
      final elbow = Offset(c.dx + dir.dx * r * 0.62, anchor.dy);
      canvas.drawLine(anchor, elbow, leader);
      canvas.drawLine(
        elbow,
        Offset(c.dx + dir.dx * r * extent, anchor.dy),
        leader,
      );
      canvas.drawCircle(anchor, 2.5, Paint()..color = AppColors.gold);
    }
  }

  // A vault door, dialled shut.
  void _drawVault(Canvas canvas, Offset c, double r) {
    final door = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: r * 1.6, height: r * 1.6),
      Radius.circular(r * 0.3),
    );

    canvas.drawRRect(
      door,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E2E34), Color(0xFF17171A)],
        ).createShader(door.outerRect),
    );
    canvas.drawRRect(
      door,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.gold.withValues(alpha: 0.9),
            AppColors.gold.withValues(alpha: 0.15),
          ],
        ).createShader(door.outerRect),
    );

    // Inset panel.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: r * 1.34, height: r * 1.34),
        Radius.circular(r * 0.24),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.08),
    );

    // Handle spokes.
    final spoke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = AppColors.gold.withValues(alpha: 0.9);
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2 + math.pi / 4;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * r * 0.2,
        c + Offset(math.cos(a), math.sin(a)) * r * 0.56,
        spoke,
      );
    }

    // Dial.
    canvas.drawCircle(
      c,
      r * 0.28,
      Paint()
        ..shader = AppColors.goldGradient.createShader(
          Rect.fromCircle(center: c, radius: r * 0.28),
        ),
    );
    canvas.drawCircle(
      c,
      r * 0.28,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF17171A).withValues(alpha: 0.5),
    );
    canvas.drawCircle(c, r * 0.1, Paint()..color = const Color(0xFF17171A));

    // Bolt indicators around the door.
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      canvas.drawCircle(
        c + Offset(math.cos(a), math.sin(a)) * r * 0.68,
        2.5,
        Paint()..color = AppColors.gold.withValues(alpha: 0.4),
      );
    }
  }

  // An ascending valuation chart with a coin anchoring the peak.
  void _drawMarket(Canvas canvas, Offset c, double r) {
    final left = c.dx - r * 0.9;
    final right = c.dx + r * 0.78;
    final bottom = c.dy + r * 0.72;

    // Gridlines.
    final grid = Paint()
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.06);
    for (var i = 0; i < 5; i++) {
      final y = bottom - i * r * 0.36;
      canvas.drawLine(Offset(left, y), Offset(right + r * 0.12, y), grid);
    }

    // Volume bars.
    final bar = Paint()..color = AppColors.gold.withValues(alpha: 0.16);
    for (var i = 0; i < 7; i++) {
      final x = left + i * (right - left) / 7 + 4;
      final h = r * (0.12 + (i % 3) * 0.07 + i * 0.03);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, bottom - h, (right - left) / 12, h),
          const Radius.circular(2),
        ),
        bar,
      );
    }

    final curve = Path()
      ..moveTo(left, bottom - r * 0.16)
      ..cubicTo(
        left + (right - left) * 0.3,
        bottom - r * 0.22,
        left + (right - left) * 0.42,
        bottom - r * 0.92,
        left + (right - left) * 0.66,
        bottom - r * 0.78,
      )
      ..cubicTo(
        left + (right - left) * 0.82,
        bottom - r * 0.7,
        right - 12,
        bottom - r * 1.28,
        right,
        bottom - r * 1.34,
      );

    // Area fill under the curve.
    canvas.drawPath(
      Path.from(curve)
        ..lineTo(right, bottom)
        ..lineTo(left, bottom)
        ..close(),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.gold.withValues(alpha: 0.28),
            AppColors.gold.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTRB(left, bottom - r * 1.4, right, bottom)),
    );

    canvas.drawPath(
      curve,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = const LinearGradient(
          colors: [AppColors.goldDark, AppColors.goldAccent],
        ).createShader(Rect.fromLTRB(left, bottom - r * 1.4, right, bottom)),
    );

    // Coin sitting on the peak.
    final peak = Offset(right, bottom - r * 1.34);
    canvas.drawCircle(
      peak,
      r * 0.34,
      Paint()
        ..color = AppColors.ink
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    _drawCoinBody(canvas, peak, r * 0.28);

    // Axis.
    canvas.drawLine(
      Offset(left, bottom),
      Offset(right + r * 0.12, bottom),
      Paint()
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.15),
    );
  }

  /// Shared metallic coin used by several of the illustrations.
  void _drawCoinBody(Canvas canvas, Offset c, double r) {
    // Outer glow.
    canvas.drawCircle(
      c,
      r * 1.5,
      Paint()
        ..shader = RadialGradient(
          colors: [AppColors.gold.withValues(alpha: 0.28), Colors.transparent],
        ).createShader(Rect.fromCircle(center: c, radius: r * 1.5)),
    );

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.45),
          radius: 1.1,
          colors: [Color(0xFFFBEFC0), Color(0xFFD8B43F), Color(0xFF8A6A16)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Reeded edge.
    final reed = Paint()
      ..strokeWidth = math.max(0.8, r * 0.03)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 56; i++) {
      final a = i * 2 * math.pi / 56;
      final dir = Offset(math.cos(a), math.sin(a));
      final facing = dir.dx * -0.6 + dir.dy * -0.7;
      reed.color = facing > 0
          ? const Color(0xFFFBEFC0).withValues(alpha: 0.6 * facing + 0.1)
          : const Color(0xFF6B5210).withValues(alpha: 0.5 * -facing + 0.1);
      canvas.drawLine(c + dir * (r * 0.9), c + dir * (r * 0.99), reed);
    }

    // Rim and field.
    canvas.drawCircle(
      c,
      r * 0.86,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, r * 0.06)
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFBEFC0), Color(0xFF8A6A16)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Laurel + star engraving.
    final relief = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, r * 0.045)
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF6B5210).withValues(alpha: 0.55);
    // Laurel wreath: a stem on each side with leaves fanning inward, so the
    // engraving reads as a wreath rather than a pair of parentheses.
    for (final side in [-1.0, 1.0]) {
      final stem = Path()
        ..moveTo(c.dx + side * r * 0.44, c.dy + r * 0.42)
        ..quadraticBezierTo(
          c.dx + side * r * 0.58,
          c.dy,
          c.dx + side * r * 0.22,
          c.dy - r * 0.46,
        );
      canvas.drawPath(stem, relief);

      final metric = stem.computeMetrics().first;
      for (var i = 0; i < 6; i++) {
        final t = 0.08 + i * 0.16;
        final pos = metric.getTangentForOffset(metric.length * t);
        if (pos == null) continue;
        // Leaf points outward-and-forward along the stem tangent.
        final normal = Offset(-pos.vector.dy, pos.vector.dx) * side;
        final tip = pos.position + normal * r * 0.2 + pos.vector * r * 0.1;
        canvas.drawPath(
          Path()
            ..moveTo(pos.position.dx, pos.position.dy)
            ..quadraticBezierTo(
              pos.position.dx + normal.dx * r * 0.19 - pos.vector.dx * r * 0.05,
              pos.position.dy + normal.dy * r * 0.19 - pos.vector.dy * r * 0.05,
              tip.dx,
              tip.dy,
            )
            ..quadraticBezierTo(
              pos.position.dx + normal.dx * r * 0.07 + pos.vector.dx * r * 0.1,
              pos.position.dy + normal.dy * r * 0.07 + pos.vector.dy * r * 0.1,
              pos.position.dx,
              pos.position.dy,
            ),
          relief,
        );
      }
    }
    final star = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final rad = i.isEven ? r * 0.26 : r * 0.11;
      final p = c + Offset(math.cos(a) * rad, math.sin(a) * rad);
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    star.close();
    canvas.drawPath(star, relief);

    // Specular sweep.
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - r * 1.2, c.dy + r * 0.2)
        ..quadraticBezierTo(
          c.dx,
          c.dy - r * 0.7,
          c.dx + r * 1.2,
          c.dy - r * 1.1,
        )
        ..lineTo(c.dx + r * 1.2, c.dy - r * 0.55)
        ..quadraticBezierTo(
          c.dx,
          c.dy - r * 0.15,
          c.dx - r * 1.2,
          c.dy + r * 0.65,
        )
        ..close(),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.38),
            Colors.white.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OnboardingArtPainter old) => old.type != type;
}
