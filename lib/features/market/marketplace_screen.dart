import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/premium_widgets.dart';
import '../../core/network/mock_api.dart';
import '../../core/storage/models.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({Key? key}) : super(key: key);

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  String _marketSearchQuery = '';
  bool _isDealerMode = false;
  String _marketTab = 'listings'; // listings, auctions
  
  List<MarketplaceListingModel> _getFilteredListings() {
    final listings = MockApi.getMarketplaceListings();
    if (_marketSearchQuery.isEmpty) return listings;
    
    final query = _marketSearchQuery.toLowerCase();
    return listings.where((m) {
      return m.collectible.name.toLowerCase().contains(query) ||
             m.collectible.country.toLowerCase().contains(query) ||
             m.sellerName.toLowerCase().contains(query);
    }).toList();
  }

  void _showListingNegotiateSheet(MarketplaceListingModel item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Place Secure Offer', style: AppTypography.sectionHeader),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Your funds will be secured in a neutral escrow smart vault until the seller ships the item and you verify its authenticity.',
                  style: AppTypography.caption,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    CircleAvatar(
                      backgroundImage: NetworkImage(item.sellerAvatar),
                      radius: 20,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(item.sellerName, style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                            if (item.isSellerVerified) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.verified, color: AppColors.emerald, size: 14),
                            ]
                          ],
                        ),
                        Text('Original Price: \$${item.price.toStringAsFixed(0)}', style: AppTypography.caption),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Your Bid Offer Amount (\$)', style: AppTypography.caption),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: (item.price * 0.95).toStringAsFixed(0),
                  keyboardType: TextInputType.number,
                  style: AppTypography.bodyMedium,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: GoldButton(
                    text: 'Initialize Escrow Offer',
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppColors.emerald,
                          content: Text(
                            'Escrow Offer sent securely to ${item.sellerName}.',
                            style: AppTypography.buttonText,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final listings = _getFilteredListings();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isDealerMode ? 'Dealer Dashboard' : 'CoinVault Market'),
        actions: [
          IconButton(
            icon: Icon(_isDealerMode ? Icons.storefront : Icons.business_center),
            onPressed: () {
              setState(() {
                _isDealerMode = !_isDealerMode;
              });
            },
          ),
        ],
      ),
      body: _isDealerMode
          ? _buildDealerDashboard()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. AI Market Insights ticker banner
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.gold.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.bolt, color: AppColors.goldDark, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI MARKET INSIGHTS', style: AppTypography.goldLabel.copyWith(fontSize: 10)),
                        const SizedBox(height: 2),
                        Text(
                          'Undervalued alert: Athenian Owls are currently trading 8% below catalog values in Chicago auctions.',
                          style: AppTypography.caption.copyWith(color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: TextField(
              onChanged: (val) {
                setState(() {
                  _marketSearchQuery = val;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search marketplace listings...',
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
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          // Segmented Control (Buy It Now vs Auctions)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _marketTab = 'listings'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _marketTab == 'listings' ? AppColors.gold : AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _marketTab == 'listings' ? AppColors.gold : AppColors.borderLight),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'BUY IT NOW',
                        style: AppTypography.caption.copyWith(
                          color: _marketTab == 'listings' ? Colors.white : AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _marketTab = 'auctions'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _marketTab == 'auctions' ? AppColors.gold : AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _marketTab == 'auctions' ? AppColors.gold : AppColors.borderLight),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'LIVE AUCTIONS',
                        style: AppTypography.caption.copyWith(
                          color: _marketTab == 'auctions' ? Colors.white : AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. Grid listings
          Expanded(
            child: _marketTab == 'auctions'
                ? _buildLiveAuctionsList()
                : listings.isEmpty
                    ? _buildEmptyState()
                    : GridView.builder(
                    padding: const EdgeInsets.all(24),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 1, // Single column list feels more premium for marketplace detail
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.9,
                    ),
                    itemCount: listings.length,
                    itemBuilder: (context, index) {
                      final item = listings[index];
                      final c = item.collectible;

                      return Card(
                        child: InkWell(
                          onTap: () => _showListingNegotiateSheet(item),
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                // Item representation image box
                                Container(
                                  width: 110,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    gradient: RadialGradient(
                                      colors: c.composition.toLowerCase().contains('gold')
                                          ? [AppColors.goldLight.withOpacity(0.4), AppColors.gold.withOpacity(0.6)]
                                          : [AppColors.borderLight, AppColors.border],
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    c.type == CollectibleType.coin ? Icons.monetization_on_outlined : Icons.note_outlined,
                                    size: 36,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 16),

                                // Data details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  c.name,
                                                  style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (item.escrowReady)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.gold.withOpacity(0.12),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    'ESCROW',
                                                    style: AppTypography.goldLabel.copyWith(fontSize: 8),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text('${c.country} • Grade: ${c.estimatedGrade}', style: AppTypography.caption),
                                        ],
                                      ),
                                      
                                      // Seller metadata
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundImage: NetworkImage(item.sellerAvatar),
                                            radius: 10,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            item.sellerName,
                                            style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold, fontSize: 11),
                                          ),
                                          if (item.isSellerVerified) ...[
                                            const SizedBox(width: 2),
                                            const Icon(Icons.verified, color: AppColors.emerald, size: 12),
                                          ],
                                        ],
                                      ),

                                      // Price and Negotiate triggers
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '\$${item.price.toStringAsFixed(0)}',
                                            style: AppTypography.sectionHeader.copyWith(color: AppColors.goldDark, fontSize: 18),
                                          ),
                                          Row(
                                            children: [
                                              Icon(Icons.remove_red_eye_outlined, size: 12, color: AppColors.textSecondary),
                                              const SizedBox(width: 4),
                                              Text('${item.views} views', style: AppTypography.caption.copyWith(fontSize: 10)),
                                              const SizedBox(width: 12),
                                              Icon(Icons.rate_review_outlined, size: 12, color: AppColors.textSecondary),
                                              const SizedBox(width: 4),
                                              Text('${item.offersCount} offers', style: AppTypography.caption.copyWith(fontSize: 10)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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

  Widget _buildDealerDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sales metrics
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TOTAL SALES (30D)', style: AppTypography.caption),
                    const SizedBox(height: 4),
                    Text('\$142,500', style: AppTypography.heroTitle.copyWith(fontSize: 32)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: AppColors.emeraldLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.show_chart, color: AppColors.emerald, size: 24),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          Text('Dealer Hub Controls', style: AppTypography.sectionHeader),
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(child: _buildDealerMetric('Inventory Size', '124 lots', Icons.inventory_2_outlined)),
              const SizedBox(width: 12),
              Expanded(child: _buildDealerMetric('Customer Inquiries', '5 pending', Icons.mail_outline)),
            ],
          ),
          const SizedBox(height: 24),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cloud_upload_outlined, color: AppColors.gold, size: 20),
                      const SizedBox(width: 8),
                      Text('Bulk Inventory Upload', style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Upload inventory listings in bulk using standard CSV, JSON files, or high-speed scanners.', style: AppTypography.caption),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: GoldButton(
                      text: 'Select CSV File',
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: AppColors.emerald,
                            content: Text('CSV parser mock initialized. 12 coins added to catalog buffer.'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          Text('Pending Customer Queries', style: AppTypography.sectionHeader),
          const SizedBox(height: 16),
          _buildQueryTile('John Doe', 'Is the 1882-CC Morgan certified by NGC?', '2 hours ago'),
          _buildQueryTile('Sarah Smith', 'Can we negotiate shipping insurance?', '1 day ago'),
          
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildDealerMetric(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.goldDark, size: 20),
          const SizedBox(height: 12),
          Text(label, style: AppTypography.caption),
          const SizedBox(height: 4),
          Text(value, style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildQueryTile(String user, String query, String time) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.goldLight,
            radius: 18,
            child: Icon(Icons.person, color: AppColors.goldDark, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user, style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(query, style: AppTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(time, style: AppTypography.caption.copyWith(fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildLiveAuctionsList() {
    final list = MockApi.getFeaturedCollectibles();

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: 2,
      itemBuilder: (context, index) {
        final item = list[index];
        final currentBid = item.retailPrice * 0.85;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: item.composition.toLowerCase().contains('gold')
                          ? [AppColors.goldLight, AppColors.gold, AppColors.goldDark]
                          : [Colors.white, AppColors.border, AppColors.textSecondary],
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      item.type == CollectibleType.coin ? Icons.monetization_on : Icons.note,
                      color: Colors.white.withOpacity(0.4),
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text('Current Bid: \$${currentBid.toStringAsFixed(0)}', style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold, color: AppColors.goldDark)),
                      const SizedBox(height: 2),
                      Text('Time Left: 2h 14m (12 bids)', style: AppTypography.caption),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.amberLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'HOT AUCTION',
                              style: AppTypography.goldLabel.copyWith(fontSize: 8, color: AppColors.amber),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () => _showBidSheet(item, currentBid),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.gold,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Text('Place Bid', style: AppTypography.buttonText.copyWith(fontSize: 11)),
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
    );
  }

  void _showBidSheet(CollectibleModel item, double currentBid) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Place Secure Bid', style: AppTypography.sectionHeader),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Lot: ${item.name}', style: AppTypography.caption),
                const SizedBox(height: 16),
                Text('Minimum Bid: \$${(currentBid + 100).toStringAsFixed(0)}', style: AppTypography.caption),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: (currentBid + 250).toStringAsFixed(0),
                  keyboardType: TextInputType.number,
                  style: AppTypography.bodyMedium,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 24),
                GoldButton(
                  text: 'Confirm Bid Lot',
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: AppColors.emerald,
                        content: Text('Bid placed successfully! You are current high bidder.'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.store_mall_directory_outlined, size: 64, color: AppColors.textSecondary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('No matching listings found', style: AppTypography.sectionHeader),
          const SizedBox(height: 8),
          Text('Try searching for specific mint marks or years.', style: AppTypography.bodyMuted),
        ],
      ),
    );
  }
}
