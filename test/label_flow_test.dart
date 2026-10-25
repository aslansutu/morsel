import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:morsel/labels.dart';
import 'package:morsel/off_client.dart';
import 'package:morsel/product_screen.dart';
import 'package:morsel/settings.dart';
import 'package:morsel/theme.dart';
import 'package:morsel/vision.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _code = '8699999999994';

/// An ingredient list as a photo's lines, under where a nutrition table ends.
const _ingredientLines = [
  TextLine('Ingredients: Sugar, palm oil, HAZELNUTS 13%,', 0.05, 0.6, 0.95, 0.64),
  TextLine('skimmed MILK powder, soya lecithin. May contain other nuts.', 0.05, 0.65, 0.95, 0.69),
];
const _ingredientList =
    'Sugar, palm oil, HAZELNUTS 13%, skimmed MILK powder, soya lecithin. May contain other nuts.';

/// The phone's side of label reading, with text a real label would give.
class _FakeVision extends Vision {
  _FakeVision(this.photo);

  final String photo;
  var scans = 0;

  /// The photo the next pick returns, when not [photo].
  String? next;

  /// What text recognition reads in a photo, by path; otherwise a nutrition table.
  final texts = <String, List<TextLine>>{};

  @override
  Future<String?> scanDocument() async {
    scans++;
    throw VisionUnavailable(null);
  }

  @override
  Future<String?> pickPhoto(ImageSource source) async => next ?? photo;

  @override
  Future<List<TextLine>> readText(String imagePath) async => texts[imagePath] ?? _nutritionLines;
}

/// A nutrition table as a photo's lines.
final _nutritionLines = [
  for (final (i, (name, value)) in const [
    ('Nutrition information', ''),
    ('Typical values', 'Per 100 g'),
    ('Energy', '2252 kJ / 539 kcal'),
    ('Fat', '30.9 g'),
    ('of which saturates', '10.6 g'),
    ('Carbohydrate', '57.5 g'),
    ('of which sugars', '56.3 g'),
    ('Protein', '6.3 g'),
    ('Salt', '0.107 g'),
  ].indexed) ...[
    TextLine(name, 0.05, i * 0.06, 0.5, i * 0.06 + 0.04),
    if (value.isNotEmpty) TextLine(value, 0.6, i * 0.06, 0.95, i * 0.06 + 0.04),
  ],
];

OffClient _client(Map<String, dynamic> body) => OffClient(
    client: MockClient((_) async => http.Response(jsonEncode(body), body['status'] == 1 ? 200 : 404)));

final _missing = {'code': _code, 'status': 0, 'status_verbose': 'product not found'};
final _noIngredients = {
  'code': _code,
  'status': 1,
  'product': {
    'code': _code,
    'product_name': 'Mystery spread',
    'nutriments': {'fat_100g': 30.9, 'sugars_100g': 56.3},
    'nutrient_levels': {'fat': 'high', 'sugars': 'high'},
  },
};
final _noNutrition = {
  'code': _code,
  'status': 1,
  'product': {'code': _code, 'product_name': 'Mystery biscuits', 'nutriments': <String, dynamic>{}},
};

