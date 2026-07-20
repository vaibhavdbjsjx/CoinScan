import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/premium_widgets.dart';
import '../../core/network/mock_api.dart';
import '../../core/storage/models.dart';

class HomeScreen extends StatefulWidget {
  final Function(int) onTabChange;
  final VoidCallback onScanPressed;

  const HomeScreen({
    Key? key,
    required this.onTabChange,
    required this.onScanPressed,
  }) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _particleController;
  final List<Offset> _particles = List.generate(
    15,
    (index) => Offset(
      (index * 73) % 300 / 300,
      (index * 117) % 300 / 300,
    ),
  );

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final featured = MockApi.getFeaturedCollectibles();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Header Section with Interactive Floating Particles
            Stack(
              children: [
                // Dark premium background block for high contrast macro coin shot representation
                Container(
                  height: 320,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(40),
                      bottomRight: Radius.circular(40),
                    ),
                  ),
                ),
                
                // Floating Golden Particles
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _particleController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: FloatingParticlesPainter(
                          particles: _particles,
                          progress: _particleController.value,
                        ),
                      );
                    },
                  ),
                ),

                // Diagonal shine overlays
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withOpacity(0.03),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // Greeting & Hero Text Content
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Good Morning,',
                                  style: AppTypography.bodyMuted.copyWith(
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Vaibhav',
                                  style: AppTypography.heroTitle.copyWith(
                                    color: Colors.white,
                                    fontSize: 28,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.gold.withOpacity(0.5), width: 1.5),
                              ),
                              child: const CircleAvatar(
                                radius: 20,
                                backgroundColor: AppColors.goldLight,
                                child: Icon(Icons.person_outline, color: AppColors.goldDark),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 36),
                        
                        // Discover history prompt card
                        Text(
                          'Discover History.',
                          style: AppTypography.heroTitle.copyWith(
                            color: Colors.white,
                            fontSize: 32,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your entire collection in one place.',
                          style: AppTypography.bodyMuted.copyWith(
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                        
                        const SizedBox(height: 32),
                        
                        // Giant Glowing Scan Button
                        Center(
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.gold.withOpacity(0.4),
                                  blurRadius: 30,
                                  spreadRadius: 2,
                                )
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: widget.onScanPressed,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.gold,
                                foregroundColor: Colors.white,
                                shape: const CircleBorder(),
                                padding: const EdgeInsets.all(28),
                                elevation: 0,
                              ),
                              child: const Icon(
                                Icons.camera_enhance_outlined,
                                size: 36,
                              ),
                            ),
                          )
                              .animate(onPlay: (controller) => controller.repeat(reverse: true))
                              .scale(
                                begin: const Offset(1.0, 1.0),
                                end: const Offset(1.06, 1.06),
                                duration: 1500.ms,
                                curve: Curves.easeInOutBack,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Quick Actions Hub Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: _QuickActionButton(
                      icon: Icons.grid_view_outlined,
                      label: 'Collection',
                      onTap: () => widget.onTabChange(1),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _QuickActionButton(
                      icon: Icons.storefront_outlined,
                      label: 'Market',
                      onTap: () => widget.onTabChange(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _QuickActionButton(
                      icon: Icons.school_outlined,
                      label: 'Learn',
                      onTap: () => widget.onTabChange(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _QuickActionButton(
                      icon: Icons.auto_graph_outlined,
                      label: 'Portfolio',
                      onTap: () => widget.onTabChange(1), // Under Collection/Portfolio
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Stats Cards Horizontal Grid Scroll
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Your Vault Stats',
                style: AppTypography.sectionHeader,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: const [
                  MetricCard(
                    title: 'Vault Value',
                    value: '\$4,280',
                    change: '+12.4%',
                    isPositive: true,
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  SizedBox(width: 16),
                  MetricCard(
                    title: 'Vault Scans',
                    value: '18 Coins',
                    change: 'Weekly',
                    isPositive: true,
                    icon: Icons.qr_code_scanner,
                  ),
                  SizedBox(width: 16),
                  MetricCard(
                    title: 'Countries',
                    value: '5 Regions',
                    change: '+1',
                    isPositive: true,
                    icon: Icons.public,
                  ),
                  SizedBox(width: 16),
                  MetricCard(
                    title: 'Rarity Index',
                    value: '94 / 100',
                    change: 'High',
                    isPositive: true,
                    icon: Icons.stars_outlined,
                  ),
                ],
              ).animate().slideX(begin: 0.1, end: 0, duration: 400.ms).fadeIn(),
            ),

            const SizedBox(height: 32),

            // Featured horizontal carousels
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Featured Collectibles',
                      style: AppTypography.sectionHeader,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => widget.onTabChange(2),
                    child: Text('View All', style: AppTypography.goldLabel),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: featured.length,
                itemBuilder: (context, index) {
                  final item = featured[index];
                  return Container(
                    width: 280,
                    margin: const EdgeInsets.only(right: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Image Mock Area (Styled Color container representing the coin type)
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: item.type == CollectibleType.coin
                                    ? [AppColors.gold.withOpacity(0.3), AppColors.goldDark.withOpacity(0.5)]
                                    : [Colors.teal.withOpacity(0.3), Colors.teal.withOpacity(0.5)],
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  top: 12,
                                  right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      item.rarity.displayName,
                                      style: AppTypography.goldLabel.copyWith(fontSize: 10),
                                    ),
                                  ),
                                ),
                                Center(
                                  child: Icon(
                                    item.type == CollectibleType.coin
                                        ? Icons.monetization_on_outlined
                                        : Icons.note_outlined,
                                    size: 48,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${item.country} • ${item.year < 0 ? '${item.year.abs()} BC' : item.year}',
                                      style: AppTypography.caption,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '\$${item.retailPrice >= 1000 ? '${(item.retailPrice / 1000).toStringAsFixed(1)}k' : item.retailPrice.toStringAsFixed(0)}',
                                    style: AppTypography.goldLabel.copyWith(fontSize: 14),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 120), // Spacing for bottom nav bar floating overlay
          ],
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionButton({
    Key? key,
    required this.icon,
    required this.label,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            height: 60,
            width: 60,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderLight, width: 1.5),
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 24),
          ),
          const SizedBox(height: 8),
          Text(label, style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class FloatingParticlesPainter extends CustomPainter {
  final List<Offset> particles;
  final double progress;

  FloatingParticlesPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.gold.withOpacity(0.18)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < particles.length; i++) {
      final baseOffset = particles[i];
      
      // Calculate dynamic shifting based on progress time loop
      final yShift = (baseOffset.dy + progress * 0.15) % 1.0;
      final xShift = (baseOffset.dx + (progress * 0.05) * (i % 2 == 0 ? 1 : -1)) % 1.0;
      
      final x = xShift * size.width;
      final y = yShift * size.height;
      final radius = 2.0 + (i % 3);

      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant FloatingParticlesPainter oldDelegate) => true;
}
