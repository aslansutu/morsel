import 'dart:math';

import 'format.dart';
import 'off_client.dart';
import 'vision.dart';

// Words that start an ingredient list, by language, and how many letters text
// recognition may get wrong in them ("Içindokller", "(indekler"). "ingredients"
// is English and French alike.
const _headings = [
  ('icindekiler', {'tr'}, 3),
  ('terkibi', {'az'}, 2),
  ('ingredients', {'en', 'fr'}, 1),
  ('ingredientes', {'es'}, 1),
  ('ingredienti', {'it'}, 1),
  ('ingredienten', {'nl'}, 1),
  ('ingrediente', {'ro'}, 1),
  ('zutaten', {'de'}, 1),
  ('skladniki', {'pl'}, 1),
  ('состав', {'ru'}, 0),
];

// Where a label moves on from its ingredients: storage, dates, who made it,
// nutrition, Turkish packs' "no pork" and "no trans fat" lines. Matched on
// folded text at the start of a word; the sentence they're in is cut off.
final _stops = RegExp(
    // Turkish
    r'(?<![a-z])(?:saklay|saklama|muhafaza|serin |sicaktan|gunes isig|buzdolab|son tuketim|'
    r'tavsiye edilen tuketim|tett\b|uretim tarihi|uretim yeri|uretici|parti no|seri no|seri numara|'
    r'isletme kayit|gida isletmecisi|mense|net miktar|enerji|besin ogeleri|besin degerleri|'
    r'beslenme|turk gida kodeks|domuz|trans yag|tuketici|ithalatci|acildiktan|kullanim|hazirlanis|'
    // English
    r'store |storage|keep |refrigerate|best before|use by|produced|manufactured|made in|packed|'
    r'distributed|imported|nutrition|typical values|energy|protect from|once opened|after opening|'
    r'consumer|net weight|net wt|directions|serving suggestion|food business|country of origin|'
    // German, French, Spanish, Italian, Dutch, Azerbaijani, Romanian, Russian
    r'nahrwert|brennwert|lagern|mindestens haltbar|hergestellt|zubereitung|nach dem offnen|'
    r'valeurs nutritionnelles|a conserver|conserver|a consommer|fabrique|apres ouverture|'
    r'valor energetico|informacion nutricional|valores nutricionales|conservar|consumir|fabricado|'
    r'elaborado|envasado|valori nutrizionali|dichiarazione nutrizionale|conservare|da consumarsi|'
    r'prodotto (?:in|da|e)|voedingswaarde|bewaren|houdbaar|geproduceerd|na opening|saxla|istehsal|'
    r'a se pastra|declaratie nutritionala|valori nutritionale|fabricat|a se consuma|'
    r'хранить|пищевая ценность|энергетическая|изготовитель|годен)|(?<![a-z])net\b');

// "May contain" statements and allergen headings, by language. Inside a list
// they belong to it; in another language they start the next list.
final _traceMarkers = <(RegExp, Set<String>)>[
  (RegExp(r'icerebil|eser miktar|iz miktar|ayni hatta|ayni tesiste|alerjen'), {'tr'}),
  (RegExp(r'may (?:also )?contain|same line|same factory|factory that|allergy'), {'en'}),
  (RegExp(r'traces'), {'en', 'fr'}),
  (RegExp(r'allergen(?!e|i)'), {'en', 'az'}),
  (RegExp(r'spuren|allergene|allergiehinweis'), {'de'}),
  (RegExp(r'peut contenir|allergenes'), {'fr'}),
  (RegExp(r'puede contener|trazas|alergenos'), {'es'}),
  (RegExp(r'puo contenere|tracce|allergeni'), {'it'}),
  (RegExp(r'kan sporen|sporen van|allergenen'), {'nl'}),
  (RegExp(r'poate contine|urme de'), {'ro'}),
  (RegExp(r'ola biler|ede biler'), {'az'}),
];

