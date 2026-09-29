import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/storage/scan_history_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';

/// Screen displaying the user's scan history with coin thumbnails,
/// identification results, and confidence scores.
class ScanHistoryScreen extends StatefulWidget {
  final ScanHistoryService historyService;

  const ScanHistoryScreen({
    super.key,
    required this.historyService,
  });

  @override
  State<ScanHistoryScreen> createState() => _ScanHistoryScreenState();
}

class _ScanHistoryScreenState extends State<ScanHistoryScreen> {
  List<ScanRecord> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final records = await widget.historyService.loadHistory();
    if (mounted) {
      setState(() {
        _records = records.toList();
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteRecord(ScanRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Scan'),
        content: Text(
          'Remove "${record.coinName ?? "Unknown coin"}" from history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: AppColors.crimson)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.historyService.deleteRecord(record.id);
      await _loadHistory();
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text('Delete all scan records? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear All', style: TextStyle(color: AppColors.crimson)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.historyService.clearHistory();
      await _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Scan History', style: AppTypography.sectionHeader),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : _records.isEmpty
              ? _buildEmptyState()
              : _buildHistoryList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.history_rounded,
            size: 64,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            'No scans yet',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your coin scan results will appear here.',
            style: AppTypography.bodyMuted,
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.md,
      ),
      itemCount: _records.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final record = _records[index];
        return _buildHistoryCard(record, index);
      },
    );
  }

  Widget _buildHistoryCard(ScanRecord record, int index) {
    final hasImage = record.frontImagePath != null &&
        !kIsWeb &&
        File(record.frontImagePath!).existsSync();
    final confidencePct = record.confidenceScore != null
        ? '${(record.confidenceScore! * 100).toInt()}%'
        : null;

    return Dismissible(
      key: ValueKey(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        decoration: const BoxDecoration(
          color: AppColors.crimson,
          borderRadius: AppRadius.allMd,
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        await _deleteRecord(record);
        return false; // We handle deletion manually
      },
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: AppRadius.allMd,
          boxShadow: AppShadows.level1,
        ),
        child: InkWell(
          borderRadius: AppRadius.allMd,
          onTap: () => _showRecordDetail(record),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                // Thumbnail
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadius.allSm,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasImage
                      ? Image.file(
                          File(record.frontImagePath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.monetization_on_outlined,
                            color: AppColors.gold,
                          ),
                        )
                      : const Icon(
                          Icons.monetization_on_outlined,
                          color: AppColors.gold,
                        ),
                ),
                const SizedBox(width: AppSpacing.md),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.coinName ?? 'Unknown Coin',
                        style: AppTypography.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (record.country != null) record.country,
                          if (record.year != null) record.year,
                          if (record.denomination != null) record.denomination,
                        ].join(' · '),
                        style: AppTypography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(record.scannedAt),
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                // Confidence badge
                if (confidencePct != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _confidenceColor(record.confidenceScore!)
                          .withValues(alpha: 0.12),
                      borderRadius: AppRadius.allPill,
                    ),
                    child: Text(
                      confidencePct,
                      style: AppTypography.numericSmall.copyWith(
                        color: _confidenceColor(record.confidenceScore!),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(
          delay: Duration(milliseconds: 50 * index),
          duration: AppDuration.fast,
        )
        .slideX(
          begin: 0.05,
          end: 0,
          delay: Duration(milliseconds: 50 * index),
          duration: AppDuration.fast,
        );
  }

  void _showRecordDetail(ScanRecord record) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: const BoxDecoration(
                  color: AppColors.border,
                  borderRadius: AppRadius.allPill,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              record.coinName ?? 'Unknown Coin',
              style: AppTypography.sectionHeader,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (record.numistaNumber != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    const Icon(Icons.verified_outlined,
                        size: 14, color: AppColors.gold),
                    const SizedBox(width: 6),
                    Text(
                      'Numista N# ${record.numistaNumber}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.goldInk,
                      ),
                    ),
                  ],
                ),
              ),
            _detailRow('Country', record.country ?? '—'),
            _detailRow('Year', record.year ?? '—'),
            _detailRow('Denomination', record.denomination ?? '—'),
            _detailRow('Status', record.statusLabel ?? '—'),
            if (record.confidenceScore != null)
              _detailRow(
                'Confidence',
                '${(record.confidenceScore! * 100).toInt()}%',
              ),
            _detailRow('Scanned', _formatDate(record.scannedAt)),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.caption),
          Flexible(
            child: Text(
              value,
              style: AppTypography.bodyMedium,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Color _confidenceColor(double score) {
    if (score >= 0.8) return AppColors.emerald;
    if (score >= 0.5) return AppColors.amber;
    return AppColors.crimson;
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}
