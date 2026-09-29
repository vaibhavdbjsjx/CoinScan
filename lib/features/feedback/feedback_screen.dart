import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';

/// Screen for sending feedback, reporting bugs, or suggesting features.
class FeedbackScreen extends StatefulWidget {
  final String? initialCategory;
  final String? scanRequestId;

  const FeedbackScreen({
    super.key,
    this.initialCategory,
    this.scanRequestId,
  });

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  late String _selectedCategory;
  bool _isSubmitting = false;

  final List<Map<String, String>> _categories = const [
    {'id': 'recognition_incorrect', 'label': 'Coin Identification Issue'},
    {'id': 'valuation_incorrect', 'label': 'Valuation or Pricing Error'},
    {'id': 'camera_problem', 'label': 'Camera / Viewfinder Problem'},
    {'id': 'gallery_problem', 'label': 'Photo Library Import Issue'},
    {'id': 'subscription_problem', 'label': 'Subscription or Quota Issue'},
    {'id': 'app_crash', 'label': 'App Crash / Freezing'},
    {'id': 'feature_request', 'label': 'Feature Suggestion'},
    {'id': 'other', 'label': 'Other Feedback'},
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? 'recognition_incorrect';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);

    try {
      final payload = {
        'category': _selectedCategory,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'app_version': '1.0.0',
        'build_number': '1',
        'platform': kIsWeb
            ? 'web'
            : (defaultTargetPlatform == TargetPlatform.android
                ? 'android'
                : 'ios'),
        if (widget.scanRequestId != null) 'request_id': widget.scanRequestId,
      };

      await ApiClient.instance.post('/v1/feedback', body: payload);

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          title: const Text('Thank You!'),
          content: const Text(
            'Your feedback has been received. Our numismatic engineering team reviews every report to improve CoinScan.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Done', style: TextStyle(color: AppColors.gold)),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      String errorMsg = e.message;
      if (e.isRateLimited) {
        errorMsg = 'Too many submissions. Please wait a few minutes before submitting another report.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: AppColors.crimson,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit feedback: $e'),
          backgroundColor: AppColors.crimson,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Send Feedback', style: AppTypography.titleMedium),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Topic Category', style: AppTypography.caption),
              const SizedBox(height: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: AppRadius.allMd,
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCategory,
                    dropdownColor: AppColors.cardBg,
                    style: AppTypography.bodyMedium,
                    isExpanded: true,
                    items: _categories.map((c) {
                      return DropdownMenuItem<String>(
                        value: c['id'],
                        child: Text(c['label']!),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedCategory = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Summary', style: AppTypography.caption),
              const SizedBox(height: AppSpacing.xs),
              TextFormField(
                controller: _titleController,
                style: AppTypography.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Brief summary of the issue or idea',
                  hintStyle: AppTypography.caption.copyWith(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.cardBg,
                  border: const OutlineInputBorder(
                    borderRadius: AppRadius.allMd,
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 3) {
                    return 'Please enter a short title (min 3 characters)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Details', style: AppTypography.caption),
              const SizedBox(height: AppSpacing.xs),
              TextFormField(
                controller: _descriptionController,
                maxLines: 5,
                style: AppTypography.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Describe what happened or what you would like to see...',
                  hintStyle: AppTypography.caption.copyWith(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.cardBg,
                  border: const OutlineInputBorder(
                    borderRadius: AppRadius.allMd,
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 5) {
                    return 'Please provide more detail (min 5 characters)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Note: Diagnostic device info (iOS/Android version, CoinScan build) is automatically attached. '
                'Photos and private account credentials are never shared.',
                style: AppTypography.caption.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.xxl),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  shape: const RoundedRectangleBorder(borderRadius: AppRadius.allMd),
                ),
                onPressed: _isSubmitting ? null : _submitFeedback,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('Submit Feedback', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
