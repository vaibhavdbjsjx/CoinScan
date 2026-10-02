import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:coinvault_ai/core/recognition/recognition_models.dart';
import 'package:coinvault_ai/core/reports/coin_report_service.dart';
import 'package:coinvault_ai/core/storage/collection_storage_service.dart';
import 'package:coinvault_ai/core/storage/models.dart';
import 'package:coinvault_ai/core/utils/pdf_generator.dart';

/// Report / PDF integrity: an identification record, never a certificate, and
/// never filled with default confidence, grade, rarity or verification claims.
void main() {
  /// Extracts the page text from the uncompressed document. The pdf package
  /// writes each word as a `[(word)]TJ` text operator; join them with spaces.
  Future<String> pdfText(CoinReportData report) async {
    final doc = PdfGenerator.buildIdentificationReport(report, compress: false);
    final raw = latin1.decode(await doc.save(), allowInvalid: true);
    final words = RegExp(r'\[\(((?:[^()\\]|\\.)*)\)\]TJ')
        .allMatches(raw)
        .map((m) => m.group(1)!.replaceAll(r'\(', '(').replaceAll(r'\)', ')'));
    return words.join(' ');
  }

  test('PDF is titled as an identification report and states limitations', () async {
    final text = await pdfText(
      CoinReportData(
        title: '1882 United States 1 Dollar',
        country: 'United States',
        denomination: '1 Dollar',
        identificationConfidence: 'Medium',
        generatedAt: DateTime(2026, 9, 30),
      ),
    );
    expect(text, contains('Coin Identification Report'));
    expect(text, contains('Authenticity: not assessed'));
    expect(text, contains('It is not a certificate'));
    for (final forbidden in ['Official', 'Certificate of', 'Sheldon Grade', 'Rarity Level', 'Report ID', '% Match']) {
      expect(text, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('Unrecorded fields are "Not recorded", never defaulted', () async {
    final text = await pdfText(
      CoinReportData(
        title: 'Unknown coin',
        country: 'Unknown',
        denomination: 'Coin',
        identificationConfidence: 'Not recorded',
        generatedAt: DateTime(2026, 9, 30),
      ),
    );
    expect(text, contains('Not recorded'));
    expect(text, contains('No verified valuation was available'));
    expect(text, isNot(contains('88')));
    expect(text, isNot(contains('Circulated')));
  });

  test('Report from a scan uses the service evidence and never invents a grade', () {
    const candidate = RecognitionCandidate(
      coinId: 'numista_1',
      providerName: 'test',
      identity: CoinIdentity(country: 'France', denomination: '1 Franc', year: 1999),
      confidence: RecognitionConfidence(
        level: ConfidenceLevel.low,
        overallScore: 0.5,
        explanation: 'Possible match.',
      ),
      evidence: [
        RecognitionEvidence(
          type: RecognitionEvidenceType.year,
          label: 'Date 1999 (unverified)',
          detail: 'Read from the photo.',
          source: 'Vision AI (read from photo)',
        ),
      ],
    );
    final report = CoinReportData.fromCandidate(candidate);
    expect(report.identificationConfidence, 'Low');
    expect(report.conditionGrade, isNull);
    expect(report.keyEvidence.single, contains('Source: Vision AI'));
    expect(report.keyEvidence.join(), isNot(contains('verified:')));
  });

  test('Vault item without confidence reports "Not recorded" and no rarity', () {
    final item = VaultCoinItem(
      id: 'v1',
      coinName: 'Coin',
      country: 'France',
      denomination: '1 Franc',
      dateAdded: DateTime(2026, 9, 30),
    );
    expect(CoinReportData.fromVaultItem(item).identificationConfidence, 'Not recorded');
    final model = item.toCollectibleModel();
    expect(model.identificationConfidence, isNull);
    expect(model.rarity, RarityLevel.notAssessed);
    expect(model.edgeType, isEmpty);
    expect(model.estimatedGrade, isEmpty);
    expect(model.historicalInfo, isEmpty);
  });

  test('Strict precious-metal parsing matches the backend rules', () {
    PreciousMetalContent? p(String s) => PreciousMetalContent.parse(s);
    expect(p('Nordic gold'), isNull);
    expect(p('Nickel silver'), isNull);
    expect(p('Brass (gold-plated)'), isNull);
    expect(p('Silver'), isNull);
    expect(p('Silver (.900)')!.fineness, 0.9);
    expect(p('Sterling Silver')!.metal, PreciousMetal.silver);
    expect(p('90% Gold, 10% Copper')!.metal, PreciousMetal.gold);
    expect(p('Bimetallic: gold (.900) centre, silver (.925) ring'), isNull);
  });
}
