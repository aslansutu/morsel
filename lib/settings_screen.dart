import 'package:flutter/material.dart';

import 'countries.dart';
import 'format.dart';
import 'settings.dart';
import 'theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings, required this.history});

  final Settings settings;
  final History history;

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
    return ListenableBuilder(
      listenable: settings,
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
