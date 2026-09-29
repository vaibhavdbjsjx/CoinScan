import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../collection/collection_vault_screen.dart';
import '../market/marketplace_screen.dart';
import '../profile/profile_screen.dart';
import '../scan/scan_screen.dart';
import 'home_screen.dart';

/// App shell: four tabs plus a raised scan action.
///
/// The bar floats over the content, so every screen needs to know how much
/// space to leave at the bottom of its scroll view. That number lives in one
/// place — [contentBottomInset] — instead of being guessed at as a magic `120`
/// in five different files.
class MainNavigationWrapper extends StatefulWidget {
  const MainNavigationWrapper({super.key});

  /// Height of the floating bar itself.
  static const double barHeight = 66;

  /// Distance from the bottom safe area to the bar.
  static const double barBottomMargin = AppSpacing.md;

  /// Bottom padding a scrollable screen must reserve so its last item clears
  /// the floating bar (including the device home indicator).
  static double contentBottomInset(BuildContext context) =>
      barHeight +
      barBottomMargin +
      MediaQuery.paddingOf(context).bottom +
      AppSpacing.lg;

  @override
  State<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends State<MainNavigationWrapper> {
  int _currentTab = 0;

  /// Lets one tab deep-link into another's inner tab (e.g. Home → Learning
  /// Hub). Bumped as a key so the target screen rebuilds on its new index.
  int _profileSubTab = 0;
  int _profileKey = 0;

  void _goToTab(int index, {int? subTab}) {
    HapticFeedback.selectionClick();
    setState(() {
      _currentTab = index;
      if (index == 3 && subTab != null && subTab != _profileSubTab) {
        _profileSubTab = subTab;
        _profileKey++;
      }
    });
  }

  void _openScanner() {
    HapticFeedback.mediumImpact();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (context) => const ScanScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      // The bar is drawn above content, so don't let the Scaffold also resize
      // for the keyboard — that would jump the bar into the middle of the page.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // IndexedStack keeps each tab's scroll position and state alive.
          IndexedStack(
            index: _currentTab,
            children: [
              HomeScreen(onTabChange: _goToTab, onScanPressed: _openScanner),
              CollectionVaultScreen(onScanPressed: _openScanner),
              const MarketplaceScreen(),
              ProfileScreen(
                key: ValueKey('profile_$_profileKey'),
                initialTab: _profileSubTab,
              ),
            ],
          ),

          Positioned(
            left: AppSpacing.base,
            right: AppSpacing.base,
            bottom: bottomInset + MainNavigationWrapper.barBottomMargin,
            child: _NavBar(currentTab: _currentTab, onTabSelected: _goToTab),
          ),

          // Raised centre action, sitting in the bar's reserved gap.
          Positioned(
            left: 0,
            right: 0,
            bottom:
                bottomInset +
                MainNavigationWrapper.barBottomMargin +
                (MainNavigationWrapper.barHeight - 56) / 2,
            child: Center(child: ScanFab(onPressed: _openScanner)),
          ),
        ],
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int currentTab;
  final void Function(int) onTabSelected;

  const _NavBar({required this.currentTab, required this.onTabSelected});

  static const _items = [
    (Icons.explore_outlined, Icons.explore_rounded, 'Home', 0),
    (Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Vault', 1),
    (Icons.storefront_outlined, Icons.storefront_rounded, 'Market', 2),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile', 3),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.allXl,
      child: BackdropFilter(
        // Real translucency: content blurs under the bar as it scrolls past.
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: MainNavigationWrapper.barHeight,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: AppRadius.allXl,
            border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
            boxShadow: AppShadows.level3,
          ),
          child: Row(
            children: [
              for (final (icon, activeIcon, label, index) in _items) ...[
                Expanded(
                  child: _NavBarItem(
                    icon: icon,
                    activeIcon: activeIcon,
                    label: label,
                    isActive: currentTab == index,
                    onTap: () => onTabSelected(index),
                  ),
                ),
                // Gap for the raised scan button, between Vault and Market.
                if (index == 1) const SizedBox(width: 64),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.goldInk : AppColors.textSecondary;

    return Semantics(
      button: true,
      selected: isActive,
      label: label,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.allMd,
          splashColor: AppColors.gold.withValues(alpha: 0.1),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The dot marks the active tab without shifting layout, so the
              // row never reflows as the user moves between tabs.
              AnimatedContainer(
                duration: AppDuration.base,
                curve: AppCurves.standard,
                height: 3,
                width: isActive ? 16 : 0,
                margin: const EdgeInsets.only(bottom: 5),
                decoration: BoxDecoration(
                  gradient: AppColors.goldGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              AnimatedSwitcher(
                duration: AppDuration.fast,
                child: Icon(
                  isActive ? activeIcon : icon,
                  key: ValueKey(isActive),
                  color: color,
                  size: 21,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: AppDuration.fast,
                style: AppTypography.captionSmall.copyWith(
                  color: color,
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Raised centre action. Lives inside the bar's Stack so it can overhang the
/// top edge without being clipped.
class ScanFab extends StatelessWidget {
  final VoidCallback onPressed;

  const ScanFab({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Scan a collectible',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                gradient: AppColors.goldGradient,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: AppShadows.goldGlow(opacity: 0.42),
              ),
              child: const Icon(
                Icons.center_focus_strong_rounded,
                color: AppColors.onGold,
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
