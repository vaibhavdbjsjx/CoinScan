import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// The metal a collectible is struck from. Drives the glyph's gradient ramp.
enum CoinMetal { gold, silver, copper, paper }

/// A struck-metal medallion, painted rather than iconographic.
///
/// Every collectible in the product renders through this widget so coins read
/// as objects with weight, light and an engraved face instead of a flat
/// Material icon on a gradient. The [seed] deterministically varies the
/// engraving (motif, rotation, reeding density) so a grid of coins looks like a
/// collection rather than the same asset repeated.
class CoinGlyph extends StatelessWidget {
  final double size;
  final CoinMetal metal;

  /// Stable per-item value (use the collectible id's hashCode) so a given coin
  /// always paints the same face.
  final int seed;

  /// Renders a banknote plate instead of a coin.
  final bool isBanknote;

  /// Semantic description. Pass null inside a card that already labels itself.
  final String? semanticLabel;

  const CoinGlyph({
    super.key,
    required this.size,
    this.metal = CoinMetal.gold,
    this.seed = 0,
    this.isBanknote = false,
    this.semanticLabel,
  });

  /// Picks the right metal from a free-text composition string.
  factory CoinGlyph.forComposition({
    Key? key,
    required double size,
    required String composition,
    required bool isBanknote,
    int seed = 0,
    String? semanticLabel,
  }) {
    final c = composition.toLowerCase();
    final metal = isBanknote
        ? CoinMetal.paper
        : c.contains('gold')
        ? CoinMetal.gold
        : c.contains('copper') || c.contains('bronze')
        ? CoinMetal.copper
        : CoinMetal.silver;
    return CoinGlyph(
      key: key,
      size: size,
      metal: metal,
      seed: seed,
      isBanknote: isBanknote,
      semanticLabel: semanticLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final glyph = SizedBox(
      width: size,
      height: isBanknote ? size * 0.62 : size,
      child: CustomPaint(
        painter: isBanknote
            ? _BanknotePainter(seed: seed)
            : _CoinPainter(metal: metal, seed: seed),
        isComplex: true,
        willChange: false,
      ),
    );

    if (semanticLabel == null) {
      return ExcludeSemantics(child: glyph);
    }
    return Semantics(label: semanticLabel, image: true, child: glyph);
  }
}

/// Gradient ramp for each metal: [highlight, mid, shadow, engraving].
class _MetalRamp {
  final Color highlight;
  final Color mid;
  final Color shadow;
  final Color engraving;

  const _MetalRamp(this.highlight, this.mid, this.shadow, this.engraving);

  static const gold = _MetalRamp(
    Color(0xFFFBEFC0),
    Color(0xFFD8B43F),
    Color(0xFF8A6A16),
    Color(0xFF6B5210),
  );
  static const silver = _MetalRamp(
    Color(0xFFFCFCFD),
    Color(0xFFC9CBD1),
    Color(0xFF7C7F88),
    Color(0xFF5E626B),
  );
  static const copper = _MetalRamp(
    Color(0xFFF3CDA6),
    Color(0xFFC98A52),
    Color(0xFF7F4E23),
    Color(0xFF66401D),
  );
  static const paper = _MetalRamp(
    Color(0xFFFDFBF4),
    Color(0xFFEFE7D2),
    Color(0xFFCBBE9C),
    Color(0xFF8C7A4E),
  );

  static _MetalRamp of(CoinMetal metal) => switch (metal) {
    CoinMetal.gold => gold,
    CoinMetal.silver => silver,
    CoinMetal.copper => copper,
    CoinMetal.paper => paper,
  };
}

class _CoinPainter extends CustomPainter {
  final CoinMetal metal;
  final int seed;