void main() {
  late Directory dir;
  late String photo;
  late LabelStore labels;
  late List<ProductLookup> loaded;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('morsel_labels');
    photo = '${dir.path}/label.png';
    File(photo).writeAsBytesSync(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));
    SharedPreferences.setMockInitialValues({});
    labels = LabelStore(await SharedPreferences.getInstance(), Directory('${dir.path}/store'));
    loaded = [];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<_FakeVision> open(WidgetTester tester, Map<String, dynamic> body) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vision = _FakeVision(photo);
    await tester.pumpWidget(MaterialApp(
      theme: morselTheme(Brightness.light),
      home: ProductScreen(
          code: _code, client: _client(body), labels: labels, vision: vision, onLoaded: loaded.add),
    ));
    await tester.pumpAndSettle();
    return vision;
  }

  Future<void> readLabelFromPhoto(WidgetTester tester) async {
    await tester.tap(find.text('Read the label'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a photo'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    // Saving copies the photo: real file work, which only moves on outside the
    // test's fake clock, one step per round.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('an unknown barcode: read the label, check it, save it, edit it', (tester) async {
    await open(tester, _missing);
    expect(find.text('Not in Open Food Facts yet'), findsOneWidget);
    await readLabelFromPhoto(tester);

    expect(find.text('Check the label'), findsOneWidget);
    expect(find.text('Found 7 of 8 values. Check each one against the photo.'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '539'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '0.107'), findsOneWidget);

    // A new product needs a name.
    await save(tester);
    expect(find.text('Add a name'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Hazelnut spread');
    await save(tester);

    expect(find.text('Hazelnut spread'), findsOneWidget);
    expect(find.text('High'), findsNWidgets(3));
    expect(find.text('Low'), findsOneWidget);
    // Only the label is known: no scores, no Open Food Facts link.
    expect(find.text('Nutri-Score'), findsNothing);
    expect(find.text('Open Food Facts'), findsNothing);
    expect(find.text('your photo of the label'), findsOneWidget);
    expect(find.text('Barcode $_code'), findsOneWidget);
    // History learns the name.
    expect(ScanRecord.fromLookup(loaded.last).name, 'Hazelnut spread');

    // Kept on the device across restarts.
    final reloaded = LabelStore(await SharedPreferences.getInstance(), Directory('${dir.path}/store'));
    expect(reloaded[_code]?.values['fat'], 30.9);
    expect(reloaded.labelPhoto(_code)?.existsSync(), isTrue);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit the label'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Hazelnut spread'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '30.9'), '31');
    await save(tester);
    expect(find.text('31 g'), findsOneWidget);
  });

  testWidgets('a known product without nutrition facts gets them from the label', (tester) async {
    await open(tester, _noNutrition);
    expect(find.text('Nutrition facts are not available for this product yet.'), findsOneWidget);
    await readLabelFromPhoto(tester);
    // Open Food Facts already has the name.
    expect(find.widgetWithText(TextFormField, 'Name'), findsNothing);
    await save(tester);

    expect(find.text('Mystery biscuits'), findsOneWidget);
    expect(find.text('High'), findsNWidgets(3));
    expect(find.text('Nutri-Score'), findsOneWidget);
    expect(find.text('Nutrition facts from '), findsOneWidget);
    expect(find.text('Open Food Facts'), findsOneWidget);
  });

  testWidgets('no scanner on this device: says so and offers a photo', (tester) async {
    final vision = await open(tester, _missing);
    await tester.tap(find.text('Read the label'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan the label'));
    await tester.pumpAndSettle();
    expect(vision.scans, 1);
    expect(find.text("This device can't scan. Choose a photo instead."), findsOneWidget);
  });

  testWidgets('the ingredient list beside the table is read too, its allergens shown', (tester) async {
    final vision = await open(tester, _missing);
    vision.texts[photo] = [..._nutritionLines, ..._ingredientLines];
    await readLabelFromPhoto(tester);
    expect(find.text('Found the ingredient list. Check it against the photo.'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, _ingredientList), findsOneWidget);
    // Read from the text as it's corrected: "other nuts" is already in it.
    expect(find.text('Allergens: Contains nuts, milk, soybeans.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Hazelnut spread');
    await save(tester);

    expect(find.text('Contains nuts, milk, soybeans'), findsOneWidget);
    expect(find.textContaining('palm oil', findRichText: true), findsOneWidget);
    expect(find.text('Read the ingredients'), findsNothing);
    final reloaded = LabelStore(await SharedPreferences.getInstance(), Directory('${dir.path}/store'));
    expect(reloaded[_code]?.ingredients, _ingredientList);
    expect(reloaded[_code]?.ingredientsLanguage, 'en');
  });

  testWidgets('a product with nutrition facts but no ingredient list gets only the list', (tester) async {
    final vision = await open(tester, _noIngredients);
    vision.texts[photo] = _ingredientLines;
    expect(find.text('The ingredient list is not available for this product yet.'), findsOneWidget);
    await tester.tap(find.text('Read the ingredients'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a photo'));
    await tester.pumpAndSettle();
    // Open Food Facts has the nutrition facts, so the form doesn't ask for them.
    expect(find.text('Per 100 ml'), findsNothing);
    expect(find.text('Try another photo'), findsNothing);
    await save(tester);

    expect(find.text('Ingredients from '), findsOneWidget);
    expect(find.textContaining('soya lecithin', findRichText: true), findsOneWidget);
    // Open Food Facts' nutrition facts stay.
    expect(find.text('30.9 g'), findsOneWidget);
    expect(labels[_code]?.values, isEmpty);
  });

  testWidgets('no list on the label photo: one is read from another photo', (tester) async {
    final vision = await open(tester, _missing);
    await readLabelFromPhoto(tester);
    expect(find.text('No ingredient list found in this photo. Type it, or read it from another photo.'),
        findsOneWidget);
    final back = '${dir.path}/back.png';
    File(photo).copySync(back);
    vision
      ..next = back
      ..texts[back] = _ingredientLines;
    await tester.tap(find.text('Read from another photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a photo'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, _ingredientList), findsOneWidget);
    expect(find.text('See that photo'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Hazelnut spread');
    await save(tester);
    expect(labels.ingredientsPhoto(_code)?.existsSync(), isTrue);
    expect(labels.labelPhoto(_code)?.path, isNot(labels.ingredientsPhoto(_code)?.path));
  });

  testWidgets('an empty form says what to enter, and saves nothing', (tester) async {
    final vision = await open(tester, _missing);
    vision.texts[photo] = const [];
    await readLabelFromPhoto(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Hazelnut spread');
    await save(tester);
    expect(find.text('Enter at least one value or the ingredient list.'), findsOneWidget);
    expect(labels[_code], isNull);
  });

  testWidgets('an impossible value is caught before saving', (tester) async {
    await open(tester, _noNutrition);
    await readLabelFromPhoto(tester);
    await tester.enterText(find.widgetWithText(TextFormField, '30.9'), '309');
    await save(tester);
    expect(find.text('Over 100 g'), findsOneWidget);
    expect(labels[_code], isNull);
  });
}
