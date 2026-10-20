import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

// Open Food Facts "knowledge panels": localized, titled sections whose text is
// HTML. Panels nest through `panel` and `panel_group` elements.

typedef PanelMap = Map<String, dynamic>;

Map<String, dynamic>? panelTitleElement(PanelMap panels, String id) =>
    (panels[id] as Map<String, dynamic>?)?['title_element'] as Map<String, dynamic>?;

/// The panel's own good/average/bad verdict, if it gives one.
Evaluation? panelEvaluation(PanelMap panels, String id) =>
    switch ((panels[id] as Map<String, dynamic>?)?['evaluation']) {
      'good' => Evaluation.good,
      'average' => Evaluation.caution,
      'bad' => Evaluation.bad,
      _ => null,
    };

/// HTML from a text element. Allergens arrive pre-marked as `span.allergen`.
class PanelHtml extends StatelessWidget {
  const PanelHtml(this.html, {super.key});

  final String html;

  @override
  Widget build(BuildContext context) {
    return HtmlWidget(
      html,
      textStyle: Theme.of(context).textTheme.bodyMedium,
      customStylesBuilder: (element) =>
          element.classes.contains('allergen') ? {'font-weight': 'bold'} : null,
      onTapUrl: (url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    );
  }
}

/// One panel as an expandable row; its elements render when expanded.
class PanelTile extends StatelessWidget {
  const PanelTile({super.key, required this.panels, required this.id, this.title});

  final PanelMap panels;
  final String id;

  /// Used when the panel has no title of its own (e.g. `additives`).
  final String? title;

  @override
  Widget build(BuildContext context) {
    final panel = panels[id] as Map<String, dynamic>?;
    if (panel == null) return const SizedBox.shrink();
    final head = panelTitleElement(panels, id);
    final evaluation = panelEvaluation(panels, id);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      leading: evaluation == null
          ? null
          : Icon(evaluation.icon, color: MorselColors.of(context).forEvaluation(evaluation)),
      title: Text(head?['title'] as String? ?? title ?? id, style: text.bodyLarge),
      subtitle: head?['subtitle'] == null
          ? null
          : Text(head!['subtitle'] as String,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final element in (panel['elements'] as List? ?? []).cast<Map<String, dynamic>>())
          _element(context, element),
      ],
    );
  }

  Widget _element(BuildContext context, Map<String, dynamic> element) {
    switch (element['element_type']) {
      case 'text':
        final html = (element['text_element'] as Map?)?['html'] as String? ?? '';
        return html.trim().isEmpty ? const SizedBox.shrink() : PanelHtml(html);
      case 'panel':
        return PanelTile(panels: panels, id: element['panel_element']['panel_id'] as String);
      case 'panel_group':
        final group = element['panel_group_element'] as Map<String, dynamic>;
        final groupTitle = group['title'] as String?;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (groupTitle != null && groupTitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(groupTitle, style: Theme.of(context).textTheme.titleSmall),
              ),
            for (final id in (group['panel_ids'] as List).cast<String>())
              PanelTile(panels: panels, id: id),
          ],
        );
      default: // tables and actions: the app shows its own nutrition table
        return const SizedBox.shrink();
    }
  }
}
