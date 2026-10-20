import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:morsel/format.dart';
import 'package:morsel/main.dart';
import 'package:morsel/off_client.dart';
import 'package:morsel/product_screen.dart';
import 'package:morsel/settings.dart';
import 'package:morsel/settings_screen.dart';
import 'package:morsel/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Response shapes match live Open Food Facts calls made on 2026-10-18.
final _nutella = {
  'code': '3017620422003',
  'status': 1,
  'status_verbose': 'product found',
  'product': {
    'code': '3017620422003',
    'product_name': 'Nutella',
    'brands': 'Nutella, Ferrero',
    'quantity': '400 g',
    'categories_tags': ['en:spreads'],
    'nutriscore_grade': 'e',
    'nova_group': 4,
    'ecoscore_grade': 'unknown',
    'nutrient_levels': {'fat': 'high', 'salt': 'low', 'saturated-fat': 'high', 'sugars': 'high'},
    'nutriments': {
      'energy-kcal_100g': 539,
      'fat_100g': 30.9,
      'salt_100g': 0.107,
      'saturated-fat_100g': 10.6,
      'sugars_100g': 56.3,
    },
    'allergens_tags': ['en:milk', 'en:nuts', 'en:soybeans'],
    'additives_tags': ['en:e322', 'en:e322i'],
    'ingredients_analysis_tags': ['en:palm-oil', 'en:non-vegan', 'en:vegetarian'],
    'knowledge_panels': {
      'ingredients': {
        'title_element': {'title': '9 ingredients'},
        'elements': [
          {
            'element_type': 'text',
            'text_element': {
              'html': 'Sugar, vegetable fat (palm), <span class="allergen">hazelnuts</span> (13%)'
            },
          },
        ],
      },
      'ingredients_added_sugars': {
        'evaluation': 'bad',
        'title_element': {'title': 'Contains added sugars (52%)'},
        'elements': [],
      },
      'nova': {
        'title_element': {'title': 'Ultra-processed foods', 'subtitle': '2 ultra-processing markers'},
        'elements': [],
      },
    },
  },
};
final _missing = {'code': '8699999999994', 'status': 0, 'status_verbose': 'product not found'};

OffClient _client(int status, Map<String, dynamic> body, [List<Uri>? requests]) =>
    OffClient(client: MockClient((request) async {
      requests?.add(request.url);
      return http.Response(jsonEncode(body), status);
    }));

