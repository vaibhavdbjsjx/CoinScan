import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';
import '../theme/theme.dart';

class GoldButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isSecondary;
  final IconData? icon;
  final bool isLoading;

  const GoldButton({
    Key? key,
    required this.text,
    required this.onPressed,
    this.isSecondary = false,
    this.icon,
    this.isLoading = false,
  }) : super(key: key);

  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    )..addListener(() {
        setState(() {
          _scale = _controller.value;
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonColor = widget.isSecondary ? Colors.white : AppColors.gold;
    final textColor = widget.isSecondary ? AppColors.textPrimary : Colors.white;
    final border = widget.isSecondary 
        ? const BorderSide(color: AppColors.border, width: 1.5)
        : BorderSide.none;

    return GestureDetector(
      onTapDown: (_) => _controller.reverse(),
      onTapUp: (_) {
        _controller.forward();
        widget.onPressed();
      },
      onTapCancel: () => _controller.forward(),
      child: Transform.scale(
        scale: _scale,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: buttonColor,
            borderRadius: BorderRadius.circular(16),
            border: border != BorderSide.none 
                ? Border.all(color: border.color, width: border.width) 
                : null,
            boxShadow: widget.isSecondary ? null : [
              BoxShadow(
                color: AppColors.gold.withOpacity(0.3),
                offset: const Offset(0, 8),
                blurRadius: 20,
                spreadRadius: -2,
              )
            ],
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: widget.isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, color: textColor, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      widget.text,
                      style: AppTypography.buttonText.copyWith(color: textColor),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const GlassCard({
    Key? key,
    required this.child,
    this.borderRadius = 24.0,
    this.padding = const EdgeInsets.all(24.0),
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final content = Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: Colors.white.withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: AppTheme.premiumShadow,
      ),
      padding: padding,
      child: child,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: content,
      );
    }
    return content;
  }
}

class PremiumShimmer extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const PremiumShimmer({
    Key? key,
    required this.width,
    required this.height,
    this.borderRadius = 12.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.borderLight,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    ).animate(onPlay: (controller) => controller.repeat())
     .shimmer(
       duration: 1500.ms,
       color: Colors.white.withOpacity(0.6),
       angle: 45,
     );
  }
}

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String change;
  final bool isPositive;
  final IconData icon;

  const MetricCard({
    Key? key,
    required this.title,
    required this.value,
    required this.change,
    required this.isPositive,
    required this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight, width: 1),
        boxShadow: AppTheme.premiumShadow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.goldDark, size: 20),
              ),
              Row(
                children: [
                  Icon(
                    isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                    color: isPositive ? AppColors.emerald : AppColors.crimson,
                    size: 12,
                  ),
                  Text(
                    change,
                    style: AppTypography.caption.copyWith(
                      color: isPositive ? AppColors.emerald : AppColors.crimson,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.caption.copyWith(fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppTypography.sectionHeader.copyWith(fontSize: 18),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PhotoStudioViewer extends StatelessWidget {
  final Widget child;
  final String backgroundType; // velvet, wood, concrete, dark, light

  const PhotoStudioViewer({
    Key? key,
    required this.child,
    required this.backgroundType,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    BoxDecoration decoration;
    
    switch (backgroundType) {
      case 'velvet':
        decoration = const BoxDecoration(
          color: AppColors.velvetBg,
          gradient: RadialGradient(
            colors: [Color(0xFF4A1000), Color(0xFF1E0300)],
            radius: 0.9,
          ),
        );
        break;
      case 'wood':
        decoration = const BoxDecoration(
          color: AppColors.woodBg,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF5D4037), Color(0xFF3E2723)],
          ),
        );
        break;
      case 'concrete':
        decoration = const BoxDecoration(
          color: AppColors.concreteBg,
          gradient: RadialGradient(
            colors: [Color(0xFF9E9E9E), Color(0xFF424242)],
            radius: 0.8,
          ),
        );
        break;
      case 'dark':
        decoration = const BoxDecoration(
          color: AppColors.textPrimary,
          gradient: RadialGradient(
            colors: [Color(0xFF3A3A3C), Color(0xFF1C1C1E)],
            radius: 0.8,
          ),
        );
        break;
      default:
        decoration = const BoxDecoration(
          color: AppColors.surface,
          gradient: RadialGradient(
            colors: [Colors.white, Color(0xFFF2F2F7)],
            radius: 0.8,
          ),
        );
    }

    return Container(
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Studio spot light overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withOpacity(0.12),
                    Colors.transparent,
                  ],
                  radius: 0.6,
                ),
              ),
            ),
          ),
          
          // Shadow drop underneath the centered child
          Container(
            height: 190,
            width: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
          ),
          
          // Child content
          child,
        ],
      ),
    );
  }
}

class PremiumBadge extends StatelessWidget {
  final double size;

  const PremiumBadge({
    Key? key,
    this.size = 20.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.gold, AppColors.goldAccent, AppColors.goldDark],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium, color: Colors.white, size: size - 4),
          const SizedBox(width: 4),
          Text(
            'PREMIUM',
            style: AppTypography.goldLabel.copyWith(
              color: Colors.white,
              fontSize: size - 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    ).animate(onPlay: (controller) => controller.repeat(reverse: true))
     .shimmer(duration: 2000.ms, color: Colors.white.withOpacity(0.4));
  }
}

