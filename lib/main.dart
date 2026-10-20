import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brand.dart';
import 'history_screen.dart';
import 'labels.dart';
import 'off_client.dart';
import 'product_screen.dart';
import 'scanner_screen.dart';
import 'settings.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'vision.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // Reading labels needs the phone's camera and text recognition, so not on the web.
  final labels = kIsWeb ? null : LabelStore(prefs, Directory('${(await appFolder()).path}/labels'));
  runApp(MorselApp(
      client: OffClient(), settings: Settings(prefs), history: History(prefs), labels: labels));
}

class MorselApp extends StatelessWidget {
  const MorselApp({
    super.key,
    required this.client,
    required this.settings,
    required this.history,
    this.labels,
    this.initialTab = DockTab.scan,
  });

  final OffClient client;
  final Settings settings;
  final History history;
  final LabelStore? labels;
  final DockTab initialTab;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Morsel',
      theme: morselTheme(Brightness.light),
      darkTheme: morselTheme(Brightness.dark),
      home: Shell(
          client: client, settings: settings, history: history, labels: labels, initialTab: initialTab),
    );
  }
}

enum DockTab { history, scan, settings }

class Shell extends StatefulWidget {
  const Shell({
    super.key,
    required this.client,
    required this.settings,
    required this.history,
    required this.initialTab,
    this.labels,
  });

  final OffClient client;
  final Settings settings;
  final History history;
  final DockTab initialTab;
  final LabelStore? labels;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  // The app opens ready to scan: that's why people open it.
  late var _tab = widget.initialTab;

  void _go(DockTab tab) => setState(() => _tab = tab);

  Future<void> _open(String code) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProductScreen(
          code: code,
          client: widget.client,
          country: widget.settings.effectiveCountry,
          labels: widget.labels,
          onLoaded: (lookup) {
            if (widget.settings.rememberScans) widget.history.record(ScanRecord.fromLookup(lookup));
          },
        ),
      ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The dock floats over the content; screens pad their bottom by
      // MediaQuery.padding, which includes the dock's height.
      extendBody: true,
      // Only the visible tab is built, so the camera runs only on the scan tab.
      body: switch (_tab) {
        DockTab.history => HistoryScreen(
            history: widget.history,
            settings: widget.settings,
            labels: widget.labels,
            onOpen: _open,
            onScan: () => _go(DockTab.scan),
            onOpenSettings: () => _go(DockTab.settings),
          ),
        DockTab.scan => ScanTab(onCode: _open),
        DockTab.settings => SettingsScreen(settings: widget.settings, history: widget.history),
      },
      bottomNavigationBar: Dock(current: _tab, onSelect: _go),
    );
  }
}

/// A floating glass capsule: History · Scan · Settings.
class Dock extends StatelessWidget {
  const Dock({super.key, required this.current, required this.onSelect});

  final DockTab current;
  final ValueChanged<DockTab> onSelect;

  static const _radius = BorderRadius.all(Radius.circular(32));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: _radius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: _radius,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer.withValues(alpha: 0.78),
                      borderRadius: _radius,
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Row(
                        children: [
                          Expanded(
                            child: _DockItem(
                              icon: Icons.history,
                              label: 'History',
                              selected: current == DockTab.history,
                              onTap: () => onSelect(DockTab.history),
                            ),
                          ),
                          _ScanButton(
                            selected: current == DockTab.scan,
                            onTap: () => onSelect(DockTab.scan),
                          ),
                          Expanded(
                            child: _DockItem(
                              icon: Icons.settings_outlined,
                              selectedIcon: Icons.settings,
                              label: 'Settings',
                              selected: current == DockTab.settings,
                              onTap: () => onSelect(DockTab.settings),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedIcon,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colour = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            // A minimum, not a fixed height, so large system text still fits.
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: selected ? scheme.primaryContainer : Colors.transparent,
            ),
            child: Column(
              // min, and no Container alignment: either one stretches the dock to the
              // full screen height. The 52 px minimum still centres the content.
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(selected ? selectedIcon ?? icon : icon, size: 22, color: colour),
                const SizedBox(height: 2),
                Text(label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colour,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Scan',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Scan a barcode',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Material(
            color: scheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox.square(
                dimension: 56,
                child: Center(child: ScanGlyph(color: scheme.onPrimary, size: 28)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
