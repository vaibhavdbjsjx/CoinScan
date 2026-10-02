import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/recognition/recognition_models.dart';
import '../../../core/storage/collection_storage_service.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';

/// ---------------------------------------------------------------------------
/// 1. EVIDENCE: WHAT SUPPORTS THIS IDENTIFICATION
/// ---------------------------------------------------------------------------
/// Renders the evidence returned by the recognition service exactly as sent,
/// including where each signal came from. Nothing is inferred or "verified"
/// on the device. Catalogue specifications are listed separately and are
/// clearly labelled as catalogue data, not measurements of the photographed coin.
class WhyWeThinkThisIsYourCoinWidget extends StatelessWidget {
  final RecognitionCandidate candidate;
  final bool hasReverseImage;

  const WhyWeThinkThisIsYourCoinWidget({
    super.key,
    required this.candidate,
    this.hasReverseImage = true,
  });

  static const title = 'What supports this identification';

  @override
  Widget build(BuildContext context) {
    final id = candidate.identity;
    final specs = <(String, String)>[
      if (id.composition != null && id.composition!.trim().isNotEmpty)
        ('Composition', id.composition!),
      if (id.weightG != null) ('Weight', '${id.weightG} g'),
      if (id.diameterMm != null) ('Diameter', '${id.diameterMm} mm'),
      if (id.thicknessMm != null) ('Thickness', '${id.thicknessMm} mm'),
      if (id.edgeType != null && id.edgeType!.trim().isNotEmpty)
        ('Edge', id.edgeType!),
      if (id.kmNumber != null && id.kmNumber!.trim().isNotEmpty)
        ('Catalogue number', id.kmNumber!),
      if (id.numistaId != null) ('Numista', 'N# ${id.numistaId}'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(icon: Icons.fact_check_outlined, title: title),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Each item shows where it came from. Details read by AI from your '
          'photo can be wrong; catalogue checks compare them with the matched record.',
          style: AppTypography.captionSmall.copyWith(
            color: AppColors.textOnInkMuted,
            height: 1.35,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (candidate.evidence.isEmpty)
          const _InfoNote(text: 'No supporting evidence was returned for this result.')
        else
          for (final ev in candidate.evidence) ...[
            _EvidenceTile(evidence: ev),
            const SizedBox(height: AppSpacing.sm),
          ],
        if (specs.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          const _SectionHeader(
            icon: Icons.menu_book_rounded,
            title: 'Catalogue record',
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Standard specifications for the matched coin type. They were not '
            'measured from your coin.',
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textOnInkMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.inkElevated,
              borderRadius: AppRadius.allMd,
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                for (final (label, value) in specs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.textOnInkMuted,
                            ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            value,
                            textAlign: TextAlign.end,
                            style: AppTypography.caption.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.gold, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            title,
            style: AppTypography.titleSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _InfoNote extends StatelessWidget {
  final String text;

  const _InfoNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: AppRadius.allMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Colors.white54, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTypography.captionSmall.copyWith(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  final RecognitionEvidence evidence;

  const _EvidenceTile({required this.evidence});

  (String, Color) get _strength => switch (evidence.strength) {
    SignalStrength.strong => ('Strong', AppColors.emerald),
    SignalStrength.moderate => ('Moderate', AppColors.gold),
    SignalStrength.weak => ('Weak', Colors.white60),
    SignalStrength.inconsistent => ('Conflicts', AppColors.crimson),
  };

  IconData get _icon => switch (evidence.type) {
    RecognitionEvidenceType.year => Icons.calendar_today_rounded,
    RecognitionEvidenceType.mintMark => Icons.label_important_outline_rounded,
    RecognitionEvidenceType.denomination => Icons.monetization_on_outlined,
    RecognitionEvidenceType.country => Icons.account_balance_rounded,
    RecognitionEvidenceType.inscription => Icons.text_fields_rounded,
    RecognitionEvidenceType.obverseReverseAgreement => Icons.flip_rounded,
    RecognitionEvidenceType.composition => Icons.toll_rounded,
    RecognitionEvidenceType.visualSimilarity => Icons.visibility_outlined,
    _ => Icons.circle_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final (strengthLabel, strengthColor) = _strength;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.inkElevated,
        borderRadius: AppRadius.allMd,
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, color: AppColors.gold, size: 18),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        evidence.label,
                        style: AppTypography.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      strengthLabel,
                      style: AppTypography.captionSmall.copyWith(
                        color: strengthColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if (evidence.detail.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    evidence.detail,
                    style: AppTypography.captionSmall.copyWith(
                      color: Colors.white70,
                      height: 1.3,
                    ),
                  ),
                ],
                if (evidence.source != null && evidence.source!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Source: ${evidence.source}',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textOnInkMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// 2. IDENTIFICATION CONFIDENCE (separate from authenticity)
/// ---------------------------------------------------------------------------
/// Shows the corroboration-gated identification level and how many catalogue
/// cross-checks passed. No percentage is shown: the underlying score is not
/// calibrated against real-world accuracy, so a "94%" would imply a
/// probability CoinScan cannot back up. Authenticity is always reported as not
/// assessed, because photo recognition cannot authenticate a coin.
class HonestConfidenceCard extends StatelessWidget {
  final RecognitionConfidence confidence;

  const HonestConfidenceCard({super.key, required this.confidence});

  static const authenticityNote =
      'Not assessed. CoinScan identifies coin types from photos; it cannot '
      'authenticate coins or detect counterfeits. For authentication, consult a '
      'professional grading service or a qualified numismatist.';

  static String levelLabel(ConfidenceLevel level) => switch (level) {
    ConfidenceLevel.high => 'High identification confidence',
    ConfidenceLevel.medium => 'Medium identification confidence',
    ConfidenceLevel.low => 'Low identification confidence',
    ConfidenceLevel.indeterminate => 'Identification uncertain',
  };

  @override
  Widget build(BuildContext context) {
    final (badgeColor, icon) = switch (confidence.level) {
      ConfidenceLevel.high => (AppColors.emerald, Icons.check_circle_rounded),
      ConfidenceLevel.medium => (AppColors.gold, Icons.info_rounded),
      ConfidenceLevel.low => (AppColors.amber, Icons.help_outline_rounded),
      ConfidenceLevel.indeterminate => (
        Colors.white60,
        Icons.warning_amber_rounded,
      ),
    };
    final checks = confidence.corroboratingChecks;
    final checksText = checks == 0
        ? 'No detail could be cross-checked against the catalogue record'
        : checks == 1
        ? '1 detail cross-checked against the catalogue record'
        : '$checks details cross-checked against the catalogue record';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.inkElevated,
        borderRadius: AppRadius.allLg,
        border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: badgeColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  levelLabel(confidence.level),
                  style: AppTypography.titleSmall.copyWith(
                    color: badgeColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            confidence.displayExplanation,
            style: AppTypography.bodyMedium.copyWith(
              color: Colors.white,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                checks > 0 ? Icons.rule_rounded : Icons.remove_circle_outline,
                size: 14,
                color: Colors.white60,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  checksText,
                  style: AppTypography.captionSmall.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 14,
                color: AppColors.textOnInkMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Authenticity: ',
                        style: AppTypography.captionSmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: authenticityNote,
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textOnInkMuted,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (confidence.level != ConfidenceLevel.high) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: AppRadius.allMd,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 14,
                    color: AppColors.gold,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      confidence.level == ConfidenceLevel.medium
                          ? 'Tip: photograph the reverse, or take a steady close-up of the date and mint mark, to narrow this down.'
                          : 'Tip: lay the coin flat under soft, even light with no glare, fill the frame, and photograph both sides.',
                      style: AppTypography.captionSmall.copyWith(
                        color: Colors.white70,
                        height: 1.3,
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

/// ---------------------------------------------------------------------------
/// 3. VALUATION TRANSPARENCY
/// ---------------------------------------------------------------------------
class TransparentValuationCard extends StatelessWidget {
  final ValuationResult? valuation;
  final RecognitionCandidate candidate;

  const TransparentValuationCard({
    super.key,
    required this.valuation,
    required this.candidate,
  });

  @override
  Widget build(BuildContext context) {
    final currency = valuation?.currencyCode ?? 'USD';
    final hasMelt = candidate.hasPreciousMetal;
    final compositionKnown =
        (candidate.identity.composition ?? '').trim().isNotEmpty;
    final valuationNotes = valuation?.valuationNotes?.trim() ?? '';

    double? meltVal;
    double? catVal;
    double? lowRange;
    double? highRange;

    if (valuation != null && valuation!.status != ValuationStatus.unavailable) {
      for (final est in valuation!.estimates) {
        if (est.type == ValuationType.metalValue) meltVal = est.mid ?? est.low;
        if (est.type == ValuationType.collectorValue) catVal = est.mid ?? est.high;
        if (est.type == ValuationType.marketEstimate) {
          lowRange = est.low;
          highRange = est.high;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.inkElevated,
        borderRadius: AppRadius.allXl,
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.price_change_outlined, color: AppColors.gold, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        'Value',
                        style: AppTypography.titleSmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: AppRadius.allPill,
                ),
                child: Text(
                  currency,
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Primary Estimated Market Range
          if (lowRange != null && highRange != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.08),
                borderRadius: AppRadius.allMd,
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Estimated Market Range',
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${lowRange.toStringAsFixed(0)} – ${highRange.toStringAsFixed(0)} $currency',
                        style: AppTypography.sectionHeader.copyWith(
                          color: Colors.white,
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                  const Icon(Icons.trending_flat_rounded, color: AppColors.gold, size: 28),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: AppRadius.allMd,
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.white54, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Market value range is currently unavailable for this specific variety.',
                      style: AppTypography.captionSmall.copyWith(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Dimension Breakdown Table
          _buildValuationRow(
            label: 'Face Value',
            value: candidate.denomination,
            description: 'Denomination legal tender value',
          ),
          const Divider(color: Colors.white10),
          _buildValuationRow(
            label: 'Intrinsic Melt Value',
            value: meltVal != null
                ? '${meltVal.toStringAsFixed(2)} $currency'
                : !compositionKnown
                    ? 'Unknown'
                    : (hasMelt ? 'Unavailable' : 'None (base-metal alloy)'),
            description: meltVal != null
                ? 'Bullion value from catalogue weight, fineness and spot price'
                : !compositionKnown
                    ? 'Metal composition is not known for this coin'
                    : (hasMelt
                        ? 'Needs catalogue fineness, weight and a live spot price'
                        : 'Alloy contains no gold, silver or platinum'),
          ),
          const Divider(color: Colors.white10),
          _buildValuationRow(
            label: 'Catalogue Guide Value',
            value: catVal != null
                ? '${catVal.toStringAsFixed(0)} $currency'
                : 'Guide value unavailable',
            description: 'Reference price for typical average condition',
          ),

          if (valuationNotes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              valuationNotes,
              key: const ValueKey('valuation_notes'),
              style: AppTypography.captionSmall.copyWith(
                color: Colors.white70,
                height: 1.35,
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.md),

          // Honest Numismatic Caveat Banner
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: AppRadius.allSm,
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined, size: 14, color: AppColors.gold),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Valuation depends heavily on strike condition, rarity, mint mark, variety and current market demand. A photograph alone cannot determine certified numismatic market value.',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textOnInkMuted,
                      fontSize: 10.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValuationRow({
    required String label,
    required String value,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textOnInkMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTypography.bodyMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// 4. CONDITION / GRADE AWARENESS
/// ---------------------------------------------------------------------------
class ConditionEstimateCard extends StatelessWidget {
  final String? conditionGrade;

  const ConditionEstimateCard({super.key, this.conditionGrade});

  @override
  Widget build(BuildContext context) {
    if (conditionGrade == null || conditionGrade!.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final grade = conditionGrade!;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.inkElevated,
        borderRadius: AppRadius.allLg,
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Condition Estimate',
                style: AppTypography.titleSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.15),
                  borderRadius: AppRadius.allPill,
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                ),
                child: Text(
                  grade,
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Visual wear pattern matches circulated collector grade standards. Photographic estimate only — not a certified grade.',
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textOnInkMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'For professional authentication and certified grading, consult a professional service such as PCGS, NGC, or a licensed numismatist.',
            style: AppTypography.captionSmall.copyWith(
              color: Colors.white54,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// 4.5. WORTH A CLOSER LOOK (Collector Insight)
/// ---------------------------------------------------------------------------
class WorthACloserLookCard extends StatelessWidget {
  final RecognitionCandidate candidate;
  final ValuationResult? valuation;

  const WorthACloserLookCard({
    super.key,
    required this.candidate,
    this.valuation,
  });

  @override
  Widget build(BuildContext context) {
    final reasons = <String>[];
    final id = candidate.identity;

    // Only an explicitly stated catalogue fineness counts as precious metal.
    final metal = candidate.preciousMetal;
    if (metal != null) {
      reasons.add(
        'The catalogue lists ${metal.displayName.toLowerCase()} at '
        '${(metal.fineness * 1000).toStringAsFixed(0)}/1000 fineness, so the coin has '
        'bullion value in addition to any collector value.',
      );
    }

    // Mint-mark notes only apply to United States issues, and the mark itself
    // was read by AI from the photo, so it is presented as something to confirm.
    final isUs = id.country.toLowerCase().contains('united states');
    if (isUs && id.mint != null && id.mint!.isNotEmpty) {
      final m = id.mint!.toUpperCase();
      if (m == 'CC') {
        reasons.add('A "CC" (Carson City) mint mark was read from the photo. Carson City issues are generally scarcer, so confirm the mark under magnification.');
      } else if (m == 'O') {
        reasons.add('An "O" (New Orleans) mint mark was read from the photo. Confirm it under magnification.');
      }
    }

    final conf = candidate.confidence;
    if (conf != null && (conf.level == ConfidenceLevel.medium || conf.level == ConfidenceLevel.low)) {
      reasons.add('The exact variety is not confirmed. Check the mint mark and reverse lettering under magnification.');
    }

    final market = valuation?.marketMid;
    if (market != null && market > 100) {
      reasons.add(
        'The market estimate (${market.toStringAsFixed(0)} ${valuation!.currencyCode}) is high enough that condition matters; a professional opinion may be worthwhile.',
      );
    }

    if (reasons.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.1),
        borderRadius: AppRadius.allLg,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: AppColors.gold, size: 18),
              const SizedBox(width: 8),
              Text(
                'Worth a Closer Look',
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.gold,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final reason in reasons.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Text(
                      reason,
                      style: AppTypography.captionSmall.copyWith(
                        color: Colors.white,
                        height: 1.35,
                      ),
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

/// ---------------------------------------------------------------------------
/// 5. "SHOULD I CONSIDER PROFESSIONAL GRADING?" DECISION GUIDE
/// ---------------------------------------------------------------------------
class ShouldIGetThisGradedCard extends StatelessWidget {
  final RecognitionCandidate candidate;
  final ValuationResult? valuation;

  const ShouldIGetThisGradedCard({
    super.key,
    required this.candidate,
    this.valuation,
  });

  @override
  Widget build(BuildContext context) {
    final isValuable = candidate.hasPreciousMetal ||
        (candidate.identity.year != null && candidate.identity.year! < 1920) ||
        (candidate.identity.mint != null && candidate.identity.mint!.isNotEmpty);

    final title = isValuable
        ? 'Possibly worth a professional opinion'
        : 'Often not cost-effective for common coins';

    final color = isValuable ? AppColors.emerald : Colors.white60;
    final icon = isValuable ? Icons.check_circle_outline : Icons.cancel_outlined;

    final explanation = isValuable
        ? 'Its age, mint mark or metal content means professional grading could be worthwhile if the coin is in high condition. A photo alone cannot determine grade or authenticity.'
        : 'Grading fees can exceed the value of common circulated coins. Check current fees with a grading service before submitting.';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.inkElevated,
        borderRadius: AppRadius.allLg,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.school_outlined, size: 18, color: AppColors.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Should I consider professional grading?',
                  style: AppTypography.titleSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  style: AppTypography.bodyMedium.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            explanation,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textOnInkMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Informational educational recommendation only; not financial or grading advice.',
            style: AppTypography.captionSmall.copyWith(
              color: Colors.white38,
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// 6. DUPLICATE DETECTION WARNING CARD
/// ---------------------------------------------------------------------------
class DuplicateWarningCard extends StatelessWidget {
  final List<VaultCoinItem> duplicates;
  final VoidCallback onViewExisting;
  final VoidCallback onAddAnyway;

  const DuplicateWarningCard({
    super.key,
    required this.duplicates,
    required this.onViewExisting,
    required this.onAddAnyway,
  });

  @override
  Widget build(BuildContext context) {
    if (duplicates.isEmpty) return const SizedBox.shrink();

    final existing = duplicates.first;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.12),
        borderRadius: AppRadius.allLg,
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.copy_rounded, color: AppColors.amber, size: 18),
              const SizedBox(width: 8),
              Text(
                'Possible Duplicate Detected',
                style: AppTypography.caption.copyWith(
                  color: AppColors.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'You already have a "${existing.coinName}" (${existing.country}) in your collection vault.',
            style: AppTypography.captionSmall.copyWith(
              color: Colors.white,
              height: 1.3,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              TextButton(
                onPressed: onViewExisting,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.gold,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                ),
                child: const Text('View existing coin'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onAddAnyway,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                ),
                child: const Text('Add duplicate anyway'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// 7. WRONG IDENTIFICATION FEEDBACK LOOP
/// ---------------------------------------------------------------------------
class WrongIdentificationFeedbackWidget extends StatefulWidget {
  final RecognitionCandidate candidate;
  final Future<void> Function(String reason, String details)? onSubmitFeedback;

  const WrongIdentificationFeedbackWidget({
    super.key,
    required this.candidate,
    this.onSubmitFeedback,
  });

  @override
  State<WrongIdentificationFeedbackWidget> createState() =>
      _WrongIdentificationFeedbackWidgetState();
}

class _WrongIdentificationFeedbackWidgetState
    extends State<WrongIdentificationFeedbackWidget> {
  bool? _isCorrect;
  bool _submitted = false;

  void _handleYes() {
    setState(() {
      _isCorrect = true;
      _submitted = true;
    });
    HapticFeedback.lightImpact();
  }

  void _handleNo() {
    setState(() => _isCorrect = false);
    HapticFeedback.mediumImpact();
    _showDefectOptionsSheet();
  }

  void _showDefectOptionsSheet() {
    final defectOptions = [
      'Wrong country',
      'Wrong year',
      'Wrong denomination',
      'Wrong mint mark',
      'Wrong variety',
      'Wrong coin entirely',
      'Value seems incorrect',
      'Other',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.inkElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'What was wrong?',
                    style: AppTypography.titleSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Your feedback directly trains our numismatic engine and improves recognition accuracy.',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textOnInkMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ...defectOptions.map(
                (reason) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.radio_button_unchecked,
                    color: AppColors.gold,
                    size: 18,
                  ),
                  title: Text(
                    reason,
                    style: AppTypography.bodyMedium.copyWith(color: Colors.white),
                  ),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    if (widget.onSubmitFeedback != null) {
                      await widget.onSubmitFeedback!(
                        reason,
                        'Reported incorrect identification for ${widget.candidate.formattedTitle}. Issue: $reason',
                      );
                    }
                    if (mounted) {
                      setState(() => _submitted = true);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Thank you! Feedback recorded for our numismatic team.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: AppRadius.allMd,
        ),
        child: Row(
          children: [
            Icon(
              _isCorrect == true ? Icons.thumb_up_rounded : Icons.check_circle_outline,
              color: AppColors.gold,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              _isCorrect == true
                  ? 'Thank you! Confirmation recorded.'
                  : 'Feedback received. Thank you!',
              style: AppTypography.captionSmall.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.inkElevated,
        borderRadius: AppRadius.allLg,
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Was this identification correct?',
              style: AppTypography.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _handleYes,
                icon: const Icon(Icons.thumb_up_outlined, size: 14),
                label: const Text('Yes'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _handleNo,
                icon: const Icon(Icons.thumb_down_outlined, size: 14),
                label: const Text('No'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
