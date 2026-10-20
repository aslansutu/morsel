import 'dart:math';

import 'format.dart';
import 'vision.dart';

/// The nutrients Morsel reads from a label, as Open Food Facts nutrient ids, in
/// the order labels list them.
const labelNutrients = [
  'energy-kcal',
  'fat',
  'saturated-fat',
  'carbohydrates',
  'sugars',
  'fiber',
  'proteins',
  'salt',
];

/// What a label's amounts are for.
enum Basis { per100g, per100ml, unknown }

class LabelReading {
  const LabelReading(this.values, this.basis);

  /// Amount per [basis] by [labelNutrients] id: kcal for energy, grams for the
  /// rest. A nutrient the label didn't show is missing.
  final Map<String, double> values;
  final Basis basis;
}

// Row names in English, Turkish, Azerbaijani, German, French, Spanish, Italian,
// Dutch and Romanian, matched on folded text (lowercase, no diacritics), with
// common misreadings ("vag" for "yağ", "luz" for "tuz"). First match wins, so
// "saturated fat" comes before "fat".
final _names = <(String, RegExp)>[
  ('saturated-fat', RegExp(r'satur|doymus|gesattigt|verzadig')),
  ('sugars', RegExp(r'sugar|seker|zucker|sucre|azucar|zuccher|suiker|zahar')),
  // Not "yağlı" (fatty, as in "tam yağlı" full-fat) nor Dutch "vetzuren" (fatty acids).
  ('fat', RegExp(r'\bfat\b|\byag(?!li)|\bvag\b|\bfett|\bgras|\bvet(?!z)')),
  ('carbohydrates', RegExp(r'carbohydr|\bcarbs\b|karbon?hid|kohlenhyd|glucid|hidratos|carboid|koolhyd')),
  ('fiber', RegExp(r'\bfib(?:re|er|ra)|\blif(?:i|ler|leri)?\b|\bposa|ballaststoff|vezel')),
  ('proteins', RegExp(r'prote|pratein|e[il]we[il]ss|eiwit')),
  ('salt', RegExp(r'\bsalt\b|\b[tl]uz\b|\bsalz\b|\bsel\b|\bsal\b|\bsale\b|\bsare\b|\bzout\b')),
  ('sodium', RegExp(r'sodium|sodyum|natrium|sodio')),
  // Not "Enerji ve Besin Öğeleri", the title of a Turkish table.
  ('energy', RegExp(r'energ|enerj(?!i ve besin)|enerii|brennwert|calorie|kalori')),
];

// Words that, before or in a nutrient's name, make it a row Morsel doesn't read:
// other kinds of fat, polyols, added sugars, ingredient lists ("sugar, palm
// oil, …") and Turkish packs' "domuz yağı içermez" (contains no lard).
final _skip = RegExp(r'unsatur|insatur|ungesatt|onverzadig|doymamis|nesatur|mono|poly|poli|trans|'
    r'added sugar|ingredien|icindekiler|zutaten|domuz');

// A linear label is one paragraph: "fat 30,9 g, of which saturates 10,6 g; …".
// Commas followed by a digit are decimal commas, not separators.
final _separator = RegExp(r';|•|,\s+(?=\D)');

// A number that isn't a percentage of the reference intake ("44%", or "%24" as
// Turkish labels write it), nor part of a code ("TR.34K-011995") or a bracketed
// unit read as a digit ("(0" for "(g").
final _number = RegExp(r'(?<!%\s?)(?<![\d.,(-])(?<![a-z]\.)\d+(?:[.,]\d+)?(?!\s?%)(?![\d.,]*\d)');
// Nor a temperature ("+4 °C"), nor digits glued to stray letters ("2ffj", or a
// script read as digits, "30фj00"); a unit may follow straight on ("18g", "34г").
final _amount = RegExp(r'(?<!%\s?)(?<![\d.,(+-])(?<!\+\s)(?<![a-z]\.)(?<![a-z\u0430-\u044f\u10d0-\u10ff])'
    r'(\d+(?:[.,]\d+)?)(?![\d.,]*\d)(?!\))'
    r'(?!\s*°)(?![a-fh-jln-qs-z\u0430-\u0432\u0434-\u0439\u043b-\u044f\u10d0-\u10ff])\s*(mg|g)?(?!\s?%)');
