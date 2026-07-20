import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/premium_widgets.dart';
import '../../core/storage/models.dart';
import '../../core/network/mock_api.dart';
import '../../core/utils/pdf_generator.dart';

class CollectionDetailScreen extends StatefulWidget {
  final CollectibleModel collectible;

  const CollectionDetailScreen({
    Key? key,
    required this.collectible,
  }) : super(key: key);

  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  bool _isFrontView = true;
  String _selectedChartDuration = '1 Year';
  bool _hasPriceAlert = false;
  bool _isSavedInVault = false;
  String _selectedStudioBg = 'light';

  // Vault form state
  final _purchasePriceController = TextEditingController();
  final _purchaseLocationController = TextEditingController();
  final _notesController = TextEditingController();
  String _storageLocation = 'Home Vault';

  @override
  void initState() {
    super.initState();
    // Pre-populate if this is already in mock portfolio
    final portfolioItems = MockApi.getPortfolioItems();
    final matchIndex = portfolioItems.indexWhere((p) => p.collectible.id == widget.collectible.id);
    if (matchIndex != -1) {
      _isSavedInVault = true;
      final match = portfolioItems[matchIndex];
      _purchasePriceController.text = match.purchasePrice.toStringAsFixed(0);
      _purchaseLocationController.text = match.purchaseLocation;
      _notesController.text = match.notes;
      _storageLocation = match.storageLocation;
    } else {
      _purchasePriceController.text = (widget.collectible.retailPrice * 0.9).toStringAsFixed(0);
      _purchaseLocationController.text = 'Numismatic Dealer';
      _notesController.text = 'Scanned and identified using CoinVault AI.';
    }
  }

