import 'package:flutter/material.dart';

/// CoinVault AI palette.
///
/// The brand is three materials: **gold**, **ink** (near-black charcoal) and
/// **ivory** (warm white). Everything else is a functional tint of those.
///
/// Contrast note: gold is a mid-luminance hue, so white-on-gold only reaches
/// 2.1:1 — well under the WCAG AA minimum of 4.5:1. Gold is therefore treated
/// as a *surface* that carries ink text (8.1:1), never as a text colour on
/// white. For gold-coloured text on light backgrounds use [goldInk] (6.2:1).
class AppColors {
  const AppColors._();

  // ---------------------------------------------------------------- surfaces
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFAFAFA);

  /// Warm off-white used for large calm areas so the app doesn't read clinical.
  static const Color surfaceWarm = Color(0xFFFBF9F5);
  static const Color cardBg = Color(0xFFFFFFFF);

  // -------------------------------------------------------------------- gold
  /// The brand gold. Use as a fill/surface, with [onGold] text on top.
  static const Color gold = Color(0xFFD4AF37);
  static const Color goldDark = Color(0xFFB89420);
  static const Color goldLight = Color(0xFFF3E5AB);
  static const Color goldAccent = Color(0xFFFFD700);

  /// Highlight used in metallic gradients — the specular edge of struck gold.
  static const Color goldSheen = Color(0xFFE5C158);

  /// Deep antique gold. The only gold that is legible as *text* on white
  /// (6.24:1) or on [surface] (5.98:1).
  static const Color goldInk = Color(0xFF7A5C12);

  /// Text/icon colour to place on top of a gold fill (8.09:1).
  static const Color onGold = Color(0xFF1C1C1E);

  // --------------------------------------------------------------------- ink
  /// Deepest ink — immersive backdrops (onboarding, scanner, hero blocks).
  static const Color ink = Color(0xFF121214);
  static const Color inkSoft = Color(0xFF1C1C1E);
  static const Color inkElevated = Color(0xFF26262A);

  // -------------------------------------------------------------------- text
  static const Color textPrimary = Color(0xFF1C1C1E);

  /// Secondary body text. Darkened from the old #8E8E93 (3.26:1, failing) to
  /// reach 5.07:1 while keeping the same neutral-grey character.
  static const Color textSecondary = Color(0xFF6E6E73);

  /// Decorative / disabled only — intentionally below text contrast minimums.
  static const Color textMuted = Color(0xFFC7C7CC);
  static const Color textMutedDark = Color(0xFFA1A1A6);

  /// Body text on ink backgrounds (6.6:1 on [ink]).
  static const Color textOnInk = Color(0xFFEDEDEF);
  static const Color textOnInkMuted = Color(0xFFA8A8AE);

  // ----------------------------------------------------------------- borders
  static const Color border = Color(0xFFE5E5EA);
  static const Color borderLight = Color(0xFFF2F2F7);

  /// Hairline on ink surfaces.
  static const Color borderOnInk = Color(0x1FFFFFFF);

  // ------------------------------------------------------------------ status
  static const Color emerald = Color(0xFF2E7D32);
  static const Color emeraldLight = Color(0xFFE8F5E9);

  static const Color crimson = Color(0xFFC62828);
  static const Color crimsonLight = Color(0xFFFFEBEE);

  static const Color amber = Color(0xFFEF6C00);
  static const Color amberLight = Color(0xFFFFF3E0);

  /// Legible amber for small text on [amberLight] / white.
  static const Color amberInk = Color(0xFFA34700);

  // ------------------------------------------------- studio mockup backdrops
  static const Color velvetBg = Color(0xFF2A0800);
  static const Color woodBg = Color(0xFF3E2723);
  static const Color concreteBg = Color(0xFF757575);

  // --------------------------------------------------------------- overlays
  static const Color overlayLight = Color(0x0A000000);
  static const Color darkOverlay = Color(0x33000000);
  static const Color shadowColor = Color(0x0D000000);

  /// Scrim behind modal content over imagery.
  static const Color scrim = Color(0x99121214);

  // -------------------------------------------------------------- gradients
  /// Struck-metal gradient for coins, CTAs and badges.
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE7C766), Color(0xFFD4AF37), Color(0xFFB89420)],
    stops: [0.0, 0.52, 1.0],
  );

  /// Immersive dark backdrop with a subtle warm lift toward the top.
  static const LinearGradient inkGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF232327), Color(0xFF141416), Color(0xFF0D0D0F)],
    stops: [0.0, 0.55, 1.0],
  );
}
