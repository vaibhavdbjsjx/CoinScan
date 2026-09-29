import 'package:intl/intl.dart';

/// Shared value formatting.
///
/// Prices were previously formatted inline at eight different call sites with
/// slightly different rules (`2.9k` here, `2850000` there), which is why the
/// same coin could show three different prices across the app. Everything now
/// routes through here.
class Fmt {
  const Fmt._();

  static final NumberFormat _whole = NumberFormat.currency(
    locale: 'en_US',
    symbol: r'$',
    decimalDigits: 0,
  );

  static final NumberFormat _plain = NumberFormat.decimalPattern('en_US');

  /// `$2,850,000` — full precision, for detail views and totals.
  static String money(num value) => _whole.format(value);

  /// `$2.85M` / `$4.2K` / `$650` — for cards and rails where space is tight.
  ///
  /// Thresholds are chosen so a value never renders with a misleading single
  /// significant digit (`$1M` for $1,449,000).
  static String moneyCompact(num value) {
    final v = value.abs();
    if (v >= 1000000) {
      return '\$${(value / 1000000).toStringAsFixed(v >= 10000000 ? 1 : 2)}M';
    }
    if (v >= 10000) return '\$${(value / 1000).toStringAsFixed(1)}K';
    return _whole.format(value);
  }

  /// `1,204`
  static String count(num value) => _plain.format(value);

  /// `+12.4%` / `−3.1%` — always signed, using a true minus glyph.
  static String percentDelta(num value) {
    final sign = value > 0 ? '+' : (value < 0 ? '−' : '');
    return '$sign${value.abs().toStringAsFixed(1)}%';
  }

  /// `1907` or `440 BC`.
  static String year(int value) =>
      value < 0 ? '${value.abs()} BC' : value.toString();

  /// `12 Apr 2025`
  static String date(DateTime value) => DateFormat('d MMM yyyy').format(value);

  /// Time-of-day greeting for the dashboard header.
  static String greeting([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}
