import 'countries.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// 30.9, 0.11, 12 — one decimal, two below 1, no trailing ".0".
String formatAmount(double value) {
  final s = value.toStringAsFixed(value < 1 ? 2 : 1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String formatTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "Today", "Yesterday", "Mon 12 Oct", or with the year when it isn't this year.
String formatDay(DateTime d, {DateTime? now}) {
  now ??= DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  final base = '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
  return d.year == now.year ? base : '$base ${d.year}';
}

/// Regional-indicator emoji for an ISO 3166 code: "TR" → 🇹🇷.
String flagOf(String code) =>
    String.fromCharCodes(code.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 0x41));

String countryName(String code) => countryNames[code.toUpperCase()] ?? code;

/// Lowercase without diacritics, so "turk" finds "Türkiye".
String fold(String s) {
  const from = 'áàâäãåçéèêëíìîïıñóòôöõøşúùûüğýÿ';
  const to = 'aaaaaaceeeeiiiiinoooooosuuuugyy';
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    out.write(i < 0 ? ch : to[i]);
  }
  return out.toString();
}
