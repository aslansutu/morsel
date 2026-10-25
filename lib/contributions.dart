import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';
import 'off_client.dart';
import 'vision.dart';

/// A photo to send, and which of the product's photos it becomes.
class ContributionPhoto {
  ContributionPhoto({required this.file, required this.selected, this.sent = false});

  factory ContributionPhoto.fromJson(Map<String, dynamic> json) => ContributionPhoto(
        file: json['file'] as String,
        selected: (json['selected'] as Map<String, dynamic>).cast<String, String>(),
        sent: json['sent'] as bool,
      );

  /// The file name inside the queue's folder.
  final String file;

  /// Language by field: 'front', 'ingredients', 'nutrition'.
  final Map<String, String> selected;
  bool sent;

  Map<String, dynamic> toJson() => {'file': file, 'selected': selected, 'sent': sent};
}

enum ContributionState { waiting, sent, refused }

/// What the user chose to send Open Food Facts about one product: photos first,
/// then fields of the product edit form.
class Contribution {
  Contribution({
    required this.code,
    required this.photos,
    required this.fields,
    required this.summary,
    this.comment,
    this.fieldsSent = false,
    this.state = ContributionState.waiting,
    this.error,
    this.attempts = 0,
    this.sentAt,
  });

  factory Contribution.fromJson(Map<String, dynamic> json) => Contribution(
        code: json['code'] as String,
        photos: [
          for (final p in (json['photos'] as List).cast<Map<String, dynamic>>()) ContributionPhoto.fromJson(p),
        ],
        fields: (json['fields'] as Map<String, dynamic>).cast<String, String>(),
        summary: json['summary'] as String,
        comment: json['comment'] as String?,
        fieldsSent: json['fieldsSent'] as bool,
        state: ContributionState.values.byName(json['state'] as String),
        error: json['error'] as String?,
        attempts: json['attempts'] as int,
        sentAt: switch (json['sentAt']) { final String s => DateTime.parse(s), _ => null },
      );

  final String code;
  final List<ContributionPhoto> photos;
  final Map<String, String> fields;

  /// What it sends, in words: "2 photos and the nutrition facts".
  final String summary;
  final String? comment;
  bool fieldsSent;
  ContributionState state;

  /// Why it was refused, or why it's still waiting.
  String? error;
  int attempts;
  DateTime? sentAt;

  Map<String, dynamic> toJson() => {
        'code': code,
        'photos': [for (final p in photos) p.toJson()],
        'fields': fields,
        'summary': summary,
        'comment': comment,
        'fieldsSent': fieldsSent,
        'state': state.name,
        'error': error,
        'attempts': attempts,
        'sentAt': sentAt?.toIso8601String(),
      };
}

/// Contributions kept on the phone until Open Food Facts confirms them, as it
/// asks apps to. Network errors, 429 and 5xx are tried again with backoff; any
/// other answer is shown to the user, not retried.
class ContributionQueue extends ChangeNotifier {
  ContributionQueue(this._prefs, this._dir,
      {required this.client, required this.account, this.vision = const Vision()}) {
    final saved = _prefs.getString('contributions');
    if (saved != null) {
      _items.addAll([for (final c in (jsonDecode(saved) as List).cast<Map<String, dynamic>>()) Contribution.fromJson(c)]);
    }
    // Signing in may be what a waiting contribution needs.
    account.addListener(send);
  }

  final SharedPreferences _prefs;

  /// Where photos wait until they're sent.
  final Directory _dir;
  final OffClient client;
  final OffAccount account;
  final Vision vision;
  final _items = <Contribution>[];
  Timer? _retry;

  /// The round of sending under way.
  Future<void>? _sending;

  /// Automatic tries before it waits for the user's *Try again*.
  static const maxAttempts = 8;

  /// The last contribution for [code].
  Contribution? latest(String code) => _items.where((c) => c.code == code).lastOrNull;