  _CoinPainter({required this.metal, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final ramp = _MetalRamp.of(metal);
    final r = size.shortestSide / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final rnd = math.Random(seed);

    // Light arrives from the upper-left, consistently across the app.
    // ------------------------------------------------------------ planchet
    final body = Paint()
      ..isAntiAlias = true
      ..shader = RadialGradient(
        center: const Alignment(-0.38, -0.42),
        radius: 1.05,
        colors: [ramp.highlight, ramp.mid, ramp.shadow],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, body);

    // ------------------------------------------------------ reeded edge
    // Fine milling around the rim catches light on the lit side only.
    final reedCount = 68 + (seed.abs() % 3) * 12;
    final reed = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, r * 0.018)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < reedCount; i++) {
      final a = i * 2 * math.pi / reedCount;
      final dir = Offset(math.cos(a), math.sin(a));
      // Facing the light → bright reed; facing away → dark reed.
      final facing = (dir.dx * -0.6 + dir.dy * -0.7);
      reed.color = facing > 0
          ? ramp.highlight.withValues(alpha: 0.55 * facing + 0.1)
          : ramp.shadow.withValues(alpha: 0.45 * -facing + 0.1);
      canvas.drawLine(c + dir * (r * 0.925), c + dir * (r * 0.995), reed);
    }

    // ---------------------------------------------------------- rim bevel
    canvas.drawCircle(
      c,
      r * 0.9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.055
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ramp.highlight.withValues(alpha: 0.95),
            ramp.shadow.withValues(alpha: 0.7),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // -------------------------------------------------------- sunken field
    canvas.drawCircle(
      c,
      r * 0.855,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.35),
          radius: 1.1,
          colors: [
            ramp.mid.withValues(alpha: 0.55),
            ramp.shadow.withValues(alpha: 0.32),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.855)),
    );

    // ------------------------------------------------------------ engraving
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate((rnd.nextDouble() - 0.5) * 0.24);
    _paintEngraving(canvas, r, ramp, seed);
    canvas.restore();

    // Legend dots around the field, like lettering beads.
    final beadCount = 16 + (seed.abs() % 4) * 4;
    final bead = Paint()..color = ramp.engraving.withValues(alpha: 0.28);
    for (var i = 0; i < beadCount; i++) {
      final a = i * 2 * math.pi / beadCount + 0.2;
      canvas.drawCircle(
        c + Offset(math.cos(a), math.sin(a)) * (r * 0.76),
        math.max(0.7, r * 0.018),
        bead,
      );
    }

