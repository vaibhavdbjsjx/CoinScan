import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/reports/coin_report_service.dart';
import '../../core/storage/collection_storage_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/pdf_generator.dart';
import '../../core/widgets/premium_widgets.dart';

/// Detail view for a coin saved in the user's vault.
///
/// Shows only what was recorded for this coin: the photos, the identification
/// and evidence captured at scan time, catalogue specifications, recorded
/// values, and the owner's own notes. Nothing is inferred: there is no rarity
/// meter, price history, generated timeline or authenticity score, because no
/// verified source for them exists.
class CollectionDetailScreen extends StatefulWidget {
  final VaultCoinItem vaultItem;

  const CollectionDetailScreen({super.key, required this.vaultItem});

  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  static const _storageOptions = [
    'Home Vault',
    'Safe Deposit Box A',
    'Safe Deposit Box B',
    'Display Cabinet',
  ];

  final _purchasePriceController = TextEditingController();
  final _notesController = TextEditingController();
  late String _storageLocation;
  bool _showFront = true;
  bool _isSaving = false;
  late VaultCoinItem _item;

  @override
  void initState() {
    super.initState();
    _item = widget.vaultItem;
    // Only a price the user actually entered; never pre-fill an estimate
    // that would then be saved as if it were the real purchase price.
    _purchasePriceController.text = _item.purchasePrice != null
        ? _item.purchasePrice!.toStringAsFixed(2)
        : '';
    _notesController.text = _item.notes ?? '';
    final stored = _item.storageLocation;
    _storageLocation = (stored != null && _storageOptions.contains(stored))
        ? stored
        : _storageOptions.first;
  }