  /// Queues [fields] and [photos] for product [code], then sends. Photos are
  /// copied without their metadata, so the originals can change or go.
  Future<void> add(String code,
      {required Map<String, String> fields,
      required List<({String path, Map<String, String> selected})> photos,
      required String summary,
      String? comment}) async {
    await _dir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final kept = <ContributionPhoto>[];
    for (final (i, photo) in photos.indexed) {
      final name = '$code-$stamp-$i.jpg';
      await File(await vision.forUpload(photo.path)).copy('${_dir.path}/$name');
      kept.add(ContributionPhoto(file: name, selected: photo.selected));
    }
    _items.add(Contribution(code: code, photos: kept, fields: fields, summary: summary, comment: comment));
    _save();
    unawaited(send());
  }

  /// Sends again after a refusal, or after the automatic tries ran out.
  Future<void> retry(Contribution contribution) {
    contribution
      ..state = ContributionState.waiting
      ..attempts = 0;
    _save();
    return send();
  }

  /// Sends what's waiting, oldest first, stopping at the first that can't go
  /// now. During a round, returns that round, which also sends what's added meanwhile.
  Future<void> send() async {
    if (_sending case final round?) return round;
    final round = Completer<void>();
    _sending = round.future;
    _retry?.cancel();
    try {
      Contribution? next() =>
          _items.where((c) => c.state == ContributionState.waiting && c.attempts < maxAttempts).firstOrNull;
      for (var c = next(); c != null; c = next()) {
        if (!await _sendOne(c)) break;
      }
    } finally {
      _sending = null;
      round.complete();
    }
  }

  /// False when it has to wait: Open Food Facts can't be reached, or there's no account.
  Future<bool> _sendOne(Contribution c) async {
    final as = await account.credentials();
    if (as == null) {
      c.error = 'Sign in to Open Food Facts to send this.';
      _save();
      return false;
    }
    try {
      for (final photo in c.photos.where((p) => !p.sent)) {
        await client.uploadPhoto(c.code, await File('${_dir.path}/${photo.file}').readAsBytes(),
            selected: photo.selected, as: as);
        photo.sent = true;
        _save();
      }
      if (c.fields.isNotEmpty && !c.fieldsSent) {
        await client.editProduct(c.code, c.fields, as: as, comment: c.comment);
        c.fieldsSent = true;
      }
      c
        ..state = ContributionState.sent
        ..sentAt = DateTime.now()
        ..error = null;
      _forget(c);
      return true;
    } on OffRefused catch (e) {
      c
        ..state = ContributionState.refused
        ..error = e.message;
      _save();
      return true;
    } on FileSystemException {
      c
        ..state = ContributionState.refused
        ..error = 'A photo is missing from the phone.';
      _save();
      return true;
    } on Object catch (e) {
      if (e is! OffException && e is! http.ClientException && e is! SocketException && e is! TimeoutException) {
        rethrow;
      }
      c
        ..attempts += 1
        ..error = "Couldn't reach Open Food Facts.";
      _save();
      if (c.attempts < maxAttempts) {
        // 30 s, 1 min, 2 min… up to 30 min, give or take half, so phones don't retry in step.
        final seconds = min(30 * pow(2, c.attempts - 1), 1800) * (0.5 + Random().nextDouble());
        _retry = Timer(Duration(seconds: seconds.round()), send);
      }
      return false;
    }
  }

  /// Once [sent], its photos go, and so does the record of an earlier one for the product.
  void _forget(Contribution sent) {
    for (final photo in sent.photos) {
      try {
        File('${_dir.path}/${photo.file}').deleteSync();
      } on FileSystemException {
        // Already gone.
      }
    }
    _items.removeWhere((c) => c != sent && c.code == sent.code && c.state == ContributionState.sent);
    _save();
  }

  void _save() {
    _prefs.setString('contributions', jsonEncode([for (final c in _items) c.toJson()]));
    notifyListeners();
  }

  @override
  void dispose() {
    _retry?.cancel();
    account.removeListener(send);
    super.dispose();
  }
}
