import 'package:flutter_test/flutter_test.dart';
import 'package:morsel/label_parser.dart';
import 'package:morsel/vision.dart';

/// A label laid out as a table. Text recognition returns each cell as its own
/// line, so the parser has to put rows back together by height.
List<TextLine> _table(List<List<String>> rows, {double top = 0.05}) => [
      for (final (r, cells) in rows.indexed)
        for (final (c, cell) in cells.indexed)
          if (cell.isNotEmpty)
            // Cells sit a little off a straight line, as they do in a photo.
            TextLine(cell, 0.05 + c * 0.3, top + r * 0.06 + c * 0.004, 0.3 + c * 0.3,
                top + r * 0.06 + c * 0.004 + 0.035),
    ];

/// Text set as a paragraph, one recognised line per printed line.
List<TextLine> _paragraph(List<String> lines, {double top = 0.05}) => [
      for (final (i, line) in lines.indexed)
        TextLine(line, 0.05, top + i * 0.05, 0.95, top + i * 0.05 + 0.035),
    ];

void main() {
  test('an English EU table: first column is per 100 g, %RI ignored', () {
    final reading = parseLabel(_table([
      ['Nutrition information'],
      ['Typical values', 'Per 100 g', 'Per 15 g portion', '%RI*'],
      ['Energy', '2252 kJ / 539 kcal', '338 kJ / 81 kcal', '4%'],
      ['Fat', '30.9 g', '4.6 g', '7%'],
      ['of which saturates', '10.6 g', '1.6 g', '8%'],
      ['Carbohydrate', '57.5 g', '8.6 g', '3%'],
      ['of which sugars', '56.3 g', '8.4 g', '9%'],
      ['Protein', '6.3 g', '0.9 g', '2%'],
      ['Salt', '0.107 g', '0.016 g', '0%'],
    ]));
    expect(reading.basis, Basis.per100g);
    expect(reading.values, {
      'energy-kcal': 539,
      'fat': 30.9,
      'saturated-fat': 10.6,
      'carbohydrates': 57.5,
      'sugars': 56.3,
      'proteins': 6.3,
      'salt': 0.107,
    });
  });

  test('a Turkish table: decimal commas, kJ/kcal pairs, capital İ', () {
    final reading = parseLabel(_table([
      ['BESİN ÖĞELERİ', "100 g'da", '1 Porsiyon (15 g)'],
      ['Enerji (kJ/kcal)', '2252/539', '338/81'],
      ['Yağ (g)', '30,9', '4,6'],
      ['Doymuş Yağ (g)', '10,6', '1,6'],
      ['KARBONHİDRAT (g)', '57,5', '8,6'],
      ['Şekerler (g)', '56,3', '8,4'],
      ['LİF (g)', '0', '0'],
      ['Protein (g)', '6,3', '0,9'],
      ['Tuz (g)', '0,107', '0,016'],
    ]));
    expect(reading.basis, Basis.per100g);
    expect(reading.values, {
      'energy-kcal': 539,
      'fat': 30.9,
      'saturated-fat': 10.6,
      'carbohydrates': 57.5,
      'sugars': 56.3,
      'fiber': 0,
      'proteins': 6.3,
      'salt': 0.107,
    });
  });

  test('a German table skips unsaturated fats and reads Eiweiß', () {
    final reading = parseLabel(_table([
      ['Nährwerte', 'pro 100 ml'],
      ['Brennwert', '2.252 kJ / 539 kcal'],
      ['Fett', '30,9 g'],
      ['davon gesättigte Fettsäuren', '10,6 g'],
      ['davon einfach ungesättigte Fettsäuren', '12 g'],
      ['Kohlenhydrate', '57,5 g'],
      ['davon Zucker', '56,3 g'],
      ['Ballaststoffe', '3,1 g'],
      ['Eiweiß', '6,3 g'],
      ['Salz', '0,11 g'],
    ]));
    expect(reading.basis, Basis.per100ml);
    expect(reading.values, {
      'energy-kcal': 539,
      'fat': 30.9,
      'saturated-fat': 10.6,
      'carbohydrates': 57.5,
      'sugars': 56.3,
      'fiber': 3.1,
      'proteins': 6.3,
      'salt': 0.11,
    });
  });

  test('a linear label in one paragraph, wrapped mid-value', () {
    final reading = parseLabel(_paragraph([
      'Nutrition information per 100 ml: energy 2 252 kJ/ 539 kcal, fat 30,9 g, of which saturates 10,6',
      'g, carbohydrate 57,5 g, of which sugars 56,3 g, protein 6,3 g, salt 0,11 g.',
    ]));
    expect(reading.basis, Basis.per100ml);
    expect(reading.values, {
      'energy-kcal': 539,
      'fat': 30.9,
      'saturated-fat': 10.6,
      'carbohydrates': 57.5,
      'sugars': 56.3,
      'proteins': 6.3,
      'salt': 0.11,
    });
  });

  test('a US label is per serving: basis unknown, sodium becomes salt', () {
    final reading = parseLabel(_paragraph([
      'Nutrition Facts',
      '8 servings per container',
      'Serving size 2/3 cup (55g)',
      'Calories 230',
      'Total Fat 8g 10%',
      'Saturated Fat 1g 5%',
      'Trans Fat 0g',
      'Cholesterol 0mg 0%',
      'Sodium 160mg 7%',
      'Total Carbohydrate 37g 13%',
      'Dietary Fiber 4g 14%',
      'Total Sugars 12g',
      'Includes 10g Added Sugars 20%',
      'Protein 3g',
    ]));
    expect(reading.basis, Basis.unknown);
    expect(reading.values, {
      'energy-kcal': 230,
      'fat': 8,
      'saturated-fat': 1,
      'carbohydrates': 37,
      'sugars': 12,
      'fiber': 4,
      'proteins': 3,
      'salt': 0.4,
    });
  });

  test('energy: kcal on the next line beats kJ, kJ alone is converted', () {
    expect(
      parseLabel(_table([
        ['Energy', '1569 kJ'],
        ['', '375 kcal'],
      ])).values['energy-kcal'],
      375,
    );
    expect(parseLabel(_table([['Energy', '2252 kJ']])).values['energy-kcal'], 538);
    expect(parseLabel(_table([['Energy (kcal)', '539']])).values['energy-kcal'], 539);
    expect(parseLabel(_table([['Energie (kJ)', '2252']])).values['energy-kcal'], 538);
  });

  test('an ingredient list in the same photo does not leak into the table', () {
    final reading = parseLabel([
      ..._paragraph([
        'Ingredients: sugar, palm oil, hazelnuts 13%, skimmed milk powder 8.7%,',
        'fat-reduced cocoa 7.4%, emulsifier: lecithins (soya), vanillin. Salt 2%',
      ]),
      ..._table([
        ['Per 100 g'],
        ['Fat', '30.9 g'],
        ['Salt', '0.107 g'],
      ], top: 0.3),
    ]);
    expect(reading.values, {'fat': 30.9, 'salt': 0.107});
  });

  test('misreads: o for 0, values over 100 g dropped, mg converted', () {
    final reading = parseLabel(_table([
      ['Salt', 'o,1 g'],
      ['Fat', '309 g'],
      ['Protein', '630 mg'],
    ]));
    expect(reading.values, {'salt': 0.1, 'proteins': 0.63});
  });

  test('a photo with no nutrition table reads nothing', () {
    final reading = parseLabel(_paragraph(['Best before end', '12 2027', 'Store in a cool dry place']));
    expect(reading.values, isEmpty);
    expect(reading.basis, Basis.unknown);
  });
}