// Turkish export packs put a language code before each language's text: "EN Milk
// Chocolate, Ingredients: …". Only before a capitalised word, so an all-caps
// "EN AZ %30" (at least 30 %) isn't one.
final _languageCode =
    RegExp(r'(?:^|(?<=[.;:)\]]\s*))(?:EN|GB|TR|AZ|AR|RU|DE|FR|ES|IT|NL|RO|BG|GR|KZ|UA|GE|HU|PL)\s+(?=\p{Lu}\p{Ll})',
        unicode: true);

// Where a sentence starts: after a full stop, a bullet, a semicolon, or a dash
// between words.
final _sentence = RegExp(r'[.•;!?]\s+|\s[-–]\s');

/// Reads the ingredient list from text recognised in a photo: what follows
/// "Ingredients:" or "İçindekiler:", down the paragraph, up to where the label
/// moves on to storage, nutrition or the next language. A label in several
/// languages gives its [language] list, or else the first. Null when the photo
/// has no heading to start from: an empty field beats someone else's text.
String? readIngredients(List<TextLine> lines, {String language = appLanguage}) =>
    readIngredientList(lines, language: language)?.text;

/// [readIngredients], with the language of the list's heading: Open Food Facts
/// keeps each language's list apart.
({String text, String language})? readIngredientList(List<TextLine> lines,
    {String language = appLanguage}) {
  // Lines in reading order, levelled by the photo's median slope, then joined
  // into rows: text recognition can return one printed line as several, side
  // by side. Lines that overlap across are rows of their own however close:
  // in a tightly cropped photo, the boxes of neighbouring lines overlap.
  final wide = lines.where((l) => l.right - l.left >= 0.15).toList();
  final slopes = [for (final l in wide.isEmpty ? lines : wide) l.slope]..sort();
  final slope = slopes.isEmpty ? 0.0 : slopes[slopes.length ~/ 2];
  double level(TextLine l) => l.centerY - slope * ((l.left + l.right) / 2 - 0.5);
  final rows = <List<TextLine>>[];
  for (final line in [...lines]..sort((a, b) => level(a).compareTo(level(b)))) {
    final row = rows.lastOrNull;
    if (row != null &&
        (level(line) - level(row.first)).abs() < min(line.height, row.first.height) / 2 &&
        row.every((l) => l.right <= line.left + 0.02 || line.right <= l.left + 0.02)) {
      row.add(line);
    } else {
      rows.add([line]);
    }
  }
  for (final row in rows) {
    row.sort((a, b) => a.left.compareTo(b.left));
  }

  // A line twice as tall as it is wide is text running sideways: a photo the
  // wrong way up, which reads as fragments.
  final headings = [
    for (final (r, row) in rows.indexed)
      for (final (c, line) in row.indexed)
        if (line.height < 2 * (line.right - line.left))
          if (_heading(line.text) case final h?) (r, c, h),
  ];
  if (headings.isEmpty) return null;
  final (r, c, heading) = headings.firstWhere((h) => h.$3.langs.contains(language), orElse: () => headings.first);

  // The paragraph under the heading: lines within its column that line up
  // with it — at its left edge, under the list's first word, or centred —
  // until a gap of a line's height or more. A heading alone on a short line
  // takes its column from the line under it. Beside a line, only what follows
  // on closely is the same line; further across is another column ("Net 500 g"),
  // and beside such a heading, anything more than a word space away.
  // A "may contain" line is the list's wherever it's set.
  final start = rows[r][c];
  final parts = [start.text.substring(heading.end)];
  final listX = start.left + heading.end / start.text.length * (start.right - start.left);
  (double, double)? column = start.right - start.left < 0.35 ? null : (start.left, start.right);
  double overlap(TextLine l) {
    final (left, right) = column ?? (start.left, start.right);
    return min(l.right, right) - max(l.left, left);
  }

  bool inColumn(TextLine l) {
    final (left, right) = column ?? (start.left, start.right);
    if (column == null) return overlap(l) > 0;
    final aligned = (l.left - left).abs() < 0.05 ||
        (l.left - listX).abs() < 0.05 ||
        ((l.left + l.right) / 2 - (left + right) / 2).abs() < 0.05 ||
        _traceMarkers.any((t) => t.$2.any(heading.langs.contains) && t.$1.hasMatch(_fold(l.text)));
    return aligned && overlap(l) >= 0.5 * (l.right - l.left);
  }

  List<TextLine> runFrom(TextLine first, Iterable<TextLine> beside) {
    final run = [first];
    for (final l in beside) {
      if (l.left - run.last.right > (column == null && first == start ? 0.02 : 0.08) ||
          (column != null && overlap(l) < 0.5 * (l.right - l.left))) {
        break;
      }
      run.add(l);
    }
    return run;
  }

  var bottom = start.bottom;
  final heights = [start.height];
  parts.addAll(runFrom(start, rows[r].skip(c + 1)).skip(1).map((l) => l.text));
  for (final row in rows.skip(r + 1)) {
    final first = row.where(inColumn).firstOrNull;
    if (first == null) continue;
    final mine = runFrom(first, row.skip(row.indexOf(first) + 1));
    final height = (heights..sort())[heights.length ~/ 2];
    if (mine.map((l) => l.top).reduce(min) - bottom > height) break;
    column ??= (mine.first.left, mine.last.right);
    parts.addAll(mine.map((l) => l.text));
    bottom = mine.map((l) => l.bottom).reduce(max);
    heights.addAll(mine.map((l) => l.height));
  }

  // A word broken at the end of a line ("Stabi-" "liser") joins up again.
  var text = parts.first;
  for (final part in parts.skip(1)) {
    text = RegExp(r'\p{L}-$', unicode: true).hasMatch(text) && RegExp(r'^\p{Ll}', unicode: true).hasMatch(part)
        ? text.substring(0, text.length - 1) + part
        : '$text $part';
  }
  text = text.replaceAll(RegExp(r'\s+'), ' ').replaceFirst(RegExp(r'^[\s:;.,•-]+'), '');
  text = _trim(text, heading.langs).replaceFirst(RegExp(r'[\s,;•-]+$'), '');
  if (text.length < 3) return null;
  return (text: text, language: heading.langs.contains(language) ? language : heading.langs.first);
}

