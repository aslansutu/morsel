import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:morsel/main.dart';
import 'package:morsel/off_client.dart';
import 'package:morsel/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Runs on a real device or simulator against the live Open Food Facts API:
//   flutter test integration_test -d <device-id>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a typed barcode is looked up on Open Food Facts', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
        MorselApp(client: OffClient(), settings: Settings(prefs), history: History(prefs)));
    await tester.pump(const Duration(seconds: 1));

    // The app opens on the scanner; the keyboard route works with or without a camera.
    await tester.tap(find.text('Type barcode'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), '3017620422003');
    await tester.tap(find.text('Look up'));

    // The camera preview never settles, so pump until the live response renders.
    final name = find.text('Nutella');
    for (var i = 0; i < 100 && name.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(name, findsOneWidget);
    expect(find.text('Nutri-Score'), findsOneWidget);
  });
}
