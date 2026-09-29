import 'package:flutter/material.dart';

import '../../core/legal/legal_config.dart';
import '../../core/legal/legal_consent_models.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';

export '../../core/legal/legal_config.dart';

/// In-app legal document viewer for Privacy Policy and Terms of Service.
///
/// Required for App Store Review — Apple mandates that subscription apps
/// display Terms and Privacy Policy accessible before and after purchase.
class LegalScreen extends StatelessWidget {
  final LegalDocument document;

  const LegalScreen({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(document.title, style: AppTypography.titleMedium),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.base,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Effective Date: ${document.effectiveDate}',
                  style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'v${document.version}',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.goldDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (!LegalConfig.isConfigured) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                key: const ValueKey('legal_pending_config_notice'),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.amber, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Configuration Notice: Operator legal identity and jurisdiction details '
                        'must be provided prior to public app store release.',
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            ..._buildSections(document),
            const SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSections(LegalDocument doc) {
    final widgets = <Widget>[];
    for (final section in doc.sections) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(section.heading, style: AppTypography.titleSmall),
        ),
      );
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          child: Text(
            section.body,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}

/// A structured legal document with titled sections and version metadata.
class LegalDocument {
  final String title;
  final String version;
  final String effectiveDate;
  final List<LegalSection> sections;

  const LegalDocument({
    required this.title,
    required this.version,
    required this.effectiveDate,
    required this.sections,
  });
}

class LegalSection {
  final String heading;
  final String body;

  const LegalSection({required this.heading, required this.body});
}

/// Pre-built legal documents for CoinScan.
class CoinScanLegalDocs {
  const CoinScanLegalDocs._();

  static const termsOfService = LegalDocument(
    title: 'Terms & Conditions',
    version: LegalVersions.currentTermsVersion,
    effectiveDate: 'September 2026',
    sections: [
      LegalSection(
        heading: '1. Service Description & Acceptance of Terms',
        body:
            'CoinScan ("Service", "App") is a mobile numismatic identification and '
            'valuation utility provided by ${LegalConfig.entityName}. '
            'By creating an account, accessing, or using CoinScan, you agree to be bound '
            'by these Terms & Conditions and acknowledge our Privacy Policy. If you do not '
            'agree, you must not access or use the Service.',
      ),
      LegalSection(
        heading: '2. Account Responsibilities & Security',
        body:
            'To access authenticated features (including personal Collection Vault, '
            'cloud sync, and multi-device entitlements), you must create an account. '
            'You are responsible for maintaining the confidentiality of your login credentials '
            'and for all activities occurring under your account. You must be at least 13 '
            'years of age (or the applicable age of majority in your jurisdiction) to create an account.',
      ),
      LegalSection(
        heading: '3. Acceptable Use & Prohibited Conduct',
        body:
            'You agree to use CoinScan solely for personal numismatic purposes. '
            'You shall not: (a) reverse engineer, decompile, or extract source code from the App; '
            '(b) submit harmful, illegal, abusive, or infringing image files; '
            '(c) conduct automated scraping, bulk querying, or denial-of-service attacks; '
            '(d) attempt to bypass server-authoritative daily scan quotas, rate limits, or paywalls.',
      ),
      LegalSection(
        heading: '4. AI Identification & Machine Vision Limitations',
        body:
            'CoinScan employs automated machine-learning vision models to analyze physical coin '
            'photographs. AI-generated results are assistive estimates based strictly on photographic '
            'signals. Camera optics, glare, lighting, cleaning, wear, surface corrosion, and '
            'counterfeits can affect results. Identification outputs are not guaranteed to be free '
            'from error or misattribution.',
      ),
      LegalSection(
        heading: '5. No Guarantee of Authenticity, Grading, or Rarity',
        body:
            'IMPORTANT NUMISMATIC DISCLAIMER: Photographic analysis CANNOT establish physical coin '
            'authenticity, metal composition, exact weight, or genuine status with certainty. '
            'CoinScan DOES NOT guarantee that any scanned item is authentic, original, or a genuine mint issue. '
            'Visual condition estimates do NOT constitute certified grading from authorized services '
            '(such as PCGS or NGC). For high-value, rare, or disputed coins, always consult an accredited, '
            'in-person certified numismatist.',
      ),
      LegalSection(
        heading: '6. Valuation Disclaimer & Market Pricing',
        body:
            'All price valuations, catalogue guides, and bullion melt estimates provided in the App '
            'are automated algorithmic estimates ONLY and DO NOT constitute an offer to purchase, '
            'financial advice, certified appraisal, or guaranteed market realization value. '
            'Face value, catalogue value, bullion melt value, and realized auction comparables are '
            'distinct numismatic metrics. CoinScan assumes no liability for price discrepancies or '
            'market fluctuations.',
      ),
      LegalSection(
        heading: '7. User Responsibility for Financial & Trading Decisions',
        body:
            'You acknowledge and agree that any purchase, sale, trade, insurance, or investment decision '
            'involving physical coins or bullion is made at your sole discretion and risk. '
            'You must perform independent due diligence prior to engaging in commercial transactions.',
      ),
      LegalSection(
        heading: '8. Subscriptions, Billing, Renewals, & Cancellations',
        body:
            'CoinScan offers auto-renewing subscription tiers (Plus and Pro) billed monthly or annually. '
            'Payment is charged to your Apple ID (App Store) or Google Account (Google Play) upon purchase confirmation. '
            'Subscriptions automatically renew unless cancelled in your device account settings at least '
            '24 hours prior to the end of the current billing cycle. Cancellations take effect at the '
            'conclusion of the active billing period. Quota allocations (Free: 3/day, Plus: 30/day, Pro: 100/day fair-use) '
            'reset on a 24-hour UTC cycle.',
      ),
      LegalSection(
        heading: '9. Refunds & Store Policies',
        body:
            'All subscription purchases and refund requests are governed exclusively by the applicable '
            'platform policies of Apple App Store or Google Play Store. CoinScan does not directly '
            'collect, store, or process credit card credentials.',
      ),
      LegalSection(
        heading: '10. Intellectual Property & Numismatic Attribution',
        body:
            'The CoinScan application, visual design, custom glyphs, algorithms, and documentation are the '
            'exclusive intellectual property of ${LegalConfig.entityName}. '
            'Numismatic catalogue information is verified and attributed in compliance with the Numista '
            'licensing terms. You retain ownership of physical coin photographs you capture.',
      ),
      LegalSection(
        heading: '11. Third-Party Services & External APIs',
        body:
            'The Service communicates with trusted external infrastructure (including Google Gemini Vision AI '
            'under enterprise zero-data-retention terms, Numista API for catalogue verification, and '
            'financial bullion/FX spot providers). CoinScan is not responsible for downtime, rate limiting, '
            'or inaccuracies originating from third-party APIs.',
      ),
      LegalSection(
        heading: '12. Account Suspension & Termination',
        body:
            'We reserve the right to suspend or terminate your account and access to the Service without '
            'prior notice if you violate these Terms, engage in fraudulent payment activity, or abuse '
            'backend resources. You may terminate your account at any time via Account Settings.',
      ),
      LegalSection(
        heading: '13. Disclaimer of Warranties',
        body:
            'COINSCAN IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EITHER '
            'EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO IMPLIED WARRANTIES OF MERCHANTABILITY, '
            'FITNESS FOR A PARTICULAR PURPOSE, TITLE, AND NON-INFRINGEMENT.',
      ),
      LegalSection(
        heading: '14. Limitation of Liability',
        body:
            'TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, ${LegalConfig.entityName} AND ITS '
            'OFFICERS, DIRECTORS, EMPLOYEES, AND AGENTS SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, '
            'SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS, DATA, USE, OR NUMISMATIC '
            'VALUE ARISING OUT OF OR IN CONNECTION WITH YOUR ACCESS OR INABILITY TO ACCESS THE SERVICE.',
      ),
      LegalSection(
        heading: '15. Governing Law & Dispute Resolution',
        body:
            'These Terms shall be governed by and construed in accordance with the laws of '
            '${LegalConfig.governingJurisdiction}, without regard to conflict of law principles. '
            'Any dispute arising hereunder shall be resolved through binding individual arbitration '
            'where permissible by law.',
      ),
      LegalSection(
        heading: '16. Changes to Terms & Mandatory Re-Consent',
        body:
            'We may modify these Terms from time to time. In the event of material changes, the terms version '
            'will increment, and continued access to authenticated account features will require explicit '
            'acceptance of the updated Terms.',
      ),
      LegalSection(
        heading: '17. Contact Information',
        body:
            'For numismatic support, legal inquiries, or terms questions, please contact:\n'
            'Email: ${LegalConfig.supportEmail}\n'
            'Entity: ${LegalConfig.entityName}\n'
            'Address: ${LegalConfig.mailingAddress}',
      ),
    ],
  );

  static const privacyPolicy = LegalDocument(
    title: 'Privacy Policy',
    version: LegalVersions.currentPrivacyVersion,
    effectiveDate: 'September 2026',
    sections: [
      LegalSection(
        heading: '1. Introduction & Scope',
        body:
            'This Privacy Policy outlines how CoinScan ("${LegalConfig.entityName}", "we", "our") '
            'collects, processes, and protects your information when you use our mobile application and related APIs.',
      ),
      LegalSection(
        heading: '2. Ephemeral Coin Image Processing',
        body:
            'When you scan a coin, captured images (front, reverse, and optional edge) are transmitted '
            'via TLS 1.3 encryption to our backend recognition service. Images are processed in-memory '
            'strictly for visual feature extraction and are NOT permanently stored on CoinScan servers. '
            'Raw photographic files are discarded immediately upon completion of recognition.',
      ),
      LegalSection(
        heading: '3. AI Vision Provider & Zero Data Retention',
        body:
            'Visual feature analysis is performed using Google Gemini Vision AI under enterprise '
            'zero-data-retention agreements. Your coin images are NOT retained, NOT logged, and '
            'are NEVER used to train machine-learning models.',
      ),
      LegalSection(
        heading: '4. Numismatic Catalogue & Market Lookups',
        body:
            'Identified coin names and years are checked against the Numista catalogue database. '
            'These lookups transmit text metadata only (e.g. "Morgan Dollar 1882") — never your photos '
            'or personal information.',
      ),
      LegalSection(
        heading: '5. Local Storage & Account Data',
        body:
            'Your Collection Vault items, scan history records, and preferred currency settings are saved '
            'locally on your device. Authentication tokens are persisted securely using platform hardware '
            'security modules (iOS Keychain and Android Keystore).',
      ),
      LegalSection(
        heading: '6. Subscriptions & Payment Telemetry',
        body:
            'All monetary transactions are processed through Apple App Store or Google Play. '
            'CoinScan never receives or stores your credit card details. We receive pseudonymous '
            'entitlement verification events (via RevenueCat webhooks) solely to provision quota access.',
      ),
      LegalSection(
        heading: '7. Data Portability & Account Deletion Rights (GDPR / CCPA)',
        body:
            'You have full ownership of your numismatic data. You may at any time:\n'
            '• Export your complete structured data archive in standard JSON format (Account -> Data Management -> Export Data).\n'
            '• Permanently delete your account, credentials, collection vault, and scan history (Account -> Delete Account).\n'
            'Deletion is immediate and cascades across all subsystems.',
      ),
      LegalSection(
        heading: '8. Legal Consent Logging',
        body:
            'To demonstrate compliance with consumer protection and App Store guidelines, we log '
            'the legal version and timestamp of your Terms & Conditions and Privacy Policy acceptance. '
            'This consent record is strictly associated with your authenticated user identifier.',
      ),
      LegalSection(
        heading: '9. Children’s Privacy',
        body:
            'CoinScan does not knowingly collect or solicit personal information from children under '
            'the age of 13. If we discover that a child under 13 has provided personal data, we will '
            'promptly purge the account and associated records.',
      ),
      LegalSection(
        heading: '10. Privacy Inquiries & Data Protection Officer',
        body:
            'For inquiries regarding this Privacy Policy, data subject access requests, or privacy practices, '
            'contact us at:\n'
            'Email: ${LegalConfig.privacyEmail}\n'
            'Entity: ${LegalConfig.entityName}',
      ),
    ],
  );
}