typedef _Heading = ({int end, Set<String> langs});

/// The first ingredient heading in [text]: where the list after it starts, and
/// its language. A misread heading counts only with its colon; so does an
/// English one, which is also a word in sentences ("see ingredients in bold").
_Heading? _heading(String text) {
  final folded = _fold(text);
  for (final m in RegExp(r'[a-zа-я]{6,}').allMatches(folded)) {
    (int, Set<String>)? best;
    for (final (word, langs, allowed) in _headings) {
      final d = _distance(m[0]!, word);
      if (d <= allowed && (best == null || d < best.$1)) best = (d, langs);
    }
    if (best == null) continue;
    final rest = folded.substring(m.end);
    final colon = RegExp(r'^\s*[:;.,]').firstMatch(rest);
    final exact = best.$1 == 0 && (best.$2.contains('tr') || rest.trim().isEmpty);
    if (colon == null && !exact) continue;
    return (end: m.end + (colon?.end ?? 0), langs: best.$2);
  }
  return null;
}

/// The list in [text], in [langs]: up to the sentence that moves on, without
/// another language's "may contain" sentences in between. Bilingual Turkish
/// packs print both lists, then both allergen statements.
String _trim(String text, Set<String> langs) {
  final folded = _fold(text);
  final ends = <int>[
    if (_heading(text) case final h?) _listEnd(text, _headingStart(folded, h.end)),
    for (final m in _languageCode.allMatches(text)) m.start,
    // Arabic or Hebrew is always another language's list: none Morsel reads is in them.
    if (RegExp(r'[\u0590-\u06ff]').firstMatch(text) case final m?) m.start,
  ];
  for (final m in _stops.allMatches(folded)) {
    final start = _sentenceStart(text, m.start);
    // "Produced in a factory that handles nuts" says what the food may contain.
    final sentence = folded.substring(start, _sentenceEnd(text, m.end));
    if (!_traceMarkers.any((t) => t.$2.any(langs.contains) && t.$1.hasMatch(sentence))) ends.add(start);
  }
  final end = ends.where((e) => e > 0).fold(text.length, min);
  final drop = [
    for (final (marker, markerLangs) in _traceMarkers)
      if (!markerLangs.any(langs.contains))
        for (final m in marker.allMatches(folded))
          (text.indexOf(RegExp(r'\S'), _sentenceStart(text, m.start)), _sentenceEnd(text, m.end)),
  ];
  final out = StringBuffer();
  for (var i = 0; i < end; i++) {
    if (!drop.any((d) => i >= d.$1 && i < d.$2)) out.write(text[i]);
  }
  return out.toString();
}