Future<(Settings, History)> _state([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  return (Settings(p), History(p));
}

String _savedScan({String? name}) => jsonEncode([
      {'code': '3017620422003', 'scannedAt': DateTime(2026, 10, 1).toIso8601String(), 'name': name},
    ]);

Widget _wrap(Widget child) => MaterialApp(theme: morselTheme(Brightness.light), home: child);

void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('OffClient', () {
    test('returns the product when status is 1', () async {
      final lookup = await _client(200, _nutella).lookup('3017620422003');
      expect(lookup.product?['product_name'], 'Nutella');
    });

    test('a missing product (HTTP 404, status 0) is not an error', () async {
      final lookup = await _client(404, _missing).lookup('8699999999994');
      expect(lookup.product, isNull);
    });

    test('server errors throw', () async {
      expect(_client(503, {}).lookup('1'), throwsA(isA<OffException>()));
    });

    test('asks for the app language, the country and the knowledge panels', () async {
      final requests = <Uri>[];
      await _client(200, _nutella, requests).lookup('3017620422003', country: 'TR');
      final query = requests.single.queryParameters;
      expect(query['lc'], 'en');
      expect(query['cc'], 'tr');
      expect(query['fields'], contains('knowledge_panels'));
    });
  });

  group('ProductScreen', () {
    testWidgets('shows scores, highlights, meters and ingredients', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(
          _wrap(ProductScreen(code: '3017620422003', client: _client(200, _nutella))));
      await tester.pumpAndSettle();

      expect(find.text('Nutella'), findsOneWidget);
      expect(find.text('Nutella, Ferrero · 400 g'), findsOneWidget);
      // Scores: letter/number plus a word, never colour alone.
      expect(find.text('E'), findsOneWidget);
      expect(find.text('Very poor'), findsOneWidget);
      expect(find.text('Ultra-processed'), findsOneWidget);
      expect(find.text('Not computed'), findsOneWidget);
      // Highlights.
      expect(find.text('Contains palm oil'), findsOneWidget);
      expect(find.text('Contains added sugars (52%)'), findsOneWidget);
      expect(find.text('Not vegan'), findsOneWidget);
      expect(find.text('Vegetarian'), findsOneWidget);
      expect(find.text('Contains milk, nuts, soybeans'), findsOneWidget);
      expect(find.text('2 additives'), findsOneWidget);
      // Meters: value plus level word.
      expect(find.text('56.3 g'), findsOneWidget);
      expect(find.text('0.11 g'), findsOneWidget);
      expect(find.text('High'), findsNWidgets(3));
      expect(find.text('Low'), findsOneWidget);
      // Ingredients come from the knowledge panel, allergens included.
      expect(find.textContaining('hazelnuts', findRichText: true), findsWidgets);
      expect(find.text('9 ingredients'), findsOneWidget);
      expect(find.text('Ultra-processed foods'), findsOneWidget);
    });

    testWidgets('an unknown barcode says so', (tester) async {
      await tester.pumpWidget(
          _wrap(ProductScreen(code: '8699999999994', client: _client(404, _missing))));
      await tester.pumpAndSettle();
      expect(find.text('Not in Open Food Facts yet'), findsOneWidget);
    });
  });

  group('History', () {
    test('a repeat scan moves to the top instead of duplicating, and survives a restart', () async {
      final (_, history) = await _state();
      for (final code in ['1', '2', '1']) {
        history.record(ScanRecord(code: code, scannedAt: DateTime.now()));
      }
      expect(history.items.map((r) => r.code), ['1', '2']);
      final reloaded = History(await SharedPreferences.getInstance());
      expect(reloaded.items.map((r) => r.code), ['1', '2']);
    });

    testWidgets('opening a scan records the lookup when remembering is on', (tester) async {
      final (settings, history) = await _state({'history': _savedScan()});
      await tester.pumpWidget(MorselApp(
          client: _client(200, _nutella),
          settings: settings,
          history: history,
          initialTab: DockTab.history));
      await tester.tap(find.text('Not in Open Food Facts'));
      await tester.pumpAndSettle();
      expect(history.items.single.name, 'Nutella');
    });

    testWidgets('nothing is recorded when remembering is off', (tester) async {
      final (settings, history) =
          await _state({'history': _savedScan(), 'rememberScans': false});
      await tester.pumpWidget(MorselApp(
          client: _client(200, _nutella),
          settings: settings,
          history: history,
          initialTab: DockTab.history));
      await tester.tap(find.text('Not in Open Food Facts'));
      await tester.pumpAndSettle();
      expect(history.items.single.name, isNull);
    });
  });

  group('Settings', () {
    testWidgets('turning off "Remember scans" deletes history, and Undo brings it back',
        (tester) async {
      final (settings, history) = await _state({'history': _savedScan(name: 'Nutella')});
      await tester.pumpWidget(MorselApp(
          client: _client(200, _nutella),
          settings: settings,
          history: history,
          initialTab: DockTab.settings));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(settings.rememberScans, isFalse);
      expect(history.items, isEmpty);
      expect(find.text('Scan history off · 1 scan deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(settings.rememberScans, isTrue);
      expect(history.items.single.name, 'Nutella');
    });

    testWidgets('the country picker finds Türkiye by typing "turk"', (tester) async {
      final (settings, history) = await _state();
      await tester.pumpWidget(_wrap(SettingsScreen(settings: settings, history: history)));
      await tester.tap(find.text('Country'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'turk');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Türkiye'));
      await tester.pumpAndSettle();
      expect(settings.country, 'TR');
      expect(find.text('🇹🇷  Türkiye'), findsOneWidget);
    });
  });

  testWidgets('the dock switches between tabs', (tester) async {
    final (settings, history) = await _state();
    await tester.pumpWidget(MorselApp(
        client: _client(200, _nutella),
        settings: settings,
        history: history,
        initialTab: DockTab.history));
    expect(find.text('No scans yet'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Remember scans'), findsOneWidget);
  });

  testWidgets('the dock stays a compact bar, even at 2× text size', (tester) async {
    final (settings, history) = await _state();
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final scale in [1.0, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpWidget(MorselApp(
          client: _client(200, _nutella),
          settings: settings,
          history: history,
          initialTab: DockTab.history));
      // Once, a stretching child made the floating dock cover the whole screen.
      expect(tester.getSize(find.byType(Dock)).height, lessThan(140), reason: 'text scale $scale');
      expect(tester.takeException(), isNull);
    }
  });

  test('formatting', () {
    expect(formatAmount(0.107), '0.11');
    expect(formatAmount(30.9), '30.9');
    expect(formatAmount(12), '12');
    final now = DateTime(2026, 10, 18, 12);
    expect(formatDay(DateTime(2026, 10, 18, 8), now: now), 'Today');
    expect(formatDay(DateTime(2026, 10, 17, 23), now: now), 'Yesterday');
    expect(formatDay(DateTime(2026, 10, 12), now: now), 'Mon 12 Oct');
    expect(fold('Türkiye'), 'turkiye');
    expect(flagOf('tr'), '🇹🇷');
  });
}