class InteractiveWorldMap extends StatefulWidget {
  final List<String> collectedContinents;
  final Function(String) onContinentTapped;

  const InteractiveWorldMap({
    Key? key,
    required this.collectedContinents,
    required this.onContinentTapped,
  }) : super(key: key);

  @override
  State<InteractiveWorldMap> createState() => _InteractiveWorldMapState();
}

class _InteractiveWorldMapState extends State<InteractiveWorldMap> {
  String? _selectedRegion;

  // Simple bounding polygons representation normalized 0.0 - 100.0
  final Map<String, List<Offset>> _regions = {
    'North America': const [
      Offset(12, 10), Offset(42, 12), Offset(38, 32), Offset(22, 38), Offset(15, 25)
    ],
    'South America': const [
      Offset(24, 40), Offset(34, 42), Offset(30, 72), Offset(25, 82)
    ],
    'Europe': const [
      Offset(40, 18), Offset(54, 15), Offset(52, 28), Offset(42, 26)
    ],
    'Africa': const [
      Offset(42, 32), Offset(54, 34), Offset(56, 44), Offset(46, 68), Offset(40, 42)
    ],
    'Asia': const [
      Offset(54, 10), Offset(88, 12), Offset(82, 45), Offset(60, 42), Offset(54, 26)
    ],
    'Australia': const [
      Offset(78, 58), Offset(90, 60), Offset(86, 76), Offset(76, 72)
    ],
  };

  void _handleTap(TapUpDetails details, BoxConstraints constraints) {
    final renderBox = context.findRenderObject() as RenderBox;
    final localPosition = details.localPosition;
    
    // Normalize coordinates to 100x100
    final xPercent = (localPosition.dx / renderBox.size.width) * 100;
    final yPercent = (localPosition.dy / renderBox.size.height) * 100;
    final tapPoint = Offset(xPercent, yPercent);

    String? tappedRegion;
    for (var entry in _regions.entries) {
      if (_isPointInPolygon(tapPoint, entry.value)) {
        tappedRegion = entry.key;
        break;
      }
    }

    if (tappedRegion != null) {
      setState(() {
        _selectedRegion = tappedRegion;
      });
      widget.onContinentTapped(tappedRegion);
    }
  }

  // Ray Casting Algorithm to check points inside polygon boundaries
  bool _isPointInPolygon(Offset point, List<Offset> polygon) {
    int intersectCount = 0;
    for (int i = 0; i < polygon.length; i++) {
      final nextIdx = (i + 1) % polygon.length;
      final ip1 = polygon[i];
      final ip2 = polygon[nextIdx];

      if (((ip1.dy > point.dy) != (ip2.dy > point.dy)) &&
          (point.dx < (ip2.dx - ip1.dx) * (point.dy - ip1.dy) / (ip2.dy - ip1.dy) + ip1.dx)) {
        intersectCount++;
      }
    }
    return intersectCount % 2 != 0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapUp: (details) => _handleTap(details, constraints),
          child: Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: CustomPaint(
              painter: WorldMapPainter(
                regions: _regions,
                collected: widget.collectedContinents,
                selected: _selectedRegion,
              ),
            ),
          ),
        );
      },
    );
  }
}

class WorldMapPainter extends CustomPainter {
  final Map<String, List<Offset>> regions;
  final List<String> collected;
  final String? selected;

  WorldMapPainter({
    required this.regions,
    required this.collected,
    required this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = AppColors.border;

    final fillPaint = Paint()..style = PaintingStyle.fill;

    regions.forEach((name, points) {
      // Map normalized coordinates (100x100) to actual canvas size
      final path = Path();
      for (int i = 0; i < points.length; i++) {
        final actualPoint = Offset(
          (points[i].dx / 100) * size.width,
          (points[i].dy / 100) * size.height,
        );
        if (i == 0) {
          path.moveTo(actualPoint.dx, actualPoint.dy);
        } else {
          path.lineTo(actualPoint.dx, actualPoint.dy);
        }
      }
      path.close();

      // Determine region color
      final isCollected = collected.contains(name);
      final isSelected = selected == name;

      if (isSelected) {
        fillPaint.color = AppColors.gold;
      } else if (isCollected) {
        fillPaint.color = AppColors.goldLight.withOpacity(0.5);
      } else {
        fillPaint.color = AppColors.borderLight;
      }

      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, borderPaint);

      // Label indicator at region center
      if (isSelected || isCollected) {
        // Draw tiny indicator node
        final center = _getPolygonCenter(points, size);
        final nodePaint = Paint()
          ..color = AppColors.goldDark
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, 4, nodePaint);
      }
    });
  }

  Offset _getPolygonCenter(List<Offset> points, Size size) {
    double xSum = 0;
    double ySum = 0;
    for (var pt in points) {
      xSum += pt.dx;
      ySum += pt.dy;
    }
    return Offset(
      ((xSum / points.length) / 100) * size.width,
      ((ySum / points.length) / 100) * size.height,
    );
  }

  @override
  bool shouldRepaint(covariant WorldMapPainter oldDelegate) =>
      oldDelegate.selected != selected || oldDelegate.collected != collected;
}

