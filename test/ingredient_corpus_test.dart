import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:morsel/format.dart';
import 'package:morsel/ingredients.dart';
import 'package:morsel/vision.dart';

// Real ingredient photos from Open Food Facts, mostly whole backs of packs, as
// each phone's text recognition read them (`lines`, by recogniser), scored
// against the photo: `truth` is the list Morsel should read (the English one
// when a label has it, as the app is in English), `contains` and `traces` the
// allergens it names. `otherLanguages` holds the same list in the label's other
// languages: reading one is not wrong, as when a recogniser misses the English
// heading. A null truth is a photo with no list to read, where reading nothing
// is right. `note` says what's special and where the truth was corrected from
// Open Food Facts to the photo.
void main() {
  final fixtures = [
    for (final file in Directory('test/fixtures/ingredients').listSync().whereType<File>())
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
  ]..sort((a, b) => (a['code'] as String).compareTo(b['code'] as String));
  final recognisers = {
    for (final f in fixtures) ...(f['lines'] as Map<String, dynamic>).keys,
  };
  Set<String> tags(Object? list) => {...(list as List).cast<String>()};

  test('the allergen words find what real labels name, and nothing else', () {
    for (final fixture in fixtures) {
      final truth = fixture['truth'] as String?;
      if (truth == null) continue;
      final found = allergenTags(truth);
      final label = '${fixture['code']} ${fixture['name']}';
      expect({...found.contains}, tags(fixture['contains']), reason: label);
      expect({...found.traces}, tags(fixture['traces']), reason: label);
    }
  });

  for (final recogniser in recognisers) {
    test('reads real ingredient lists as $recogniser recognises them', () {
      var lists = 0, close = 0, rough = 0, wrong = 0, missed = 0;
      var named = 0, foundRight = 0, extra = 0;
      final report = StringBuffer();
      for (final fixture in fixtures) {
        final recognised = (fixture['lines'] as Map<String, dynamic>)[recogniser] as List?;
        if (recognised == null) continue;
        final got = readIngredients([for (final m in recognised) TextLine.fromMap(m as Map<String, dynamic>)]);
        final truth = fixture['truth'] as String?;
        final label = '${fixture['code']} ${fixture['name']}';
        if (truth == null) {
          if (got != null) {
            wrong++;
            report.writeln('$label: read "$got" from a photo without a list');
          }
          continue;
        }
        lists++;
        final score = got == null
            ? 0.0
            : [truth, ...?(fixture['otherLanguages'] as List?)?.cast<String>()].map((t) => _similarity(got, t)).reduce(max);
        if (got == null) {
          missed++;
        } else if (score >= 0.9) {
          close++;
        } else if (score >= 0.6) {
          rough++;
        } else {
          wrong++;
        }

        // Allergens, as the user would see them before correcting the text.
        final found = allergenTags(got ?? '');
        final misses = <String>[];
        for (final (kind, expected, list) in [
          ('contains', tags(fixture['contains']), found.contains),
          ('may contain', tags(fixture['traces']), found.traces),
        ]) {
          named += expected.length;
          foundRight += expected.where(list.contains).length;
          extra += list.where((t) => !expected.contains(t)).length;
          misses.addAll([
            for (final t in expected.where((t) => !list.contains(t))) '$kind $t missed',
            for (final t in list.where((t) => !expected.contains(t))) '$kind $t extra',
          ]);
        }
        if (got == null || score < 0.9 || misses.isNotEmpty) {
          report.writeln('$label: ${(score * 100).round()} % alike${misses.map((m) => ', $m').join()}');
        }
      }
      // ignore: avoid_print
      print('$recogniser\n$report$lists lists: $close read closely (≥ 90 % alike), $rough roughly, '
          '$wrong wrong, $missed missed. Allergens: $foundRight of $named found, $extra extra.');
      // A missed list costs the user typing; a wrong one, text from elsewhere on
      // the pack or unreadable, costs trust. On 2026-10-19, of 31 lists:
      // vision-macos 24 close, 5 rough, 0 wrong, 2 missed, allergens 107 of 121
      // and none extra; vision-ios-simulator 23, 5, 1 (a cheese label it reads
      // as noise), 2, allergens 104 of 121 and none extra.
      expect(wrong, lessThanOrEqualTo(1));
      expect(close + rough, greaterThanOrEqualTo(0.8 * lists));
      expect(foundRight, greaterThanOrEqualTo(0.85 * named));
      expect(extra, lessThanOrEqualTo(2));
    });
  }
}

/// How alike two texts are, from 0 to 1: one minus the share of characters to
/// change, ignoring case, accents and spacing.
double _similarity(String a, String b) {
  String norm(String s) => fold(s).replaceAll(RegExp(r'\s+'), ' ').trim();
  final (x, y) = (norm(a), norm(b));
  var previous = List.generate(y.length + 1, (j) => j);
  for (var i = 1; i <= x.length; i++) {
    final current = [i, ...List.filled(y.length, 0)];
    for (var j = 1; j <= y.length; j++) {
      current[j] = min(min(current[j - 1], previous[j]) + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1));
    }
    previous = current;
  }
  return 1 - previous[y.length] / max(x.length, y.length);
}
