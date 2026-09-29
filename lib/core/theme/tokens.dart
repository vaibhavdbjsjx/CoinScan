/// Design tokens for CoinVault AI.
///
/// Every spacing, radius, duration and shadow in the app resolves to one of
/// these values. Screens should never invent their own magic numbers — if a
/// value is missing here, add it here first so the whole product stays in sync.
library;

import 'package:flutter/material.dart';

import 'colors.dart';

/// 4pt spacing scale.
class AppSpacing {
  const AppSpacing._();

  /// 2 — hairline separation between tightly coupled text.
  static const double xxs = 2;

  /// 4 — label to value.
  static const double xs = 4;

  /// 8 — icon to label.
  static const double sm = 8;

  /// 12 — inside dense components.
  static const double md = 12;

  /// 16 — default component padding.
  static const double base = 16;

  /// 20 — roomy card padding.
  static const double lg = 20;

  /// 24 — screen gutter.
  static const double xl = 24;

  /// 32 — between sections.
  static const double xxl = 32;

  /// 40 — major section break.
  static const double xxxl = 40;

  /// 56 — hero breathing room.
  static const double huge = 56;

  /// Horizontal screen gutter. Grows slightly on wider canvases.
  static double gutter(double width) =>
      width >= AppBreakpoints.medium ? 32 : 24;
}

/// Corner radii. Larger surfaces take larger radii so curvature reads as
/// consistent rather than uniform.
class AppRadius {
  const AppRadius._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double pill = 999;

  static const BorderRadius allXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius allSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius allMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius allLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius allXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius allXxl = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius allPill = BorderRadius.all(Radius.circular(pill));
}

/// Motion durations. Anything the user triggers directly should land in
/// [fast]–[base]; only decorative/ambient motion runs longer.
class AppDuration {
  const AppDuration._();

  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration page = Duration(milliseconds: 520);
  static const Duration ambient = Duration(milliseconds: 2400);
}

/// Shared easing curves.
class AppCurves {
  const AppCurves._();

  /// Default for entrances and size changes.
  static const Curve standard = Curves.easeOutCubic;

  /// Material 3 "emphasized decelerate" — for hero content arriving on screen.
  static const Curve emphasized = Cubic(0.05, 0.7, 0.1, 1.0);

  /// For elements leaving.
  static const Curve exit = Curves.easeInCubic;

  /// Slight overshoot for tactile, playful moments (badges, success states).
  static const Curve overshoot = Curves.easeOutBack;
}

/// Layout breakpoints (logical pixels of the shortest usable width).
class AppBreakpoints {
  const AppBreakpoints._();

  /// Phones.
  static const double compact = 600;

  /// Large phones landscape / small tablets.
  static const double medium = 840;

  /// The widest a single reading column should ever get. Keeps the app from
  /// stretching into an unusable full-bleed layout on tablets and web.
  static const double maxContentWidth = 520;
}

/// A cohesive elevation ramp. Shadows are warm-tinted rather than pure black so
/// they sit correctly against the ivory background.
class AppShadows {
  const AppShadows._();

  /// Resting cards.
  static const List<BoxShadow> level1 = [
    BoxShadow(color: Color(0x0A1C1917), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(
      color: Color(0x0F1C1917),
      offset: Offset(0, 4),
      blurRadius: 12,
      spreadRadius: -2,
    ),
  ];

  /// Raised / interactive surfaces.
  static const List<BoxShadow> level2 = [
    BoxShadow(color: Color(0x0D1C1917), offset: Offset(0, 2), blurRadius: 4),
    BoxShadow(
      color: Color(0x141C1917),
      offset: Offset(0, 10),
      blurRadius: 28,
      spreadRadius: -6,
    ),
  ];

  /// Floating chrome (nav bar, sheets, menus).
  static const List<BoxShadow> level3 = [
    BoxShadow(color: Color(0x0F1C1917), offset: Offset(0, 4), blurRadius: 8),
    BoxShadow(
      color: Color(0x1F1C1917),
      offset: Offset(0, 18),
      blurRadius: 44,
      spreadRadius: -10,
    ),
  ];

  /// Warm halo under gold CTAs. Kept subtle — the glow should suggest weight,
  /// not neon.
  static List<BoxShadow> goldGlow({double opacity = 0.34}) => [
    BoxShadow(
      color: AppColors.gold.withValues(alpha: opacity * 0.6),
      offset: const Offset(0, 2),
      blurRadius: 8,
    ),
    BoxShadow(
      color: AppColors.gold.withValues(alpha: opacity),
      offset: const Offset(0, 10),
      blurRadius: 28,
      spreadRadius: -8,
    ),
  ];
}

/// Motion helpers that honour the platform "reduce motion" accessibility
/// setting. Ambient/looping animations must be gated on [allowed] so the app
/// stays comfortable for motion-sensitive users.
class Motion {
  const Motion._();

  /// False when the user has asked the OS to reduce motion.
  static bool allowed(BuildContext context) =>
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// Collapses a duration to zero when motion is reduced.
  static Duration duration(BuildContext context, Duration value) =>
      allowed(context) ? value : Duration.zero;
}
