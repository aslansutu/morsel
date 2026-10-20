import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:morsel/label_parser.dart';
import 'package:morsel/vision.dart';

// Real nutrition label photos from Open Food Facts, as each phone's text
// recognition read them (`lines`, by recogniser: Apple Vision on a Mac with the
// iOS app's request, the iOS simulator, ML Kit on Android), scored against what
// the photo shows (`truth`, from Open Food Facts; `note` says where it was
// corrected to the photo). A fixture with `skip` has no readable table.
void main() {
  final fixtures = [
    for (final file in Directory('test/fixtures/labels').listSync().whereType<File>())
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
  ]..sort((a, b) => (a['code'] as String).compareTo(b['code'] as String));
  final recognisers = {
    for (final f in fixtures) ...(f['lines'] as Map<String, dynamic>).keys,
  };

  for (final recogniser in recognisers) {
    test('reads real nutrition labels as $recogniser recognises them', () {
      var compared = 0, matched = 0, wrong = 0;
      final report = StringBuffer();
      for (final fixture in fixtures) {
        final recognised = (fixture['lines'] as Map<String, dynamic>)[recogniser] as List?;
        if (fixture['skip'] != null || recognised == null) continue;
        final reading = parseLabel([for (final m in recognised) TextLine.fromMap(m as Map<String, dynamic>)]);
        final truth = fixture['truth'] as Map<String, dynamic>;
        final misses = <String>[];
        for (final id in labelNutrients) {
          final expected = (truth[id] as num?)?.toDouble();
          if (expected == null) continue;
          compared++;
          final got = reading.values[id];
          // Labels round, and people typing them in round differently.
          final tolerance = id == 'energy-kcal' ? 1.5 : max(0.051, expected * 0.02);
          if (got != null && (got - expected).abs() <= tolerance) {
            matched++;
          } else {
            if (got != null) wrong++;
            misses.add('$id ${got ?? '—'} (label $expected)');
          }
        }
        if (misses.isNotEmpty) report.writeln('${fixture['code']} ${fixture['name']}: ${misses.join(', ')}');
      }
      // ignore: avoid_print
      print('$recogniser\n$report$matched of $compared values read right, $wrong wrong, '
          '${compared - matched - wrong} left empty');
      // A value left empty costs the user typing; a wrong one costs trust. Keep
      // wrong rare. On 2026-10-18: vision-macos 116 of 147 right, 2 wrong (20 of
      // the 29 left empty were never recognised); vision-ios-simulator 60 of 76
      // right, 3 wrong.
      expect(matched / compared, greaterThanOrEqualTo(0.75));
      expect(wrong / compared, lessThanOrEqualTo(0.05));
    });
  }
}
