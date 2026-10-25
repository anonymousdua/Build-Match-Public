import 'package:intl/intl.dart';

class Fmt {
  Fmt._();

  static final _date = DateFormat('dd MMM yyyy');
  static final _amount = NumberFormat('#,##0.##');
  static final _qty = NumberFormat('#,##0.###');

  static String date(DateTime? d) => d == null ? '—' : _date.format(d.toLocal());

  /// 'AED 678,756.4'
  static String aed(num? v) => v == null ? '—' : 'AED ${_amount.format(v)}';

  /// 'AED 20 – 24'
  static String aedRange(num? min, num? max) {
    if (min == null && max == null) return '—';
    if (min != null && max != null && min != max) return 'AED ${_amount.format(min)} – ${_amount.format(max)}';
    return 'AED ${_amount.format(min ?? max!)}';
  }

  static String qty(num? v) => v == null ? '—' : _qty.format(v);

  static String percent(num? v) => v == null ? '—' : '${v.round()}%';

  /// For populating text fields from numbers without trailing ".0".
  static String plainNumber(num? v) {
    if (v == null) return '';
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  /// Date for the API ('2026-11-20').
  static String isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? parseDate(Object? v) => v == null ? null : DateTime.tryParse(v.toString());

  static double? parseDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int parseInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static String greeting([DateTime? now]) {
    final h = (now ?? DateTime.now()).hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}
