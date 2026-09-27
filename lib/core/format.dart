import 'package:intl/intl.dart';

String currencySymbol = 'Rs';

final _money = NumberFormat('#,##0.##', 'en_US');
final _date = DateFormat('d MMM y');
final _dateTime = DateFormat('d MMM y, h:mm a');
final _month = DateFormat('MMM y');
final _iso = DateFormat('yyyy-MM-dd');

double toDouble(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

int toInt(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

String money(Object? v, {bool symbol = true}) {
  final n = toDouble(v);
  final s = _money.format(n.abs());
  return '${n < 0 ? '-' : ''}${symbol ? '$currencySymbol ' : ''}$s';
}

String fmtDate(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '—' : _date.format(d);
}

String fmtDateTime(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '—' : _dateTime.format(d);
}

String fmtMonth(Object? ym) {
  final d = DateTime.tryParse('${ym ?? ''}-01');
  return d == null ? '—' : _month.format(d);
}

String isoDate(DateTime d) => _iso.format(d);

String isoMonth(DateTime d) => DateFormat('yyyy-MM').format(d);

String today() => isoDate(DateTime.now());

String firstOfMonth([DateTime? d]) {
  final x = d ?? DateTime.now();
  return isoDate(DateTime(x.year, x.month, 1));
}

String lastOfMonth([DateTime? d]) {
  final x = d ?? DateTime.now();
  return isoDate(DateTime(x.year, x.month + 1, 0));
}

String orDash(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s.isEmpty ? '—' : s;
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = parts.first[0];
  final last = parts.length > 1 ? parts.last[0] : '';
  return (first + last).toUpperCase();
}

String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