  @override
  void dispose() {
    _purchasePriceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    final priceText = _purchasePriceController.text.trim();
    final price = priceText.isEmpty ? null : double.tryParse(priceText);
    if (priceText.isNotEmpty && (price == null || price < 0)) {
      AppSnack.show(context, 'Enter a valid purchase price.', tone: SnackTone.error);
      return;
    }
    setState(() => _isSaving = true);
    final updated = _item.copyWith(
      purchasePrice: price,
      storageLocation: _storageLocation,
      notes: _notesController.text.trim(),
    );
    try {
      await CollectionStorageService.instance.saveItem(updated);
      if (!mounted) return;
      setState(() => _item = updated);
      AppSnack.show(context, 'Changes saved.', tone: SnackTone.success);
    } catch (_) {
      if (!mounted) return;
      AppSnack.show(
        context,
        'Your changes could not be saved. Check your connection and try again.',
        tone: SnackTone.error,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteFromVault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from vault?'),
        content: Text('"${_item.coinName}" will be removed from your vault.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: AppColors.crimson)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await CollectionStorageService.instance.deleteItem(_item.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      AppSnack.show(
        context,
        'The coin could not be removed. Check your connection and try again.',
        tone: SnackTone.error,
      );
    }
  }

  Future<void> _exportPdf() async {
    try {
      final file = await PdfGenerator.generateIdentificationReport(
        CoinReportData.fromVaultItem(_item),
        purchasePrice: _item.purchasePrice,
        purchaseCurrency: _item.currencyCode,
        storageLocation: _item.storageLocation,
        notes: _item.notes,
      );
      if (!mounted) return;
      AppSnack.show(
        context,
        'Report saved: ${file.path.split('/').last}',
        tone: SnackTone.success,
      );
    } catch (_) {
      if (!mounted) return;
      AppSnack.show(context, 'The report could not be created.', tone: SnackTone.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final subtitle = [
      item.country,
      if (item.year != null)
        item.year! < 0 ? '${item.year!.abs()} BC' : '${item.year}',
      item.denomination,
    ].join(' • ');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Coin details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export identification report',
            onPressed: _exportPdf,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.crimson),
            tooltip: 'Remove from vault',
            onPressed: _deleteFromVault,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.base,
            AppSpacing.xl,
            AppSpacing.huge,
          ),
          children: [
            _PhotoPanel(
              item: item,
              showFront: _showFront,
              onToggle: (front) => setState(() => _showFront = front),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(item.coinName, style: AppTypography.sectionHeader.copyWith(fontSize: 22)),
            const SizedBox(height: AppSpacing.xs),
            Text(subtitle, style: AppTypography.bodyMuted),
            const SizedBox(height: AppSpacing.xl),
            _IdentificationCard(item: item),
            const SizedBox(height: AppSpacing.base),
            _ValueCard(item: item),
            const SizedBox(height: AppSpacing.base),
            _CatalogueCard(item: item),
            if ((item.conditionEstimate ?? item.grade)?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: AppSpacing.base),
              _DetailCard(
                icon: Icons.workspace_premium_outlined,
                title: 'Condition',
                children: [
                  _KeyValue('Recorded condition', (item.conditionEstimate ?? item.grade)!),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'A photo-based estimate, not a professional grade.',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.base),
            _DetailCard(
              icon: Icons.edit_note_rounded,
              title: 'Your records',
              children: [
                Text('Purchase price (${item.currencyCode})', style: AppTypography.caption),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  key: const ValueKey('purchase_price_field'),
                  controller: _purchasePriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: 'Not recorded'),
                ),
                const SizedBox(height: AppSpacing.base),
                Text('Storage location', style: AppTypography.caption),
                const SizedBox(height: AppSpacing.xs),
                DropdownButtonFormField<String>(
                  initialValue: _storageLocation,
                  items: [
                    for (final loc in _storageOptions)
                      DropdownMenuItem(value: loc, child: Text(loc)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _storageLocation = v);
                  },
                ),
                const SizedBox(height: AppSpacing.base),
                Text('Notes', style: AppTypography.caption),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: _notesController,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(hintText: 'Add your own notes'),
                ),
                const SizedBox(height: AppSpacing.lg),
                GoldButton(
                  text: 'Save changes',
                  isLoading: _isSaving,
                  onPressed: _isSaving ? null : _saveChanges,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats a recorded amount with its currency, or an em dash when none exists.
String formatVaultAmount(double? amount, String currencyCode) {
  if (amount == null || amount.isNaN || amount.isInfinite || amount <= 0) {
    return '—';
  }
  if (currencyCode.toUpperCase() == 'USD') return '\$${amount.toStringAsFixed(2)}';
  return '${amount.toStringAsFixed(2)} ${currencyCode.toUpperCase()}';
}

class _PhotoPanel extends StatelessWidget {
  final VaultCoinItem item;
  final bool showFront;
  final ValueChanged<bool> onToggle;

  const _PhotoPanel({required this.item, required this.showFront, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final path = showFront ? item.frontImagePath : item.reverseImagePath;
    final hasPhoto = !kIsWeb && path != null && path.isNotEmpty && File(path).existsSync();
    final hasReverse = item.reverseImagePath != null && item.reverseImagePath!.isNotEmpty;

    return Column(
      children: [
        Container(
          height: 240,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surfaceWarm,
            borderRadius: AppRadius.allXl,
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: hasPhoto
              ? Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const _NoPhoto(),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CoinGlyph.forComposition(
                      size: 120,
                      composition: item.composition ?? '',
                      isBanknote: false,
                      semanticLabel: 'Coin illustration',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const _NoPhoto(),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Front')),
            ButtonSegment(value: false, label: Text('Reverse')),
          ],
          selected: {showFront},
          onSelectionChanged: (s) => onToggle(s.first),
          showSelectedIcon: false,
        ),
        if (!hasReverse && !showFront)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text('No reverse photo was saved.', style: AppTypography.caption),
          ),
      ],
    );
  }
}

class _NoPhoto extends StatelessWidget {
  const _NoPhoto();

  @override
  Widget build(BuildContext context) =>
      Text('No photo available', style: AppTypography.caption);
}

class _IdentificationCard extends StatelessWidget {
  final VaultCoinItem item;

  const _IdentificationCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final level = item.confidenceLevel?.trim();
    return _DetailCard(
      icon: Icons.fact_check_outlined,
      title: 'Identification',
      children: [
        _KeyValue(
          'Identification confidence',
          (level == null || level.isEmpty) ? 'Not recorded' : level,
        ),
        const SizedBox(height: AppSpacing.md),
        if (item.keyEvidence.isEmpty)
          Text('No evidence details were saved with this coin.', style: AppTypography.caption)
        else ...[
          Text('Evidence recorded at scan time', style: AppTypography.caption),
          const SizedBox(height: AppSpacing.xs),
          for (final e in item.keyEvidence)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Icon(Icons.circle, size: 5, color: AppColors.goldDark),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(e, style: AppTypography.bodyMedium.copyWith(fontSize: 13))),
                ],
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'Authenticity: not assessed. Photo recognition identifies the coin type; '
          'it cannot authenticate coins or detect counterfeits.',
          style: AppTypography.caption,
        ),
      ],
    );
  }
}

class _ValueCard extends StatelessWidget {
  final VaultCoinItem item;

  const _ValueCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final code = item.currencyCode;
    return _DetailCard(
      icon: Icons.payments_outlined,
      title: 'Value',
      children: [
        Row(
          children: [
            _PriceMetric(
              label: 'Saved estimate',
              value: formatVaultAmount(item.currentEstimatedValue, code),
            ),
            const SizedBox(width: AppSpacing.md),
            _PriceMetric(label: 'Melt value', value: formatVaultAmount(item.meltValue, code)),
          ],
        ),
        if (item.valuationRange != null && item.valuationRange!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _KeyValue('Market range (at scan time)', item.valuationRange!),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'Values were recorded when you saved this coin and are not updated '
          'automatically. Melt value covers metal content only.',
          style: AppTypography.caption,
        ),
      ],
    );
  }
}

class _CatalogueCard extends StatelessWidget {
  final VaultCoinItem item;

  const _CatalogueCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (item.mintMark != null && item.mintMark!.isNotEmpty) ('Mint mark', item.mintMark!),
      if (item.composition != null && item.composition!.isNotEmpty)
        ('Composition', item.composition!),
      if (item.weightG != null && item.weightG! > 0) ('Weight', '${item.weightG} g'),
      if (item.diameterMm != null && item.diameterMm! > 0) ('Diameter', '${item.diameterMm} mm'),
      if (item.kmNumber != null && item.kmNumber!.isNotEmpty) ('Catalogue number', item.kmNumber!),
      if (item.numistaId != null) ('Numista', 'N# ${item.numistaId}'),
    ];
    return _DetailCard(
      icon: Icons.menu_book_rounded,
      title: 'Catalogue details',
      children: [
        if (rows.isEmpty)
          Text('No catalogue details were saved for this coin.', style: AppTypography.caption)
        else ...[
          for (final (label, value) in rows) _KeyValue(label, value),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Standard specifications for the matched coin type, not measurements of your coin.',
            style: AppTypography.caption,
          ),
        ],
      ],
    );
  }
}

class _DetailCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _DetailCard({required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: AppRadius.allLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.goldDark),
              const SizedBox(width: AppSpacing.sm),
              Text(title, style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ...children,
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  final String label;
  final String value;

  const _KeyValue(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: AppTypography.bodyMuted)),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceMetric extends StatelessWidget {
  final String label;
  final String value;

  const _PriceMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.allMd,
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.caption),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTypography.numericMedium.copyWith(fontSize: 17, color: AppColors.goldInk),
            ),
          ],
        ),
      ),
    );
  }
}
