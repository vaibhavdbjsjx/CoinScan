import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

export 'coin_glyph.dart';

/// Visual weight of a [GoldButton].
enum GoldButtonVariant {
  /// Gold fill, ink label. The single primary action on a screen.
  primary,

  /// White fill, hairline border. Secondary actions and OAuth providers.
  secondary,

  /// Ink fill, white label. Primary action *on top of* gold or imagery.
  ink,

  /// No fill. Tertiary actions.
  ghost,
}

enum GoldButtonSize { regular, compact }

/// The product's primary action.
///
/// Notable behaviour:
/// * Ink label on gold (8.1:1) — white on gold only reaches 2.1:1.
/// * Press is a scale + shadow-collapse driven by [AnimatedScale], and is
///   skipped entirely when the user has reduced motion enabled.
/// * Real [InkWell] semantics: keyboard focus ring, hover cursor on web/desktop,
///   and a proper disabled state that also blocks the tap.
/// * While [isLoading] the button keeps its width and announces "busy" instead
///   of silently swapping content.
class GoldButton extends StatefulWidget {
  final String text;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final GoldButtonVariant variant;
  final GoldButtonSize size;

  /// Stretches to the available width. Defaults to true — most CTAs in this
  /// app are full-bleed within their gutter.
  final bool expand;