int _headingStart(String folded, int end) =>
    RegExp(r'[a-zа-я]+\s*[:;.,]?\s*$').firstMatch(folded.substring(0, end))?.start ?? end;

/// Where the list ends before the next language's heading at [at]: the start
/// of its sentence, or a slash just before it ("traces of milk./Ingredientes:").
int _listEnd(String text, int at) {
  final slash = RegExp(r'/\s*$').firstMatch(text.substring(0, at));
  return slash?.start ?? _sentenceStart(text, at);
}

int _sentenceStart(String text, int at) {
  final m = _sentence.allMatches(text.substring(0, at)).lastOrNull;
  return m == null ? at : m.start + (text[m.start] == '.' ? 1 : 0);
}

/// Just past the end of the sentence [at] is in, with the space after it.
int _sentenceEnd(String text, int at) => _sentence.allMatches(text, at).firstOrNull?.end ?? text.length;

/// Lowercase without diacritics, one character for one, so a match in the
/// folded text points back into the original.
String _fold(String s) {
  final out = StringBuffer();
  for (final ch in s.split('')) {
    final f = fold(ch);
    // "İ" lowercases to "i" plus a combining dot.
    out.write(switch (f.isEmpty ? ch : f[0]) {
      'ə' => 'e',
      'ł' => 'l',
      'ă' => 'a',
      'ș' => 's',
      'ț' || 'ţ' => 't',
      'œ' => 'o',
      final c => c,
    });
  }
  return out.toString();
}

int _distance(String a, String b) {
  var previous = List.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final current = [i, ...List.filled(b.length, 0)];
    for (var j = 1; j <= b.length; j++) {
      current[j] = min(min(current[j - 1], previous[j]) + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
    }
    previous = current;
  }
  return previous[b.length];
}

// --- Allergens --------------------------------------------------------------

/// An allergen named in an ingredient list: its Open Food Facts tag, where it
/// is in the text, and whether the list only says the food may contain it.
typedef Allergen = ({String tag, int start, int end, bool trace});