    // ------------------------------------------------------------ specular
    // A soft diagonal sweep, clipped to the planchet.
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - r * 1.2, c.dy + r * 0.15)
        ..quadraticBezierTo(
          c.dx - r * 0.1,
          c.dy - r * 0.75,
          c.dx + r * 1.2,
          c.dy - r * 1.1,
        )
        ..lineTo(c.dx + r * 1.2, c.dy - r * 0.5)
        ..quadraticBezierTo(
          c.dx - r * 0.1,
          c.dy - r * 0.2,
          c.dx - r * 1.2,
          c.dy + r * 0.6,
        )
        ..close(),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.34),
            Colors.white.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Contact shading on the unlit lower-right quadrant grounds the object.
    canvas.drawCircle(
      c + Offset(r * 0.34, r * 0.38),
      r,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                ramp.shadow.withValues(alpha: 0.0),
                ramp.shadow.withValues(alpha: 0.35),
              ],
              stops: const [0.55, 1.0],
            ).createShader(
              Rect.fromCircle(
                center: c + Offset(r * 0.34, r * 0.38),
                radius: r,
              ),
            ),
    );
    canvas.restore();

    // Crisp outer edge.
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ramp.shadow.withValues(alpha: 0.5),
    );
  }

  /// Four engraved faces, chosen by seed: laurel wreath, standing figure,
  /// owl (ancient), and a radiant star.
  void _paintEngraving(Canvas canvas, double r, _MetalRamp ramp, int seed) {
    final relief = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(1.0, r * 0.038)
      ..color = ramp.engraving.withValues(alpha: 0.62);

    // A 1px light offset copy above the relief reads as raised metal.
    final lit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = relief.strokeWidth
      ..color = ramp.highlight.withValues(alpha: 0.5);

    void stroke(Path p) {
      canvas.save();
      canvas.translate(-r * 0.016, -r * 0.016);
      canvas.drawPath(p, lit);
      canvas.restore();
      canvas.drawPath(p, relief);
    }

    switch (seed.abs() % 4) {
      case 0:
        // Laurel wreath framing a central star.
        for (final side in [-1.0, 1.0]) {
          final branch = Path()
            ..moveTo(side * r * 0.44, r * 0.42)
            ..quadraticBezierTo(side * r * 0.56, 0, side * r * 0.24, -r * 0.44);
          stroke(branch);
          for (var i = 0; i < 5; i++) {
            final t = i / 4;
            final a = -math.pi * 0.16 + t * math.pi * 0.72;
            final base = Offset(
              side * (r * 0.5 - t * r * 0.2) * math.cos(a * 0.6),
              (t - 0.5) * r * 0.82,
            );
            final leaf = Path()
              ..moveTo(base.dx, base.dy)
              ..quadraticBezierTo(
                base.dx + side * r * 0.16,
                base.dy - r * 0.1,
                base.dx + side * r * 0.05,
                base.dy - r * 0.19,
              );
            stroke(leaf);
          }
        }
        _star(canvas, Offset.zero, r * 0.2, stroke);
        break;

      case 1:
        // Striding figure — Liberty/Victory silhouette.
        final figure = Path()
          ..moveTo(0, -r * 0.46)
          ..lineTo(0, r * 0.1)
          ..moveTo(0, r * 0.1)
          ..lineTo(-r * 0.2, r * 0.46)
          ..moveTo(0, r * 0.1)
          ..lineTo(r * 0.22, r * 0.44)
          ..moveTo(0, -r * 0.28)
          ..lineTo(-r * 0.3, -r * 0.05)
          ..moveTo(0, -r * 0.28)
          ..lineTo(r * 0.32, -r * 0.36);
        stroke(figure);
        canvas.drawCircle(Offset(0, -r * 0.55), r * 0.1, relief);
        // Radiant rays behind the figure.
        for (var i = 0; i < 9; i++) {
          final a = -math.pi + i * math.pi / 8;
          final ray = Path()
            ..moveTo(math.cos(a) * r * 0.6, math.sin(a) * r * 0.6)
            ..lineTo(math.cos(a) * r * 0.72, math.sin(a) * r * 0.72);
          canvas.drawPath(ray, relief);
        }
        break;

      case 2:
        // Athenian owl.
        canvas.drawCircle(Offset(-r * 0.17, -r * 0.16), r * 0.13, relief);
        canvas.drawCircle(Offset(r * 0.17, -r * 0.16), r * 0.13, relief);
        canvas.drawCircle(Offset(-r * 0.17, -r * 0.16), r * 0.05, lit);
        canvas.drawCircle(Offset(r * 0.17, -r * 0.16), r * 0.05, lit);
        stroke(
          Path()
            ..moveTo(0, -r * 0.1)
            ..lineTo(-r * 0.06, r * 0.02)
            ..lineTo(r * 0.06, r * 0.02)
            ..close(),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(0, r * 0.24),
            width: r * 0.5,
            height: r * 0.6,
          ),
          relief,
        );
        // Olive sprig.
        stroke(
          Path()
            ..moveTo(-r * 0.52, -r * 0.4)
            ..quadraticBezierTo(-r * 0.4, -r * 0.34, -r * 0.3, -r * 0.24),
        );
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(
            Offset(-r * 0.5 + i * r * 0.09, -r * 0.44 + i * r * 0.05),
            r * 0.045,
            relief,
          );
        }
        break;

      default:
        // Concentric guilloché with a radiant centre.
        for (var ring = 0; ring < 3; ring++) {
          canvas.drawCircle(
            Offset.zero,
            r * (0.26 + ring * 0.14),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(0.8, r * 0.016)
              ..color = ramp.engraving.withValues(alpha: 0.32 - ring * 0.06),
          );
        }
        _star(canvas, Offset.zero, r * 0.24, stroke);
        break;
    }
  }

  void _star(
    Canvas canvas,
    Offset center,
    double radius,
    void Function(Path) stroke,
  ) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final rad = i.isEven ? radius : radius * 0.44;
      final p = center + Offset(math.cos(a) * rad, math.sin(a) * rad);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    stroke(path);
  }

  @override
  bool shouldRepaint(covariant _CoinPainter old) =>
      old.metal != metal || old.seed != seed;
}

