import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:morsel/ingredients.dart';
import 'package:morsel/label_parser.dart';
import 'package:morsel/labels.dart';
import 'package:morsel/off_client.dart';
import 'package:morsel/product_screen.dart';
import 'package:morsel/theme.dart';
import 'package:morsel/vision.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The phone's own text recognition on real label photos from Open Food Facts,
// scored against what each photo shows (test/fixtures/labels has the same
// labels as recognised on a Mac):
//   flutter test integration_test/label_test.dart -d <device-id>
const _labels = {
  '5449000016645': {'energy-kcal': 42, 'fat': 0, 'saturated-fat': 0, 'carbohydrates': 10.6, 'sugars': 10.6, 'proteins': 0, 'salt': 0}, // Coca-Cola
  '5411188124689': {'energy-kcal': 44, 'fat': 1.8, 'saturated-fat': 0.2, 'carbohydrates': 5.5, 'sugars': 0, 'fiber': 1.3, 'proteins': 0.7, 'salt': 0.1}, // Oat No Sugars
  '7300400112734': {'energy-kcal': 403, 'fat': 9.5, 'saturated-fat': 1.2, 'carbohydrates': 63, 'sugars': 2, 'fiber': 6.5, 'proteins': 13, 'salt': 1.1125}, // Sesam
  '7622210750495': {'energy-kcal': 557, 'fat': 34, 'saturated-fat': 19, 'carbohydrates': 56, 'sugars': 48, 'fiber': 1.6, 'proteins': 4.8, 'salt': 0.38}, // MMMAX Oreo
  '8683417000140': {'energy-kcal': 571, 'fat': 35, 'saturated-fat': 13, 'carbohydrates': 53, 'sugars': 47, 'fiber': 3.6, 'proteins': 9.3, 'salt': 0.2175}, // Tadelle
  '8690504135913': {'energy-kcal': 543, 'fat': 31, 'saturated-fat': 14, 'carbohydrates': 58, 'sugars': 38, 'fiber': 2.4, 'proteins': 6.5, 'salt': 0.2}, // ülker çikolata
  '8690526069500': {'energy-kcal': 360, 'fat': 7.5, 'saturated-fat': 1.8, 'carbohydrates': 53, 'sugars': 1.3, 'fiber': 13, 'proteins': 14, 'salt': 0.02}, // Yulaf Ezmesi
  '8692971435190': {'energy-kcal': 215, 'fat': 16.5, 'saturated-fat': 10.7, 'carbohydrates': 3.5, 'sugars': 3.5, 'proteins': 13, 'salt': 2}, // İçim white cheese 900g
  '8695077020512': {'energy-kcal': 224, 'fat': 18, 'saturated-fat': 11.7, 'carbohydrates': 3.5, 'sugars': 3.5, 'proteins': 12, 'salt': 1.5}, // suzme peynir
  '8695077044020': {'energy-kcal': 312, 'fat': 25, 'saturated-fat': 17, 'carbohydrates': 0.2, 'sugars': 0.2, 'proteins': 21, 'salt': 1.4}, // Tam Yağlı Tost Peyniri
};

// The ingredient photos of test/fixtures/ingredients, by the name Open Food
// Facts gives the photo: their URLs need no product lookup, which Open Food
// Facts rate-limits.
const _ingredientPhotos = {
  '3017620422003': 'ingredients_en.821',
  '5411188124689': 'ingredients_en.348',
  '5449000016645': 'ingredients_en.9',
  '7300400112734': 'ingredients_en.32',
  '7622210750495': 'ingredients_tr.13',
  '8680244600062': 'ingredients_tr.5',
  '8680908020113': 'ingredients_en.27',
  '8682214704916': 'ingredients_tr.7',
  '8682214708815': 'ingredients_tr.8',
  '8682615106098': 'ingredients_tr.5',
  '8682615107293': 'ingredients_tr.5',
  '8683417000126': 'ingredients_tr.18',
  '8690504010203': 'ingredients_tr.23',
  '8690504023135': 'ingredients_tr.15',
  '8690504028536': 'ingredients_en.58',
  '8690504065395': 'ingredients_en.26',
  '8690504079767': 'ingredients_en.11',
  '8690504135913': 'ingredients_en.14',
  '8690526018065': 'ingredients_tr.5',
  '8690526063508': 'ingredients_en.21',
  '8690526069500': 'ingredients_tr.20',
  '8690533034010': 'ingredients_tr.8',
  '8690629437855': 'ingredients_en.10',
  '8690632243054': 'ingredients_tr.8',
  '8690635430055': 'ingredients_tr.7',
  '8690766009205': 'ingredients_en.51',
  '8690787561010': 'ingredients_tr.7',
  '8691058141948': 'ingredients_en.12',
  '8691225153521': 'ingredients_tr.7',
  '8691641080036': 'ingredients_tr.29',
  '8692971433554': 'ingredients_tr.7',
  '8692971435190': 'ingredients_en.5',
  '8694587138496': 'ingredients_tr.5',
  '8695077020512': 'ingredients_en.11',
  '8695077026248': 'ingredients_tr.5',
  '8695077044020': 'ingredients_en.5',
  '8695077046994': 'ingredients_tr.12',
  '8696362500382': 'ingredients_en.6',
  '8699141056025': 'ingredients_tr.14',
};

