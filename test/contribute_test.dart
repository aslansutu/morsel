import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:morsel/account.dart';
import 'package:morsel/contribute_screen.dart';
import 'package:morsel/contributions.dart';
import 'package:morsel/labels.dart';
import 'package:morsel/off_client.dart';
import 'package:morsel/product_screen.dart';
import 'package:morsel/theme.dart';
import 'package:morsel/vision.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _code = '8699999999994';

/// The Keychain or Keystore, in memory.
class _FakeSecrets extends Secrets {
  final values = <String, String>{};

  @override
  Future<String?> read(String name) async => values[name];

  @override
  Future<void> write(String name, String value) async => values[name] = value;

  @override
  Future<void> delete(String name) async => values.remove(name);
}

/// Photos made ready to send: the copy says which photo it was made from, so a
/// test can tell an upload went through [forUpload], which drops the metadata.
class _FakeVision extends Vision {
  _FakeVision(this.dir);

  final Directory dir;
  var _made = 0;

  @override
  Future<String> forUpload(String imagePath) async {
    final ready = '${dir.path}/ready-${_made++}.jpg';
    await File(ready).writeAsString('ready:${imagePath.split('/').last}');
    return ready;
  }
}

/// Open Food Facts, answering lookups with [product] and every write with [write].
class _Server {
  _Server({this.product});

  final Map<String, dynamic>? product;
  http.Response Function(http.Request request) write = (_) => http.Response('{"status":"success"}', 200);
  final writes = <http.Request>[];

  late final client = OffClient(client: MockClient((request) async {
    if (request.method == 'GET') {
      final body = product == null
          ? {'code': _code, 'status': 0}
          : {'code': _code, 'status': 1, 'product': product};
      return http.Response(jsonEncode(body), product == null ? 404 : 200);
    }
    writes.add(request);
    return write(request);
  }));

  List<http.Request> at(String path) => writes.where((r) => r.url.path == path).toList();

  /// What a photo upload was made from, and which fields it was selected for.
  static (String, Map<String, dynamic>) upload(http.Request r) {
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return (utf8.decode(base64Decode(body['image_data_base64'] as String)), body['selected'] as Map<String, dynamic>);
  }
}

const _shared = (user: 'morsel', password: 'shared-pw');

