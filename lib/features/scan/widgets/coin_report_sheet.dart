import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/reports/coin_report_service.dart';
import '../../../core/utils/pdf_generator.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';

/// Modal display of the shareable "My Coin Report".
class CoinReportSheet extends StatelessWidget {
  final CoinReportData report;

  const CoinReportSheet({super.key, required this.report});

  static void show(BuildContext context, CoinReportData report) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => CoinReportSheet(report: report),
    );
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: report.toShareableText()));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coin Report summary copied to clipboard!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _generatePdf(BuildContext context) async {
    try {
      final file = await PdfGenerator.generateCollectibleReport(
        report.toCollectibleModel(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.emerald,
            content: Text(
              'PDF Report saved: ${file.path.split('/').last}',
              style: const TextStyle(color: Colors.white),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.crimson,
            content: Text(
              'Failed to generate PDF: $e',
              style: const TextStyle(color: Colors.white),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'My Coin Report',
                    style: AppTypography.titleMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white12),

            // Scrollable Certificate Card
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: AppColors.inkElevated,
                      borderRadius: AppRadius.allXl,
                      border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // CoinScan Branding Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: AppColors.goldGradient,
                                  ),
                                  child: const Icon(
                                    Icons.toll_rounded,
                                    size: 16,
                                    color: AppColors.ink,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'COINSCAN',
                                  style: AppTypography.goldLabel.copyWith(
                                    fontSize: 13,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.emerald.withValues(alpha: 0.15),
                                borderRadius: AppRadius.allPill,
                                border: Border.all(
                                  color: AppColors.emerald.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                report.confidenceLevel,
                                style: AppTypography.captionSmall.copyWith(
                                  color: AppColors.emerald,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: AppSpacing.lg),

                        // Coin Title
                        Text(
                          report.title,
                          style: AppTypography.sectionHeader.copyWith(
                            color: Colors.white,
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${report.country} • ${report.denomination}',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textOnInkMuted,
                          ),
                        ),

                        // Optional Image thumbnail if available
                        if (!kIsWeb &&
                            report.frontImagePath != null &&
                            File(report.frontImagePath!).existsSync()) ...[
                          const SizedBox(height: AppSpacing.md),
                          ClipRRect(
                            borderRadius: AppRadius.allMd,
                            child: Image.file(
                              File(report.frontImagePath!),
                              height: 160,
                              width: double.infinity,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                        ],

                        const SizedBox(height: AppSpacing.lg),
                        const Divider(color: Colors.white12),
                        const SizedBox(height: AppSpacing.md),

                        // Specifications Grid
                        Wrap(
                          spacing: AppSpacing.xl,
                          runSpacing: AppSpacing.md,
                          children: [
                            if (report.year != null)
                              _buildSpec('Year', '${report.year}'),
                            if (report.mintMark != null)
                              _buildSpec('Mint Mark', report.mintMark!),
                            if (report.composition != null)
                              _buildSpec('Composition', report.composition!),
                            if (report.valuationRange != null)
                              _buildSpec('Estimated Range', report.valuationRange!),
                            if (report.numistaReference != null)
                              _buildSpec('Catalogue', report.numistaReference!),
                          ],
                        ),

                        if (report.keyEvidence.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          const Divider(color: Colors.white12),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Key Verified Evidence',
                            style: AppTypography.caption.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          for (final e in report.keyEvidence)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.check_rounded,
                                    size: 14,
                                    color: AppColors.gold,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      e,
                                      style: AppTypography.captionSmall.copyWith(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],

                        const SizedBox(height: AppSpacing.lg),
                        const Divider(color: Colors.white12),
                        const SizedBox(height: AppSpacing.sm),

                        // Footer Note
                        Text(
                          'CoinScan Personal Numismatics Assistant • coinscan.app',
                          style: AppTypography.captionSmall.copyWith(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Actions
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copyToClipboard(context),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy Summary'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _generatePdf(context),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: const Text('Export PDF'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.ink,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpec(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.captionSmall.copyWith(
            color: AppColors.textOnInkMuted,
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
    );
  }
}