/// The full-size photo [name] of the product [code] (13 digits).
String _photoUrl(String code, String name) => 'https://images.openfoodfacts.org/images/products/'
    '${code.substring(0, 3)}/${code.substring(3, 6)}/${code.substring(6, 9)}/${code.substring(9)}/$name.full.jpg';

Future<String> _download(String url, String name) async {
  final res = await http.get(Uri.parse(url), headers: {'User-Agent': 'Morsel/0.1.0'});
  expect(res.statusCode, 200, reason: url);
  final file = File('${Directory.systemTemp.path}/$name');
  await file.writeAsBytes(res.bodyBytes);
  return file.path;
}

Future<Map<String, dynamic>> _product(String code) async {
  final res = await http.get(
    Uri.https('world.openfoodfacts.org', '/api/v2/product/$code',
        {'fields': 'product_name,image_nutrition_url,image_front_url,nutriments'}),
    headers: {'User-Agent': 'Morsel/0.1.0'},
  );
  return ((jsonDecode(res.body) as Map<String, dynamic>)['product'] as Map<String, dynamic>?) ?? {};
}

/// The real Vision, except that "Choose a photo" returns [photos] in turn: the
/// system photo picker is outside the app, where a test can't tap.
class _ChosenPhotos extends Vision {
  _ChosenPhotos(this.photos);
  final List<String> photos;
  @override
  Future<String?> pickPhoto(ImageSource source) async => photos.removeAt(0);
}

