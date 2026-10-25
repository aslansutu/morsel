import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'off_client.dart';
import 'vision.dart';

/// The user's own Open Food Facts account, which what they send is credited to.
/// Sending without one, through a Morsel account, is pending (docs/ROADMAP.md).
class OffAccount extends ChangeNotifier {
  OffAccount(this._prefs, {this._secrets = const Secrets()});

  final SharedPreferences _prefs;
  final Secrets _secrets;

  static const _password = 'offPassword';

  /// The username the user signed in with; null when they haven't.
  String? get user => _prefs.getString('offUser');

  bool get canSend => user != null;

  /// Checks the account with Open Food Facts, then keeps it: the password in
  /// [Secrets], never in preferences. Throws what [OffClient.signIn] throws.
  Future<void> signIn(OffClient client, String user, String password) async {
    await client.signIn(user, password);
    await _secrets.write(_password, password);
    await _prefs.setString('offUser', user);
    notifyListeners();
  }

  /// Creates an Open Food Facts account and signs in with it; the sign-in is
  /// what confirms the account exists. The email goes to Open Food Facts only.
  Future<void> signUp(OffClient client,
      {required String user,
      required String name,
      required String email,
      required String password,
      required bool newsletter}) async {
    await client.signUp(user: user, name: name, email: email, password: password, newsletter: newsletter);
    try {
      await signIn(client, user, password);
    } on OffRefused {
      throw OffRefused("Open Food Facts didn't sign the new account in. If it emailed you, follow its "
          'link, then sign in.');
    }
  }

  Future<void> signOut() async {
    await _secrets.delete(_password);
    await _prefs.remove('offUser');
    notifyListeners();
  }

  /// What to send with now; null when the user isn't signed in.
  Future<OffCredentials?> credentials() async {
    final user = this.user;
    if (user == null) return null;
    if (await _secrets.read(_password) case final password?) return OffCredentials(user, password);
    // A backup restored without the key that decrypts the password.
    await signOut();
    return null;
  }
}
