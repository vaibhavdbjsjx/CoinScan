import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/storage/models.dart';
import '../../core/widgets/premium_widgets.dart';

class CompareScreen extends StatelessWidget {
  final CollectibleModel item1;
  final CollectibleModel item2;

  const CompareScreen({
    Key? key,
    required this.item1,
    required this.item2,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Compare Collectibles'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Headings side-by-side
            Row(
              children: [
                Expanded(child: _buildItemHeader(item1)),
                const SizedBox(width: 16),
                Expanded(child: _buildItemHeader(item2)),
              ],
            ),
            const SizedBox(height: 32),

            // Specs comparison table layout
            Table(
              border: const TableBorder(
                horizontalInside: BorderSide(color: AppColors.borderLight),
                bottom: BorderSide(color: AppColors.borderLight),
              ),
              children: [
                _buildCompareRow('Type', item1.type.name.toUpperCase(), item2.type.name.toUpperCase()),
                _buildCompareRow('Origin', item1.country, item2.country),
                _buildCompareRow('Year', '${item1.year < 0 ? '${item1.year.abs()} BC' : item1.year}', '${item2.year < 0 ? '${item2.year.abs()} BC' : item2.year}'),
                _buildCompareRow('Composition', item1.composition, item2.composition),
                _buildCompareRow('Weight', '${item1.weightG}g', '${item2.weightG}g'),
                _buildCompareRow('Diameter', '${item1.diameterMm}mm', '${item2.diameterMm}mm'),
                _buildCompareRow('Grade', item1.estimatedGrade, item2.estimatedGrade),
                _buildCompareRow('Rarity', item1.rarity.displayName, item2.rarity.displayName),
                _buildCompareRow(
                  'Retail Value', 
                  '\$${item1.retailPrice >= 1000 ? '${(item1.retailPrice / 1000).toStringAsFixed(1)}k' : item1.retailPrice}', 
                  '\$${item2.retailPrice >= 1000 ? '${(item2.retailPrice / 1000).toStringAsFixed(1)}k' : item2.retailPrice}'
                ),
                _buildCompareRow('Investment', item1.investmentRating, item2.investmentRating),
              ],
            ),
            
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: GoldButton(
                text: 'Dismiss',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemHeader(CollectibleModel item) {
    final isGold = item.composition.toLowerCase().contains('gold');
    return Column(
      children: [
        Container(
          height: 100,
          width: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: isGold
                  ? [AppColors.goldLight, AppColors.gold, AppColors.goldDark]
                  : [Colors.white, AppColors.border, AppColors.textSecondary],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
              )
            ],
          ),
          child: Center(
            child: Icon(
              item.type == CollectibleType.coin ? Icons.monetization_on : Icons.note,
              color: isGold ? Colors.white.withOpacity(0.8) : AppColors.textPrimary.withOpacity(0.3),
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          item.name,
          style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  TableRow _buildCompareRow(String label, String val1, String val2) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      val1, 
                      style: AppTypography.bodyMedium,
                      textAlign: TextAlign.left,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      val2, 
                      style: AppTypography.bodyMedium.copyWith(
                        color: val1 == val2 ? AppColors.textPrimary : AppColors.goldDark,
                        fontWeight: val1 == val2 ? FontWeight.normal : FontWeight.bold,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