void main() {
  late Directory dir;
  late SharedPreferences prefs;
  late _FakeSecrets secrets;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('morsel_contribute');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    secrets = _FakeSecrets();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ContributionQueue queue(_Server server, {bool shared = true}) => ContributionQueue(
        prefs,
        Directory('${dir.path}/queue'),
        client: server.client,
        account: OffAccount(prefs, shared: shared ? _shared : null, secrets: secrets),
        vision: _FakeVision(dir),
      );

  // A 1×1 PNG: the screens show the photos.
  String photo(String name) => (File('${dir.path}/$name')
        ..writeAsBytesSync(base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')))
      .path;

  group('writing to Open Food Facts', () {
    test('a photo goes to the staging server, selected for each field in its language, with who sent it', () async {
      final server = _Server();
      await server.client.uploadPhoto(_code, utf8.encode('jpeg'),
          selected: {'nutrition': 'tr', 'ingredients': 'tr'}, as: const OffCredentials('alice', 'pw'));
      final request = server.writes.single;
      expect(request.url.toString(), 'https://world.openfoodfacts.net/api/v3/product/$_code/images');
      expect(request.headers['Authorization'], 'Basic ${base64Encode(utf8.encode('off:off'))}');
      expect(request.headers['User-Agent'], startsWith('Morsel/'));
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['user_id'], 'alice');
      expect(body['app_name'], 'Morsel');
      // A user's own account needs no id telling them apart.
      expect(body.containsKey('app_uuid'), isFalse);
      expect(body['selected'], {
        'nutrition': {'tr': <String, dynamic>{}},
        'ingredients': {'tr': <String, dynamic>{}},
      });
    });

    test("product fields go through the edit form, with the shared account's per-install id", () async {
      final server = _Server();
      await server.client.editProduct(_code, {'quantity': '500 g'},
          as: const OffCredentials('morsel', 'pw', appUuid: 'abc'), comment: 'Morsel: the quantity');
      final request = server.writes.single;
      expect(request.url.path, '/cgi/product_jqm2.pl');
      expect(request.bodyFields, {
        'code': _code,
        'user_id': 'morsel',
        'password': 'pw',
        'app_name': 'Morsel',
        'app_version': isA<String>(),
        'app_uuid': 'abc',
        'comment': 'Morsel: the quantity',
        'quantity': '500 g',
      });
    });

    test("what Open Food Facts refuses is not retried; what it can't answer is", () async {
      final server = _Server();
      Future<void> answer(int status, String body) {
        server.write = (_) => http.Response(body, status);
        return server.client.editProduct(_code, const {}, as: const OffCredentials('alice', 'pw'));
      }

      // Shapes from world.openfoodfacts.net, 2026-10-25.
      await expectLater(answer(403, '<!doctype html><title>Error</title>'),
          throwsA(isA<OffRefused>().having((e) => e.message, 'message', 'Wrong username or password')));
      await expectLater(answer(200, '{"status_verbose":"no user credentials","status":0}'),
          throwsA(isA<OffRefused>().having((e) => e.message, 'message', 'no user credentials')));
      await expectLater(
          answer(400, '{"errors":[{"message":{"id":"invalid_code","name":"Invalid code"}}],"status":"failure"}'),
          throwsA(isA<OffRefused>().having((e) => e.message, 'message', 'Invalid code')));
      for (final status in [429, 503]) {
        await expectLater(answer(status, ''), throwsA(isA<OffException>().having((e) => e, 'refused', isNot(isA<OffRefused>()))));
      }
    });
  });

  group('the queue', () {
    test('a contribution waits on the phone until Open Food Facts confirms it, sending no photo twice', () async {
      final server = _Server()..write = (r) => r.url.path.contains('/images')
          ? http.Response('{"status":"success"}', 200)
          : http.Response('', 503);
      final first = queue(server);
      await first.add(_code,
          fields: {'quantity': '500 g'},
          photos: [(path: photo('label.jpg'), selected: {'nutrition': 'en'})],
          summary: 'a photo and the quantity');
      await first.send();
      final waiting = first.latest(_code)!;
      expect(waiting.state, ContributionState.waiting);
      expect(waiting.error, "Couldn't reach Open Food Facts.");
      // The upload is what forUpload made, without the original's metadata.
      expect(_Server.upload(server.at('/api/v3/product/$_code/images').single).$1, 'ready:label.jpg');
      first.dispose();

      // After a restart, only the fields are left to send.
      server
        ..writes.clear()
        ..write = (_) => http.Response('{"status":1,"status_verbose":"fields saved"}', 200);
      final second = queue(server);
      await second.send();
      expect(server.writes.map((r) => r.url.path), ['/cgi/product_jqm2.pl']);
      expect(second.latest(_code)!.state, ContributionState.sent);
      expect(Directory('${dir.path}/queue').listSync(), isEmpty);
      second.dispose();
    });

    test('a refusal is shown and not retried until the user tries again', () async {
      final server = _Server()..write = (_) => http.Response('<html>Error</html>', 403);
      final q = queue(server);
      await q.add(_code, fields: {'quantity': '500 g'}, photos: const [], summary: 'the quantity');
      await q.send();
      expect(q.latest(_code)!.state, ContributionState.refused);
      expect(q.latest(_code)!.error, 'Wrong username or password');
      final tries = server.writes.length;
      await q.send();
      expect(server.writes.length, tries);

      server.write = (_) => http.Response('{"status":1}', 200);
      await q.retry(q.latest(_code)!);
      expect(q.latest(_code)!.state, ContributionState.sent);
      q.dispose();
    });
  });

  group('the account', () {
    test('signing in checks the password with Open Food Facts and keeps it in secure storage, not preferences',
        () async {
      final server = _Server()..write = (_) => http.Response('<html>Signed in</html>', 200);
      final account = OffAccount(prefs, shared: _shared, secrets: secrets);
      await account.signIn(server.client, 'alice', 'secret-pw');
      expect(server.writes.single.url.path, '/cgi/session.pl');
      expect(account.user, 'alice');
      expect(secrets.values.values, contains('secret-pw'));
      expect(prefs.getKeys().map((k) => '${prefs.get(k)}').join(), isNot(contains('secret-pw')));
      final as = (await account.credentials())!;
      expect((as.user, as.password, as.appUuid), ('alice', 'secret-pw', null));
    });

    test('a wrong password stores nothing; without signing in, the shared account goes with an id per install',
        () async {
      final server = _Server()..write = (_) => http.Response('<html>Error</html>', 403);
      final account = OffAccount(prefs, shared: _shared, secrets: secrets);
      await expectLater(account.signIn(server.client, 'alice', 'wrong'), throwsA(isA<OffRefused>()));
      expect(account.user, isNull);
      expect(secrets.values, isEmpty);
      final as = (await account.credentials())!;
      expect(as.user, 'morsel');
      expect(as.appUuid, hasLength(32));
      expect(OffAccount(prefs, shared: _shared, secrets: secrets).appUuid, as.appUuid);
    });
  });

  group('the send screen', () {
    Future<void> settle(WidgetTester tester) async {
      // Copying photos is real file work, which only moves on outside the test's
      // fake clock, one step per round.
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('a label for an unknown product goes as one upload for both of its photos, then its facts',
        (tester) async {
      tall(tester);
      final labels = LabelStore(prefs, Directory('${dir.path}/labels'));
      await tester.runAsync(() => labels.save(
            LabelEntry(
              code: _code,
              values: const {'fat': 30.9, 'sugars': 56.3},
              perMl: false,
              savedAt: DateTime(2026, 10, 25),
              name: 'Fındık kreması',
              ingredients: 'Şeker, FINDIK (%13)',
              ingredientsLanguage: 'tr',
            ),
            labelImage: photo('label.jpg'),
            productImage: photo('front.jpg'),
          ));
      final server = _Server();
      final contributions = queue(server);
      await tester.pumpWidget(MaterialApp(
        theme: morselTheme(Brightness.light),
        home: ProductScreen(
            code: _code, client: server.client, labels: labels, contributions: contributions, vision: _FakeVision(dir)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Share what you read'), findsOneWidget);
      await tester.tap(find.text('Send to Open Food Facts'));
      await tester.pumpAndSettle();
      expect(find.text('Add to Open Food Facts'), findsOneWidget);
      expect(find.text('Sends 3 photos, the name, the nutrition facts and the ingredient list.'), findsOneWidget);
      // A brand where Open Food Facts has none is added, not replaced.
      await tester.enterText(find.widgetWithText(TextFormField, 'Brand'), 'Kardelen');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Send to Open Food Facts'));
      await settle(tester);

      // The label photo is both the nutrition and the ingredients photo: one upload.
      final uploads = server.at('/api/v3/product/$_code/images').map(_Server.upload).toList();
      expect(uploads, hasLength(2));
      expect(uploads[0].$1, contains('-photo-'));
      expect(uploads[0].$2, {'front': {'tr': <String, dynamic>{}}});
      expect(uploads[1].$1, contains('-label-'));
      expect(uploads[1].$2, {'ingredients': {'tr': <String, dynamic>{}}, 'nutrition': {'tr': <String, dynamic>{}}});
      final fields = server.at('/cgi/product_jqm2.pl').single.bodyFields;
      expect(fields, containsPair('user_id', 'morsel'));
      expect(fields, containsPair('app_uuid', hasLength(32)));
      expect(fields, containsPair('product_name_tr', 'Fındık kreması'));
      expect(fields, containsPair('add_brands', 'Kardelen'));
      expect(fields, containsPair('ingredients_text_tr', 'Şeker, FINDIK (%13)'));
      expect(fields, containsPair('lang', 'tr'));
      expect(fields, containsPair('nutrition_data_per', '100g'));
      expect(fields, containsPair('nutriment_fat', '30.9'));
      expect(fields, containsPair('nutriment_fat_unit', 'g'));
      expect(fields, containsPair('nutriment_sugars', '56.3'));
      expect(fields.containsKey('nutriment_salt'), isFalse);

      expect(find.textContaining("Sent to Open Food Facts' test server on"), findsOneWidget);
      expect(find.text('Something wrong or missing?'), findsOneWidget);
    });

    testWidgets('only what the user changes is sent: a corrected brand, and nutrition as the whole table',
        (tester) async {
      tall(tester);
      final product = {
        'code': _code,
        'lang': 'en',
        'product_name': 'Hazelnut spread',
        'brands': 'Ferrero',
        'quantity': '400 g',
        'ingredients_text_en': 'Sugar, palm oil, hazelnuts',
        'nutrition_data_per': '100g',
        'nutriments': {'fat_100g': 30.9, 'sugars_100g': 56.3},
      };
      final server = _Server(product: product);
      await tester.pumpWidget(MaterialApp(
        theme: morselTheme(Brightness.light),
        home: ContributeScreen(
          code: _code,
          product: product,
          queue: queue(server),
          labels: LabelStore(prefs, Directory('${dir.path}/labels')),
          vision: _FakeVision(dir),
        ),
      ));
      expect(find.text('Change something above to send it.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send to Open Food Facts')).onPressed,
          isNull);

      await tester.enterText(find.widgetWithText(TextFormField, 'Ferrero'), 'Ferrero, Nutella');
      await tester.enterText(find.widgetWithText(TextFormField, '30.9'), '31');
      await tester.pump();
      expect(find.text('Sends the brand and the nutrition facts.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Send to Open Food Facts'));
      await settle(tester);

      expect(server.at('/api/v3/product/$_code/images'), isEmpty);
      final fields = server.at('/cgi/product_jqm2.pl').single.bodyFields;
      expect(
        fields.keys.where((k) => !const ['code', 'user_id', 'password', 'app_name', 'app_version', 'app_uuid', 'comment'].contains(k)),
        unorderedEquals(['brands', 'nutrition_data_per', 'nutriment_fat', 'nutriment_fat_unit', 'nutriment_sugars', 'nutriment_sugars_unit']),
      );
      expect(fields['brands'], 'Ferrero, Nutella');
      expect(fields['nutriment_fat'], '31');
      expect(fields['nutriment_sugars'], '56.3');
    });

    testWidgets('without an account to send with, it asks the user to sign in first', (tester) async {
      tall(tester);
      final server = _Server()..write = (_) => http.Response('<html>Signed in</html>', 200);
      await tester.pumpWidget(MaterialApp(
        theme: morselTheme(Brightness.light),
        home: ContributeScreen(
          code: _code,
          product: null,
          queue: queue(server, shared: false),
          labels: LabelStore(prefs, Directory('${dir.path}/labels')),
          vision: _FakeVision(dir),
        ),
      ));
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in to send'));
      await tester.pumpAndSettle();
      expect(find.text('Open Food Facts account'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Username'), 'alice');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'secret-pw');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Send to Open Food Facts'), findsOneWidget);
      expect(find.text('Sent as alice.'), findsOneWidget);
    });
  });
}
