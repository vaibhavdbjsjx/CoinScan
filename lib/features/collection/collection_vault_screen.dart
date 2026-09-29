import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/storage/collection_storage_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/premium_widgets.dart';
import 'collection_detail_screen.dart';
import 'compare_screen.dart';

class CollectionVaultScreen extends StatefulWidget {
  final VoidCallback onScanPressed;

  const CollectionVaultScreen({super.key, required this.onScanPressed});

  @override
  State<CollectionVaultScreen> createState() => _CollectionVaultScreenState();
}

class _CollectionVaultScreenState extends State<CollectionVaultScreen> {
  List<VaultCoinItem> _vaultItems = [];
  bool _isLoading = true;

  String _searchQuery = '';
  String _activeFilter = 'All';
  final List<String> _filters = [
    'All',
    'Precious Metals',
    'Worth a Closer Look',
    'Gold',
    'Silver',
    'Favorites',
  ];

  String _selectedSort = 'date_added'; // date_added, value_high, year_desc, year_asc, name_asc
  String? _selectedContinent;

  // Compare Mode State
  bool _isCompareMode = false;
  final List<VaultCoinItem> _compareSelection = [];

  @override
  void initState() {
    super.initState();
    _loadCollection();
  }

  Future<void> _loadCollection() async {
    setState(() => _isLoading = true);
    final items = await CollectionStorageService.instance.loadCollection();
    if (mounted) {
      setState(() {
        _vaultItems = items;
        _isLoading = false;
      });
    }
  }

  List<VaultCoinItem> _getFilteredAndSortedItems() {
    final filtered = _vaultItems.where((item) {
      // Continent filter
      if (_selectedContinent != null) {
        final country = item.country.toLowerCase();
        bool matchContinent = false;
        if (_selectedContinent == 'North America' &&
            (country.contains('united states') ||
                country.contains('canada') ||
                country.contains('mexico') ||
                country.contains('america'))) {
          matchContinent = true;
        } else if (_selectedContinent == 'Europe' &&
            (country.contains('greece') ||
                country.contains('uk') ||
                country.contains('united kingdom') ||
                country.contains('britain') ||
                country.contains('france') ||
                country.contains('germany') ||
                country.contains('italy') ||
                country.contains('spain') ||
                country.contains('russia') ||
                country.contains('switzerland'))) {
          matchContinent = true;
        } else if (_selectedContinent == 'Asia' &&
            (country.contains('china') ||
                country.contains('japan') ||
                country.contains('india') ||
                country.contains('korea'))) {
          matchContinent = true;
        } else if (_selectedContinent == 'Africa' &&
            (country.contains('south africa') ||
                country.contains('egypt') ||
                country.contains('nigeria') ||
                country.contains('kenya'))) {
          matchContinent = true;
        } else if (_selectedContinent == 'South America' &&
            (country.contains('brazil') ||
                country.contains('argentina') ||
                country.contains('peru') ||
                country.contains('colombia'))) {
          matchContinent = true;
        } else if (_selectedContinent == 'Oceania' &&
            (country.contains('australia') ||
                country.contains('new zealand'))) {
          matchContinent = true;
        }
        if (!matchContinent) return false;
      }

      // Smart filter
      if (_activeFilter == 'Precious Metals' && !item.hasPreciousMetal) {
        return false;
      }
      if (_activeFilter == 'Worth a Closer Look' && !item.isWorthCloserLook) {
        return false;
      }
      if (_activeFilter == 'Gold') {
        final comp = item.composition?.toLowerCase() ?? '';
        if (!comp.contains('gold')) return false;
      }
      if (_activeFilter == 'Silver') {
        final comp = item.composition?.toLowerCase() ?? '';
        if (!comp.contains('silver')) return false;
      }
      if (_activeFilter == 'Favorites' && !item.isFavorite) {
        return false;
      }

      // Search query filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesName = item.coinName.toLowerCase().contains(query);
        final matchesCountry = item.country.toLowerCase().contains(query);
        final matchesDenom = item.denomination.toLowerCase().contains(query);
        final matchesMint = item.mintMark?.toLowerCase().contains(query) ?? false;
        final matchesComp = item.composition?.toLowerCase().contains(query) ?? false;
        final matchesYear = item.year?.toString().contains(query) ?? false;
        if (!matchesName &&
            !matchesCountry &&
            !matchesDenom &&
            !matchesMint &&
            !matchesComp &&
            !matchesYear) {
          return false;
        }
      }

      return true;
    }).toList();