/// Gives the screen time to be photographed from outside (`simctl io screenshot`, `adb screencap`).
Future<void> _pose(WidgetTester tester, String name) async {
  // ignore: avoid_print
  print('SHOT $name');
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(finder, findsWidgets);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const vision = Vision();

  testWidgets('text recognition reads real nutrition labels', (tester) async {
    var compared = 0, matched = 0, wrong = 0;
    for (final MapEntry(key: code, value: truth) in _labels.entries) {
      final url = (await _product(code))['image_nutrition_url'] as String;
      // The full-size photo, as a phone camera would give, not the 400 px preview.
      final path = await _download(url.replaceFirst(RegExp(r'\.\d+\.jpg$'), '.full.jpg'), '$code.jpg');
      final lines = await vision.readText(path);
      expect(lines, isNotEmpty, reason: code);
      // What this phone recognised, for test/fixtures/labels.
      // ignore: avoid_print
      print('OCR $code ${jsonEncode([for (final l in lines) l.toMap()])}');
      final reading = parseLabel(lines);
      final misses = <String>[];
      for (final MapEntry(key: id, value: expected) in truth.entries) {
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
      // ignore: avoid_print
      print('LABEL $code: ${lines.length} lines${misses.isEmpty ? '' : ' · ${misses.join(', ')}'}');
    }
    // ignore: avoid_print
    print('LABEL TOTAL $matched of $compared right, $wrong wrong');
    // The same bar as test/label_corpus_test.dart.
    expect(matched / compared, greaterThanOrEqualTo(0.75));
    expect(wrong / compared, lessThanOrEqualTo(0.05));
  });

  testWidgets('text recognition reads real ingredient lists', (tester) async {
    var lists = 0;
    for (final MapEntry(key: code, value: name) in _ingredientPhotos.entries) {
      final path = await _download(_photoUrl(code, name), '$code-ingredients.jpg');
      final lines = await vision.readText(path);
      // What this phone recognised, for test/fixtures/ingredients, which scores it.
      // ignore: avoid_print
      print('INGREDIENTS $code ${jsonEncode([for (final l in lines) l.toMap()])}');
      final list = readIngredients(lines);
      if (list != null) lists++;
      // ignore: avoid_print
      print('LIST $code: ${list ?? '—'}');
    }
    // ignore: avoid_print
    print('LIST TOTAL $lists of ${_ingredientPhotos.length} photos gave a list');
    // 31 of the photos have a list with a heading text recognition can read.
    expect(lists, greaterThanOrEqualTo(20));
  });

  testWidgets('the subject cut-out returns the product on white', (tester) async {
    final product = await _product('3017620422003');
    final url = (product['image_front_url'] as String).replaceFirst(RegExp(r'\.\d+\.jpg$'), '.full.jpg');
    final photo = await _download(url, 'front.jpg');
    final String? cut;
    try {
      cut = await vision.cutOut(photo);
    } on PlatformException catch (e) {
      // Vision's foreground mask needs the phone's neural hardware; the simulator has none.
      expect(e.message, contains('inference context'));
      // ignore: avoid_print
      print('CUTOUT not on this simulator');
      return;
    }
    // ignore: avoid_print
    print('CUTOUT ${cut == null ? 'no subject' : '${File(cut).lengthSync()} bytes at $cut'}');
    expect(cut, isNotNull);
    expect(File(cut!).existsSync(), isTrue);
  });

  testWidgets('the whole flow on the device: read, check, add a photo, save', (tester) async {
    // Tadelle's label is a clean Turkish and English table; a hazelnut spread's
    // jar has its ingredient list in both languages.
    String full(Map<String, dynamic> p, String key) =>
        (p[key] as String).replaceFirst(RegExp(r'\.\d+\.jpg$'), '.full.jpg');
    final label = await _download(full(await _product('8683417000140'), 'image_nutrition_url'), 'flow-label.jpg');
    final list = await _download(_photoUrl('8682615106098', 'ingredients_tr.5'), 'flow-ingredients.jpg');
    final front = await _download(full(await _product('3017620422003'), 'image_front_url'), 'flow-front.jpg');
    final dir = Directory('${Directory.systemTemp.path}/flow-store');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    SharedPreferences.setMockInitialValues({});
    final labels = LabelStore(await SharedPreferences.getInstance(), dir);

    await tester.pumpWidget(MaterialApp(
      theme: morselTheme(Brightness.light),
      darkTheme: morselTheme(Brightness.dark),
      home: ProductScreen(
          code: '8699999999994', client: OffClient(), labels: labels, vision: _ChosenPhotos([label, list, front])),
    ));
    await _until(tester, find.text('Read the label'));
    await _pose(tester, 'not-found');

    await tester.tap(find.text('Read the label'));
    await tester.pumpAndSettle();
    await _pose(tester, 'source-sheet');
    await tester.tap(find.text('Choose a photo'));
    await _until(tester, find.textContaining('Check each one against the photo'));
    await _pose(tester, 'review');

    // The form is longer than the screen, and a list builds only what's in view.
    Future<void> scrollTo(Finder finder) =>
        tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
    await scrollTo(find.text('Read from another photo'));
    await tester.tap(find.text('Read from another photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a photo'));
    await _until(tester, find.text('See that photo'));
    await tester.pumpAndSettle();
    await _pose(tester, 'review-ingredients');
    await scrollTo(find.widgetWithText(TextFormField, 'Name'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Nutella (test)');
    await scrollTo(find.text('Add photo'));
    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a photo'));
    await _until(tester, find.text('Change'));
    await tester.pumpAndSettle();
    await _pose(tester, 'review-photo');

    await scrollTo(find.text('Save'));
    await tester.tap(find.text('Save'));
    await _until(tester, find.text('Nutella (test)'));
    await tester.pumpAndSettle();
    await _pose(tester, 'saved');
    await scrollTo(find.text('Ingredients'));
    await tester.pumpAndSettle();
    await _pose(tester, 'saved-ingredients');
    expect(labels['8699999999994']?.values, isNotEmpty);
    expect(labels['8699999999994']?.ingredients, isNotNull);
    expect(labels.productPhoto('8699999999994')?.existsSync(), isTrue);
  });
}
