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

class OffException implements Exception {
  OffException(this.message);
  final String message;
  @override
  String toString() => message;
}

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

  static const _userAgent = 'Morsel/0.1.0';
  static const _fields = [
    'code',
    'product_name',
    'product_name_$appLanguage',
    'brands',
    'quantity',
    'image_front_url',
    'image_front_small_url',
    'categories_tags',
    'nutriscore_grade',
    'nova_group',
    'ecoscore_grade',
    'nutrient_levels',
    'nutriments',
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
}
