import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/storage/collection_storage_service.dart';
import '../../core/storage/models.dart';
import '../../core/storage/scan_history_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/premium_widgets.dart';
import '../scan/scan_history_screen.dart';
import 'main_navigation_wrapper.dart';

/// The dashboard — where the user lands after signing in.
///
/// Structure is deliberately front-loaded: the single most valuable action
/// (scan) sits inside the hero, portfolio state comes next, and browsable
/// content comes last. Everything is a sliver so the screen scrolls as one
/// surface and supports pull-to-refresh.
class HomeScreen extends StatefulWidget {
  final void Function(int tab, {int? subTab}) onTabChange;
  final VoidCallback onScanPressed;

  const HomeScreen({
    super.key,
    required this.onTabChange,
    required this.onScanPressed,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _particles = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  final ScrollController _scroll = ScrollController();

  /// Drives hero parallax.
  double _scrollOffset = 0;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    CollectionStorageService.instance.loadCollection().then((_) {
      if (mounted) setState(() {});
    });
    ScanHistoryService.instance.loadHistory().then((_) {
      if (mounted) setState(() {});
    });
    // A real first-load state rather than popping in fully formed — these are
    // the same skeletons the live API path will use.
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  void _onScroll() {
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    if ((offset - _scrollOffset).abs() > 1.5) {
      setState(() => _scrollOffset = offset);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ambient motion is suspended entirely when the OS asks to reduce motion.
    if (Motion.allowed(context)) {
      if (!_particles.isAnimating) _particles.repeat();
    } else {
      _particles.stop();
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _particles.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    HapticFeedback.mediumImpact();
    setState(() => _loading = true);
    await Future.wait([
      CollectionStorageService.instance.loadCollection(),
      ScanHistoryService.instance.loadHistory(),
      Future<void>.delayed(const Duration(milliseconds: 900)),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final gutter = AppSpacing.gutter(MediaQuery.sizeOf(context).width);
    final featured = CollectionStorageService.instance.items
        .map((i) => i.toCollectibleModel())
        .toList();
    final stats = CollectionStorageService.instance.calculateStats();
    final vaultValue = stats.totalEstimatedValue;
    final itemCount = stats.totalCoins;
    final regionsCount = stats.uniqueCountries;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.goldInk,
        backgroundColor: Colors.white,
        edgeOffset: 100,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(child: _buildHero(gutter)),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, AppSpacing.xxl, gutter, 0),
              sliver: SliverList.list(
                children: [
                  _buildQuickActions(),
                  const SizedBox(height: AppSpacing.xxl),
                  _buildPortfolioSummary(vaultValue, itemCount, regionsCount),
                ],
              ),
            ),
            SliverToBoxAdapter(child: _buildStatsRail(gutter)),
            SliverToBoxAdapter(child: _buildFeatured(gutter, featured)),
            SliverToBoxAdapter(child: _buildAdvisor(gutter)),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MainNavigationWrapper.contentBottomInset(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------- hero

  Widget _buildHero(double gutter) {
    final topPadding = MediaQuery.paddingOf(context).top;
    // Hero drifts at a fraction of scroll speed for depth.
    final parallax = Motion.allowed(context)
        ? (_scrollOffset * 0.3).clamp(0.0, 110.0)
        : 0.0;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(AppRadius.xxl),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(0, -parallax * 0.45),
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _particles,
                  builder: (context, _) => CustomPaint(
                    painter: _HeroBackdropPainter(progress: _particles.value),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              topPadding + AppSpacing.md,
              gutter,
              AppSpacing.xxl,
            ),
            child: Transform.translate(
              offset: Offset(0, -parallax * 0.12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroHeader(),
                  const SizedBox(height: AppSpacing.xxl),
                  Reveal(
                    index: 0,
                    child: Text(
                      'What are you\nholding today?',
                      style: AppTypography.heroTitle.copyWith(
                        color: Colors.white,
                        fontSize: 30,
                        height: 1.14,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Reveal(
                    index: 1,
                    child: Text(
                      'Point your camera at a coin or note for an instant identification.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textOnInkMuted,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Reveal(index: 2, child: _buildScanCta()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Fmt.greeting(),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textOnInkMuted,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'Collector',
                style: AppTypography.sectionHeader.copyWith(
                  color: Colors.white,
                  fontSize: 22,
                ),
              ),
            ],
          ),
        ),
        _HeroIconButton(
          icon: Icons.history_rounded,
          label: 'Scan History',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ScanHistoryScreen(
                  historyService: ScanHistoryService.instance,
                ),
              ),
            );
          },
        ),
        const SizedBox(width: AppSpacing.sm),
        _HeroIconButton(
          icon: Icons.notifications_none_rounded,
          label: 'Notifications',
          badge: false,
          onTap: _showNotificationsSheet,
        ),
        const SizedBox(width: AppSpacing.sm),
        Semantics(
          button: true,
          label: 'Your profile',
          child: GestureDetector(
            onTap: () => widget.onTabChange(3),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.goldGradient,
              ),
              child: const CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.inkElevated,
                child: Text(
                  'V',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Primary CTA — a labelled bar rather than a bare pulsing circle. The icon
  /// alone never told a first-time user what tapping would do.
  Widget _buildScanCta() {
    return Semantics(
      button: true,
      label: 'Scan a collectible. Identify, grade and value in seconds.',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.mediumImpact();
              widget.onScanPressed();
            },
            borderRadius: AppRadius.allMd,
            child: Ink(
              decoration: BoxDecoration(
                gradient: AppColors.goldGradient,
                borderRadius: AppRadius.allMd,
                boxShadow: AppShadows.goldGlow(opacity: 0.34),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.base,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.center_focus_strong_rounded,
                      color: AppColors.onGold,
                      size: 22,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Scan a collectible',
                            style: AppTypography.buttonText,
                          ),
                          Text(
                            'Identify, grade and value in seconds',
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.onGold.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.onGold,
                      size: 19,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------- quick actions

  Widget _buildQuickActions() {
    final actions = <(IconData, String, VoidCallback)>[
      (Icons.inventory_2_outlined, 'Vault', () => widget.onTabChange(1)),
      (Icons.storefront_outlined, 'Market', () => widget.onTabChange(2)),
      // Deep-links to the Learning Hub tab instead of dumping the user on the
      // profile showcase and making them find it.
      (Icons.school_outlined, 'Learn', () => widget.onTabChange(3, subTab: 2)),
      (
        Icons.emoji_events_outlined,
        'Badges',
        () => widget.onTabChange(3, subTab: 1),
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Reveal(
              index: i,
              child: _QuickAction(
                icon: actions[i].$1,
                label: actions[i].$2,
                onTap: actions[i].$3,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showNotificationsSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Notifications', style: AppTypography.sectionHeader),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.notifications_off_outlined,
                      size: 48,
                      color: AppColors.textMuted.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'No notifications yet',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Scan and save coins to receive updates about your collection.',
                      textAlign: TextAlign.center,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------- portfolio summary

  Widget _buildPortfolioSummary(double value, int itemCount, int regionsCount) {
    if (_loading) {
      return const PremiumShimmer(
        width: double.infinity,
        height: 136,
        borderRadius: AppRadius.xl,
      );
    }

    final isEmpty = itemCount == 0;

    return GlassCard(
      accent: true,
      onTap: () => widget.onTabChange(1),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('VAULT VALUE', style: AppTypography.goldLabel),
                    const SizedBox(height: AppSpacing.xs),
                    AnimatedValue(
                      value: isEmpty ? 0.0 : value,
                      formatter: Fmt.moneyCompact,
                      style: AppTypography.numericLarge.copyWith(fontSize: 30),
                    ),
                  ],
                ),
              ),
              const AppChip(
                label: 'Vault Ready',
                icon: Icons.shield_outlined,
                foreground: AppColors.goldDark,
                background: AppColors.goldLight,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _InlineStat(label: 'Items', value: '$itemCount'),
              _InlineStat(label: 'Regions', value: '$regionsCount'),
              const _InlineStat(label: 'Avg. grade', value: '—'),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- stats rail

  Widget _buildStatsRail(double gutter) {
    final stats = CollectionStorageService.instance.calculateStats();
    final scanCount = ScanHistoryService.instance.cachedRecordCount;
    final cards = [
      MetricCard(
        title: 'Total scans',
        value: '$scanCount',
        change: scanCount > 0 ? 'Lifetime' : '—',
        isPositive: scanCount > 0,
        showTrendArrow: false,
        icon: Icons.qr_code_scanner_rounded,
      ),
      MetricCard(
        title: 'Countries',
        value: '${stats.uniqueCountries}',
        change: stats.uniqueCountries > 0 ? 'Represented' : '—',
        isPositive: stats.uniqueCountries > 0,
        showTrendArrow: false,
        icon: Icons.public_rounded,
      ),
      MetricCard(
        title: 'Silver coins',
        value: '${stats.silverCoinsCount}',
        change: stats.silverCoinsCount > 0 ? 'Precious' : '—',
        isPositive: stats.silverCoinsCount > 0,
        showTrendArrow: false,
        icon: Icons.auto_awesome_rounded,
      ),
      MetricCard(
        title: 'Gold coins',
        value: '${stats.goldCoinsCount}',
        change: stats.goldCoinsCount > 0 ? 'Precious' : '—',
        isPositive: stats.goldCoinsCount > 0,
        showTrendArrow: false,
        icon: Icons.trending_up_rounded,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xxl),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: const SectionHeading(title: 'At a glance'),
        ),
        const SizedBox(height: AppSpacing.base),
        SizedBox(
          height: 136,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gutter),
            itemCount: _loading ? 3 : cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, i) => _loading
                ? const PremiumShimmer(
                    width: 148,
                    height: 136,
                    borderRadius: AppRadius.lg,
                  )
                : Reveal(index: i, child: cards[i]),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- featured

  Widget _buildFeatured(double gutter, List<CollectibleModel> items) {
    if (!_loading && items.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(gutter, AppSpacing.xxl, gutter, 0),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.allXl,
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeading(
                title: 'Your Vault',
                eyebrow: 'Portfolio',
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'No coins logged in your collection yet. Scan a coin to identify strike details, calculate estimated value, and begin tracking your vault.',
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              GoldButton(
                text: 'Scan your first coin',
                size: GoldButtonSize.compact,
                expand: false,
                icon: Icons.camera_alt_outlined,
                onPressed: widget.onScanPressed,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xxl),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: SectionHeading(
            title: 'Featured collectibles',
            eyebrow: 'Your Vault',
            actionLabel: 'View All',
            onAction: () => widget.onTabChange(1),
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        SizedBox(
          height: 256,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gutter),
            itemCount: _loading ? 3 : items.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.base),
            itemBuilder: (context, i) => _loading
                ? const PremiumShimmer(
                    width: 210,
                    height: 256,
                    borderRadius: AppRadius.xl,
                  )
                : Reveal(
                    index: i,
                    child: _FeaturedCard(
                      item: items[i],
                      onTap: () => widget.onTabChange(1),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- advisor

  Widget _buildAdvisor(double gutter) {
    if (_loading) return const SizedBox(height: AppSpacing.xxl);

    final stats = CollectionStorageService.instance.calculateStats();
    String tip;
    if (stats.totalCoins == 0) {
      tip = 'Your vault is currently empty. Use the camera scanner to catalog your first coin, identify its strike and variety, and begin tracking your collection portfolio.';
    } else if (stats.silverCoinsCount > 0 || stats.goldCoinsCount > 0) {
      tip = 'Your vault holds precious metal specimens. Keep high-resolution front, reverse, and rim scans with raking light at 45 degrees to document surface preservation and authentic mint luster.';
    } else if (stats.uniqueCountries > 1) {
      tip = 'Your collection spans multiple world regions. Be sure to check variety details and mint marks across different mint jurisdictions to identify scarce die varieties.';
    } else {
      tip = 'Document coin variety and mint mark strike details carefully. Even subtle die markers can significantly affect market desirability and grading tier.';
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, AppSpacing.xxl, gutter, 0),
      child: Reveal(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.inkSoft, AppColors.ink],
            ),
            borderRadius: AppRadius.allXl,
            boxShadow: AppShadows.level2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.16),
                      borderRadius: AppRadius.allXs,
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.gold,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'ADVISOR',
                    style: AppTypography.goldLabel.copyWith(
                      color: AppColors.gold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                tip,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textOnInk,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              GoldButton(
                text: 'See all insights',
                size: GoldButtonSize.compact,
                expand: false,
                onPressed: () => widget.onTabChange(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

class _HeroIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool badge;
  final VoidCallback onTap;

  const _HeroIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: badge ? '$label, unread' : label,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.white.withValues(alpha: 0.08),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 40,
              width: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 19),
                  if (badge)
                    Positioned(
                      top: 10,
                      right: 11,
                      child: Container(
                        height: 7,
                        width: 7,
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.inkSoft,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: AppColors.surface,
          borderRadius: AppRadius.allMd,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            splashColor: AppColors.gold.withValues(alpha: 0.1),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: AppRadius.allMd,
                border: Border.all(color: AppColors.borderLight),
              ),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(
                children: [
                  Icon(icon, color: AppColors.textPrimary, size: 21),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    label,
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  final String label;
  final String value;

  const _InlineStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppTypography.numericSmall),
          const SizedBox(height: 1),
          Text(label, style: AppTypography.captionSmall),
        ],
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  final CollectibleModel item;
  final VoidCallback onTap;

  const _FeaturedCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isNote = item.type == CollectibleType.banknote;

    return Semantics(
      button: true,
      label:
          '${item.name}. ${item.country}, ${Fmt.year(item.year)}. '
          '${item.rarity.displayName}. ${Fmt.moneyCompact(item.retailPrice)}',
      child: ExcludeSemantics(
        child: SizedBox(
          width: 210,
          child: GlassCard(
            onTap: onTap,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Specimen plate.
                Container(
                  height: 132,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-0.3, -0.4),
                      radius: 1.1,
                      colors: [AppColors.surfaceWarm, Color(0xFFEFEAE0)],
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(AppRadius.xl),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: CoinGlyph.forComposition(
                          size: isNote ? 122 : 88,
                          composition: item.composition,
                          isBanknote: isNote,
                          seed: item.id.hashCode,
                        ),
                      ),
                      Positioned(
                        top: AppSpacing.sm,
                        left: AppSpacing.sm,
                        child: AppChip(label: item.rarity.displayName),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 36,
                        child: Text(
                          item.name,
                          style: AppTypography.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${item.country} · ${Fmt.year(item.year)}',
                        style: AppTypography.captionSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              Fmt.moneyCompact(item.retailPrice),
                              style: AppTypography.numericSmall.copyWith(
                                fontSize: 15,
                                color: AppColors.goldInk,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Vault items have no price history; only show a
                          // trend when a real, non-zero trend exists.
                          if (item.priceTrendPercentage != 0) ...[
                            const Icon(
                              Icons.arrow_outward_rounded,
                              size: 12,
                              color: AppColors.emerald,
                            ),
                            Text(
                              Fmt.percentDelta(item.priceTrendPercentage),
                              style: AppTypography.numericSmall.copyWith(
                                fontSize: 11,
                                color: AppColors.emerald,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ink hero backdrop: gradient wash, warm key light and slow-drifting motes.
class _HeroBackdropPainter extends CustomPainter {
  final double progress;

  _HeroBackdropPainter({required this.progress});

  static final List<Offset> _seeds = List.generate(
    18,
    (i) => Offset(((i * 73) % 100) / 100, ((i * 137) % 100) / 100),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()..shader = AppColors.inkGradient.createShader(rect),
    );

    // Warm key light from the upper right.
    final aura = Offset(size.width * 0.86, size.height * 0.1);
    canvas.drawCircle(
      aura,
      size.width * 0.72,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                AppColors.gold.withValues(alpha: 0.22),
                AppColors.gold.withValues(alpha: 0.04),
                Colors.transparent,
              ],
              stops: const [0.0, 0.4, 1.0],
            ).createShader(
              Rect.fromCircle(center: aura, radius: size.width * 0.72),
            ),
    );

    final dust = Paint();
    for (var i = 0; i < _seeds.length; i++) {
      final seed = _seeds[i];
      final dir = i.isEven ? 1 : -1;
      final x = ((seed.dx + progress * 0.12 * dir) % 1.0) * size.width;
      final y = ((seed.dy - progress * 0.2) % 1.0) * size.height;
      // Motes fade as they approach the lower edge.
      final fade = (1 - (y / size.height)).clamp(0.15, 1.0);
      dust.color = AppColors.gold.withValues(alpha: 0.22 * fade);
      canvas.drawCircle(Offset(x, y), 1.0 + (i % 3) * 0.9, dust);
    }

    // Hairline along the bottom edge grounds the block against the page.
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 1, size.width, 1),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            AppColors.gold.withValues(alpha: 0.35),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _HeroBackdropPainter old) =>
      old.progress != progress;
}
