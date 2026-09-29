/// Legal entity configuration and compile-time overrides.
///
/// ## Mandatory Release Requirement
/// Before publishing to Apple App Store or Google Play Store, the operator MUST
/// supply the real legal entity name, registered jurisdiction, and physical mailing address.
///
/// These values can be provided at compile-time via `--dart-define`:
///   --dart-define=LEGAL_ENTITY_NAME="Acme Numismatics LLC"
///   --dart-define=LEGAL_GOVERNING_JURISDICTION="Delaware, United States"
///   --dart-define=LEGAL_MAILING_ADDRESS="123 Main St, Suite 100, Wilmington, DE 19801"
///   --dart-define=LEGAL_SUPPORT_EMAIL="support@coinscan.app"
///   --dart-define=LEGAL_PRIVACY_EMAIL="privacy@coinscan.app"
///
/// If unprovided, the app falls back to clear, honest placeholder descriptors
/// that are prominently flagged so unverified entities are NEVER misrepresented as real.
class LegalConfig {
  const LegalConfig._();

  static const String entityName = String.fromEnvironment(
    'LEGAL_ENTITY_NAME',
    defaultValue: '[LEGAL ENTITY PENDING — Configuration Required Before Release]',
  );

  static const String governingJurisdiction = String.fromEnvironment(
    'LEGAL_GOVERNING_JURISDICTION',
    defaultValue: '[GOVERNING JURISDICTION PENDING — Configuration Required Before Release]',
  );

  static const String mailingAddress = String.fromEnvironment(
    'LEGAL_MAILING_ADDRESS',
    defaultValue: '[LEGAL MAILING ADDRESS PENDING — Configuration Required Before Release]',
  );

  static const String supportEmail = String.fromEnvironment(
    'LEGAL_SUPPORT_EMAIL',
    defaultValue: 'support@coinscan.app',
  );

  static const String privacyEmail = String.fromEnvironment(
    'LEGAL_PRIVACY_EMAIL',
    defaultValue: 'privacy@coinscan.app',
  );

  /// Whether all mandatory legal identity fields have been configured.
  static bool get isConfigured =>
      !entityName.contains('PENDING') &&
      !governingJurisdiction.contains('PENDING') &&
      !mailingAddress.contains('PENDING');

  /// Identifies the list of pending legal items required for App Store submission.
  static List<String> get pendingRequirements {
    final pending = <String>[];
    if (entityName.contains('PENDING')) {
      pending.add('Legal Entity Name (LEGAL_ENTITY_NAME)');
    }
    if (governingJurisdiction.contains('PENDING')) {
      pending.add('Governing Jurisdiction (LEGAL_GOVERNING_JURISDICTION)');
    }
    if (mailingAddress.contains('PENDING')) {
      pending.add('Legal Mailing Address (LEGAL_MAILING_ADDRESS)');
    }
    return pending;
  }
}