// Units may come in two scripts: "557 ккал/kcal", "2325 кдж/kJ".
final _kcal = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:ккал\s*/\s*)?k?kcal|(\d+(?:[.,]\d+)?)\s*(?:kkal|ккал)');
final _kj = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:кдж\s*/\s*)?(?:kj|кдж)');
// "2 252 kJ", "2.252 kJ": a thousands separator, only ever in energy values.
final _thousands = RegExp(r"(?<!\d)(\d{1,2})[ .,'](\d{3})(?!\d)");
// Misreadings: 0 as the letter o ("o,5 g", "og"), a lost decimal comma after a leading
// zero ("02" for "0,2"), and units as digits: "(g)" after a row name as "(0)" or
// "(9)", a units column's "g-q" as "9-9", and 1 as i or l inside a number ("0.i0").
final _letterO = RegExp(r'(?<![a-z])o(?=[.,]\d|\s?m?g\b)');
final _letterOne = RegExp(r'(?<=\d[.,]?)[il](?=\d)');
final _lostDecimal = RegExp(r'(?<![\d.,])0(\d{1,2})(?![\d.,])');
final _unitInBrackets = RegExp(r'\(\s*(?:[0o9gq]|mg|ml)\s*\)');
// A row's units in several scripts, "(г/g/q/გ)", where გ reads as 8.
final _unitList = RegExp(r'\([^()\s]{0,8}(?:/[^()\s]{0,8})+\)');
final _unitPair = RegExp(r'(?<![\d.,])\d\s*-\s*\d(?![\d.,])');
// Column headings: "100 g", "100g'da", "100 ml", "per 100 gr", Azerbaijani "100q", "100 г".
final _per100 = RegExp(r'100\s*(?:g|gr|gram|grams|gramm|q|ml|г)(?![a-z])');

