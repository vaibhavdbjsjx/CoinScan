import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:coinvault_ai/features/profile/legal_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Legal Configuration & Safety Tests', () {
    test('1. LegalConfig identifies unconfigured defaults as pending', () {
      // By default in test runs without --dart-define, configuration must be pending
      expect(LegalConfig.isConfigured, isFalse);
      expect(LegalConfig.entityName, contains('PENDING'));
      expect(LegalConfig.governingJurisdiction, contains('PENDING'));
      expect(LegalConfig.mailingAddress, contains('PENDING'));

      final pending = LegalConfig.pendingRequirements;
      expect(pending, hasLength(3));
      expect(pending[0], contains('LEGAL_ENTITY_NAME'));
      expect(pending[1], contains('LEGAL_GOVERNING_JURISDICTION'));
      expect(pending[2], contains('LEGAL_MAILING_ADDRESS'));
    });

    test('2. Legal documents contain no unresolved [PLACEHOLDER] raw strings', () {
      const terms = CoinScanLegalDocs.termsOfService;
      for (final sec in terms.sections) {
        expect(sec.body.contains('[LEGAL_ENTITY_NAME_PLACEHOLDER]'), isFalse);
        expect(sec.body.contains('[GOVERNING_JURISDICTION_PLACEHOLDER]'), isFalse);
        expect(sec.body.contains('[LEGAL_MAILING_ADDRESS_PLACEHOLDER]'), isFalse);
      }

      const privacy = CoinScanLegalDocs.privacyPolicy;
      for (final sec in privacy.sections) {
        expect(sec.body.contains('[LEGAL_ENTITY_NAME_PLACEHOLDER]'), isFalse);
        expect(sec.body.contains('[GOVERNING_JURISDICTION_PLACEHOLDER]'), isFalse);
        expect(sec.body.contains('[LEGAL_MAILING_ADDRESS_PLACEHOLDER]'), isFalse);
      }
    });

    testWidgets('3. LegalScreen renders configuration warning notice when unconfigured', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LegalScreen(document: CoinScanLegalDocs.termsOfService),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('legal_pending_config_notice')), findsOneWidget);
      expect(
        find.text(
          'Configuration Notice: Operator legal identity and jurisdiction details '
          'must be provided prior to public app store release.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('4. LegalScreen renders disclaimers and disclosures cleanly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LegalScreen(document: CoinScanLegalDocs.termsOfService),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Terms & Conditions'), findsWidgets);
      expect(find.text('4. AI Identification & Machine Vision Limitations'), findsOneWidget);
      expect(find.text('5. No Guarantee of Authenticity, Grading, or Rarity'), findsOneWidget);
      expect(find.text('6. Valuation Disclaimer & Market Pricing'), findsOneWidget);
      expect(find.text('8. Subscriptions, Billing, Renewals, & Cancellations'), findsOneWidget);
    });
  });
}
