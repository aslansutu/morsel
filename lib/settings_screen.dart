import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'account.dart';
import 'contributions.dart';
import 'countries.dart';
import 'format.dart';
import 'off_client.dart';
import 'settings.dart';
import 'theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings, required this.history, this.contributions});

  final Settings settings;
  final History history;

  /// Null where Morsel doesn't send to Open Food Facts (the web).
  final ContributionQueue? contributions;

  String get _countryLabel {
    final chosen = settings.country;
    if (chosen != null) return '${flagOf(chosen)}  ${countryName(chosen)}';
    final device = Settings.deviceCountry;
    return device == null ? 'Automatic' : 'Automatic · ${flagOf(device)}  ${countryName(device)}';
  }

  Future<void> _pickCountry(BuildContext context) async {
    final picked = await Navigator.of(context).push<({String? code})>(MaterialPageRoute(
      builder: (_) => CountryPicker(selected: settings.country),
    ));
    if (picked != null) settings.country = picked.code;
  }

  void _setRemember(BuildContext context, bool on) {
    if (on) {
      settings.rememberScans = true;
      return;
    }
    // Off means forgotten: clear now, but let the user take it back.
    settings.rememberScans = false;
    final removed = history.clear();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(removed.isEmpty
            ? 'Scan history off'
            : 'Scan history off · ${removed.length} scan${removed.length == 1 ? '' : 's'} deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            settings.rememberScans = true;
            history.restore(removed);
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = MorselColors.of(context).inkMuted;
    final account = contributions?.account;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, ?account]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(
          children: [
            const _GroupHeader('Region'),
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('Country'),
              subtitle: Text(_countryLabel),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickCountry(context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
              child: Text('Open Food Facts uses it for country-specific links and comparisons.',
                  style: text.bodySmall?.copyWith(color: muted)),
            ),
            const _GroupHeader('Privacy'),
            SwitchListTile(
              secondary: const Icon(Icons.history),
              title: const Text('Remember scans'),
              subtitle: const Text('Keeps your scan history on this device only. Turning it off deletes it.'),
              value: settings.rememberScans,
              onChanged: (on) => _setRemember(context, on),
            ),
            if ((contributions, account) case (final contributions?, final account?)) ...[
              const _GroupHeader('Open Food Facts'),
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text('Account'),
                subtitle: Text(switch (account.user) {
                  final user? => 'Signed in as $user',
                  null => 'Not signed in: needed to send to Open Food Facts',
                }),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AccountScreen(account: account, client: contributions.client))),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
              child: Text(
                'Product data from Open Food Facts, available under the Open Database License.',
                style: text.bodySmall?.copyWith(color: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Signing in to Open Food Facts, so what the user sends is credited to them.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.account, required this.client});

  final OffAccount account;
  final OffClient client;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  var _checking = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final user = _user.text.trim();
    if (user.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final error = await _attempt(() => widget.account.signIn(widget.client, user, _password.text));
    if (!mounted) return;
    setState(() {
      _checking = false;
      _error = error;
    });
    if (error == null) Navigator.of(context).pop();
  }

  Future<void> _signUp() async {
    final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => SignUpScreen(account: widget.account, client: widget.client)));
    // Signed in with the new account: back to whatever needed it.
    if (created == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = MorselColors.of(context).inkMuted;
    final account = widget.account;
    return Scaffold(
      appBar: AppBar(title: const Text('Open Food Facts account')),
      body: ListenableBuilder(
        listenable: account,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (account.user case final user?) ...[
              Text('Signed in as $user', style: text.titleMedium),
              const SizedBox(height: 4),
              Text('What you send to Open Food Facts is credited to this account.', style: text.bodyMedium),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(onPressed: account.signOut, child: const Text('Sign out')),
              ),
              const SizedBox(height: 8),
              Text('After signing out, sign in again to send anything.',
                  style: text.bodySmall?.copyWith(color: muted)),
            ] else ...[
              Text(
                'Sign in to send photos and corrections to Open Food Facts. What you send is credited '
                'to your account.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 16),
              AutofillGroup(
                child: Column(
                  children: [
                    TextField(
                      controller: _user,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                          labelText: 'Username', helperText: 'Not your email', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _signIn(),
                      decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Text(error, style: text.bodyMedium),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _checking ? null : _signIn,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: Text(_checking ? 'Checking…' : 'Sign in'),
              ),
              const SizedBox(height: 24),
              Text('New to Open Food Facts?', style: text.titleSmall),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _checking ? null : _signUp,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('Create an account'),
              ),
              const SizedBox(height: 16),
              Text(_passwordNote, style: text.bodySmall?.copyWith(color: muted)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Where the password goes, said on both screens that take one.
final _passwordNote = 'Your password stays on this phone, in its secure storage, and goes only to '
    'Open Food Facts.${offWriteHost == 'world.openfoodfacts.net' ? " While Morsel is tested, it uses Open Food "
        "Facts' test server, which has accounts of its own." : ''}';

/// Runs [action] and returns what to tell the user when it fails; null when it worked.
Future<String?> _attempt(Future<void> Function() action) async {
  try {
    await action();
    return null;
  } on OffRefused catch (e) {
    return e.message;
  } on Exception {
    return "Couldn't reach Open Food Facts. Check your connection and try again.";
  }
}

/// Creating an Open Food Facts account without leaving Morsel, as Open Food
/// Facts' own app does. Pops with true once signed in with it.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, required this.account, required this.client});

  final OffAccount account;
  final OffClient client;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _newsletter = false;
  var _agreed = false;
  var _creating = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_user, _name, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    final error = await _attempt(() => widget.account.signUp(widget.client,
        user: _user.text.trim(),
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        newsletter: _newsletter));
    if (!mounted) return;
    setState(() {
      _creating = false;
      _error = error;
    });
    if (error == null) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = MorselColors.of(context).inkMuted;
    // The size of a checkbox row's title, so the terms link lines up with its sentence.
    final link = text.bodyLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline);
    void open(String path) => launchUrl(Uri.https(offWriteHost, path), mode: LaunchMode.externalApplication);
    return Scaffold(
      appBar: AppBar(title: const Text('Create an account')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('A free Open Food Facts account. What you send is published under your username.',
                style: text.bodyMedium),
            const SizedBox(height: 16),
            AutofillGroup(
              child: Column(
                children: [
                  TextFormField(
                    controller: _user,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.newUsername],
                    decoration: const InputDecoration(
                        labelText: 'Username',
                        helperText: 'Public. Lowercase letters, digits and dashes.',
                        border: OutlineInputBorder()),
                    // Open Food Facts' own rules for a username.
                    validator: (t) => switch (t?.trim() ?? '') {
                      '' => 'Choose a username',
                      final u when !RegExp(r'^[a-z0-9-]+$').hasMatch(u) =>
                        'Only lowercase letters, digits and dashes',
                      final u when u.length > 40 => 'At most 40 characters',
                      _ => null,
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                    validator: (t) => switch (t?.trim().length ?? 0) {
                      < 2 => 'At least 2 characters',
                      > 60 => 'At most 60 characters',
                      _ => null,
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    autocorrect: false,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                        labelText: 'Email',
                        helperText: "Goes only to Open Food Facts. Morsel doesn't keep it.",
                        border: OutlineInputBorder()),
                    validator: (t) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t?.trim() ?? '')
                        ? null
                        : 'Enter an email address',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                        labelText: 'Password', helperText: 'At least 6 characters', border: OutlineInputBorder()),
                    validator: (t) => (t?.length ?? 0) < 6 ? 'At least 6 characters' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _newsletter,
              onChanged: (v) => setState(() => _newsletter = v!),
              title: const Text("Send me Open Food Facts' newsletter"),
            ),
            FormField<bool>(
              validator: (_) => _agreed ? null : 'Agree to the terms to create an account',
              builder: (field) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _agreed,
                    onChanged: (v) {
                      setState(() => _agreed = v!);
                      field.didChange(v);
                    },
                    title: Wrap(
                      children: [
                        const Text("I agree to Open Food Facts' "),
                        InkWell(onTap: () => open('/terms-of-use'), child: Text('terms of use', style: link)),
                      ],
                    ),
                  ),
                  if (field.errorText case final error?)
                    Text(error, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
                ],
              ),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Text(error, style: text.bodyMedium),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _creating ? null : _create,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: Text(_creating ? 'Creating…' : 'Create account'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => open('/cgi/user.pl'),
              child: const Text('Or create it on the Open Food Facts website'),
            ),
            const SizedBox(height: 8),
            Text(_passwordNote, style: text.bodySmall?.copyWith(color: muted)),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }
}

/// Pops with `(code: null)` for automatic, `(code: 'TR')` for a country, or
/// nothing when dismissed.
class CountryPicker extends StatefulWidget {
  const CountryPicker({super.key, required this.selected});

  final String? selected;

  @override
  State<CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<CountryPicker> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final q = fold(_query.trim());
    final matches = countryNames.entries
        .where((e) => q.isEmpty || fold(e.value).contains(q) || e.key.toLowerCase() == q)
        .toList();
    final device = Settings.deviceCountry;
    final check = Icon(Icons.check, color: Theme.of(context).colorScheme.primary);
    return Scaffold(
      appBar: AppBar(title: const Text('Country')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              hintText: 'Search countries',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (q.isEmpty)
                  ListTile(
                    leading: const Icon(Icons.my_location),
                    title: const Text('Automatic'),
                    subtitle: Text(device == null
                        ? 'Follows this device'
                        : 'Follows this device: ${countryName(device)}'),
                    trailing: widget.selected == null ? check : null,
                    onTap: () => Navigator.of(context).pop((code: null)),
                  ),
                for (final MapEntry(key: code, value: name) in matches)
                  ListTile(
                    leading: Text(flagOf(code), style: const TextStyle(fontSize: 24)),
                    title: Text(name),
                    trailing: widget.selected == code ? check : null,
                    onTap: () => Navigator.of(context).pop((code: code)),
                  ),
                if (matches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No country matches that search.', textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
