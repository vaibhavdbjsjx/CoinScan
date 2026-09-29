import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/recognition/recognition_models.dart';
import '../../../core/storage/collection_storage_service.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';

/// ---------------------------------------------------------------------------
/// 1. "WHY WE THINK THIS IS YOUR COIN" EVIDENCE SECTION
/// ---------------------------------------------------------------------------
class WhyWeThinkThisIsYourCoinWidget extends StatelessWidget {
  final RecognitionCandidate candidate;
  final bool hasReverseImage;

  const WhyWeThinkThisIsYourCoinWidget({
    super.key,
    required this.candidate,
    this.hasReverseImage = true,
  });

  @override
  Widget build(BuildContext context) {
    final id = candidate.identity;
    final evidenceCards = <_EvidenceItem>[];

    // 1. Date
    if (id.year != null) {
      evidenceCards.add(
        _EvidenceItem(
          icon: Icons.calendar_today_rounded,
          label: 'Date Detected',
          value: '${id.year}',
          detail: 'Year inscribed on obverse matches catalogue record.',
        ),
      );
    }

    // 2. Country & Design
    if (id.country.isNotEmpty && id.country != 'Unknown') {
      evidenceCards.add(
        _EvidenceItem(
          icon: Icons.account_balance_rounded,
          label: 'Issuing Country & Motif',
          value: id.country,
          detail: 'Portrait, heraldry, and national design elements align with official issue.',
        ),
      );
    }

    // 3. Denomination
    if (id.denomination.isNotEmpty && id.denomination != 'Unknown') {
      evidenceCards.add(
        _EvidenceItem(
          icon: Icons.monetization_on_outlined,
          label: 'Denomination',
          value: id.denomination,
          detail: 'Denomination text/numerals confirmed against issuing authority.',
        ),
      );
    }

    // 4. Mint Mark
    if (id.mint != null && id.mint!.isNotEmpty) {
      evidenceCards.add(
        _EvidenceItem(
          icon: Icons.label_important_outline_rounded,
          label: 'Mint / Facility Mark',
          value: 'Mint mark: ${id.mint}',
          detail: 'Identified branch mint insignia corresponds to recorded strike batches.',
        ),
      );
    } else {
      evidenceCards.add(
        const _EvidenceItem(
          icon: Icons.label_off_outlined,
          label: 'Mint Mark Status',
          value: 'No mint mark detected',
          detail: 'Consistent with main facility issues (e.g. Philadelphia / standard royal mint).',
        ),
      );
    }

    // 5. Composition
    if (id.composition != null && id.composition!.isNotEmpty) {
      evidenceCards.add(
        _EvidenceItem(
          icon: Icons.toll_rounded,
          label: 'Alloy Composition',
          value: id.composition!,
          detail: candidate.hasPreciousMetal
              ? 'Contains precious ${candidate.preciousMetalType} metal alloy.'
              : 'Base metal composition consistent with circulating specification.',
        ),
      );
    }

    // 6. Diameter
    if (id.diameterMm != null) {
      evidenceCards.add(
        _EvidenceItem(
          icon: Icons.straighten_rounded,
          label: 'Standard Diameter',
          value: '${id.diameterMm} mm',
          detail: 'Conforms to official minting planchet diameter.',
        ),
      );
    }

    // 7. Weight
    if (id.weightG != null) {
      evidenceCards.add(
        _EvidenceItem(
          icon: Icons.scale_rounded,
          label: 'Standard Struck Weight',
          value: '${id.weightG} g',
          detail: 'Official legal weight standard for this issue.',
        ),
      );
    }

    // 8. Obverse / Reverse Die Concordance
    evidenceCards.add(
      _EvidenceItem(
        icon: Icons.sync_alt_rounded,
        label: 'Die Alignment Concordance',
        value: hasReverseImage ? 'Dual-die confirmed' : 'Single-die visual match',
        detail: hasReverseImage
            ? 'Front portrait and reverse device belong to matching die pairings.'
            : 'Front design matched. Scan reverse side for full dual-die verification.',
      ),
    );

    // 9. Catalogue Reference
    if (id.numistaId != null || id.kmNumber != null) {
      final cat = [
        if (id.numistaId != null) 'Numista N# ${id.numistaId}',
        if (id.kmNumber != null) id.kmNumber!,
      ].join(' • ');
      evidenceCards.add(
        _EvidenceItem(
          icon: Icons.menu_book_rounded,
          label: 'Numismatic Catalogue Reference',
          value: cat,
          detail: 'Verified against international standard numismatic records.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.verified_outlined, color: AppColors.gold, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Why we think this is your coin',
                style: AppTypography.titleSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Evidence verified directly from your photograph against numismatic catalogue records.',
          style: AppTypography.captionSmall.copyWith(
            color: AppColors.textOnInkMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final item in evidenceCards) ...[
          _buildEvidenceCard(item),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  Widget _buildEvidenceCard(_EvidenceItem item) {
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
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(item.icon, color: AppColors.gold, size: 16),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      flex: 2,
                      child: Text(
                        item.label,
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textOnInkMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 3,
                      child: Text(
                        item.value,
                        style: AppTypography.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  item.detail,
                  style: AppTypography.captionSmall.copyWith(
                    color: Colors.white70,
                    height: 1.3,
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

class _EvidenceItem {
  final IconData icon;
  final String label;
  final String value;
  final String detail;

  const _EvidenceItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });
}

/// ---------------------------------------------------------------------------
/// 2. HONEST CONFIDENCE SYSTEM
/// ---------------------------------------------------------------------------
class HonestConfidenceCard extends StatelessWidget {
  final RecognitionConfidence confidence;

  const HonestConfidenceCard({super.key, required this.confidence});

  @override
  Widget build(BuildContext context) {
    final (badgeLabel, badgeColor, icon) = switch (confidence.level) {
      ConfidenceLevel.high => (
        'HIGH CONFIDENCE',
        AppColors.emerald,
        Icons.check_circle_rounded,
      ),
      ConfidenceLevel.medium => (
        'MEDIUM CONFIDENCE',
        AppColors.gold,
        Icons.info_outline_rounded,
      ),
      ConfidenceLevel.low => (
        'LOW CONFIDENCE',
        AppColors.amber,
        Icons.help_outline_rounded,
      ),
      ConfidenceLevel.indeterminate => (
        'UNCERTAIN',
        Colors.white60,
        Icons.warning_amber_rounded,
      ),
    };

    final pct = (confidence.overallScore * 100).toInt();

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.16),
                    borderRadius: AppRadius.allPill,
                    border: Border.all(color: badgeColor.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: badgeColor),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          badgeLabel,
                          style: AppTypography.captionSmall.copyWith(
                            color: badgeColor,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$pct% Evidence Match',
                style: AppTypography.captionSmall.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            confidence.honestExplanation,
            style: AppTypography.bodyMedium.copyWith(
              color: Colors.white,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(color: Colors.white12),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              _buildBar('Visual Motif', confidence.visualScore, badgeColor),
              const SizedBox(width: 8),
              _buildBar('Inscriptions & OCR', confidence.ocrScore, badgeColor),
              const SizedBox(width: 8),
              _buildBar('Catalogue Concordance', confidence.metadataScore, badgeColor),
            ],
          ),
          if (confidence.level != ConfidenceLevel.high) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: AppRadius.allMd,
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline_rounded, size: 14, color: AppColors.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      confidence.level == ConfidenceLevel.medium
                          ? 'Tip: Capturing the reverse side or a steady close-up of the date & mint mark will resolve candidate ambiguity.'
                          : 'Tip: Reposition the coin flat under diffused light to eliminate surface glare and reveal subtle die inscriptions.',
                      style: AppTypography.captionSmall.copyWith(
                        color: Colors.white70,
                        fontSize: 10.5,
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

  Widget _buildBar(String label, double score, Color color) {
    final pct = (score * 100).toInt();
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textOnInkMuted,
              fontSize: 10,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$pct%',
                style: AppTypography.captionSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: score.clamp(0.0, 1.0),
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 3,
            ),
          ),
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
              Row(
                children: [
                  const Icon(Icons.price_change_outlined, color: AppColors.gold, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Transparent Valuation',
                    style: AppTypography.titleSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
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
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
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
    final comp = id.composition?.toLowerCase() ?? '';

    if (comp.contains('gold')) {
      reasons.add('Contains gold precious metal alloy with substantial intrinsic bullion value.');
    } else if (comp.contains('silver')) {
      reasons.add('Contains historic silver alloy with melt valuation protection.');
    } else if (comp.contains('platinum')) {
      reasons.add('Rare platinum composition issue.');
    }

    if (id.mint != null && id.mint!.isNotEmpty) {
      final m = id.mint!.toUpperCase();
      if (m == 'CC' || m == 'CARSON CITY') {
        reasons.add('Carson City ("CC") mint issues are historically scarce and avidly collected.');
      } else if (m == 'S' || m == 'SAN FRANCISCO') {
        reasons.add('San Francisco ("S") mint mark identified. Inspect strike sharpness.');
      } else if (m == 'D' || m == 'DENVER' || m == 'DAHLONEGA') {
        reasons.add('Branch mint strike ("D"). Verify date positioning.');
      } else if (m == 'O' || m == 'NEW ORLEANS') {
        reasons.add('Historic New Orleans ("O") Southern branch mint strike.');
      } else if (m == 'W' || m == 'WEST POINT') {
        reasons.add('West Point ("W") commemorative or special circulation issue.');
      }
    }

    if (id.year != null && id.year! < 1950) {
      reasons.add('Pre-1950 vintage specimen (${id.year}). Surviving population decreases significantly in higher preservation grades.');
    }

    final conf = candidate.confidence;
    if (conf != null && (conf.level == ConfidenceLevel.medium || conf.level == ConfidenceLevel.low)) {
      reasons.add('Unresolved die characteristics: verify mint mark or reverse lettering under 10x magnification to confirm exact catalogue variety.');
    }

    if (valuation?.marketMid != null && valuation!.marketMid! > 100) {
      reasons.add('Premium market estimate (\$${valuation!.marketMid!.toStringAsFixed(0)} ${valuation!.currencyCode}): may justify certified holder encapsulation if state of preservation is uncirculated.');
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
        ? 'Possibly worth investigating'
        : 'Probably not cost-effective';

    final color = isValuable ? AppColors.emerald : Colors.white60;
    final icon = isValuable ? Icons.check_circle_outline : Icons.cancel_outlined;

    final explanation = isValuable
        ? 'The coin\'s vintage, mint mark, or metal content suggests that professional evaluation could be worthwhile if visual condition is high.'
        : 'Professional grading submission fees typically range from \$25 to \$60 per coin. For common-date circulated issues, fees often exceed market value.';

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
              Text(
                title,
                style: AppTypography.bodyMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
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
          Text(
            'Was this identification correct?',
            style: AppTypography.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
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