// The EU's 14 allergens as words in English, Turkish, German, French, Spanish,
// Italian, Dutch and Azerbaijani, matched at the start of a word on folded text
// (Turkish adds suffixes: "fındığı", "sütlü"). An entry without a tag claims
// words that look like an allergen and aren't: coconut, nutmeg, cocoa butter,
// pine nuts, coconut and plant milks, maltodextrin, ammonia caramel. Earlier
// entries win where matches overlap.
final _allergens = <(String?, RegExp)>[
  (null, RegExp(r'(?<=(?:cevizi|badem|soya|yulaf|pirinc|coconut|almond|soy|oat|rice) )(?:sutu|milk|drink)|'
      r'(?<=(?:peanut|nut|almond|cashew|hazelnut) )butter|(?:cocoa|kakao|shea|cacao) ?(?:butter|yag|beurre)|'
      r'beurre de cacao|kakaobutter|hindistan cevizi|muskat cevizi|cam fisti[kg]|coconut|\bcoco\b|kokos|'
      r'noix de (?:coco|muscade)|nuez (?:de coco|moscada)|noce (?:di cocco|moscata)|nootmuskaat|nutmeg|'
      r'pine nuts?|malto|maltit|maltoz|maltose|sulfit karamel|sulphite caramel|kostik sulfit|bean curd|'
      r'cream of tartar|arpacik')),
  ('en:peanuts', RegExp(r'[yv]er ?fisti[kg]|fistik ezme|peanut|groundnut|arachi|erdnuss|cacahu|\bmani\b|pinda|aardno')),
  ('en:molluscs', RegExp(r'murekkep bali[kg]|midye|kalamar|ahtapot|istiridye|salyangoz|yumusakca|mollus|'
      r'mussel|oyster|squid|octopus|\bclams?\b|scallop|snail|cuttlefish|calamar|weichtier|muschel|auster|'
      r'tintenfisch|moule|huitre|poulpe|seiche|escargot|palourde|mejillon|ostra|pulpo|sepia|almeja|cozz|'
      r'ostric|polpo|seppi|vongol|weekdier|mossel|oester|inktvis')),
  ('en:crustaceans', RegExp(r'karides|yengec|istakoz|kerevit|kabuklu deniz|crustac|shrimp|prawn|\bcrabs?\b|'
      r'lobster|crayfish|langoust|krill|krebs|garnele|krabbe|hummer|crevette|crabe|homard|gamba|camaron|'
      r'cangrejo|langosta|crostace|gamber|granchi|aragost|scampi|schaaldier|garnal|kreeft')),
  ('en:fish', RegExp(r'bali[kg]|hamsi|somon|sardalya|uskumru|\bfish|anchov|tuna|salmon|\bcod\b|sardin|mackerel|'
      r'pollock|haddock|fisch|sardelle|lachs|poisson|\bthon|saumon|anchois|cabillaud|pescado|\batun|anchoa|'
      r'bacalao|pesce|tonno|acciug|merluzz|\bvis\b|tonijn|zalm|ansjovis|kabeljauw')),
  ('en:nuts', RegExp(r'findi[kg]|badem|ceviz|antep fisti[kg]|kaju|pekan|pikan|brezilya|makadamya|'
      r'sert kabuklu|almond|hazelnut|walnut|cashew|pecan|brazil|pistach|macadamia|\btree nuts?|\bnuts?\b|'
      r'mandel|haselnuss|walnuss|paranuss|pistazie|schalenfr|\bnusse?\b|amande|noisette|\bnoix|cajou|'
      r'fruits a coque|almendra|avellana|\bnue[zc]|anacard|frutos de cascara|mandorl|nocciol|\bnoc[ei]\b|'
      r'frutta a guscio|amandel|hazelno|walno|\bnoten\b|findiq|badam|\bqoz|puste')),
  ('en:gluten', RegExp(r'bugday|\barpa|cavdar|yulaf|gluten|qluten|irmik|bulgur|kuskus|siyez|'
      r'\bmalt|wheat|barley|\brye\b|\boats?\b|oatmeal|spelt|kamut|semolina|couscous|weizen|gerste|'
      r'roggen|hafer|dinkel|griess|\bble\b|froment|\borge\b|seigle|avoine|epeautre|trigo|cebada|centeno|'
      r'avena|espelta|frumento|\bgrano\b|\borzo\b|segale|farro|tarwe|\bgerst|rogge|haver|bugda|\bgrau\b')),
  ('en:eggs', RegExp(r'yumurta|\beggs?\b|albumen|\beier|eigelb|\bei\b|volle?i\b|huhnerei|\bo?euf|huevo|\buov[ao]|'
      r'eieren')),
  ('en:soybeans', RegExp(r'soya|\bsoy\b|soybean|edamame|\btofu|\bsoja|\bsoia')),
  ('en:milk', RegExp(r'\bsut|\bsud\b|peynir|tereya[gk]|kaymak|yo[gk]urt|kefir|ayran|laktoz|kazein|\blor\b|'
      r'sade yag|milk|dairy|cream|cheese|butter|\bwhey|lactos|casein|yogh?urt|ghee|\bcurd|milch|sahne|\brahm|'
      r'\bkase|molke|quark|\blait|creme|beurre|fromage|lactoserum|yaourt|leche|\bnata\b|mantequilla|queso|'
      r'suero|\blatte|panna|burro|formaggi|lattosio|siero|\bmelk|\broom\b|boter|\bkaas|\bwei\b|lactoza|'
      r'\blapte')),
  ('en:celery', RegExp(r'kereviz|celery|celeriac|sellerie|celeri|\bapio\b|sedano|selderij|telina')),
  ('en:mustard', RegExp(r'hardal|mustard|\bsenf|moutarde|mostaza|senape|mosterd|mustar')),
  ('en:sesame-seeds', RegExp(r'susam|tahin|sesam|kuncut')),
  ('en:sulphur-dioxide-and-sulphites', RegExp(r'sulfit|sulphit|sulfiet|solfit|kukurt dioksit|'
      r'sul(?:ph|f)ur dioxide|schwefeldioxid|anhydride sulfureux|dioxido de azufre|anidride solforosa|'
      r'zwaveldioxide|\be ?22[0-8]\b')),
  ('en:lupin', RegExp(r'lupin|acibakla|altramuz')),
];