/// Reads a nutrition table from text recognised in a photo.
///
/// Finds the value columns and reads the per 100 g one: under a "100 g"
/// heading, or worked out from how the columns compare. Values the user must
/// check, not facts: the review form shows them next to the photo.
LabelReading parseLabel(List<TextLine> lines) {
  final rows = _rowsOf(lines);
  // Each nutrient name found: its id, the text after it, its row, and whether
  // it's a table row rather than part of a paragraph.
  final found = <(String, _Text, int, bool)>[];
  for (final (i, row) in rows.indexed) {
    // Only a row naming several nutrients is a paragraph to split; a comma in a
    // single row's names in several languages is not a separator.
    final ids = {for (final (id, name) in _names) if (name.hasMatch(row.text)) id};
    final segments = ids.length > 1 ? row.split(_separator) : [row];
    for (final segment in segments) {
      final skip = _skip.firstMatch(segment.text);
      for (final (id, name) in _names) {
        final match = name.firstMatch(segment.text);
        if (match == null) continue;
        // Words after the name are often the next column's text, not this row's.
        // Energy keeps its name, which can carry the unit: "Calories 230".
        if (skip == null || skip.start >= match.end) {
          found.add((id, segment.from(id == 'energy' ? match.start : match.end), i, segments.length == 1));
        }
        break;
      }
    }
  }

  // A nutrient's block: its name's lines (one per language on some labels) and
  // the lines under them that name nothing, which can hold its values.
  bool hasValue(_Text t) => _clean(t.text).contains(RegExp(r'\d'));
  // A line under a name lends it a value only if the value is a cell of its own
  // or carries a unit; prose under a table has numbers too ("17 porsiyondur").
  bool valueLike(_Text t) =>
      RegExp(r'\d').allMatches(t.text).any((m) => t.numbers[m.start]) ||
      RegExp(r'\d\s*(?:mg|g|kcal|kj|г|ккал|кдж)(?![a-z])').hasMatch(_clean(t.text));
  // A line starts another row when it names a nutrient, even one Morsel doesn't
  // read, or a unit the way a row name does: "luz (g)" is "Tuz (g)" misread.
  bool named(_Text t) =>
      _names.any((n) => n.$2.hasMatch(t.text)) ||
      _per100.hasMatch(t.text) ||
      RegExp(r'\((?:g|mg|kcal|kj|ml)\)|kalsiyum|calcium|vitamin|kolesterol|cholest').hasMatch(t.text);
  final blocks = <(String, List<_Text>, bool)>[];
  for (final (k, (id, text, i, inTable)) in found.indexed) {
    final values = [if (hasValue(text)) text];
    if (inTable) {
      final next = k + 1 < found.length ? found[k + 1].$3 : rows.length;
      for (var j = i + 1; j < next && j <= i + 3 && !named(rows[j]); j++) {
        if (hasValue(rows[j]) && valueLike(rows[j])) values.add(rows[j]);
      }
    }
    final last = blocks.lastOrNull;
    if (last != null && last.$1 == id && last.$3 && inTable) {
      last.$2.addAll(values);
    } else {
      blocks.add((id, values, inTable));
    }
  }
  // Some labels put a block's value on its last line, level with the next
  // block's name: "Fat / Grasas / …" with nothing, then "of which saturates"
  // with fat's 1,8 g and "bunun içerisinde doymuş yağ" with 0,2 g. A value can't
  // belong to two lines of one block, so the first goes up a block.
  // A block with percentages is a row whose amount went unread, not one waiting
  // for a value from below.
  bool amount(_Text t) => _grams(_clean(t.text)) != null;
  bool percent(_Text t) => t.text.contains('%');
  for (var k = 0; k + 1 < blocks.length; k++) {
    final (above, below) = (blocks[k], blocks[k + 1]);
    if (above.$3 && below.$3 && !above.$2.any((t) => amount(t) || percent(t)) &&
        below.$2.where(amount).length >= 2) {
      above.$2.add(below.$2.removeAt(below.$2.indexWhere(amount)));
    }
  }

  final columns = _columns(rows, [for (final b in blocks) if (b.$3) ...b.$2]);
  // Whether most amounts carry their unit ("10,6 g"), which tells a misread
  // unit from a lost decimal comma.
  final amounts = [
    for (final b in blocks)
      if (b.$1 != 'energy')
        for (final t in b.$2) ..._amount.allMatches(_clean((b.$3 && columns != null ? t.within(columns.per100) : t).text)),
  ];
  final unitsWritten = amounts.isNotEmpty && amounts.where((m) => m[2] != null).length >= amounts.length * 0.6;
  final values = <String, double>{};
  var energyGuessed = false;
  for (final (id, texts, inTable) in blocks) {
    final crop = inTable ? columns : null;
    String tail(_Text t) => _clean((crop == null ? t : t.within(crop.per100)).text);
    if (id == 'energy') {
      // An energy worked out from kJ, or guessed, gives way to a kcal printed further down.
      if (values.containsKey('energy-kcal') && !energyGuessed) continue;
      final (kcal, guessed) = _energy(texts.map(tail).join('  '));
      if (kcal != null && (!values.containsKey('energy-kcal') || !guessed)) {
        values['energy-kcal'] = kcal;
        energyGuessed = guessed;
      }
      continue;
    }
    if (values.containsKey(id)) continue;
    for (final text in texts) {
      var grams = _grams(tail(text), unitsWritten: unitsWritten);
      if (grams == null) continue;
      // Ten times what the other column says: the decimal point was lost ("36" for 3,6).
      final other = crop?.other, scale = crop?.scale;
      if (other != null && scale != null) {
        final beside = _grams(_clean(text.within(other).text), unitsWritten: unitsWritten);
        final off = beside == null || beside == 0 ? null : grams / beside / scale;
        if (off != null && off > 7 && off < 14) grams = _round(grams / 10, 3);
      }
      values[id] = grams;
      break;
    }
  }
  final sodium = values.remove('sodium');
  if (sodium != null) values.putIfAbsent('salt', () => _round(sodium * 2.5, 2));
  return LabelReading(values, _basis(rows.map((r) => r.text).join('\n')));
}

/// Folded text, with where each character came from: its position across the
/// photo, and the extent of its cell — the line text recognition returned.
class _Text {
  _Text(this.text, this.xs, this.lo, this.hi, this.numbers);

  final String text;
  final List<double> xs;
  final List<double> lo;
  final List<double> hi;

  /// Whether the character's cell holds only numbers and units: "1310 / 312", "30,9 g".
  final List<bool> numbers;

  _Text sub(int start, [int? end]) => _Text(text.substring(start, end), xs.sublist(start, end),
      lo.sublist(start, end), hi.sublist(start, end), numbers.sublist(start, end));

  _Text from(int start) => sub(start);

