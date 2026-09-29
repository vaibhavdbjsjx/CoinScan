import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/auth/auth_service.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/scan_history_service.dart';
import '../../core/storage/collection_storage_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../main.dart';

/// Data Management & Privacy Controls Screen.
///
/// Supports:
/// - Export scan history & collection metadata (JSON format)
/// - Clear local scan history
/// - Clear local collection vault
/// - Permanent Account Deletion with mandatory confirmation phrase
class DataManagementScreen extends StatefulWidget {
  final ScanHistoryService historyService;
  final CollectionStorageService collectionService;

  const DataManagementScreen({
    super.key,
    required this.historyService,
    required this.collectionService,
  });

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  bool _isExporting = false;

  Future<void> _exportData() async {
    setState(() => _isExporting = true);
    Map<String, dynamic>? serverData;
    if (AuthService.instance.currentState.isAuthenticated) {
      try {
        serverData = await ApiClient.instance.exportAccountData();
      } catch (e) {
        debugPrint('Server data export non-fatal failure: $e');
      }
    }

    final historyJsonString = await widget.historyService.exportToJson();
    final collectionJsonString = await widget.collectionService.exportToJson();

    dynamic parsedHistory;
    dynamic parsedCollection;
    try {
      parsedHistory = jsonDecode(historyJsonString);
    } catch (_) {
      parsedHistory = historyJsonString;
    }
    try {
      parsedCollection = jsonDecode(collectionJsonString);
    } catch (_) {
      parsedCollection = collectionJsonString;
    }

    final exportBundle = {
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'app_version': '1.0.0',
      'user_id': AuthService.instance.currentState.user?.userId ?? 'guest',
      'account_metadata': serverData,
      'vault_collection': parsedCollection,
      'scan_history': parsedHistory,
    };

    final finalJsonString = const JsonEncoder.withIndent('  ').convert(exportBundle);

    String? savedFilePath;
    if (!kIsWeb) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final file = File('${dir.path}/coinscan_data_export_$timestamp.json');
        await file.writeAsString(finalJsonString, flush: true);
        savedFilePath = file.path;
      } catch (e) {
        debugPrint('File write export error: $e');
      }
    }

    await Clipboard.setData(ClipboardData(text: finalJsonString));
    setState(() => _isExporting = false);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('Data Export Ready'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your machine-readable data export (${finalJsonString.length} bytes) has been generated and copied to your clipboard.',
              style: AppTypography.bodyMedium,
            ),
            if (savedFilePath != null) ...[
              const SizedBox(height: 12),
              Text(
                'Archive saved to:\n$savedFilePath',
                style: AppTypography.caption.copyWith(fontSize: 11),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: finalJsonString));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Export JSON copied to clipboard.')),
                );
              }
            },
            child: const Text('Copy Again', style: TextStyle(color: AppColors.gold)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('Clear Scan History?'),
        content: const Text(
          'This will permanently delete all local coin scan records from this device. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear', style: TextStyle(color: AppColors.crimson)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.historyService.clearHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan history cleared.')),
      );
    }
  }

  Future<void> _deleteAccount() async {
    final textController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('Delete Account Permanently?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will permanently delete your account, saved collections, scan records, and active API keys. '
              'Active Apple App Store subscriptions should be cancelled in your device settings.\n\n'
              'Type "DELETE MY ACCOUNT" to confirm:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: textController,
              style: AppTypography.bodyMedium,
              decoration: const InputDecoration(
                hintText: 'DELETE MY ACCOUNT',
                filled: true,
                fillColor: AppColors.surface,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (textController.text.trim().toUpperCase() == 'DELETE MY ACCOUNT') {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Delete Permanently', style: TextStyle(color: AppColors.crimson)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const PopScope(
          canPop: false,
          child: Center(
            child: Card(
              color: AppColors.cardBg,
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.gold),
                    SizedBox(height: AppSpacing.lg),
                    Text(
                      'Permanently deleting account...',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      try {
        await AuthService.instance.deleteAccount();

        await widget.historyService.clearHistory();
        await widget.collectionService.clearCollection();
        if (mounted) {
          final subService = SubscriptionProvider.maybeOf(context);
          await subService?.reset();
        }

        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account and all associated records permanently deleted.')),
        );
        context.go('/login');
      } catch (e) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();

        String message = 'Failed to delete account on server. Your local data has not been deleted.';
        if (e is ApiException) {
          message = e.message;
        }
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.cardBg,
            title: const Text('Deletion Failed'),
            content: Text(message, style: const TextStyle(color: AppColors.textSecondary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK', style: TextStyle(color: AppColors.gold)),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Data & Privacy', style: AppTypography.titleMedium),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          _buildSectionHeader('Data Portability'),
          _buildActionCard(
            title: 'Export My Data',
            subtitle: 'Download your scan history and collection records in JSON format.',
            icon: Icons.download_rounded,
            onTap: _isExporting ? null : _exportData,
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildSectionHeader('Local Storage Management'),
          _buildActionCard(
            title: 'Clear Scan History',
            subtitle: 'Delete locally stored recognition records.',
            icon: Icons.history_rounded,
            onTap: _clearHistory,
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildSectionHeader('Danger Zone'),
          _buildActionCard(
            title: 'Delete Account & Data',
            subtitle: 'Permanently remove all numismatic data, collections, and linked credentials.',
            icon: Icons.delete_forever_rounded,
            isDestructive: true,
            onTap: _deleteAccount,
          ),
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

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    return Card(
      color: AppColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.allMd,
        side: BorderSide(
          color: isDestructive
              ? AppColors.crimson.withValues(alpha: 0.4)
              : AppColors.border,
          width: 0.5,
        ),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isDestructive ? AppColors.crimson : AppColors.gold,
        ),
        title: Text(
          title,
          style: AppTypography.bodyMedium.copyWith(
            color: isDestructive ? AppColors.crimson : AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(subtitle, style: AppTypography.caption),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        onTap: onTap,
      ),
    );
  }
}
