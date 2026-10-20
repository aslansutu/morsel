import 'package:flutter_test/flutter_test.dart';
import 'package:morsel/ingredients.dart';
import 'package:morsel/vision.dart';

/// A photo's lines, one under another down the page, as text recognition
/// returns them: (text, left, right).
List<TextLine> _page(List<(String, double, double)> lines) => [
      for (final (i, (text, left, right)) in lines.indexed) TextLine(text, left, i * 0.05, right, i * 0.05 + 0.04),
    ];

void main() {
  group('reading the list', () {
    test('reads the list after "İçindekiler:" up to the storage line', () {
      expect(
        readIngredients(_page([
          ('FINDIKLI KREMA', 0.05, 0.4),
          ('İçindekiler: Şeker, bitkisel yağ (palm), FINDIK (%13),', 0.05, 0.9),
          ('yağsız SÜT tozu, emülgatör (SOYA lesitini). Eser miktarda', 0.05, 0.9),
          ('yer fıstığı içerebilir. Serin ve kuru yerde saklayınız.', 0.05, 0.9),
        ])),
        'Şeker, bitkisel yağ (palm), FINDIK (%13), yağsız SÜT tozu, emülgatör (SOYA lesitini). '
        'Eser miktarda yer fıstığı içerebilir.',
      );
    });

    test('a bilingual label gives the English list, without the Turkish warning', () {
      expect(
        readIngredients(_page([
          ('İçindekiler: Fındık (%40), şeker.', 0.05, 0.9),
          ('Ingredients: Hazelnut (40%), sugar.', 0.05, 0.9),
          ('Alerjen Uyarısı: Fındık içerir.', 0.05, 0.6),
          ('Allergen Warning: Contains hazelnut.', 0.05, 0.6),
          ('ORTALAMA ENERJİ VE BESİN ÖĞELERİ', 0.05, 0.6),
        ])),
        'Hazelnut (40%), sugar. Allergen Warning: Contains hazelnut.',
      );
      // In Turkish, the list ends where the English one starts.
      expect(
        readIngredients(_page([
          ('İçindekiler: Fındık (%40), şeker. Ingredients: Hazelnut (40%), sugar.', 0.05, 0.9),
        ]), language: 'tr'),
        'Fındık (%40), şeker.',
      );
    });

    test('a misread heading counts with its colon; "see ingredients in bold" is no heading', () {
      expect(readIngredients(_page([('Içindokller: Şeker, tuz.', 0.05, 0.9)])), 'Şeker, tuz.');
      expect(readIngredients(_page([('Allergy advice: see ingredients in bold.', 0.05, 0.9)])), isNull);
    });

    test('another column beside the list stays out', () {
      expect(
        readIngredients([
          const TextLine('Ingredients: Wheat flour, sugar,', 0.05, 0.10, 0.6, 0.14),
          const TextLine('Net 500 g', 0.8, 0.10, 0.95, 0.14),
          const TextLine('palm oil, salt.', 0.05, 0.15, 0.6, 0.19),
          const TextLine('Made in Turkey', 0.7, 0.20, 0.95, 0.24),
        ]),
        'Wheat flour, sugar, palm oil, salt.',
      );
    });

    test('beside a heading alone on a short line, the next column stays out', () {
      // The iOS simulator read a cheese label this way, a nutrition table 0.03 across.
      expect(
        readIngredients(const [
          TextLine('İçindekiler: Süt,', 0.0, 0.40, 0.28, 0.44),
          TextLine('Yağ (g) 20,5', 0.31, 0.40, 0.45, 0.44),
          TextLine('peynir mayası, tuz.', 0.0, 0.45, 0.25, 0.49),
        ]),
        'Süt, peynir mayası, tuz.',
      );
    });

    test('Arabic text ends the list: it is always another language', () {
      expect(
        readIngredients(_page([('Ingredients: Wheat flour, salt', 0.05, 0.9), ('المكونات: دقيق القمح، ملح', 0.05, 0.9)])),
        'Wheat flour, salt',
      );
    });

    test('a word broken at the end of a line joins up', () {
      expect(
        readIngredients(_page([
          ('INGREDIENTS: Water, Oat (9.9%), Stabi-', 0.05, 0.9),
          ('liser (Gellan gum), Sea salt.', 0.05, 0.9),
        ])),
        'Water, Oat (9.9%), Stabiliser (Gellan gum), Sea salt.',
      );
    });

    test('a photo without a list heading, or with text running sideways, reads nothing', () {
      expect(readIngredients(_page([('Energy 2252 kJ / 539 kcal', 0.05, 0.6), ('Fat 30.9 g', 0.05, 0.6)])), isNull);
      expect(readIngredients(const [TextLine('Ingredients: Sugar, cocoa butter.', 0.4, 0.1, 0.45, 0.9)]), isNull);
      expect(readIngredients(const []), isNull);
    });
  });

  group('allergens', () {
    test('Turkish suffixes and capitals: FINDIĞI, sütlü, yumurtalı', () {
      final found = allergenTags('Şeker, FINDIĞI ezmesi, sütlü çikolata, yumurtalı kek');
      expect(found.contains, ['en:nuts', 'en:milk', 'en:eggs']);
      // The whole word is marked, for bold text on the product page.
      const text = 'Şeker, FINDIĞI';
      final hazelnut = findAllergens(text).single;
      expect(text.substring(hazelnut.start, hazelnut.end), 'FINDIĞI');
    });

    test('coconut, cocoa butter, nutmeg and plant milks are not allergens', () {
      expect(findAllergens('Hindistan cevizi, kakao yağı, coconut milk, cocoa butter, nutmeg, kokosnuss'), isEmpty);
      // But almond milk is still almonds.
      expect(allergenTags('almond milk').contains, ['en:nuts']);
    });

    test('peanuts and tree nuts are told apart', () {
      final found = allergenTags('Yer fıstığı, Antep fıstığı, fıstık ezmesi, kaju fıstığı, peanuts, pistachios');
      expect(found.contains, ['en:peanuts', 'en:nuts']);
    });

    test('"may contain" is a trace, also without a full stop before it', () {
      final found = allergenTags('Wheat flour, sugar May contain traces of nuts and milk.');
      expect(found.contains, ['en:gluten']);
      expect(found.traces, ['en:nuts', 'en:milk']);
      // A Turkish verb ends its sentence: what follows is not a trace.
      expect(allergenTags('Eser miktarda fındık içerebilir, süt tozu').contains, ['en:milk']);
      // Only "traces of" read, as the iOS simulator did on a bar's label.
      final bar = allergenTags('ROASTED PEANUTS %15, SOY LECITHIN traces of hazelnut.');
      expect(bar.contains, ['en:peanuts', 'en:soybeans']);
      expect(bar.traces, ['en:nuts']);
    });

    test('"gluten-free", "laktozsuz" and "içermez" do not count', () {
      expect(findAllergens('Gluten free. Contains no milk. Laktozsuz. Domuz yağı ve gluten içermez.'), isEmpty);
    });

    test('ammonia caramel and maltodextrin are not sulphites or gluten', () {
      expect(findAllergens('amonyum sülfit karamel, maltodekstrin, maltitol'), isEmpty);
      expect(allergenTags('sodyum metabisülfit, arpa maltı').contains,
          ['en:sulphur-dioxide-and-sulphites', 'en:gluten']);
    });

    test('a food that contains something is not also listed as may contain it', () {
      final found = allergenTags('Fındık, şeker. Eser miktarda fındık ve süt içerebilir.');
      expect(found.contains, ['en:nuts']);
      expect(found.traces, ['en:milk']);
    });

    test('allergens marked with underscores, as Open Food Facts writes them', () {
      expect(allergenTags('Yarım yağlı inek _sütü_').contains, ['en:milk']);
    });
  });
}