// A sentence saying the food may contain something, or doesn't contain it.
final _trace = RegExp(r'icerebil|eser miktar|iz miktar|ayni hatta|ayni tesiste|may (?:also )?contain|traces|'
    r'same (?:line|factory)|factory that|spuren|peut contenir|puede contener|trazas|puo contenere|tracce|'
    r'kan sporen|sporen van|poate contine|urme|ola biler|ede biler');
final _absent = RegExp(r'icermez|icermemektedir|yoktur|bulunmaz|does not contain|contains no|free from|'
    r'enthalt kein|ne contient pas|no contiene|non contiene|bevat geen|nu contine');

/// The allergens [ingredients] names, in the order they appear. "Gluten-free",
/// "glutensiz" and "does not contain" don't count.
List<Allergen> findAllergens(String ingredients) {
  // Open Food Facts and some labels mark allergens "_süt_" or "*süt*".
  final folded = _fold(ingredients).replaceAll(RegExp('[_*]'), ' ');
  // Sentences, and bracketed asides such as "[may contain hazelnuts]". A
  // Turkish sentence ends on its verb, also before a comma ("… içerebilir,
  // trans yağ içermez"), and "may contain" starts one, also without a full
  // stop before it, or when only its "traces of" was read.
  final sentences = [
    for (final m in RegExp(r'(?:[^.;\[\]]|\.\d)+?(?:(?:icerebil[a-z]*|icerir|icermez|icermemektedir|yoktur)\b|'
            r'(?=[.;\[\]]|$|may (?:also )?contain|traces of|eser miktar|iz miktar|kann spuren|peut contenir|'
            r'puede contener))')
        .allMatches(folded))
      (m.start, m.end, m[0]!),
  ];
  final claimed = <(int, int)>[];
  final found = <Allergen>[];
  for (final (tag, pattern) in _allergens) {
    for (final m in pattern.allMatches(folded)) {
      if (claimed.any((c) => m.start < c.$2 && c.$1 < m.end)) continue;
      claimed.add((m.start, m.end));
      if (tag == null) continue;
      final word = RegExp(r'^[a-z]*').firstMatch(folded.substring(m.end))!;
      final after = folded.substring(m.end + word.end);
      final before = folded.substring(0, m.start);
      if (RegExp(r'^s[iu]z').hasMatch(folded.substring(m.end)) ||
          RegExp(r'^[\s-]*(?:free|frei)\b').hasMatch(after) ||
          RegExp(r'\b(?:sans|sin|senza|zonder|ohne|without|no|non)[\s-]+$').hasMatch(before)) {
        continue;
      }
      final (_, _, sentence) = sentences.lastWhere((s) => s.$1 <= m.start, orElse: () => (0, 0, ''));
      if (_absent.hasMatch(sentence)) continue;
      found.add((tag: tag, start: m.start, end: m.end + word.end, trace: _trace.hasMatch(sentence)));
    }
  }
  return found..sort((a, b) => a.start.compareTo(b.start));
}

/// [findAllergens] as Open Food Facts lists them: what the food contains, and
/// what it only may contain.
({List<String> contains, List<String> traces}) allergenTags(String ingredients) {
  final found = findAllergens(ingredients);
  final contains = {for (final a in found) if (!a.trace) a.tag};
  return (
    contains: contains.toList(),
    traces: {for (final a in found) if (a.trace && !contains.contains(a.tag)) a.tag}.toList(),
  );
}
