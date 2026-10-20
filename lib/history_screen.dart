import 'dart:io';

import 'package:flutter/material.dart';

import 'brand.dart';
import 'format.dart';
import 'labels.dart';
import 'settings.dart';
import 'theme.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({
    super.key,
    required this.history,
    required this.settings,
    required this.onOpen,
    required this.onScan,
    required this.onOpenSettings,
    this.labels,
  });

  final History history;
  final Settings settings;

  /// For the photos people took of products Open Food Facts doesn't know.
  final LabelStore? labels;
  final ValueChanged<String> onOpen;
  final VoidCallback onScan;
  final VoidCallback onOpenSettings;

  void _clearAll(BuildContext context) {
    final removed = history.clear();
    _undoable(context, '${removed.length} scans cleared', () => history.restore(removed));
  }

  static void _undoable(BuildContext context, String message, VoidCallback undo) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'Undo', onPressed: undo),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([history, settings]),
      builder: (context, _) {
        final items = history.items;
        return Scaffold(
          appBar: AppBar(
            title: const Text('History'),
            actions: [
              if (items.isNotEmpty)
                IconButton(
                  tooltip: 'Clear history',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: () => _clearAll(context),
                ),
            ],
          ),
          body: items.isNotEmpty
              ? _list(context, items)
              : settings.rememberScans
                  ? _Empty(
                      art: const MorselMark(),
                      title: 'No scans yet',
                      body: 'Products you scan show up here, newest first.',
                      action: FilledButton.icon(
                        onPressed: onScan,
                        icon: ScanGlyph(color: Theme.of(context).colorScheme.onPrimary, size: 20),
                        label: const Text('Scan a barcode'),
                      ),
                    )
                  : _Empty(
                      art: Icon(Icons.history_toggle_off,
                          size: 48, color: MorselColors.of(context).inkMuted),
                      title: 'Scan history is off',
                      body: 'Turn on "Remember scans" in Settings to keep a list of what you scan.',
                      action: OutlinedButton(
                        onPressed: onOpenSettings,
                        child: const Text('Open Settings'),
                      ),
                    ),
        );
      },
    );
  }

  Widget _list(BuildContext context, List<ScanRecord> items) {
    // Day headers interleaved with (index, record) rows.
    final rows = <Object>[];
    String? day;
    for (final (i, record) in items.indexed) {
      final label = formatDay(record.scannedAt);
      if (label != day) rows.add(day = label);
      rows.add((i, record));
    }
    return ListView.builder(
      // The dock floats over the list; MediaQuery's bottom padding includes it.
      padding: EdgeInsets.only(bottom: 16 + MediaQuery.paddingOf(context).bottom),
      itemCount: rows.length,
      itemBuilder: (context, j) {
        final row = rows[j];
        if (row is String) return _DayHeader(row);
        final (index, record) = row as (int, ScanRecord);
        return Dismissible(
          key: ValueKey(record.code),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Theme.of(context).colorScheme.surfaceContainer,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: const Icon(Icons.delete_outline),
          ),
          onDismissed: (_) {
            history.removeAt(index);
            _undoable(context, 'Scan removed', () => history.insertAt(index, record));
          },
          child: _HistoryTile(
            record: record,
            photo: labels?.productPhoto(record.code),
            onTap: () => onOpen(record.code),
          ),
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: MorselColors.of(context).inkMuted)),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record, required this.onTap, this.photo});

  final ScanRecord record;
  final VoidCallback onTap;
  final File? photo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = MorselColors.of(context).inkMuted;
    final known = record.name != null;
    final grade = record.nutriScore;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 48,
        height: 48,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: record.imageUrl == null
            ? (photo == null
                ? Icon(known ? Icons.image_outlined : Icons.search_off, color: muted)
                : Image.file(photo!, fit: BoxFit.contain))
            : Image.network(record.imageUrl!,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : Icon(Icons.image_outlined, color: muted),
                errorBuilder: (_, _, _) => Icon(Icons.image_outlined, color: muted)),
      ),
      title: Text(record.name ?? 'Not in Open Food Facts',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${record.brand ?? record.code} · ${formatTime(record.scannedAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: nutriScoreFills.containsKey(grade)
          ? Semantics(
              label: 'Nutri-Score ${grade!.toUpperCase()}',
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: nutriScoreFills[grade],
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(grade.toUpperCase(),
                    style: TextStyle(color: nutriScoreInk[grade], fontWeight: FontWeight.w800)),
              ),
            )
          : null,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.art, required this.title, required this.body, required this.action});

  final Widget art;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(32, 32, 32, 32 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            art,
            const SizedBox(height: 16),
            Text(title, style: text.titleMedium),
            const SizedBox(height: 8),
            Text(body, style: text.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            action,
          ],
        ),
      ),
    );
  }
}