  /// Without the cells of numbers outside [column]. Words stay: a value written
  /// inside a line of words has no column to cut by. Gaps become a space so
  /// numbers from either side never run together.
  _Text within((double, double) column) {
    final keep = [
      for (var i = 0; i < text.length; i++) !numbers[i] || (hi[i] >= column.$1 && lo[i] <= column.$2),
    ];
    final out = StringBuffer();
    final at = <int>[];
    for (var i = 0; i < text.length; i++) {
      if (!keep[i]) continue;
      if (i > 0 && !keep[i - 1] && out.isNotEmpty) {
        out.write(' ');
        at.add(i);
      }
      out.write(text[i]);
      at.add(i);
    }
    return _Text(out.toString(), [for (final i in at) xs[i]], [for (final i in at) lo[i]],
        [for (final i in at) hi[i]], [for (final i in at) numbers[i]]);
  }

  List<_Text> split(RegExp separator) {
    final parts = <_Text>[];
    var start = 0;
    for (final m in separator.allMatches(text)) {
      parts.add(sub(start, m.start));
      start = m.end;
    }
    parts.add(from(start));
    return parts;
  }
}

// A cell of numbers and units: "1310 / 312", "30,9 g", "<0,1", "%11", "34 r/g";
// or a units column's cell, "(kcal)", which belongs to a row the same way.
final _units = RegExp(r'\b(?:mg|g|gr|kj|kcal|kkal|ml|r|q)\b');
final _numbersOnly = RegExp(r'^[\d\s.,/<>%()*+-]*\d[\d\s.,/<>%()*+-]*$');
final _unitOnly = RegExp(r'^\(?\s*(?:kj\s*/\s*)?(?:kcal|kj|g|mg|ml)\s*\)?$');

/// Joins recognised lines into table rows, read left to right. Text recognition
/// often returns a row's name and its values as separate lines, and a photo taken
/// at an angle tilts every row, so lines are first turned level by their median slope.
List<_Text> _rowsOf(List<TextLine> lines) {
  final wide = lines.where((l) => l.right - l.left >= 0.15).toList();
  final slopes = [for (final l in wide.isEmpty ? lines : wide) l.slope]..sort();
  final slope = slopes.isEmpty ? 0.0 : slopes[slopes.length ~/ 2];
  double level(TextLine l) => l.centerY - slope * ((l.left + l.right) / 2 - 0.5);
  double height(TextLine l) => (l.height - (slope * (l.right - l.left)).abs()).clamp(l.height * 0.3, l.height);
  bool numbers(TextLine l) =>
      !_unitPair.hasMatch(l.text) &&
      _numbersOnly.hasMatch(_fold(l.text).replaceAll(_units, '').replaceAll(RegExp('ккал|кдж|г'), ''));
  bool attached(TextLine l) => numbers(l) || _unitOnly.hasMatch(_fold(l.text));

  final rows = <List<TextLine>>[];
  for (final line in lines.where((l) => !attached(l)).toList()..sort((a, b) => level(a).compareTo(level(b)))) {
    final row = rows.lastOrNull;
    if (row != null && (level(line) - level(row.first)).abs() < min(height(row.first), height(line)) / 2) {
      row.add(line);
    } else {
      rows.add([line]);
    }
  }
  // A value sits beside its name, though rarely exactly level with it: it joins
  // the nearest row within a line's height, or starts a row of its own.
  for (final line in lines.where(attached)) {
    final nearest = rows.isEmpty
        ? null
        : rows.reduce((a, b) => (level(a.first) - level(line)).abs() <= (level(b.first) - level(line)).abs() ? a : b);
    if (nearest != null && (level(nearest.first) - level(line)).abs() < height(nearest.first)) {
      nearest.add(line);
    } else {
      rows.add([line]);
    }
  }
  rows.sort((a, b) => level(a.first).compareTo(level(b.first)));
  return [
    for (final row in rows)
      () {
        row.sort((a, b) => a.left.compareTo(b.left));
        final text = StringBuffer();
        final xs = <double>[], lo = <double>[], hi = <double>[], nums = <bool>[];
        void add(String s, double x, TextLine cell, bool isNumbers) {
          text.write(s);
          for (var k = 0; k < s.length; k++) {
            xs.add(x);
            lo.add(cell.left);
            hi.add(cell.right);
            nums.add(isNumbers);
          }
        }

        for (final (i, cell) in row.indexed) {
          final isNumbers = numbers(cell);
          if (i > 0) add('  ', cell.left, cell, isNumbers);
          for (final (j, ch) in cell.text.split('').indexed) {
            // Characters spread evenly across their cell.
            add(_fold(ch), cell.left + (j + 0.5) / cell.text.length * (cell.right - cell.left), cell, isNumbers);
          }
        }
        return _Text(text.toString(), xs, lo, hi, nums);
      }(),
  ];
}

