import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';

/// Market Explorer screen providing numismatic market trends, bullion benchmarks,
/// and price guide reference data.
///
/// Complies with Apple App Store Guideline 2.2 and Google Play policies by
/// clearly labeling upcoming marketplace transactions as "Coming Soon" and
/// avoiding any simulated or mock payment/escrow flows.
class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  bool _notificationSubscribed = false;
  String _selectedCategory = 'all';

  static const List<_MarketBenchmark> _benchmarks = [
    _MarketBenchmark(
      symbol: 'XAU',
      name: 'Gold Spot Benchmark',
      priceDisplay: '—',
      changeDisplay: 'No live feed',
      description: 'Fine gold spot rate (troy oz)',
      icon: Icons.monetization_on_rounded,
      color: AppColors.gold,
    ),
    _MarketBenchmark(
      symbol: 'XAG',
      name: 'Silver Spot Benchmark',
      priceDisplay: '—',
      changeDisplay: 'No live feed',
      description: 'Fine silver spot rate (troy oz)',
      icon: Icons.circle_outlined,
      color: Color(0xFFC0C0C0),
    ),
    _MarketBenchmark(
      symbol: 'XPT',
      name: 'Platinum Benchmark',
      priceDisplay: '—',
      changeDisplay: 'No live feed',
      description: 'Pure platinum spot rate (troy oz)',
      icon: Icons.diamond_outlined,
      color: Color(0xFF90CAF9),
    ),
  ];

  static const List<_PriceGuideSeries> _seriesGuides = [
    _PriceGuideSeries(
      id: 'morgan',
      category: 'us_silver',
      name: 'Morgan Silver Dollar',
      years: '1878 – 1921',
      composition: '90% Silver, 10% Copper',
      typicalGrade: 'VF-20 to MS-65',
      catalogRange: '\$35 – \$1,200+',
      trendStatus: 'Strong Collector Demand',
      notableKeys: '1889-CC, 1893-S, 1895 Proof',
    ),
    _PriceGuideSeries(
      id: 'peace',
      category: 'us_silver',
      name: 'Peace Silver Dollar',
      years: '1921 – 1935',
      composition: '90% Silver, 10% Copper',
      typicalGrade: 'XF-40 to MS-64',
      catalogRange: '\$30 – \$450+',
      trendStatus: 'Stable Liquidity',
      notableKeys: '1921 High Relief, 1928 Philadelphia',
    ),
    _PriceGuideSeries(
      id: 'saint_gaudens',
      category: 'us_gold',
      name: 'Saint-Gaudens \$20 Double Eagle',
      years: '1907 – 1933',
      composition: '90% Gold, 10% Copper',
      typicalGrade: 'AU-55 to MS-66',
      catalogRange: '\$2,650 – \$15,000+',
      trendStatus: 'Bullion-Linked Growth',
      notableKeys: '1907 High Relief, 1927-D',
    ),
    _PriceGuideSeries(
      id: 'sovereign',
      category: 'world_gold',
      name: 'British Gold Sovereign',
      years: '1817 – Present',
      composition: '22 Karat (91.67% Gold)',
      typicalGrade: 'EF-45 to MS-64',
      catalogRange: '\$620 – \$2,500+',
      trendStatus: 'High Global Liquidity',
      notableKeys: '1819 George III, 1917 London',
    ),
    _PriceGuideSeries(
      id: 'athenian_owl',
      category: 'ancient',
      name: 'Athenian Owl Tetradrachm',
      years: 'c. 454 – 404 BC',
      composition: 'Fine Silver (~17.2g)',
      typicalGrade: 'Fine to Choice AU',
      catalogRange: '\$750 – \$4,500+',
      trendStatus: 'Historic High Interest',
      notableKeys: 'Archaic transitional issues',
    ),
    _PriceGuideSeries(
      id: 'walking_liberty',
      category: 'us_silver',
      name: 'Walking Liberty Half Dollar',
      years: '1916 – 1947',
      composition: '90% Silver, 10% Copper',
      typicalGrade: 'VG-8 to MS-65',
      catalogRange: '\$14 – \$650+',
      trendStatus: 'Popular Type Coin',
      notableKeys: '1921, 1921-D, 1921-S',
    ),
  ];

  List<_PriceGuideSeries> get _filteredSeries {
    if (_selectedCategory == 'all') return _seriesGuides;
    return _seriesGuides.where((s) => s.category == _selectedCategory).toList();
  }

  void _handleNotifyToggle() {
    setState(() {
      _notificationSubscribed = !_notificationSubscribed;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.inkElevated,
        content: Text(
          _notificationSubscribed
              ? 'You will be notified when verified peer-to-peer trading launches.'
              : 'Trading launch notifications cancelled.',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.gold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Market Explorer'),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.base,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildComingSoonBanner(),
            const SizedBox(height: AppSpacing.xl),
            _buildSectionHeader('PRECIOUS METALS SPOT BENCHMARKS'),
            const SizedBox(height: AppSpacing.xs),
            _buildDataNotice(
              'Live spot prices are not connected yet, so no prices are shown.',
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildBenchmarksGrid(),
            const SizedBox(height: AppSpacing.xxl),
            _buildSectionHeader('NUMISMATIC PRICE GUIDES & CATALOG TRENDS'),
            const SizedBox(height: AppSpacing.xs),
            _buildDataNotice(
              'Static reference ranges for general education only — not live market prices and not a valuation of your coin.',
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildCategoryFilter(),
            const SizedBox(height: AppSpacing.base),
            ..._buildSeriesCards(),
            const SizedBox(height: AppSpacing.xxl),
            _buildGradingScaleReference(),
            const SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
    );
  }

  Widget _buildDataNotice(String text) {
    return Text(
      text,
      style: AppTypography.captionSmall.copyWith(color: AppColors.textMuted),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: AppTypography.goldLabel.copyWith(
        color: AppColors.textMuted,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildComingSoonBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.inkElevated,
        borderRadius: AppRadius.allLg,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
        boxShadow: AppShadows.goldGlow(opacity: 0.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.15),
                  borderRadius: AppRadius.allPill,
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'COMING IN UPCOMING RELEASE',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.storefront_outlined, color: AppColors.gold, size: 24),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Verified Collector Marketplace',
            style: AppTypography.titleMedium.copyWith(color: AppColors.textOnInk),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Direct collector acquisitions, accredited dealer storefronts, and certified slab '
            'trading are currently in active preparation. To ensure community safety, all transactions '
            'will be governed by third-party authenticity guarantees.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textOnInkMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _handleNotifyToggle,
                  icon: Icon(
                    _notificationSubscribed
                        ? Icons.check_circle_rounded
                        : Icons.notifications_active_outlined,
                    size: 18,
                    color: AppColors.gold,
                  ),
                  label: Text(
                    _notificationSubscribed
                        ? 'Notification Saved'
                        : 'Notify Me When Available',
                    style: AppTypography.buttonTextSmall.copyWith(
                      color: AppColors.gold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.gold),
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBenchmarksGrid() {
    return Column(
      children: _benchmarks.map((bm) {
        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.allMd,
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bm.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(bm.icon, color: bm.color, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bm.name, style: AppTypography.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      bm.description,
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    bm.priceDisplay,
                    style: AppTypography.numericMedium.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    bm.changeDisplay,
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCategoryFilter() {
    final categories = [
      ('all', 'All Series'),
      ('us_silver', 'US Silver'),
      ('us_gold', 'US Gold'),
      ('world_gold', 'World Gold'),
      ('ancient', 'Ancient Coins'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((cat) {
          final isSelected = _selectedCategory == cat.$1;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              label: Text(cat.$2),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedCategory = cat.$1),
              selectedColor: AppColors.gold,
              backgroundColor: AppColors.surface,
              labelStyle: TextStyle(
                color: isSelected ? AppColors.onGold : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? AppColors.gold : AppColors.borderLight,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Widget> _buildSeriesCards() {
    final series = _filteredSeries;
    return series.map((s) {
      return Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.allMd,
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    s.name,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  s.catalogRange,
                  style: AppTypography.numericMedium.copyWith(
                    color: AppColors.goldDark,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${s.years} • ${s.composition}',
              style: AppTypography.captionSmall.copyWith(color: AppColors.textMuted),
            ),
            const Divider(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Typical Grades', style: AppTypography.captionSmall),
                      const SizedBox(height: 2),
                      Text(s.typicalGrade, style: AppTypography.bodyMedium),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Market Status', style: AppTypography.captionSmall),
                      const SizedBox(height: 2),
                      Text(
                        s.trendStatus,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.emerald,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Key Dates: ${s.notableKeys}',
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildGradingScaleReference() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.allMd,
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined, color: AppColors.goldDark, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Numismatic Grading Scale Reference',
                style: AppTypography.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'CoinScan identification guides reference standard international 70-point '
            'Sheldon scale designations:\n'
            '• G-4 to VG-8: Heavy design wear with visible rims.\n'
            '• F-12 to VF-20: Moderate wear with prominent major details intact.\n'
            '• XF-40 to AU-58: Light friction on high points; original mint luster emerging.\n'
            '• MS-60 to MS-70: Mint State uncirculated with no post-strike wear.\n\n'
            'Disclaimer: Values shown are catalogue reference benchmarks for informational '
            'purposes only and do not constitute an appraisal, valuation warranty, or commercial offer.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketBenchmark {
  final String symbol;
  final String name;
  final String priceDisplay;
  final String changeDisplay;
  final String description;
  final IconData icon;
  final Color color;

  const _MarketBenchmark({
    required this.symbol,
    required this.name,
    required this.priceDisplay,
    required this.changeDisplay,
    required this.description,
    required this.icon,
    required this.color,
  });
}

class _PriceGuideSeries {
  final String id;
  final String category;
  final String name;
  final String years;
  final String composition;
  final String typicalGrade;
  final String catalogRange;
  final String trendStatus;
  final String notableKeys;

  const _PriceGuideSeries({
    required this.id,
    required this.category,
    required this.name,
    required this.years,
    required this.composition,
    required this.typicalGrade,
    required this.catalogRange,
    required this.trendStatus,
    required this.notableKeys,
  });
}
