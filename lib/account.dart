import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'off_client.dart';
import 'vision.dart';

/// Who Morsel sends contributions to Open Food Facts as: the user's own account
/// once they sign in, so what they send is credited to them, or else Morsel's
/// shared account, which a build gets from `--dart-define-from-file` (README.md).
class OffAccount extends ChangeNotifier {
  OffAccount(this._prefs, {this.shared, this._secrets = const Secrets()});

  final SharedPreferences _prefs;
  final Secrets _secrets;

  /// Morsel's own account; null when this build has none, and then nothing is
  /// sent until the user signs in.
  final ({String user, String password})? shared;

  static const _password = 'offPassword';

  /// The username the user signed in with; null when they haven't.
  String? get user => _prefs.getString('offUser');

  bool get canSend => user != null || shared != null;

  /// Checks the account with Open Food Facts, then keeps it: the password in
  /// [Secrets], never in preferences. Throws what [OffClient.signIn] throws.
  Future<void> signIn(OffClient client, String user, String password) async {
    await client.signIn(user, password);
    await _secrets.write(_password, password);
    await _prefs.setString('offUser', user);
    notifyListeners();
  }

  Future<void> signOut() async {
    await _secrets.delete(_password);
    await _prefs.remove('offUser');
    notifyListeners();
  }

  /// What to send with now; null when there's nothing to send with.
  Future<OffCredentials?> credentials() async {
    if (user case final user?) {
      if (await _secrets.read(_password) case final password?) return OffCredentials(user, password);
      // A backup restored without the key that decrypts the password.
      await signOut();
    }
    if (shared case final shared?) return OffCredentials(shared.user, shared.password, appUuid: appUuid);
    return null;
  }

  /// A random id for this install, made once; it says nothing about the user.
  String get appUuid {
    if (_prefs.getString('offAppUuid') case final saved?) return saved;
    final random = Random.secure();
    final id = [for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
    _prefs.setString('offAppUuid', id);
    return id;
  }
}
