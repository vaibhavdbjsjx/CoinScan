import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';

/// In-app Help & Support Center.
///
/// Communicates honest numismatic guidelines, two-sided capture necessity,
/// confidence score interpretations, and valuation disclaimers.
class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Help & Support', style: AppTypography.titleMedium),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.base,
        ),
        children: [
          const _HelpSection(
            title: 'Scanning & Identification',
            items: [
              _HelpItem(
                question: 'Why does CoinScan require both sides of the coin?',
                answer:
                    'Coins are minted from two distinct master dies: the obverse (front) and reverse (back). '
                    'Many countries share identical portrait designs across multiple denominations, or repeat motifs '
                    'across different centuries. Capturing both sides allows CoinScan to verify die consistency, cross-reference '
                    'inscriptions with catalogue records, and detect mules, fantasies, or counterfeit mismatches.',
              ),
              _HelpItem(
                question: 'How do I improve scan accuracy?',
                answer:
                    '• Place your coin on a neutral, solid-color background.\n'
                    '• Ensure diffuse, even lighting to avoid heavy glare on reflective surfaces.\n'
                    '• Hold the camera parallel to the coin face rather than at an angle.\n'
                    '• Avoid casting shadows across the coin inscriptions.',
              ),
              _HelpItem(
                question: 'What does the Confidence percentage mean?',
                answer:
                    'Confidence represents a transparent multi-signal score combining:\n'
                    '1. Visual AI feature agreement (obverse and reverse alignment)\n'
                    '2. High-precision OCR matching of dates, denominations, and mint marks\n'
                    '3. Numista catalogue physical specification alignment\n\n'
                    'A score above 85% indicates a high-certainty match, while lower scores signify rare varieties or heavily worn coins requiring manual verification.',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const _HelpSection(
            title: 'Valuation & Pricing',
            items: [
              _HelpItem(
                question: 'Are CoinScan valuations guaranteed?',
                answer:
                    'No. All market values provided in CoinScan are automated numismatic estimates for informational purposes only. '
                    'Coin prices fluctuate based on exact Sheldon condition grades (e.g. MS63 vs MS65), toning, strike quality, '
                    'and live auction demand. For rare or high-value coins, always consult a certified professional numismatist.',
              ),
              _HelpItem(
                question: 'Why is valuation unavailable for some coins?',
                answer:
                    'If a coin is made of base metal (e.g. modern zinc/copper) and lacks sufficient recent verified auction '
                    'records for its specific condition, CoinScan displays "Value unavailable" rather than fabricating an artificial price.',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          _HelpSection(
            title: 'Subscriptions & Quotas',
            items: [
              const _HelpItem(
                question: 'When do daily scan quotas reset?',
                answer:
                    'Daily scan limits reset automatically at 00:00:00 UTC worldwide.',
              ),
              _HelpItem(
                question: 'How do I restore my subscription?',
                answer:
                    'Open Settings → Account → Restore Purchases. As long as you are signed into the same '
                    '${(!kIsWeb && Platform.isAndroid) ? 'Google Play account' : 'Apple ID'}, '
                    'your active Plus or Pro subscription will restore immediately.',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  final String title;
  final List<_HelpItem> items;

  const _HelpSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.titleSmall.copyWith(color: AppColors.gold),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...items,
      ],
    );
  }
}

class _HelpItem extends StatelessWidget {
  final String question;
  final String answer;

  const _HelpItem({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.cardBg,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.allMd,
        side: BorderSide(color: AppColors.border, width: 0.5),
      ),
      child: ExpansionTile(
        title: Text(question, style: AppTypography.bodyMedium),
        iconColor: AppColors.gold,
        collapsedIconColor: AppColors.textMuted,
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.base,
          0,
          AppSpacing.base,
          AppSpacing.base,
        ),
        children: [
          Text(
            answer,
            style: AppTypography.bodyMuted.copyWith(
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