  @override
  void dispose() {
    _purchasePriceController.dispose();
    _purchaseLocationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _exportPdfReport() async {
    final double? price = _isSavedInVault ? double.tryParse(_purchasePriceController.text) : null;
    final String? storage = _isSavedInVault ? _storageLocation : null;
    final String? notesVal = _isSavedInVault ? _notesController.text : null;
    
    try {
      final file = await PdfGenerator.generateCollectibleReport(
        widget.collectible,
        purchasePrice: price,
        storageLocation: storage,
        notes: notesVal,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.emerald,
            content: Text(
              'PDF Report saved to: ${file.path.split('/').last}',
              style: AppTypography.buttonText,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.crimson,
            content: Text(
              'Error generating report: $e',
              style: AppTypography.buttonText,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.collectible;
    final prices = MockApi.getPriceHistory(c.id, _selectedChartDuration);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(c.type == CollectibleType.coin ? 'Coin Analysis' : 'Banknote Analysis'),
        actions: [
          IconButton(
            icon: Icon(
              _hasPriceAlert ? Icons.notifications_active : Icons.notifications_none,
              color: _hasPriceAlert ? AppColors.goldDark : AppColors.textPrimary,
            ),
            onPressed: () {
              setState(() {
                _hasPriceAlert = !_hasPriceAlert;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppColors.goldDark,
                  content: Text(
                    _hasPriceAlert ? 'Price alerts enabled for this item.' : 'Price alerts disabled.',
                    style: AppTypography.buttonText,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: _exportPdfReport,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Swipe between Front & Back Premium Visualizer
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isFrontView = !_isFrontView;
                      });
                    },
                    child: Container(
                      height: 260,
                      width: 260,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.borderLight, width: 1.5),
                        boxShadow: AppTheme.premiumShadow,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: PhotoStudioViewer(
                        backgroundType: _selectedStudioBg,
                        child: Container(
                          height: 180,
                          width: 180,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                          ),
                          child: CustomPaint(
                            painter: DetailedCoinGraphicPainter(
                              collectible: c,
                              isFront: _isFrontView,
                            ),
                          ),
                        ),
                      ),
                    )
                        .animate(key: ValueKey('coin_view_$_isFrontView'))
                        .flipH(duration: 400.ms),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.swap_horizontal_circle_outlined, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        _isFrontView ? 'FRONT SIDE (TAP TO SWIPE)' : 'REVERSE SIDE (TAP TO SWIPE)',
                        style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'PHOTO STUDIO BG FILTER',
                    style: AppTypography.goldLabel.copyWith(fontSize: 9, letterSpacing: 1),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: ['light', 'dark', 'velvet', 'wood', 'concrete'].map((bg) {
                      final isSel = _selectedStudioBg == bg;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedStudioBg = bg),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSel ? AppColors.gold : AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSel ? AppColors.gold : AppColors.borderLight,
                            ),
                          ),
                          child: Text(
                            bg.toUpperCase(),
                            style: AppTypography.caption.copyWith(
                              color: isSel ? Colors.white : AppColors.textSecondary,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 2. Primary Summary Information
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      c.category.toUpperCase(),
                      style: AppTypography.goldLabel,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(c.name, style: AppTypography.sectionHeader.copyWith(fontSize: 22)),
                  const SizedBox(height: 8),
                  Text(
                    '${c.country} • Minted in ${c.year < 0 ? '${c.year.abs()} BC' : c.year}',
                    style: AppTypography.bodyMuted,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 3. Rarity Score Visual Meter
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Rarity Level', style: AppTypography.caption),
                        Text(
                          c.rarity.displayName.toUpperCase(),
                          style: AppTypography.goldLabel.copyWith(fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Colored rating indicator bars
                    Row(
                      children: List.generate(6, (index) {
                        final val = _getRarityBarValue(c.rarity);
                        final isActive = index <= val;
                        return Expanded(
                          child: Container(
                            height: 6,
                            margin: EdgeInsets.only(right: index == 5 ? 0 : 4),
                            decoration: BoxDecoration(
                              color: isActive ? AppColors.gold : AppColors.border,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Rarity rating is based on surviving population estimates and frequency in public auction archives.',
                      style: AppTypography.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 4. Authenticity Analysis (Expert observations)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.verified_outlined, color: AppColors.emerald, size: 20),
                              const SizedBox(width: 8),
                              Text('Authenticity', style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.emeraldLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${(c.authenticityConfidence * 100).toStringAsFixed(0)}% Confidence',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.emerald,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'AI Engine observations & structural alignment checks:',
                        style: AppTypography.caption.copyWith(fontSize: 11),
                      ),
                      const SizedBox(height: 12),
                      ...c.authenticityReasons.map((reason) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 4.0),
                                child: Icon(Icons.check_circle_outline, color: AppColors.emerald, size: 14),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  reason,
                                  style: AppTypography.bodyMedium.copyWith(fontSize: 13, color: AppColors.textPrimary),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 5. Sheldon Coin Grading Scale Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.workspace_premium_outlined, color: AppColors.goldDark, size: 20),
                          const SizedBox(width: 8),
                          Text('Sheldon Grade Estimation', style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            height: 60,
                            width: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.gold.withOpacity(0.1),
                              border: Border.all(color: AppColors.gold, width: 1.5),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              c.estimatedGrade,
                              style: AppTypography.goldLabel.copyWith(fontSize: 18),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.estimatedGrade.startsWith('MS') ? 'Mint State Strike' : 'Circulated Condition',
                                  style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Estimated surface quality and strike grade matching certification requirements.',
                                  style: AppTypography.caption,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      Text(c.gradeExplanation, style: AppTypography.bodyMuted),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // 6. Valuation & Price Trends Chart
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Price Analysis', style: AppTypography.sectionHeader),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.emeraldLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Rating: ${c.investmentRating}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.emerald,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Pricing tags row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  _PriceMetric(label: 'Retail', value: '\$${c.retailPrice >= 1000 ? '${(c.retailPrice / 1000).toStringAsFixed(1)}k' : c.retailPrice}'),
                  const SizedBox(width: 12),
                  _PriceMetric(label: 'Auction', value: '\$${c.auctionPrice >= 1000 ? '${(c.auctionPrice / 1000).toStringAsFixed(1)}k' : c.auctionPrice}'),
                  const SizedBox(width: 12),
                  _PriceMetric(label: 'Dealer', value: '\$${c.dealerPrice >= 1000 ? '${(c.dealerPrice / 1000).toStringAsFixed(1)}k' : c.dealerPrice}'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Interactive Line Chart Container
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 240,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.borderLight),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Time selector
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: ['1 Month', '6 Months', '1 Year', '5 Years'].map((duration) {
                        final isSel = _selectedChartDuration == duration;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedChartDuration = duration;
                            });
                          },
                          child: Text(
                            duration,
                            style: AppTypography.caption.copyWith(
                              color: isSel ? AppColors.goldDark : AppColors.textSecondary,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 28),

                    // Chart viewport
                    Expanded(
                      child: LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: List.generate(prices.length, (idx) {
                                return FlSpot(idx.toDouble(), prices[idx]);
                              }),
                              isCurved: true,
                              color: AppColors.gold,
                              barWidth: 4,
                              isStrokeCapRound: true,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: AppColors.gold.withOpacity(0.08),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // 7. Full Specifications Table
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('Technical Specifications', style: AppTypography.sectionHeader),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Table(
                border: const TableBorder(
                  bottom: BorderSide(color: AppColors.borderLight),
                  horizontalInside: BorderSide(color: AppColors.borderLight),
                ),
                children: [
                  _buildSpecRow('Country / Origin', c.country),
                  _buildSpecRow('Year of Issue', '${c.year < 0 ? '${c.year.abs()} BC' : c.year}'),
                  _buildSpecRow('Nominal Value', c.denomination),
                  _buildSpecRow('Metal / Purity', c.composition),
                  _buildSpecRow('Actual Weight', '${c.weightG} g'),
                  _buildSpecRow('Diameter', '${c.diameterMm} mm'),
                  _buildSpecRow('Thickness', '${c.thicknessMm} mm'),
                  _buildSpecRow('Edge Type', c.edgeType),
                  _buildSpecRow('Mint Mark', c.mintMark),
                  _buildSpecRow('Master Engraver', c.designer),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 8. Historical Timeline & Essay Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('Historical Background', style: AppTypography.sectionHeader),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildMuseumTimeline(c),
            ),

            const SizedBox(height: 32),

            // 9. Save to Collection Vault Fields Manager
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Vault Storage Management', style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                        Switch.adaptive(
                          value: _isSavedInVault,
                          activeColor: AppColors.gold,
                          onChanged: (val) {
                            setState(() {
                              _isSavedInVault = val;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: val ? AppColors.emerald : AppColors.crimson,
                                content: Text(
                                  val ? 'Item successfully saved to Collection Vault.' : 'Removed from Collection Vault.',
                                  style: AppTypography.buttonText,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    if (_isSavedInVault) ...[
                      const SizedBox(height: 20),
                      Text('Purchase Price (\$)', style: AppTypography.caption),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _purchasePriceController,
                        style: AppTypography.bodyMedium,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Purchase Origin / Seller', style: AppTypography.caption),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _purchaseLocationController,
                        style: AppTypography.bodyMedium,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Storage Vault Box', style: AppTypography.caption),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _storageLocation,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        ),
                        items: ['Home Vault', 'Safe Deposit Box A', 'Safe Deposit Box B', 'Display Cabinet'].map((loc) {
                          return DropdownMenuItem(
                            value: loc,
                            child: Text(loc, style: AppTypography.bodyMedium),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _storageLocation = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Text('Personal Notes', style: AppTypography.caption),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _notesController,
                        style: AppTypography.bodyMedium,
                        maxLines: 3,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 60),

            // Bottom CTA for return
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: GoldButton(
                  text: 'Back to Vault',
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ),

            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }

  int _getRarityBarValue(RarityLevel level) {
    switch (level) {
      case RarityLevel.common: return 0;
      case RarityLevel.uncommon: return 1;
      case RarityLevel.rare: return 2;
      case RarityLevel.veryRare: return 3;
      case RarityLevel.extremelyRare: return 4;
      case RarityLevel.museumGrade: return 5;
    }
  }

  TableRow _buildSpecRow(String label, String value) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14.0),
          child: Text(label, style: AppTypography.caption),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14.0),
          child: Text(
            value,
            style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildMuseumTimeline(CollectibleModel c) {
    List<Map<String, String>> timelineData;
    if (c.id == 'coin_saint_gaudens') {
      timelineData = [
        {'year': '1905', 'title': 'Roosevelt Initiative', 'desc': 'President Theodore Roosevelt commissions sculptor Augustus Saint-Gaudens to redesign US coinage.'},
        {'year': '1907', 'title': 'First High Relief Strikes', 'desc': 'First 11,250 high relief coins struck. The rim type was modified to flat to accommodate vault stackings.'},
        {'year': '1933', 'title': 'Executive Order Recall', 'desc': 'Executive Order 6102 outlaws gold ownership, ordering the melting of virtually all 1933 Double Eagles.'},
      ];
    } else if (c.id == 'coin_athenian_owl') {
      timelineData = [
        {'year': '454 BC', 'title': 'Treasury Relocation', 'desc': 'Athens relocates the Delian League treasury to the Acropolis, funding massive Owl coin production.'},
        {'year': '440 BC', 'title': 'Classical Mint Peak', 'desc': 'Owl designs reach their aesthetic pinnacle under master craftsmen during the height of the Golden Age.'},
        {'year': '404 BC', 'title': 'Peloponnesian Defeat', 'desc': 'Athens surrenders to Sparta, leading to temporary closures of the municipal minting treasuries.'},
      ];
    } else {
      timelineData = [
        {'year': '${c.year - 2}', 'title': 'Engraving Masterwork', 'desc': 'Initial die models drafted and approved by the central mint committee.'},
        {'year': '${c.year}', 'title': 'Inaugural Strike Release', 'desc': 'First series batch released into standard commercial circulation channels.'},
        {'year': '${c.year + 10}', 'title': 'Design Retirement', 'desc': 'Dies retired or updated to newer commemorative variation profiles.'},
      ];
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.museum_outlined, color: AppColors.goldDark, size: 20),
              const SizedBox(width: 8),
              Text(
                'MUSEUM TIMELINE MODE',
                style: AppTypography.goldLabel.copyWith(fontSize: 10, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...List.generate(timelineData.length, (idx) {
            final t = timelineData[idx];
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Timeline column
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.gold, width: 1),
                      ),
                      child: Text(
                        t['year']!,
                        style: AppTypography.goldLabel.copyWith(fontSize: 10),
                      ),
                    ),
                    if (idx < timelineData.length - 1)
                      Container(
                        height: 50,
                        width: 2,
                        color: AppColors.border,
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                
                // Content column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t['title']!,
                        style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t['desc']!,
                        style: AppTypography.caption.copyWith(height: 1.4),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 8),
          Text(
            c.historicalInfo,
            style: AppTypography.bodyMuted.copyWith(height: 1.5, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _PriceMetric extends StatelessWidget {
  final String label;
  final String value;

  const _PriceMetric({
    Key? key,
    required this.label,
    required this.value,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          children: [
            Text(label, style: AppTypography.caption),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTypography.sectionHeader.copyWith(fontSize: 16, color: AppColors.goldDark),
            ),
          ],
        ),
      ),
    );
  }
}

class DetailedCoinGraphicPainter extends CustomPainter {
  final CollectibleModel collectible;
  final bool isFront;

  DetailedCoinGraphicPainter({required this.collectible, required this.isFront});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..isAntiAlias = true;

    // Draw gold or silver composition gradient based on coin model
    final isGold = collectible.composition.toLowerCase().contains('gold');
    
    final gradient = RadialGradient(
      colors: isGold
          ? [AppColors.goldLight, AppColors.gold, AppColors.goldDark]
          : [Colors.white, AppColors.border, AppColors.textSecondary],
      stops: const [0.1, 0.7, 1.0],
    ).createShader(Rect.fromCircle(center: center, radius: size.width / 2));
    
    paint.shader = gradient;
    canvas.drawCircle(center, size.width / 2, paint);

    // Decorative inner rim
    paint.shader = null;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    paint.color = Colors.white.withOpacity(0.3);
    canvas.drawCircle(center, size.width / 2 - 12, paint);

    // Core symbol representations
    paint.style = PaintingStyle.fill;
    paint.color = (isGold ? AppColors.goldDark : AppColors.textPrimary).withOpacity(0.3);

    if (isFront) {
      // Draw a silhouette portrait/liberty head representation
      final path = Path()
        ..moveTo(center.dx - 10, center.dy + 35)
        ..lineTo(center.dx + 10, center.dy + 35)
        ..quadraticBezierTo(center.dx + 5, center.dy + 15, center.dx + 10, center.dy)
        ..quadraticBezierTo(center.dx + 25, center.dy - 10, center.dx + 10, center.dy - 30)
        ..quadraticBezierTo(center.dx - 20, center.dy - 25, center.dx - 15, center.dy - 5)
        ..quadraticBezierTo(center.dx - 25, center.dy + 15, center.dx - 10, center.dy + 35);
      canvas.drawPath(path, paint);
      
      // Star borders
      paint.color = Colors.white.withOpacity(0.4);
      for (int i = 0; i < 12; i++) {
        final angle = i * pi / 6;
        final starLoc = Offset(
          center.dx + (size.width / 2 - 20) * cos(angle),
          center.dy + (size.width / 2 - 20) * sin(angle),
        );
        canvas.drawCircle(starLoc, 2.5, paint);
      }
    } else {
      // Draw reverse design representation (Eagle or Owl depending on details)
      if (collectible.id == 'coin_athenian_owl') {
        // Draw Athenian owl reverse silhouette
        paint.color = AppColors.textPrimary.withOpacity(0.45);
        canvas.drawCircle(Offset(center.dx - 10, center.dy - 10), 8, paint);
        canvas.drawCircle(Offset(center.dx + 10, center.dy - 10), 8, paint);
        canvas.drawOval(
          Rect.fromCenter(center: Offset(center.dx, center.dy + 10), width: 25, height: 30),
          paint,
        );
      } else {
        // Draw standard flying eagle reverse silhouette
        final eaglePath = Path()
          ..moveTo(center.dx - 45, center.dy - 10)
          ..quadraticBezierTo(center.dx - 10, center.dy - 15, center.dx, center.dy - 5)
          ..quadraticBezierTo(center.dx + 10, center.dy - 15, center.dx + 45, center.dy - 10)
          ..quadraticBezierTo(center.dx + 10, center.dy + 5, center.dx + 5, center.dy + 25)
          ..quadraticBezierTo(center.dx, center.dy + 15, center.dx - 5, center.dy + 25)
          ..quadraticBezierTo(center.dx - 10, center.dy + 5, center.dx - 45, center.dy - 10);
        canvas.drawPath(eaglePath, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DetailedCoinGraphicPainter oldDelegate) => true;
}
