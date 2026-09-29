import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import '../../core/auth/auth_service.dart';
import '../../core/storage/scan_history_service.dart';
import '../../core/storage/collection_storage_service.dart';
import '../../core/subscriptions/subscription_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../help/help_center_screen.dart';
import '../feedback/feedback_screen.dart';
import '../subscription/paywall_screen.dart';
import 'legal_screen.dart';
import 'data_management_screen.dart';

/// Main Application Settings Screen with progressive disclosure.
class AccountSettingsScreen extends StatelessWidget {
  final SubscriptionService subscriptionService;
  final ScanHistoryService historyService;
  final CollectionStorageService collectionService;

  const AccountSettingsScreen({
    super.key,
    required this.subscriptionService,
    required this.historyService,
    required this.collectionService,
  });

  Future<void> _showSignOutDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('Sign Out?'),
        content: const Text(
          'Are you sure you want to sign out? Your session tokens and subscription state will be cleared from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign Out', style: TextStyle(color: AppColors.crimson)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await AuthService.instance.signOut();
      await subscriptionService.reset();
      // NOTE: Collection and scan history are NOT cleared on sign-out.
      // AuthService.signOut() already resets user context isolation.
      // Data destruction only occurs on explicit account deletion.
      if (context.mounted) {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Settings & Account', style: AppTypography.titleMedium),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          StreamBuilder<AuthState>(
            stream: AuthService.instance.authStateChanges,
            initialData: AuthService.instance.currentState,
            builder: (context, snapshot) {
              final authState = snapshot.data;
              if (authState != null && authState.isAuthenticated) {
                final user = authState.user;
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.xl),
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: AppRadius.allMd,
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.gold.withValues(alpha: 0.15),
                        child: const Icon(Icons.person_rounded, color: AppColors.gold, size: 28),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.displayName ?? 'Numismatist',
                              style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?.email ?? '',
                              style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          (user?.tier ?? 'FREE').toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          _buildSectionHeader('Account & Subscription'),
          _buildTile(
            context,
            icon: Icons.workspace_premium_rounded,
            title: 'Membership & Plans',
            subtitle: 'Upgrade to Plus or Pro for higher scan quotas',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PaywallScreen(subscriptionService: subscriptionService),
                ),
              );
            },
          ),
          _buildTile(
            context,
            icon: Icons.restore_rounded,
            title: 'Restore Purchases',
            subtitle: 'Reactivate previous App Store subscriptions',
            onTap: () async {
              await subscriptionService.restorePurchases();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Purchases restored.')),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildSectionHeader('Data & Privacy'),
          _buildTile(
            context,
            icon: Icons.security_rounded,
            title: 'Data Management & Privacy',
            subtitle: 'Export data, clear history, or delete account',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DataManagementScreen(
                    historyService: historyService,
                    collectionService: collectionService,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildSectionHeader('Help & Support'),
          _buildTile(
            context,
            icon: Icons.help_outline_rounded,
            title: 'Help Center & FAQs',
            subtitle: 'Numismatic guidelines, scanning tips, and value disclaimers',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HelpCenterScreen()),
              );
            },
          ),
          _buildTile(
            context,
            icon: Icons.feedback_outlined,
            title: 'Send Feedback & Bug Reports',
            subtitle: 'Report a recognition issue or suggest new features',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FeedbackScreen()),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildSectionHeader('Legal & Compliance'),
          _buildTile(
            context,
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'Zero image retention and data protection standards',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LegalScreen(
                    document: CoinScanLegalDocs.privacyPolicy,
                  ),
                ),
              );
            },
          ),
          _buildTile(
            context,
            icon: Icons.description_outlined,
            title: 'Terms of Service',
            subtitle: 'Numismatic estimates disclaimer & subscription terms',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LegalScreen(
                    document: CoinScanLegalDocs.termsOfService,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildSectionHeader('Account Session'),
          _buildTile(
            context,
            icon: Icons.logout_rounded,
            title: 'Sign Out',
            subtitle: 'Log out of this device and reset local session',
            onTap: () => _showSignOutDialog(context),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Center(
            child: Text(
              'CoinScan v1.0.0 (Build 1)',
              style: AppTypography.captionSmall.copyWith(color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        title,
        style: AppTypography.titleSmall.copyWith(color: AppColors.gold),
      ),
    );
  }

  Widget _buildTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      color: AppColors.cardBg,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.allMd,
        side: BorderSide(color: AppColors.border, width: 0.5),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.gold),
        title: Text(title, style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: AppTypography.caption),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        onTap: onTap,
      ),
    );
  }
}