  const GoldButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.variant = GoldButtonVariant.primary,
    this.size = GoldButtonSize.regular,
    this.expand = true,
  });

  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton> {
  bool _pressed = false;

  GoldButtonVariant get _variant => widget.variant;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  void _handleTap() {
    HapticFeedback.selectionClick();
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.size == GoldButtonSize.compact;
    final height = compact ? 44.0 : 54.0;
    final animate = Motion.allowed(context);

    final (
      Color background,
      Color foreground,
      BoxBorder? border,
    ) = switch (_variant) {
      GoldButtonVariant.primary => (AppColors.gold, AppColors.onGold, null),
      GoldButtonVariant.secondary => (
        Colors.white,
        AppColors.textPrimary,
        Border.all(color: AppColors.border, width: 1.2),
      ),
      GoldButtonVariant.ink => (AppColors.inkSoft, Colors.white, null),
      GoldButtonVariant.ghost => (Colors.transparent, AppColors.goldInk, null),
    };

    final effectiveBackground = _enabled ? background : AppColors.borderLight;
    final effectiveForeground = _enabled ? foreground : AppColors.textSecondary;

    final label = Text(
      widget.text,
      style:
          (compact ? AppTypography.buttonTextSmall : AppTypography.buttonText)
              .copyWith(color: effectiveForeground),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final button = Semantics(
      button: true,
      enabled: _enabled,
      label: widget.isLoading ? '${widget.text}, loading' : null,
      child: AnimatedScale(
        scale: _pressed && animate ? 0.97 : 1.0,
        duration: AppDuration.instant,
        curve: AppCurves.standard,
        child: AnimatedContainer(
          duration: AppDuration.fast,
          height: height,
          decoration: BoxDecoration(
            color: effectiveBackground,
            gradient: _variant == GoldButtonVariant.primary && _enabled
                ? AppColors.goldGradient
                : null,
            borderRadius: AppRadius.allMd,
            border: border,
            boxShadow: _variant == GoldButtonVariant.primary && _enabled
                ? AppShadows.goldGlow(opacity: _pressed ? 0.16 : 0.32)
                : _variant == GoldButtonVariant.ink && _enabled
                ? AppShadows.level2
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: _enabled ? _handleTap : null,
              onTapDown: _enabled ? (_) => _setPressed(true) : null,
              onTapUp: _enabled ? (_) => _setPressed(false) : null,
              onTapCancel: _enabled ? () => _setPressed(false) : null,
              borderRadius: AppRadius.allMd,
              splashColor: effectiveForeground.withValues(alpha: 0.08),
              highlightColor: effectiveForeground.withValues(alpha: 0.05),
              focusColor: effectiveForeground.withValues(alpha: 0.12),
              child: Center(
                child: AnimatedSwitcher(
                  duration: AppDuration.fast,
                  child: widget.isLoading
                      ? SizedBox(
                          key: const ValueKey('loading'),
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              effectiveForeground,
                            ),
                          ),
                        )
                      : Row(
                          key: const ValueKey('label'),
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(
                                widget.icon,
                                color: effectiveForeground,
                                size: compact ? 17 : 19,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                            ],
                            Flexible(child: label),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return widget.expand
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

/// A soft, layered surface for grouped content.
///
/// Fixes a subtle bug in the original: the ripple was painted *under* the
/// card's own opaque background, so taps produced no feedback at all. The
/// decoration now sits on a [Material] whose ink is clipped to the card shape.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Optional accent — draws a hairline gold rule along the top edge.
  final bool accent;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = AppRadius.xl,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppShadows.level2,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          splashColor: AppColors.gold.withValues(alpha: 0.07),
          highlightColor: AppColors.gold.withValues(alpha: 0.04),
          child: Stack(
            children: [
              if (accent)
                Positioned(
                  left: AppSpacing.xl,
                  right: AppSpacing.xl,
                  top: 0,
                  child: Container(
                    height: 2,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.gold,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton placeholder with a travelling sheen.
///
/// Honours reduce-motion by falling back to a static tint, and marks itself as
/// a live region so screen readers announce "loading" rather than reading an
/// empty box.
class PremiumShimmer extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const PremiumShimmer({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = AppRadius.sm,
  });

  @override
  State<PremiumShimmer> createState() => _PremiumShimmerState();
}

class _PremiumShimmerState extends State<PremiumShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.allowed(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);

    return Semantics(
      label: 'Loading',
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  gradient: LinearGradient(
                    begin: Alignment(-1.6 + _controller.value * 3.2, -0.4),
                    end: Alignment(-0.6 + _controller.value * 3.2, 0.4),
                    colors: const [
                      AppColors.borderLight,
                      Color(0xFFFAFAFC),
                      AppColors.borderLight,
                    ],
                  ),
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Compact KPI tile used across the dashboard rails.
class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String change;
  final bool isPositive;
  final IconData icon;

  /// Set false for informational chips like "Weekly" that aren't a delta.
  final bool showTrendArrow;
  final VoidCallback? onTap;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.change,
    required this.isPositive,
    required this.icon,
    this.showTrendArrow = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final trendColor = isPositive ? AppColors.emerald : AppColors.crimson;

    return Semantics(
      container: true,
      label: '$title, $value, $change',
      child: ExcludeSemantics(
        child: GlassCard(
          onTap: onTap,
          borderRadius: AppRadius.lg,
          padding: const EdgeInsets.all(AppSpacing.base),
          child: SizedBox(
            width: 148,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.12),
                        borderRadius: AppRadius.allXs,
                      ),
                      child: Icon(icon, color: AppColors.goldInk, size: 16),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showTrendArrow)
                            Icon(
                              isPositive
                                  ? Icons.arrow_outward_rounded
                                  : Icons.south_east_rounded,
                              color: trendColor,
                              size: 13,
                            ),
                          Flexible(
                            child: Text(
                              change,
                              style: AppTypography.numericSmall.copyWith(
                                color: showTrendArrow
                                    ? trendColor
                                    : AppColors.textSecondary,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  value,
                  style: AppTypography.numericMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  title,
                  style: AppTypography.captionSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Section heading with an optional trailing action, so every list header in
/// the app aligns and sizes identically.
class SectionHeading extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeading({
    super.key,
    required this.title,
    this.eyebrow,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eyebrow != null) ...[
                Text(eyebrow!.toUpperCase(), style: AppTypography.goldLabel),
                const SizedBox(height: AppSpacing.xs),
              ],
              Text(
                title,
                style: AppTypography.sectionHeader,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel!,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.goldInk,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.goldInk,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Consistent empty state: illustration, message, and a way forward.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 88,
                width: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.gold.withValues(alpha: 0.16),
                      AppColors.gold.withValues(alpha: 0.02),
                    ],
                  ),
                ),
                child: Icon(icon, size: 34, color: AppColors.goldInk),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                title,
                style: AppTypography.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                style: AppTypography.bodyMuted,
                textAlign: TextAlign.center,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.xl),
                GoldButton(
                  text: actionLabel!,
                  onPressed: onAction,
                  expand: false,
                  size: GoldButtonSize.compact,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small status/metadata chip.
class AppChip extends StatelessWidget {
  final String label;
  final Color? foreground;
  final Color? background;
  final IconData? icon;

  const AppChip({
    super.key,
    required this.label,
    this.foreground,
    this.background,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? AppColors.goldInk;
    return Container(
      padding: EdgeInsets.fromLTRB(icon == null ? 8 : 6, 4, 8, 4),
      decoration: BoxDecoration(
        color: background ?? AppColors.gold.withValues(alpha: 0.12),
        borderRadius: AppRadius.allXs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label.toUpperCase(),
            style: AppTypography.goldLabel.copyWith(color: fg, fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}

/// Animated tabular counter used for valuations, so figures resolve into place
/// instead of popping in. Falls back to the final value under reduce-motion.
class AnimatedValue extends StatelessWidget {
  final double value;
  final TextStyle? style;

  /// Formats the interpolated value. Defaults to a plain rounded integer.
  final String Function(double)? formatter;
  final Duration duration;

  const AnimatedValue({
    super.key,
    required this.value,
    this.style,
    this.formatter,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    final format = formatter ?? (v) => v.round().toString();
    final effectiveStyle = style ?? AppTypography.numericLarge;

    if (!Motion.allowed(context)) {
      return Text(format(value), style: effectiveStyle);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: duration,
      curve: AppCurves.emphasized,
      builder: (context, v, _) => Text(format(v), style: effectiveStyle),
    );
  }
}

class PremiumBadge extends StatelessWidget {
  final double size;

  const PremiumBadge({super.key, this.size = 20.0});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Premium member',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            gradient: AppColors.goldGradient,
            borderRadius: AppRadius.allXs,
            boxShadow: AppShadows.goldGlow(opacity: 0.22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                color: AppColors.onGold,
                size: math.max(10, size - 6),
              ),
              const SizedBox(width: 4),
              Text(
                'PREMIUM',
                style: AppTypography.goldLabel.copyWith(
                  color: AppColors.onGold,
                  fontSize: math.max(8, size - 11),
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tap-to-filter world map showing which regions the collection covers.
class InteractiveWorldMap extends StatefulWidget {
  final List<String> collectedContinents;
  final void Function(String) onContinentTapped;

  const InteractiveWorldMap({
    super.key,
    required this.collectedContinents,
    required this.onContinentTapped,
  });

  @override
  State<InteractiveWorldMap> createState() => _InteractiveWorldMapState();
}

class _InteractiveWorldMapState extends State<InteractiveWorldMap>
    with SingleTickerProviderStateMixin {
  String? _selectedRegion;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  // Coarse landmass outlines, normalised to a 100x100 space.
  static const Map<String, List<Offset>> _regions = {
    'North America': [
      Offset(12, 10),
      Offset(42, 12),
      Offset(38, 32),
      Offset(22, 38),
      Offset(15, 25),
    ],
    'South America': [
      Offset(24, 40),
      Offset(34, 42),
      Offset(30, 72),
      Offset(25, 82),
    ],
    'Europe': [Offset(40, 18), Offset(54, 15), Offset(52, 28), Offset(42, 26)],
    'Africa': [
      Offset(42, 32),
      Offset(54, 34),
      Offset(56, 44),
      Offset(46, 68),
      Offset(40, 42),
    ],
    'Asia': [
      Offset(54, 10),
      Offset(88, 12),
      Offset(82, 45),
      Offset(60, 42),
      Offset(54, 26),
    ],
    'Australia': [
      Offset(78, 58),
      Offset(90, 60),
      Offset(86, 76),
      Offset(76, 72),
    ],
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.allowed(context)) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _handleTap(TapUpDetails details, Size size) {
    final tapPoint = Offset(
      (details.localPosition.dx / size.width) * 100,
      (details.localPosition.dy / size.height) * 100,
    );

    for (final entry in _regions.entries) {
      if (_isPointInPolygon(tapPoint, entry.value)) {
        HapticFeedback.selectionClick();
        setState(() => _selectedRegion = entry.key);
        widget.onContinentTapped(entry.key);
        return;
      }
    }
  }

  /// Ray casting — odd crossing count means the point is inside.
  bool _isPointInPolygon(Offset point, List<Offset> polygon) {
    var intersections = 0;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      if (((a.dy > point.dy) != (b.dy > point.dy)) &&
          (point.dx <
              (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx)) {
        intersections++;
      }
    }
    return intersections.isOdd;
  }

  @override
  Widget build(BuildContext context) {
    final collected = widget.collectedContinents;

    return Semantics(
      label: collected.isEmpty
          ? 'Collection map. No regions collected yet.'
          : 'Collection map. Regions collected: ${collected.join(', ')}.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, 172);
          return GestureDetector(
            onTapUp: (details) => _handleTap(details, size),
            child: Container(
              height: size.height,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.surfaceWarm, AppColors.surface],
                ),
                borderRadius: AppRadius.allLg,
                border: Border.all(color: AppColors.borderLight),
              ),
              clipBehavior: Clip.antiAlias,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  painter: WorldMapPainter(
                    regions: _regions,
                    collected: collected,
                    selected: _selectedRegion,
                    pulse: _pulse.value,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class WorldMapPainter extends CustomPainter {
  final Map<String, List<Offset>> regions;
  final List<String> collected;
  final String? selected;
  final double pulse;

  WorldMapPainter({
    required this.regions,
    required this.collected,
    required this.selected,
    this.pulse = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Faint graticule so empty areas still read as a map.
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = AppColors.border.withValues(alpha: 0.45);
    for (var i = 1; i < 6; i++) {
      final y = size.height * i / 6;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var i = 1; i < 8; i++) {
      final x = size.width * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..style = PaintingStyle.fill;

    regions.forEach((name, points) {
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final p = Offset(
          (points[i].dx / 100) * size.width,
          (points[i].dy / 100) * size.height,
        );
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();

      final isCollected = collected.contains(name);
      final isSelected = selected == name;

      if (isSelected) {
        fill.shader = AppColors.goldGradient.createShader(path.getBounds());
        stroke.color = AppColors.goldInk;
      } else if (isCollected) {
        fill.shader = null;
        fill.color = AppColors.gold.withValues(alpha: 0.3);
        stroke.color = AppColors.gold.withValues(alpha: 0.7);
      } else {
        fill.shader = null;
        fill.color = AppColors.border.withValues(alpha: 0.55);
        stroke.color = AppColors.border;
      }

      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
      fill.shader = null;

      if (isSelected || isCollected) {
        final center = _polygonCenter(points, size);
        // Slow radar ping on collected regions.
        final t = (pulse + name.hashCode.abs() % 100 / 100) % 1.0;
        canvas.drawCircle(
          center,
          3 + t * 12,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = AppColors.goldInk.withValues(alpha: (1 - t) * 0.5),
        );
        canvas.drawCircle(center, 3.5, Paint()..color = AppColors.goldInk);
        canvas.drawCircle(center, 1.4, Paint()..color = AppColors.goldLight);
      }
    });
  }

  Offset _polygonCenter(List<Offset> points, Size size) {
    var x = 0.0;
    var y = 0.0;
    for (final p in points) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(
      (x / points.length / 100) * size.width,
      (y / points.length / 100) * size.height,
    );
  }

  @override
  bool shouldRepaint(covariant WorldMapPainter old) =>
      old.selected != selected ||
      old.collected != collected ||
      old.pulse != pulse;
}

/// Studio backdrop for inspecting a collectible against different surfaces.
class PhotoStudioViewer extends StatelessWidget {
  final Widget child;

  /// One of: velvet, wood, concrete, dark, light.
  final String backgroundType;

  const PhotoStudioViewer({
    super.key,
    required this.child,
    required this.backgroundType,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = switch (backgroundType) {
      'velvet' => const BoxDecoration(
        gradient: RadialGradient(
          colors: [Color(0xFF4A1000), Color(0xFF1E0300)],
          radius: 0.9,
        ),
      ),
      'wood' => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5D4037), Color(0xFF3E2723)],
        ),
      ),
      'concrete' => const BoxDecoration(
        gradient: RadialGradient(
          colors: [Color(0xFF9E9E9E), Color(0xFF424242)],
          radius: 0.8,
        ),
      ),
      'dark' => const BoxDecoration(
        gradient: RadialGradient(
          colors: [Color(0xFF3A3A3C), AppColors.ink],
          radius: 0.8,
        ),
      ),
      _ => const BoxDecoration(
        gradient: RadialGradient(
          colors: [Colors.white, Color(0xFFF2F2F7)],
          radius: 0.8,
        ),
      ),
    };

    final isLight =
        backgroundType != 'velvet' &&
        backgroundType != 'wood' &&
        backgroundType != 'dark' &&
        backgroundType != 'concrete';

    return AnimatedContainer(
      duration: AppDuration.base,
      curve: AppCurves.standard,
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Key light from above.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 0.75,
                  colors: [
                    Colors.white.withValues(alpha: isLight ? 0.5 : 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Contact shadow so the subject sits on the surface.
          Positioned(
            bottom: 0,
            child: Container(
              height: 34,
              width: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                gradient: RadialGradient(
                  colors: [
                    Colors.black.withValues(alpha: isLight ? 0.22 : 0.55),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          child,
          // Vignette.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.95,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: isLight ? 0.06 : 0.35),
                    ],
                    stops: const [0.6, 1.0],
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

/// Tone of an [AppSnack] message.
enum SnackTone { neutral, success, warning, error }

/// One consistent toast for the whole app.
///
/// Replaces eleven ad-hoc `SnackBar`s that each picked their own background
/// colour — several of which rendered dark text on a saturated fill. All
/// messages now share the ink surface, a status glyph, and the floating shape
/// defined in the theme.
class AppSnack {
  const AppSnack._();

  static void show(
    BuildContext context,
    String message, {
    SnackTone tone = SnackTone.neutral,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final (IconData icon, Color accent) = switch (tone) {
      SnackTone.success => (Icons.check_circle_rounded, AppColors.emerald),
      SnackTone.warning => (Icons.info_rounded, AppColors.gold),
      SnackTone.error => (Icons.error_rounded, AppColors.crimson),
      SnackTone.neutral => (Icons.auto_awesome_rounded, AppColors.gold),
    };

    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: accent, size: 18),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodyMedium.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
        duration: Duration(milliseconds: message.length > 70 ? 5000 : 3200),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
    );
  }
}

/// Staggered entrance for lists and stacked content.
///
/// Wraps [child] in a fade + rise that starts after `index * stagger`. Returns
/// the child untouched when reduce-motion is on.
class Reveal extends StatelessWidget {
  final Widget child;
  final int index;
  final Duration stagger;
  final double offsetY;

  const Reveal({
    super.key,
    required this.child,
    this.index = 0,
    this.stagger = const Duration(milliseconds: 60),
    this.offsetY = 16,
  });

  @override
  Widget build(BuildContext context) {
    if (!Motion.allowed(context)) return child;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppDuration.slow + stagger * index,
      curve: Interval(
        (index * 0.06).clamp(0.0, 0.6),
        1.0,
        curve: AppCurves.emphasized,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * offsetY),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
