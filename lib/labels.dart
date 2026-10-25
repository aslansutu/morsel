import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nutrition facts and the ingredient list the user read off a label and
/// checked, for a product Open Food Facts doesn't know or lacks them for.
class LabelEntry {
  LabelEntry({
    required this.code,
    required this.values,
    required this.perMl,
    required this.savedAt,
    this.name,
    this.ingredients,
    this.ingredientsLanguage,
    this.labelFile,
    this.photoFile,
    this.ingredientsFile,
  });

  factory LabelEntry.fromJson(Map<String, dynamic> json) => LabelEntry(
        code: json['code'] as String,
        values: {
          for (final e in (json['values'] as Map<String, dynamic>).entries) e.key: (e.value as num).toDouble(),
        },
        perMl: json['perMl'] as bool,
        savedAt: DateTime.parse(json['savedAt'] as String),
        name: json['name'] as String?,
        ingredients: json['ingredients'] as String?,
        ingredientsLanguage: json['ingredientsLanguage'] as String?,
        labelFile: json['labelFile'] as String?,
        photoFile: json['photoFile'] as String?,
        ingredientsFile: json['ingredientsFile'] as String?,
      );

  final String code;

  /// Only for a product Open Food Facts doesn't know.
  final String? name;

  /// Per 100 g, or per 100 ml when [perMl], by `labelNutrients` id. Empty when
  /// only the ingredients were read.
  final Map<String, double> values;
  final bool perMl;
  final DateTime savedAt;

  /// The ingredient list as the user checked it.
  final String? ingredients;

  /// The language of [ingredients], from its heading; null when typed.
  final String? ingredientsLanguage;

  /// Photo file names inside the store's folder. [ingredientsFile] only when
  /// the list was read from a photo of its own.
  final String? labelFile;
  final String? photoFile;
  final String? ingredientsFile;

  Map<String, dynamic> toJson() => {
        'code': code,
        'values': values,
        'perMl': perMl,
        'savedAt': savedAt.toIso8601String(),
        'name': name,
        'ingredients': ingredients,
        'ingredientsLanguage': ingredientsLanguage,
        'labelFile': labelFile,
        'photoFile': photoFile,
        'ingredientsFile': ingredientsFile,
      };
}

/// Labels the user has read, kept only on this device: the facts in
/// preferences, the photos in [_dir].
class LabelStore extends ChangeNotifier {
  LabelStore(this._prefs, this._dir) {
    final saved = _prefs.getString('labels');
    if (saved != null) {
      for (final e in (jsonDecode(saved) as List).cast<Map<String, dynamic>>()) {
        final entry = LabelEntry.fromJson(e);
        _entries[entry.code] = entry;
      }
    }
  }

  final SharedPreferences _prefs;
  final Directory _dir;
  final _entries = <String, LabelEntry>{};

  LabelEntry? operator [](String code) => _entries[code];

  File? labelPhoto(String code) => _file(_entries[code]?.labelFile);
  File? productPhoto(String code) => _file(_entries[code]?.photoFile);
  File? ingredientsPhoto(String code) => _file(_entries[code]?.ingredientsFile);

  File? _file(String? name) => name == null ? null : File('${_dir.path}/$name');

  /// Saves [entry] with copies of the image files [labelImage], [productImage]
  /// and [ingredientsImage]; a path the store already holds is kept as it is.
  Future<LabelEntry> save(LabelEntry entry,
      {required String labelImage, String? productImage, String? ingredientsImage}) async {
    await _dir.create(recursive: true);
    final old = _entries[entry.code];
    final stamp = DateTime.now().millisecondsSinceEpoch;
    Future<String?> keep(String? path, String? oldName, String kind) async {
      if (path == null) return null;
      if (oldName != null && path == _file(oldName)!.path) return oldName;
      // A new name each time, so the image cache never shows the old photo.
      final name = '${entry.code}-$kind-$stamp.jpg';
      await File(path).copy('${_dir.path}/$name');
      return name;
    }

    final saved = LabelEntry(
      code: entry.code,
      values: entry.values,
      perMl: entry.perMl,
      savedAt: entry.savedAt,
      name: entry.name,
      ingredients: entry.ingredients,
      ingredientsLanguage: entry.ingredientsLanguage,
      labelFile: await keep(labelImage, old?.labelFile, 'label'),
      photoFile: await keep(productImage, old?.photoFile, 'photo'),
      ingredientsFile: await keep(ingredientsImage, old?.ingredientsFile, 'ingredients'),
    );
    final kept = {saved.labelFile, saved.photoFile, saved.ingredientsFile};
    for (final name in [old?.labelFile, old?.photoFile, old?.ingredientsFile]) {
      if (name != null && !kept.contains(name)) {
        try {
          await _file(name)!.delete();
        } on FileSystemException {
          // Already gone.
        }
      }
    }
    _entries[entry.code] = saved;
    await _prefs.setString('labels', jsonEncode(_entries.values.map((e) => e.toJson()).toList()));
    notifyListeners();
    return saved;
  }
}
