/// Strict precious-metal detection for coin compositions.
///
/// Mirrors the backend's `parse_precious_metal_fineness`: a composition only
/// counts as precious metal when it states a fineness explicitly (for example
/// "Silver (.900)", "90% silver", "0.999 fine gold") or names a defined
/// standard ("sterling silver"). Alloy names are never guessed from keywords:
/// "Nordic gold" and "nickel silver" contain no gold or silver, and plated or
/// gilt coins are not precious-metal coins.
library;

enum PreciousMetal { silver, gold, platinum }

class PreciousMetalContent {
  final PreciousMetal metal;

  /// Fine metal fraction, 0 < fineness <= 1.
  final double fineness;

  const PreciousMetalContent(this.metal, this.fineness);

  String get displayName => switch (metal) {
    PreciousMetal.silver => 'Silver',
    PreciousMetal.gold => 'Gold',
    PreciousMetal.platinum => 'Platinum',
  };

  static const _nonPreciousMarkers = [
    'plated',
    'gilt',
    'gilded',
    'coated',
    'nickel silver',
    'german silver',
    'nordic gold',
    'gold-colored',
    'gold coloured',
    'gold-coloured',
    'silver-colored',
    'silver coloured',
  ];

  static const _metalPattern = r'(silver|gold|platinum)';

  static final _patterns = <(RegExp, String)>[
    (
      RegExp(_metalPattern + r'\s*\(\s*(0?\.\d{2,4}|\d{3,4}(?:\.\d+)?)\s*\)'),
      'metal_first',
    ),
    (RegExp(r'(\d{1,3}(?:\.\d+)?)\s*%\s*' + _metalPattern), 'percent'),
    (
      RegExp(r'(?<![\d.])(0?\.\d{3,4})\s*(?:fine\s+)?' + _metalPattern),
      'decimal',
    ),
    (
      RegExp(r'(?<![\d.%])(\d{3}(?:\.\d)?)\s*(?:fine\s+)?' + _metalPattern),
      'millesimal',
    ),
  ];

  /// Returns the explicitly stated precious-metal content, or null.
  static PreciousMetalContent? parse(String? composition) {
    if (composition == null || composition.trim().isEmpty) return null;
    final text = composition.toLowerCase();
    if (_nonPreciousMarkers.any(text.contains)) return null;

    final found = <PreciousMetal, Set<double>>{};
    void add(PreciousMetal metal, double value) {
      if (value > 0 && value <= 1) {
        found
            .putIfAbsent(metal, () => <double>{})
            .add(double.parse(value.toStringAsFixed(4)));
      }
    }

    if (text.contains('sterling silver') || text.contains('sterling')) {
      add(PreciousMetal.silver, 0.925);
    }

    for (final (pattern, kind) in _patterns) {
      for (final match in pattern.allMatches(text)) {
        final String rawValue;
        final String metalName;
        if (kind == 'metal_first') {
          metalName = match.group(1)!;
          rawValue = match.group(2)!;
        } else {
          rawValue = match.group(1)!;
          metalName = match.group(2)!;
        }
        var value = double.tryParse(rawValue);
        if (value == null) continue;
        if (kind == 'percent') {
          value = value / 100.0;
        } else if (value > 1.0) {
          value = value / 1000.0;
        }
        add(_metalFromName(metalName), value);
      }
    }

    // Nothing explicit, or ambiguous (bimetallic / contradictory statements).
    if (found.length != 1) return null;
    final entry = found.entries.first;
    if (entry.value.length != 1) return null;
    return PreciousMetalContent(entry.key, entry.value.first);
  }

  static PreciousMetal _metalFromName(String name) => switch (name) {
    'gold' => PreciousMetal.gold,
    'platinum' => PreciousMetal.platinum,
    _ => PreciousMetal.silver,
  };
}