class _BanknotePainter extends CustomPainter {
  final int seed;

  _BanknotePainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    const ramp = _MetalRamp.paper;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(1),
      Radius.circular(size.shortestSide * 0.06),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ramp.highlight, ramp.mid],
        ).createShader(rect),
    );

    canvas.save();
    canvas.clipRRect(rrect);

    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = ramp.engraving.withValues(alpha: 0.34);

    // Guilloché: interfering sine waves, the security pattern of engraved
    // currency.
    for (var band = 0; band < 7; band++) {
      final path = Path();
      final phase = seed * 0.7 + band * 0.55;
      final amp = size.height * 0.075;
      final mid = size.height * (0.16 + band * 0.115);
      for (double x = 0; x <= size.width; x += 2) {
        final y =
            mid +
            math.sin(x / size.width * 6.4 + phase) * amp +
            math.sin(x / size.width * 15.1 - phase) * amp * 0.35;
        x == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, ink);
    }

    // Portrait medallion.
    final portrait = Offset(size.width * 0.27, size.height * 0.5);
    final pr = size.height * 0.3;
    canvas.drawOval(
      Rect.fromCenter(center: portrait, width: pr * 1.6, height: pr * 2.1),
      Paint()..color = ramp.highlight.withValues(alpha: 0.92),
    );
    canvas.drawOval(
      Rect.fromCenter(center: portrait, width: pr * 1.6, height: pr * 2.1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = ramp.engraving.withValues(alpha: 0.55),
    );
    // Bust.
    canvas.drawCircle(
      portrait.translate(0, -pr * 0.34),
      pr * 0.3,
      Paint()..color = ramp.engraving.withValues(alpha: 0.4),
    );
    canvas.drawPath(
      Path()
        ..moveTo(portrait.dx - pr * 0.52, portrait.dy + pr * 0.72)
        ..quadraticBezierTo(
          portrait.dx,
          portrait.dy - pr * 0.1,
          portrait.dx + pr * 0.52,
          portrait.dy + pr * 0.72,
        )
        ..close(),
      Paint()..color = ramp.engraving.withValues(alpha: 0.4),
    );

    // Corner denomination panels.
    for (final corner in [
      Offset(size.width * 0.86, size.height * 0.2),
      Offset(size.width * 0.86, size.height * 0.8),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: corner,
            width: size.width * 0.16,
            height: size.height * 0.16,
          ),
          const Radius.circular(3),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = ramp.engraving.withValues(alpha: 0.5),
      );
    }

    // Security thread.
    canvas.drawLine(
      Offset(size.width * 0.62, 0),
      Offset(size.width * 0.62, size.height),
      Paint()
        ..strokeWidth = 2
        ..color = AppColors.goldInk.withValues(alpha: 0.22),
    );

    // Paper sheen.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.3),
            Colors.white.withValues(alpha: 0.0),
            ramp.shadow.withValues(alpha: 0.18),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect),
    );
    canvas.restore();

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ramp.shadow.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(covariant _BanknotePainter old) => old.seed != seed;
}
