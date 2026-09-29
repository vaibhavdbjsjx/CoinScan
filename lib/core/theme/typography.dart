import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// The CoinVault AI type ramp: a single family (Inter) used with disciplined
/// sizing and tabular numbers.
///
/// Prices, valuations and stats use [FontFeature.tabularFigures] so digits
/// share a fixed advance width:
///    columns line up and live-updating values stop jittering. Slashed zero
///    keeps serial numbers and grades unambiguous.
class AppTypography {
  const AppTypography._();

  static const List<FontFeature> _tabular = [
    FontFeature.tabularFigures(),
    FontFeature.slashedZero(),
  ];

  // ------------------------------------------------------------------ display

  /// Reserved for the single most important line on a screen (onboarding hero,
  /// vault valuation).
  static TextStyle get displayLarge => GoogleFonts.inter(
    fontSize: 40,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: 0,
    height: 1.06,
  );

  /// Screen-level hero title.
  static TextStyle get heroTitle => GoogleFonts.inter(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: 0,
    height: 1.12,
  );

  // -------------------------------------------------------------------- title

  /// Section headers within a screen.
  static TextStyle get sectionHeader => GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: 0,
    height: 1.25,
  );

  /// Card titles and list-row headings.
  static TextStyle get titleMedium => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: 0,
    height: 1.3,
  );

  /// Compact card titles.
  static TextStyle get titleSmall => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: 0,
    height: 1.3,
  );

  // --------------------------------------------------------------------- body

  static TextStyle get bodyLarge => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    letterSpacing: 0,
    height: 1.5,
  );

  static TextStyle get bodyMedium => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    letterSpacing: 0,
    height: 1.45,
  );

  /// Secondary body copy — supporting text, descriptions, hints.
  static TextStyle get bodyMuted => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    letterSpacing: 0,
    height: 1.45,
  );

  /// Lead paragraph under a hero title.
  static TextStyle get subtitle => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    letterSpacing: 0,
    height: 1.55,
  );

  // -------------------------------------------------------------------- small

  static TextStyle get caption => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    letterSpacing: 0,
    height: 1.35,
  );

  /// The smallest text the app is allowed to render.
  static TextStyle get captionSmall => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    letterSpacing: 0,
    height: 1.3,
  );

  /// Wide-tracked uppercase eyebrow label in antique gold. Always pair with
  /// `.toUpperCase()` text.
  static TextStyle get goldLabel => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.goldInk,
    letterSpacing: 0,
    height: 1.2,
  );

  /// Neutral eyebrow, for when gold would compete with nearby accents.
  static TextStyle get overline => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: 0,
    height: 1.2,
  );

  // ------------------------------------------------------------------ numeric

  /// Hero figures — vault valuation, headline prices.
  static TextStyle get numericLarge => GoogleFonts.inter(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: 0,
    height: 1.1,
    fontFeatures: _tabular,
  );

  /// Stat-card values.
  static TextStyle get numericMedium => GoogleFonts.inter(
    fontSize: 19,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: 0,
    height: 1.2,
    fontFeatures: _tabular,
  );

  /// Inline figures — deltas, counts, grades.
  static TextStyle get numericSmall => GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: 0,
    height: 1.2,
    fontFeatures: _tabular,
  );

  // ------------------------------------------------------------------ button

  static TextStyle get buttonText => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.onGold,
    letterSpacing: 0,
    height: 1.2,
  );

  static TextStyle get buttonTextSmall => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.onGold,
    letterSpacing: 0,
    height: 1.2,
  );
}
