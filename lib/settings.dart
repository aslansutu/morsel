import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'off_client.dart';

class Settings extends ChangeNotifier {
  Settings(this._prefs);

  final SharedPreferences _prefs;

  /// The country the user picked, or null to follow the device region.
  String? get country => _prefs.getString('country');
  set country(String? code) {
    code == null ? _prefs.remove('country') : _prefs.setString('country', code);
    notifyListeners();
  }

  /// The country used for lookups.
  String? get effectiveCountry => country ?? deviceCountry;

  static String? get deviceCountry => PlatformDispatcher.instance.locale.countryCode;

  bool get rememberScans => _prefs.getBool('rememberScans') ?? true;
  set rememberScans(bool value) {
    _prefs.setBool('rememberScans', value);
    notifyListeners();
  }
}

class ScanRecord {
  ScanRecord({
    required this.code,
    required this.scannedAt,
    this.name,
    this.brand,
    this.imageUrl,
    this.nutriScore,
  });

  factory ScanRecord.fromLookup(ProductLookup lookup) {
    final p = lookup.product;
    return ScanRecord(
      code: lookup.code,
      scannedAt: DateTime.now(),
      name: p == null ? null : productName(p),
      brand: p?['brands'] as String?,
      imageUrl: p?['image_front_small_url'] as String?,
      nutriScore: p?['nutriscore_grade'] as String?,
    );
  }

  factory ScanRecord.fromJson(Map<String, dynamic> json) => ScanRecord(
        code: json['code'] as String,
        scannedAt: DateTime.parse(json['scannedAt'] as String),
        name: json['name'] as String?,
        brand: json['brand'] as String?,
        imageUrl: json['imageUrl'] as String?,
        nutriScore: json['nutriScore'] as String?,
      );

  final String code;
  final DateTime scannedAt;

  /// Null when Open Food Facts didn't know the barcode.
  final String? name;
  final String? brand;
  final String? imageUrl;
  final String? nutriScore;

  Map<String, dynamic> toJson() => {
        'code': code,
        'scannedAt': scannedAt.toIso8601String(),
        'name': name,
        'brand': brand,
        'imageUrl': imageUrl,
        'nutriScore': nutriScore,
      };
}

/// Past scans, newest first, kept only on this device.
class History extends ChangeNotifier {
  History(this._prefs) {
    final saved = _prefs.getString('history');
    if (saved != null) {
      _items.addAll((jsonDecode(saved) as List)
          .map((e) => ScanRecord.fromJson(e as Map<String, dynamic>)));
    }
  }

  static const limit = 200;

  final SharedPreferences _prefs;
  final _items = <ScanRecord>[];

  List<ScanRecord> get items => List.unmodifiable(_items);

  /// Adds a scan; scanning the same barcode again moves it to the top.
  void record(ScanRecord record) {
    _items
      ..removeWhere((r) => r.code == record.code)
      ..insert(0, record);
    if (_items.length > limit) _items.removeRange(limit, _items.length);
    _save();
  }

  void removeAt(int index) {
    _items.removeAt(index);
    _save();
  }

  void insertAt(int index, ScanRecord record) {
    _items.insert(index, record);
    _save();
  }

  /// Removes everything and returns it, so the caller can offer undo.
  List<ScanRecord> clear() {
    final removed = List.of(_items);
    _items.clear();
    _save();
    return removed;
  }

  void restore(List<ScanRecord> records) {
    _items
      ..clear()
      ..addAll(records);
    _save();
  }

  void _save() {
    _prefs.setString('history', jsonEncode(_items.map((r) => r.toJson()).toList()));
    notifyListeners();
  }
}
