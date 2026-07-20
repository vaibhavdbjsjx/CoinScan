import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/premium_widgets.dart';
import '../../core/network/mock_api.dart';
import '../../core/storage/models.dart';
import 'collection_detail_screen.dart';
import 'compare_screen.dart';

class CollectionVaultScreen extends StatefulWidget {
  final VoidCallback onScanPressed;

  const CollectionVaultScreen({
    Key? key,
    required this.onScanPressed,
  }) : super(key: key);

  @override
  State<CollectionVaultScreen> createState() => _CollectionVaultScreenState();
}

class _CollectionVaultScreenState extends State<CollectionVaultScreen> {
  String _searchQuery = '';
  String _activeFolder = 'All'; // All, Gold, Silver, Ancient, Errors, Favorites
  final List<String> _folders = ['All', 'Gold', 'Silver', 'Ancient', 'Errors', 'Favorites'];
  String? _selectedContinent;
  
  // Compare Mode State
  bool _isCompareMode = false;
  final List<CollectibleModel> _compareSelection = [];

  List<PortfolioItemModel> _getFilteredItems() {
    final items = MockApi.getPortfolioItems();
    return items.where((item) {
      final c = item.collectible;
      
      // Continent filter
      if (_selectedContinent != null) {
        final country = c.country.toLowerCase();
        if (_selectedContinent == 'North America' && !country.contains('united states')) return false;
        if (_selectedContinent == 'Europe' && !country.contains('greece')) return false;
        if (_selectedContinent != 'North America' && _selectedContinent != 'Europe') return false;
      }
      
      // Folder filter
      if (_activeFolder == 'Gold' && !c.composition.toLowerCase().contains('gold')) return false;
      if (_activeFolder == 'Silver' && !c.composition.toLowerCase().contains('silver')) return false;
      if (_activeFolder == 'Ancient' && c.year > 500) return false; // ancient threshold
      if (_activeFolder == 'Errors' && c.errorType == null) return false;
      if (_activeFolder == 'Favorites' && !item.isFavorite) return false;

      // Text search query filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesName = c.name.toLowerCase().contains(query);
        final matchesCountry = c.country.toLowerCase().contains(query);
        final matchesComposition = c.composition.toLowerCase().contains(query);
        final matchesYear = c.year.toString().contains(query);
        return matchesName || matchesCountry || matchesComposition || matchesYear;
      }
      return true;
    }).toList();
  }

  void _handleItemTap(CollectibleModel collectible) {
    if (_isCompareMode) {
      setState(() {
        if (_compareSelection.any((x) => x.id == collectible.id)) {
          _compareSelection.removeWhere((x) => x.id == collectible.id);
        } else {
          if (_compareSelection.length < 2) {
            _compareSelection.add(collectible);
          }
        }
      });
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CollectionDetailScreen(collectible: collectible),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = _getFilteredItems();
    
    // Aggregate values
    double totalValuation = 0.0;
    for (var item in MockApi.getPortfolioItems()) {
      totalValuation += item.collectible.retailPrice;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Collection Vault'),
        actions: [
          IconButton(
            icon: Icon(
              _isCompareMode ? Icons.compare_arrows : Icons.compare,
              color: _isCompareMode ? AppColors.goldDark : AppColors.textPrimary,
            ),
            onPressed: () {
              setState(() {
                _isCompareMode = !_isCompareMode;
                _compareSelection.clear();
              });
              if (_isCompareMode) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Compare Mode Active: Select two items to compare details.'),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Valuation Dashboard Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: GlassCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('VAULT VALUATION', style: AppTypography.caption),
                          const SizedBox(height: 4),
                          Text(
                            '\$${totalValuation.toStringAsFixed(0)}',
                            style: AppTypography.heroTitle.copyWith(fontSize: 36),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldLight,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.trending_up, color: AppColors.emerald, size: 28),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMiniStat('Monthly Growth', '+6.8%', true),
                      _buildMiniStat('Total Items', '${MockApi.getPortfolioItems().length}', false),
                      _buildMiniStat('Purity Rating', '92%', false),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 2. Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: TextField(
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search by country, year, metal...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.borderLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.gold),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          // 3. Smart Folder Tabs
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _folders.length,
              itemBuilder: (context, index) {
                final folder = _folders[index];
                final isSel = _activeFolder == folder;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _activeFolder = folder;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSel ? AppColors.gold : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSel ? AppColors.gold : AppColors.borderLight,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      folder,
                      style: AppTypography.caption.copyWith(
                        color: isSel ? Colors.white : AppColors.textPrimary,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Dynamic World Map Heatmap
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Collection Map Heatmap', style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                if (_selectedContinent != null)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedContinent = null;
                      });
                    },
                    child: Text('Reset Map Filter', style: AppTypography.goldLabel.copyWith(fontSize: 11)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: InteractiveWorldMap(
              collectedContinents: _getCollectedContinents(),
              onContinentTapped: (continent) {
                setState(() {
                  _selectedContinent = continent;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppColors.goldDark,
                    content: Text('Filtered vault by region: $continent'),
                  ),
                );
              },
            ),
          ),

          // Collection Goals / Series completion progress
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text('Series Collection Goals', style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: MockApi.getSeriesCompletions().length,
              itemBuilder: (context, index) {
                final goal = MockApi.getSeriesCompletions()[index];
                return Container(
                  width: 250,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              goal.title,
                              style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            goal.progressPercentage == 1.0 ? Icons.check_circle : Icons.star_border,
                            color: AppColors.gold,
                            size: 16,
                          ),
                        ],
                      ),
                      Text(
                        '${goal.ownedCount} / ${goal.totalCount} collected',
                        style: AppTypography.caption.copyWith(fontSize: 11),
                      ),
                      LinearProgressIndicator(
                        value: goal.progressPercentage,
                        color: AppColors.gold,
                        backgroundColor: AppColors.border,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // 4. Comparison Bar Drawer (Active only in Compare mode when items are selected)
          if (_isCompareMode && _compareSelection.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.goldLight.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.gold),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Selected: ${_compareSelection.length} / 2 items',
                      style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (_compareSelection.length == 2)
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => CompareScreen(
                                item1: _compareSelection[0],
                                item2: _compareSelection[1],
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.goldDark,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('Compare Now', style: AppTypography.buttonText.copyWith(fontSize: 12)),
                      )
                    else
                      Text('Select 1 more item', style: AppTypography.caption),
                  ],
                ),
              ),
            ),

          // 5. Items Grid List
          Expanded(
            child: filteredItems.isEmpty
                ? _buildEmptyState()
                : GridView.builder(
                    padding: const EdgeInsets.all(24),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = filteredItems[index];
                      final c = item.collectible;
                      final isSelected = _compareSelection.any((x) => x.id == c.id);

                      return GestureDetector(
                        onTap: () => _handleItemTap(c),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isSelected ? AppColors.gold : AppColors.borderLight,
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: AppTheme.premiumShadow,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Visual Graphic Card top area
                              Expanded(
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: c.composition.toLowerCase().contains('gold')
                                          ? [AppColors.goldLight.withOpacity(0.3), AppColors.gold.withOpacity(0.5)]
                                          : [AppColors.borderLight, AppColors.border],
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      Center(
                                        child: Icon(
                                          c.type == CollectibleType.coin
                                              ? Icons.monetization_on_outlined
                                              : Icons.note_outlined,
                                          size: 40,
                                          color: AppColors.textPrimary.withOpacity(0.2),
                                        ),
                                      ),
                                      if (_isCompareMode)
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: Icon(
                                            isSelected ? Icons.check_circle : Icons.radio_button_off,
                                            color: isSelected ? AppColors.goldDark : Colors.white70,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.name,
                                      style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${c.country} • ${c.year < 0 ? '${c.year.abs()} BC' : c.year}',
                                      style: AppTypography.caption,
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          c.estimatedGrade,
                                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          '\$${c.retailPrice >= 1000 ? '${(c.retailPrice / 1000).toStringAsFixed(1)}k' : c.retailPrice.toStringAsFixed(0)}',
                                          style: AppTypography.goldLabel,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, bool isAppreciation) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.bold,
            color: isAppreciation ? AppColors.emerald : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.layers_clear_outlined, size: 64, color: AppColors.textSecondary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('No Vault items found', style: AppTypography.sectionHeader),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isEmpty ? 'Tap scan to add your first rare collectible.' : 'Refine your query filter terms.',
            style: AppTypography.bodyMuted,
          ),
          const SizedBox(height: 24),
          GoldButton(
            text: 'Scan New Coin',
            onPressed: widget.onScanPressed,
          ),
        ],
      ),
    );
  }

  List<String> _getCollectedContinents() {
    final list = <String>{};
    for (var item in MockApi.getPortfolioItems()) {
      final country = item.collectible.country.toLowerCase();
      if (country.contains('united states')) list.add('North America');
      if (country.contains('greece')) list.add('Europe');
    }
    return list.toList();
  }
}