/// Where the per 100 g values are, the column of values beside it, and how many
/// times larger the per 100 g values are than that column's.
typedef _Columns = ({(double, double) per100, (double, double)? other, double? scale});

/// The value columns, from cells of numbers that line up. Null when values
/// aren't cells of their own, as on a label written as one paragraph.
_Columns? _columns(List<_Text> rows, List<_Text> values) {
  final spans = <(double, double, int)>[
    for (final (i, text) in values.indexed)
      for (final m in _number.allMatches(text.text))
        if (text.numbers[m.start]) (text.lo[m.start], text.hi[m.start], i),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  // Cells that overlap or nearly touch belong to one column.
  final columns = <(double, double, Set<int>)>[];
  for (final (left, right, row) in spans) {
    final last = columns.lastOrNull;
    if (last != null && left - last.$2 < 0.04) {
      columns.last = (last.$1, max(right, last.$2), last.$3..add(row));
    } else {
      columns.add((left, right, {row}));
    }
  }
  // A column has a value in at least half the rows that have any.
  final rowsWithValues = {for (final s in spans) s.$3}.length;
  final real = [
    for (final c in columns)
      if (c.$3.length >= max(3, (rowsWithValues / 2).ceil())) (c.$1 - 0.02, c.$2 + 0.02),
  ];
  if (real.isEmpty) return null;

  double? valueIn(_Text text, (double, double) column) {
    for (final m in _number.allMatches(text.text)) {
      if (text.numbers[m.start] && text.lo[m.start] >= column.$1 && text.hi[m.start] <= column.$2) {
        return _parse(m[0]!);
      }
    }
    return null;
  }

  _Columns pick((double, double) per100, (double, double)? other) {
    if (other == null) return (per100: per100, other: null, scale: null);
    final ratios = [
      for (final text in values)
        if ((valueIn(text, per100), valueIn(text, other)) case (final x?, final y?) when y > 0) x / y,
    ]..sort();
    return (per100: per100, other: other, scale: ratios.isEmpty ? null : ratios[ratios.length ~/ 2]);
  }

  (double, double)? besides((double, double) column) => real.where((c) => c != column).firstOrNull;

  // A "100 g" heading over a column; with several, the first, as on EU labels.
  // A heading in a short cell of its own over no column at all means that
  // column wasn't read: better empty than another column's values.
  // "RI (%) per 100 g" heads percentages, not amounts.
  final headed = <(double, double)>{};
  (double, double)? unread;
  for (final row in rows) {
    for (final m in _per100.allMatches(row.text)) {
      if (row.text.substring(max(0, m.start - 12), m.start).contains('%')) continue;
      final x = (row.xs[m.start] + row.xs[m.end - 1]) / 2;
      final under = real.where((c) => x >= c.$1 && x <= c.$2).firstOrNull;
      final (left, right) = (row.lo[m.start], row.hi[m.start]);
      if (under != null) {
        headed.add(under);
      } else if (right - left < 0.3 && !real.any((c) => right >= c.$1 && left <= c.$2)) {
        unread ??= (left, right);
      }
    }
  }
  if (headed.isNotEmpty) {
    final first = headed.reduce((a, b) => a.$1 <= b.$1 ? a : b);
    return pick(first, besides(first));
  }
  if (unread != null) return (per100: unread, other: null, scale: null);
  if (real.length < 2) return pick(real.first, null);

  // No heading to go by (text recognition garbles them: "f00 o ig"). The first
  // two columns are the same food per 100 g and per portion, so their values
  // keep one ratio: a 40 g portion makes the per 100 g column 2.5 times larger.
  final (a, b) = (real[0], real[1]);
  final ratio = pick(b, a).scale;
  if (ratio == null) return pick(a, b);
  final all = rows.map((r) => r.text).join('\n');
  final portions = [
    for (final m in RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:g|gr|ml)\b').allMatches(all))
      if (_parse(m[1]!) case final p when p > 0 && p != 100) p,
  ];
  bool near(double x, double y) => (x - y).abs() <= 0.15 * y;
  if (portions.any((p) => near(ratio, 100 / p))) return pick(b, a);
  if (portions.any((p) => near(ratio, p / 100))) return pick(a, b);
  // No portion size either: a food's portion is usually under 100 g, a drink's
  // over 100 ml.
  final drink = RegExp(r'\d\s*ml\b').hasMatch(all);
  if (ratio > 1.15) return drink ? pick(a, b) : pick(b, a);
  if (ratio < 0.87) return drink ? pick(b, a) : pick(a, b);
  return pick(a, b);
}

// "İ" lowercases to "i" plus a combining dot; "ß" has no single-letter fold; and
// fold() leaves out Romanian's ă, ș and ț.
String _fold(String s) => fold(s)
    .replaceAll('\u0307', '')
    .replaceAll('ß', 'ss')
    .replaceAll('ă', 'a')
    .replaceAll('ș', 's')
    .replaceAll('ț', 't');

String _clean(String s) => s
    .replaceAll(_unitInBrackets, ' ')
    .replaceAll(_unitList, ' ')
    .replaceAll(_unitPair, ' ')
    .replaceAll(_letterO, '0')
    .replaceAll(_letterOne, '1');

double _parse(String s) => double.parse(s.replaceAll(',', '.'));

double _round(double v, int places) => double.parse(v.toStringAsFixed(places));

/// The first amount in [tail], in grams. A percentage is a share of the daily
/// reference intake, not the amount, and nothing has more than 100 g in 100 g.
/// Four digits or more is a code, or a script text recognition can't read
/// ("3608080" for Georgian), so the next number is tried.
///
/// Where the label writes its units ([unitsWritten]), a bare number ending in 9
/// is its "g" misread: "09" is "0 g". Elsewhere a leading zero lost its decimal
/// comma: "02" is 0,2.
double? _grams(String tail, {bool unitsWritten = false}) {
  if (!unitsWritten) tail = tail.replaceAllMapped(_lostDecimal, (m) => '0.${m[1]}');
  for (final m in _amount.allMatches(tail)) {
    var number = m[1]!;
    if (RegExp(r'^\d{4,}$').hasMatch(number)) continue;
    if (unitsWritten && m[2] == null && number.length > 1 && number.endsWith('9')) {
      number = number.substring(0, number.length - 1);
    }
    final grams = _parse(number) / (m[2] == 'mg' ? 1000 : 1);
    return grams <= 100 ? grams : null;
  }
  return null;
}

/// Energy in kcal, and whether it's only worked out (from kJ) or guessed, from
/// the row's text, which may carry the unit: "(kcal) 539", "Calories 230".
(double?, bool) _energy(String text) {
  // A heading's "100 g" (or "100 q üçün") is never the energy.
  text = text.replaceAll(RegExp(r'100\s*(?:g|q|ml)'), ' ').replaceAllMapped(_thousands, (m) => '${m[1]}${m[2]}');
  double? plausible(double kcal) => kcal <= 950 ? _round(kcal, 0) : null;

  if (_kcal.firstMatch(text) case final m?) return (plausible(_parse(m[1] ?? m[2]!)), false);
  final numbers = [for (final m in _number.allMatches(text)) _parse(m[0]!)];
  // "Energy (kJ/kcal) 2252/539": kilojoules are 4.184 × kilocalories.
  for (var i = 0; i + 1 < numbers.length; i++) {
    final (a, b) = (numbers[i], numbers[i + 1]);
    if (b > 0 && (a / b - 4.184).abs() < 0.25) return (plausible(b), false);
    if (a > 0 && (b / a - 4.184).abs() < 0.25) return (plausible(a), false);
  }
  if (_kj.firstMatch(text) case final m?) return (plausible(_parse(m[1]!) / 4.184), true);
  if (numbers.isEmpty) return (null, false);
  // The unit is in the row name: "Energy (kcal) 539", "Calories 230", "Energy (kJ) 2252".
  if (RegExp(r'kcal|kkal|calorie|kalori').hasMatch(text)) return (plausible(numbers.first), false);
  if (text.contains('kj')) return (plausible(numbers.first / 4.184), true);
  // Or nowhere text recognition could read it, where labels mean kcal: a guess
  // (the review form says kcal next to it), so a kcal printed further down wins.
  return (numbers.length == 1 ? plausible(numbers.first) : null, true);
}

Basis _basis(String text) {
  final g = RegExp(r'100\s*(?:g|gr|gram|grams|gramm|q)\b').firstMatch(text);
  final ml = RegExp(r'100\s*ml\b').firstMatch(text);
  if (g == null && ml == null) return Basis.unknown;
  if (g == null) return Basis.per100ml;
  if (ml == null) return Basis.per100g;
  return ml.start < g.start ? Basis.per100ml : Basis.per100g;
}
