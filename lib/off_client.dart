import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Result of looking a barcode up on Open Food Facts.
class ProductLookup {
  ProductLookup({required this.code, required this.product});

  final String code;

  /// `null` when Open Food Facts has no product for [code].
  final Map<String, dynamic>? product;
}

/// Open Food Facts couldn't be reached or couldn't answer: worth trying again later.
class OffException implements Exception {
  OffException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Open Food Facts answered no. Sending the same again won't help, so it isn't retried.
class OffRefused extends OffException {
  OffRefused(super.message);
}

/// Who a contribution is sent as: the user's own Open Food Facts account, or
/// Morsel's shared one.
class OffCredentials {
  const OffCredentials(this.user, this.password, {this.appUuid});

  /// The username, never the email: Open Food Facts asks for it.
  final String user;
  final String password;

  /// A random id per install, sent with the shared account only, so Open Food
  /// Facts' moderators can block one person without blocking Morsel.
  final String? appUuid;
}

/// Where contributions go: Open Food Facts' staging server until the flow is
/// proven on a phone (docs/ARCHITECTURE.md). Staging has its own accounts and
/// asks every request for basic auth `off:off`. Production: world.openfoodfacts.org.
const offWriteHost = 'world.openfoodfacts.net';

/// The app's UI is English-only for now; product text and knowledge panels are
/// requested in the same language so a screen never mixes two. Follow the UI
/// language here once the app is translated.
const appLanguage = 'en';

/// The product's name in [appLanguage] when it has one, else its main name.
String? productName(Map<String, dynamic> product) {
  final localized = product['product_name_$appLanguage'] as String?;
  if (localized != null && localized.isNotEmpty) return localized;
  final name = product['product_name'] as String?;
  return name == null || name.isEmpty ? null : name;
}

class OffClient {
  OffClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _version = '0.1.0';
  static const _userAgent = 'Morsel/$_version';
  static const _fields = [
    'code',
    'lang',
    'product_name',
    'product_name_$appLanguage',
    'brands',
    'quantity',
    'image_front_url',
    'image_front_small_url',
    'image_ingredients_url',
    'image_nutrition_url',
    'ingredients_text',
    'ingredients_text_$appLanguage',
    'categories_tags',
    'nutriscore_grade',
    'nova_group',
    'ecoscore_grade',
    'nutrient_levels',
    'nutriments',
    'nutrition_data_per',
    'allergens_tags',
    'traces_tags',
    'additives_tags',
    'ingredients_analysis_tags',
    'last_modified_t',
    'knowledge_panels',
  ];

  /// [country] is an ISO 3166 code; Open Food Facts uses it for country-specific
  /// links and category comparisons.
  Future<ProductLookup> lookup(String code, {String? country}) async {
    final uri = Uri.https(
      'world.openfoodfacts.org',
      '/api/v2/product/$code',
      {
        'fields': _fields.join(','),
        'lc': appLanguage,
        if (country != null) 'cc': country.toLowerCase(),
      },
    );
    // Browsers refuse to set User-Agent, so only native builds send it.
    final res = await _client.get(
      uri,
      headers: kIsWeb ? null : {'User-Agent': _userAgent},
    );
    // A missing product is HTTP 404 and an invalid code is HTTP 200; both carry status 0.
    if (res.statusCode != 200 && res.statusCode != 404) {
      throw OffException('Open Food Facts returned HTTP ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final found = body['status'] == 1;
    return ProductLookup(
      code: code,
      product: found ? body['product'] as Map<String, dynamic> : null,
    );
  }

  // --- Writes: docs/ARCHITECTURE.md, "Sending to Open Food Facts" ---------

  Map<String, String> get _writeHeaders => {
        if (!kIsWeb) 'User-Agent': _userAgent,
        if (offWriteHost == 'world.openfoodfacts.net') 'Authorization': 'Basic ${base64Encode(utf8.encode('off:off'))}',
      };

  /// Who sent it, as Open Food Facts asks apps to say on every write.
  static Map<String, String> _sender(OffCredentials as) => {
        'user_id': as.user,
        'password': as.password,
        'app_name': 'Morsel',
        'app_version': _version,
        'app_uuid': ?as.appUuid,
      };

  /// Checks a username and password. Throws [OffRefused] when they're wrong.
  Future<void> signIn(String user, String password) async {
    final res = await _client.post(Uri.https(offWriteHost, '/cgi/session.pl'),
        headers: _writeHeaders, body: {'user_id': user, 'password': password});
    _checkWrite(res);
  }

  /// Uploads a photo of product [code] and selects it as the product's photo
  /// for each field in [selected] ('front', 'ingredients', 'nutrition'), in that
  /// field's language: an upload alone isn't shown where a photo is already
  /// selected. Creates the product when Open Food Facts doesn't have it. The old
  /// photo stays in the product's history.
  Future<void> uploadPhoto(String code, List<int> jpeg,
      {required Map<String, String> selected, required OffCredentials as}) async {
    final res = await _client.post(
      Uri.https(offWriteHost, '/api/v3/product/$code/images'),
      headers: {..._writeHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({
        ..._sender(as),
        'image_data_base64': base64Encode(jpeg),
        'selected': {
          for (final MapEntry(key: field, value: language) in selected.entries) field: {language: <String, Object>{}},
        },
      }),
    );
    _checkWrite(res);
  }

  /// Sets [fields] on product [code], creating it if needed, through the product
  /// edit form: the one write API that takes nutrition facts, while v3's are reworked.
  Future<void> editProduct(String code, Map<String, String> fields,
      {required OffCredentials as, String? comment}) async {
    final res = await _client.post(
      Uri.https(offWriteHost, '/cgi/product_jqm2.pl'),
      headers: _writeHeaders,
      body: {'code': code, ..._sender(as), 'comment': ?comment, ...fields},
    );
    _checkWrite(res);
  }

  /// Throws [OffException] when Open Food Facts couldn't answer (429, 5xx), and
  /// [OffRefused] when it answered no: an HTTP error, or HTTP 200 whose body says
  /// "failure" (v3) or status 0 (v2).
  static void _checkWrite(http.Response res) {
    if (res.statusCode == 429 || res.statusCode >= 500) {
      throw OffException('Open Food Facts returned HTTP ${res.statusCode}');
    }
    Map<String, dynamic>? body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } on FormatException {
      // The v2 endpoints answer errors with an HTML page.
    }
    final errors = (body?['errors'] as List?)?.cast<Map<String, dynamic>>();
    final reason = (errors?.firstOrNull?['message'] as Map?)?['name'] as String? ?? body?['status_verbose'] as String?;
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw OffRefused(reason ?? 'Wrong username or password');
    }
    if (res.statusCode >= 400 || body?['status'] == 'failure' || body?['status'] == 0) {
      throw OffRefused(reason ?? 'Open Food Facts returned HTTP ${res.statusCode}');
    }
  }
}