    // Sorting
    switch (_selectedSort) {
      case 'value_high':
        filtered.sort((a, b) {
          final valA = a.currentEstimatedValue ??
              a.initialValuationSnapshot ??
              a.purchasePrice ??
              0.0;
          final valB = b.currentEstimatedValue ??
              b.initialValuationSnapshot ??
              b.purchasePrice ??
              0.0;
          return valB.compareTo(valA);
        });
        break;
      case 'year_asc':
        filtered.sort((a, b) => (a.year ?? 9999).compareTo(b.year ?? 9999));
        break;
      case 'year_desc':
        filtered.sort((a, b) => (b.year ?? -9999).compareTo(a.year ?? -9999));
        break;
      case 'name_asc':
        filtered.sort((a, b) =>
            a.coinName.toLowerCase().compareTo(b.coinName.toLowerCase()));
        break;
      case 'date_added':
      default:
        filtered.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
        break;
    }

    return filtered;
  }

  Future<void> _handleItemTap(VaultCoinItem item) async {
    if (_isCompareMode) {
      setState(() {
        if (_compareSelection.any((x) => x.id == item.id)) {
          _compareSelection.removeWhere((x) => x.id == item.id);
        } else {
          if (_compareSelection.length < 2) {
            _compareSelection.add(item);
          }
        }
      });
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CollectionDetailScreen(vaultItem: item),
        ),
      );
      // Reload on return so edits or deletions are immediately reflected
      _loadCollection();
    }
  }

  List<String> _getCollectedContinents() {
    final list = <String>{};
    for (var item in _vaultItems) {
      final country = item.country.toLowerCase();
      if (country.contains('united states') ||
          country.contains('canada') ||
          country.contains('mexico') ||
          country.contains('america')) {
        list.add('North America');
      } else if (country.contains('greece') ||
          country.contains('uk') ||
          country.contains('britain') ||
          country.contains('france') ||
          country.contains('germany') ||
          country.contains('italy') ||
          country.contains('spain')) {
        list.add('Europe');
      } else if (country.contains('china') ||
          country.contains('japan') ||
          country.contains('india')) {
        list.add('Asia');
      } else if (country.contains('australia')) {
        list.add('Oceania');
      } else if (country.contains('south africa') || country.contains('egypt')) {
        list.add('Africa');
      } else if (country.contains('brazil') || country.contains('argentina')) {
        list.add('South America');
      }
    }
    return list.toList();
  }

  @override
  Widget build(BuildContext context) {
    final stats = CollectionStorageService.instance.calculateStats();
    final insights = CollectionStorageService.instance.generateInsights();
    final filteredItems = _getFilteredAndSortedItems();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Collection Vault'),
        actions: [
          // Sort Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort Collection',
            initialValue: _selectedSort,
            onSelected: (val) {
              setState(() => _selectedSort = val);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'date_added',
                child: Text('Date Added (Newest)'),
              ),
              PopupMenuItem(
                value: 'value_high',
                child: Text('Highest Value'),
              ),
              PopupMenuItem(
                value: 'year_desc',
                child: Text('Year (Newest)'),
              ),
              PopupMenuItem(
                value: 'year_asc',
                child: Text('Year (Oldest)'),
              ),
              PopupMenuItem(
                value: 'name_asc',
                child: Text('Name (A–Z)'),
              ),
            ],
          ),
          // Compare Toggle
          IconButton(
            icon: Icon(
              _isCompareMode ? Icons.compare_arrows : Icons.compare,
              color: _isCompareMode
                  ? AppColors.goldDark
                  : AppColors.textPrimary,
            ),
            tooltip: 'Compare Mode',
            onPressed: () {
              setState(() {
                _isCompareMode = !_isCompareMode;
                _compareSelection.clear();
              });
              if (_isCompareMode) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Compare Mode Active: Select two items to compare details.',
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : RefreshIndicator(
              onRefresh: _loadCollection,
              color: AppColors.gold,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
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
                                    '\$${stats.totalEstimatedValue.toStringAsFixed(0)}',
                                    style: AppTypography.heroTitle.copyWith(
                                      fontSize: 36,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: const BoxDecoration(
                                  color: AppColors.emeraldLight,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.account_balance_wallet_outlined,
                                  color: AppColors.emerald,
                                  size: 28,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildMiniStat('Total Items', '${stats.totalCoins}'),
                              _buildMiniStat(
                                'Precious Metals',
                                '${stats.silverCoinsCount + stats.goldCoinsCount}',
                              ),
                              _buildMiniStat('Countries', '${stats.uniqueCountries}'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 2. Real Insights Banner (if available)
                  if (insights.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.goldLight.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.auto_awesome_rounded,
                                  color: AppColors.goldDark,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'COLLECTION INSIGHTS',
                                  style: AppTypography.caption.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.goldDark,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final insight in insights.take(3))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('• ', style: TextStyle(color: AppColors.goldDark)),
                                    Expanded(
                                      child: Text(
                                        insight,
                                        style: AppTypography.caption.copyWith(
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                  // 3. Search Field
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: TextField(
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search by country, year, metal, variety...',
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

                  // 4. Smart Filter Chips
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: _filters.length,
                      itemBuilder: (context, index) {
                        final filter = _filters[index];
                        final isSel = _activeFilter == filter;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _activeFilter = filter;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSel ? AppColors.gold : AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSel ? AppColors.gold : AppColors.borderLight,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              filter,
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

                  // 5. Dynamic World Map Heatmap (Real data)
                  if (_vaultItems.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Collection Map Heatmap',
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_selectedContinent != null)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _selectedContinent = null;
                                });
                              },
                              child: Text(
                                'Reset Map Filter',
                                style: AppTypography.goldLabel.copyWith(fontSize: 11),
                              ),
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
                  ],

                  // 6. Series Collection Goals (Calculated from Real Vault)
                  if (_vaultItems.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'Series Collection Goals',
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Builder(
                      builder: (context) {
                        final stats = CollectionStorageService.instance.calculateStats();
                        final vaultTarget = ((stats.totalCoins / 5).floor() + 1) * 5;
                        final preciousCount = stats.silverCoinsCount + stats.goldCoinsCount;
                        final historicCount = _vaultItems.where((v) => v.year != null && v.year! < 1950).length;

                        final goals = [
                          (title: 'Vault Builder Milestone', target: vaultTarget, current: stats.totalCoins),
                          (title: 'World Countries Registry', target: 5, current: stats.uniqueCountries.clamp(0, 5)),
                          (title: 'Precious Metals Set', target: 5, current: preciousCount.clamp(0, 5)),
                          (title: 'Vintage Coins (Pre-1950)', target: 5, current: historicCount.clamp(0, 5)),
                        ];

                        return SizedBox(
                          height: 110,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            itemCount: goals.length,
                            itemBuilder: (context, index) {
                              final goal = goals[index];
                              final progress = (goal.current / goal.target).clamp(0.0, 1.0);

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
                                            style: AppTypography.bodyMedium.copyWith(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Icon(
                                          progress == 1.0
                                              ? Icons.check_circle
                                              : Icons.star_border,
                                          color: AppColors.gold,
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '${goal.current} / ${goal.target} collected',
                                      style: AppTypography.caption.copyWith(fontSize: 11),
                                    ),
                                    LinearProgressIndicator(
                                      value: progress,
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
                        );
                      },
                    ),
                  ],

                  // 7. Comparison Bar Drawer (Active only in Compare mode when items are selected)
                  if (_isCompareMode && _compareSelection.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.goldLight.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.gold),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Selected: ${_compareSelection.length} / 2 items',
                              style: AppTypography.caption.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_compareSelection.length == 2)
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => CompareScreen(
                                        item1: _compareSelection[0].toCollectibleModel(),
                                        item2: _compareSelection[1].toCollectibleModel(),
                                      ),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.goldDark,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'Compare Now',
                                  style: AppTypography.buttonText.copyWith(
                                    fontSize: 12,
                                  ),
                                ),
                              )
                            else
                              Text('Select 1 more item', style: AppTypography.caption),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // 8. Items Grid or Empty State
                  if (filteredItems.isEmpty)
                    _buildEmptyState()
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          final isSelected = _compareSelection.any((x) => x.id == item.id);
                          return _buildVaultCoinCard(item, isSelected);
                        },
                      ),
                    ),

                  const SizedBox(height: 96),
                ],
              ),
            ),
    );
  }

  Widget _buildVaultCoinCard(VaultCoinItem item, bool isSelected) {
    final hasImage = !kIsWeb && item.frontImagePath != null && File(item.frontImagePath!).existsSync();
    final isGold = item.composition?.toLowerCase().contains('gold') ?? false;
    final isSilver = item.composition?.toLowerCase().contains('silver') ?? false;

    final double? val = item.currentEstimatedValue ?? item.initialValuationSnapshot ?? item.purchasePrice;
    final String displayVal = val != null
        ? '\$${val >= 1000 ? '${(val / 1000).toStringAsFixed(1)}k' : val.toStringAsFixed(0)}'
        : (item.valuationRange ?? '—');

    return GestureDetector(
      onTap: () => _handleItemTap(item),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
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
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: hasImage
                        ? Image.file(
                            File(item.frontImagePath!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildFallbackGraphic(isGold, isSilver),
                          )
                        : _buildFallbackGraphic(isGold, isSilver),
                  ),
                  if (item.isWorthCloserLook)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.goldDark,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Closer Look',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.coinName,
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.country}${item.year != null ? ' • ${item.year}' : ''}',
                    style: AppTypography.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        item.conditionEstimate ?? item.grade ?? 'Verified',
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        displayVal,
                        style: AppTypography.goldLabel.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
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
  }

  Widget _buildFallbackGraphic(bool isGold, bool isSilver) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isGold
              ? [
                  AppColors.goldLight.withValues(alpha: 0.35),
                  AppColors.gold.withValues(alpha: 0.55),
                ]
              : isSilver
                  ? [
                      const Color(0xFFECEFF1),
                      const Color(0xFFCFD8DC),
                    ]
                  : [
                      AppColors.borderLight,
                      AppColors.border,
                    ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.monetization_on_outlined,
          size: 40,
          color: AppColors.textPrimary.withValues(alpha: 0.25),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.goldLight.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.toll_outlined,
                size: 56,
                color: AppColors.goldDark,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _searchQuery.isEmpty && _activeFilter == 'All'
                  ? 'Your Vault is Empty'
                  : 'No Matching Coins Found',
              style: AppTypography.sectionHeader,
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isEmpty && _activeFilter == 'All'
                  ? 'Scan your coins with CoinScan to record and track your genuine collection, condition grades, and market values.'
                  : 'No coins matched your active query or filters.',
              style: AppTypography.bodyMuted,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_searchQuery.isEmpty && _activeFilter == 'All')
              GoldButton(
                text: 'Scan Your First Coin',
                onPressed: widget.onScanPressed,
              )
            else
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                    _activeFilter = 'All';
                    _selectedContinent = null;
                  });
                },
                child: const Text('Reset All Filters'),
              ),
          ],
        ),
      ),
    );
  }
}
