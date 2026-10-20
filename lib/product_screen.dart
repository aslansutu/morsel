import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand.dart';
import 'format.dart';
import 'ingredients.dart';
import 'label_screen.dart';
import 'labels.dart';
import 'off_client.dart';
import 'panels.dart';
import 'theme.dart';
import 'vision.dart';

/// Whether Open Food Facts has the nutrients the meters show.
bool hasNutrition(Map<String, dynamic> product) {
  final nutriments = (product['nutriments'] as Map<String, dynamic>?) ?? {};
  return _Nutrition._meters.any((m) => _num(nutriments['${m.$1}_100g']) != null);
}

/// The ingredient list in Open Food Facts' panel, as HTML; null when it has none.
String? _ingredientList(PanelMap panels) {
  final elements = ((panels['ingredients'] as Map<String, dynamic>?)?['elements'] as List?) ?? [];
  return elements
      .cast<Map<String, dynamic>>()
      .where((e) => e['element_type'] == 'text')
      .map((e) => (e['text_element'] as Map)['html'] as String)
      .firstOrNull;
}

/// Whether Open Food Facts has the ingredient list the page shows.
bool hasIngredients(Map<String, dynamic> product) =>
    _ingredientList((product['knowledge_panels'] as Map<String, dynamic>?) ?? {}) != null;

/// What [label] fills in on [product]'s page: what Open Food Facts lacks.
({bool nutrition, bool ingredients}) labelFills(Map<String, dynamic>? product, LabelEntry label) => (
      nutrition: label.values.isNotEmpty && (product == null || !hasNutrition(product)),
      ingredients: label.ingredients != null && (product == null || !hasIngredients(product)),
    );

/// [product] with what [label] fills in, in Open Food Facts' shape, or the
/// label alone when [product] is null. Levels use Open Food Facts' thresholds,
/// so a meter reads the same whoever measured the food. Allergens come from
/// the label's ingredient list.
Map<String, dynamic>? withLabel(Map<String, dynamic>? product, LabelEntry? label) {
  if (label == null) return product;
  final fills = labelFills(product, label);
  double scaled(double threshold) => label.perMl ? threshold / 2 : threshold;
  final allergens = fills.ingredients ? allergenTags(label.ingredients!) : null;
  List<String> merged(String key, List<String> tags) => {...?(product?[key] as List?)?.cast<String>(), ...tags}.toList();
  return {
    ...?product,
    if (product == null) 'product_name': label.name,
    if (fills.nutrition) ...{
      'nutriments': {
        for (final MapEntry(:key, :value) in label.values.entries) '${key}_100g': value,
      },
      'nutrient_levels': {
        for (final (id, _, low, high) in _Nutrition._meters)
          if (label.values[id] case final v?)
            id: v < scaled(low) ? 'low' : (v > scaled(high) ? 'high' : 'moderate'),
      },
      // The page says "per 100 ml", and halves the thresholds, for beverages.
      'categories_tags': [
        ...?(product?['categories_tags'] as List?)?.where((t) => t != 'en:beverages'),
        if (label.perMl) 'en:beverages',
      ],
    },
    if (allergens != null) ...{
      'allergens_tags': merged('allergens_tags', allergens.contains),
      'traces_tags': merged('traces_tags', allergens.traces),
    },
  };
}

class ProductScreen extends StatefulWidget {
  const ProductScreen({
    super.key,
    required this.code,
    required this.client,
    this.country,
    this.onLoaded,
    this.labels,
    this.vision = const Vision(),
  });

  final String code;
  final OffClient client;
  final String? country;

  /// Labels read on this device; null where Morsel can't read labels (the web).
  final LabelStore? labels;
  final Vision vision;

  /// Called after every completed lookup, found or not.
  final ValueChanged<ProductLookup>? onLoaded;

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  late Future<ProductLookup> _lookup = _load();

  Future<ProductLookup> _load() async {
    final lookup = await widget.client.lookup(widget.code, country: widget.country);
    widget.onLoaded?.call(_withLabel(lookup));
    return lookup;
  }

  /// The saved label, where it fills in for Open Food Facts: a product it doesn't
  /// know, or one without nutrition facts or an ingredient list.
  LabelEntry? _labelFor(Map<String, dynamic>? product) {
    final label = widget.labels?[widget.code];
    return label != null && (product == null || !hasNutrition(product) || !hasIngredients(product)) ? label : null;
  }

  ProductLookup _withLabel(ProductLookup lookup) =>
      ProductLookup(code: lookup.code, product: withLabel(lookup.product, _labelFor(lookup.product)));

  /// Reads the label for what Open Food Facts lacks, or edits the one already saved.
  Future<void> _readLabel(ProductLookup lookup) async {
    final labels = widget.labels!;
    final product = lookup.product;
    final saved = _labelFor(product);
    final image = saved != null
        ? labels.labelPhoto(widget.code)?.path
        : await pickLabelImage(context, widget.vision);
    if (image == null || !mounted) return;
    final entry = await Navigator.of(context).push<LabelEntry>(MaterialPageRoute(
      builder: (_) => LabelScreen(
        code: widget.code,
        labelImage: image,
        store: labels,
        vision: widget.vision,
        newProduct: product == null,
        nutrition: product == null || !hasNutrition(product),
        ingredients: product == null || !hasIngredients(product),
        entry: saved,
      ),
    ));
    if (entry == null || !mounted) return;
    setState(() {});
    widget.onLoaded?.call(_withLabel(lookup));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: FutureBuilder<ProductLookup>(
        future: _lookup,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Message(
              icon: Icons.cloud_off,
              title: "Couldn't reach Open Food Facts",
              body: 'Check your connection and try again.',
              action: FilledButton(
                onPressed: () => setState(() => _lookup = _load()),
                child: const Text('Try again'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return _Message(title: 'Looking up ${widget.code}…');
          }
          final lookup = snapshot.data!;
          final label = _labelFor(lookup.product);
          final product = withLabel(lookup.product, label);
          final readLabel = widget.labels == null ? null : () => _readLabel(lookup);
          if (product == null) {
            final scanAnother = OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Scan another'),
            );
            return _Message(
              art: const MorselMark(),
              title: 'Not in Open Food Facts yet',
              body: readLabel == null
                  ? 'No product has the barcode ${widget.code}.'
                  : 'No product has the barcode ${widget.code}. '
                      'Read its nutrition label to keep the facts on this phone.',
              action: readLabel == null
                  ? scanAnother
                  : Column(
                      children: [
                        FilledButton.icon(
                          onPressed: readLabel,
                          icon: const Icon(Icons.document_scanner_outlined),
                          label: const Text('Read the label'),
                        ),
                        const SizedBox(height: 8),
                        scanAnother,
                      ],
                    ),
            );
          }
          return _ProductView(
            code: widget.code,
            product: product,
            known: lookup.product != null,
            label: label,
            fills: label == null ? null : labelFills(lookup.product, label),
            photo: widget.labels?.productPhoto(widget.code),
            labelPhoto: widget.labels?.labelPhoto(widget.code),
            onReadLabel: readLabel,
          );
        },
      ),
    );
  }
}

class _ProductView extends StatelessWidget {
  const _ProductView({
    required this.code,
    required this.product,
    required this.known,
    this.label,
    this.fills,
    this.photo,
    this.labelPhoto,
    this.onReadLabel,
  });

  final String code;
  final Map<String, dynamic> product;

  /// Open Food Facts knows the product; otherwise everything shown is from [label].
  final bool known;

  /// The user's label, when its facts are on this page, and which of them.
  final LabelEntry? label;
  final ({bool nutrition, bool ingredients})? fills;
  final File? photo;
  final File? labelPhoto;

  /// Reads the label, or edits it once saved; null where labels can't be read.
  final VoidCallback? onReadLabel;

  @override
  Widget build(BuildContext context) {
    final panels = (product['knowledge_panels'] as Map<String, dynamic>?) ?? {};
    final beverage = ((product['categories_tags'] as List?) ?? []).contains('en:beverages');
    final ownList = fills?.ingredients == true ? label!.ingredients : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        _Header(product: product, photo: photo),
        // A product only the user's label knows has no scores or details, and
        // highlights only from its ingredient list.
        if (known) ...[
          const SizedBox(height: 20),
          _Scores(product: product),
        ],
        if (known || ownList != null) ...[
          const SizedBox(height: 16),
          _Highlights(product: product, panels: panels),
        ],
        const SizedBox(height: 28),
        _Section(
          title: beverage ? 'Per 100 ml' : 'Per 100 g',
          child: _Nutrition(
            product: product,
            beverage: beverage,
            onReadLabel: fills?.nutrition == true ? null : onReadLabel,
          ),
        ),
        const SizedBox(height: 28),
        _Section(
          title: 'Ingredients',
          trailing: ownList == null ? (panelTitleElement(panels, 'ingredients')?['title'] as String?) : null,
          child: _Ingredients(panels: panels, ownList: ownList, onReadLabel: onReadLabel),
        ),
        if (known) ...[
          const SizedBox(height: 28),
          _Section(
            title: 'Details',
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (id, title) in const [
                    ('nutriscore_2023', null),
                    ('nova', null),
                    ('additives', 'Additives'),
                    ('environment_card', null),
                  ])
                    if (panels.containsKey(id)) PanelTile(panels: panels, id: id, title: title),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        if ((label, fills) case (final label?, final fills?))
          _LabelSource(label: label, known: known, fills: fills, labelPhoto: labelPhoto, onEdit: onReadLabel),
        if (known) _Footer(code: code, product: product) else _Barcode(code),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.product, this.photo});

  final Map<String, dynamic> product;

  /// The user's own photo, for a product Open Food Facts has no photo of.
  final File? photo;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final imageUrl = product['image_front_url'] as String?;
    final placeholder = Icon(Icons.image_outlined, color: MorselColors.of(context).inkMuted);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 88,
          height: 88,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white, // product photos are shot on white; keep them on white in dark mode too
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          // Open Food Facts' image server can take 10 s; the placeholder holds the space.
          child: imageUrl == null
              ? (photo == null ? placeholder : Image.file(photo!, fit: BoxFit.contain))
              : Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => placeholder,
                  loadingBuilder: (_, child, progress) => progress == null ? child : placeholder,
                ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(productName(product) ?? 'Unnamed product',
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                [product['brands'], product['quantity']]
                    .whereType<String>()
                    .where((s) => s.isNotEmpty)
                    .join(' · '),
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- The three scores ------------------------------------------------------

class _Scores extends StatelessWidget {
  const _Scores({required this.product});

  final Map<String, dynamic> product;

  static const _nutriWords = {
    'a': 'Very good',
    'b': 'Good',
    'c': 'Average',
    'd': 'Poor',
    'e': 'Very poor',
  };
  static const _novaWords = {
    1: ('Unprocessed', Evaluation.good),
    2: ('Culinary ingredient', Evaluation.caution),
    3: ('Processed', Evaluation.caution),
    4: ('Ultra-processed', Evaluation.bad),
  };

  @override
  Widget build(BuildContext context) {
    final colors = MorselColors.of(context);
    final grade = product['nutriscore_grade'] as String?;
    final nova = (product['nova_group'] as num?)?.toInt();
    final green = product['ecoscore_grade'] as String?;
    final (greenLabel, greenWord, greenEval) = switch (green) {
      'a-plus' => ('A+', 'Very low impact', Evaluation.good),
      'a' || 'b' => (green!.toUpperCase(), 'Low impact', Evaluation.good),
      'c' => ('C', 'Moderate impact', Evaluation.caution),
      'd' || 'e' || 'f' => (green!.toUpperCase(), 'High impact', Evaluation.bad),
      'not-applicable' => ('–', 'Not applicable', Evaluation.unknown),
      _ => ('?', 'Not computed', Evaluation.unknown),
    };
    final (novaWord, novaEval) = _novaWords[nova] ?? ('Unknown', Evaluation.unknown);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ScoreTile(
              name: 'Nutri-Score',
              word: _nutriWords[grade] ?? 'Unknown',
              badge: _Badge(
                text: _nutriWords.containsKey(grade) ? grade!.toUpperCase() : '?',
                fill: nutriScoreFills[grade] ?? colors.unknown,
                textColor: nutriScoreInk[grade] ?? Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ScoreTile(
              name: 'Processing',
              word: novaWord,
              badge: _Badge.status(context, nova?.toString() ?? '?', novaEval),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ScoreTile(
              name: 'Green-Score',
              word: greenWord,
              badge: _Badge.status(context, greenLabel, greenEval),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreTile extends StatelessWidget {
  const _ScoreTile({required this.name, required this.word, required this.badge});

  final String name;
  final String word;
  final Widget badge;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            badge,
            const SizedBox(height: 10),
            Text(word, style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(name,
                style: text.labelSmall?.copyWith(color: MorselColors.of(context).inkMuted)),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.fill, required this.textColor});

  /// A status fill; light-mode fills take white text, dark-mode fills take ink.
  factory _Badge.status(BuildContext context, String text, Evaluation evaluation) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _Badge(
      text: text,
      fill: MorselColors.of(context).forEvaluation(evaluation),
      textColor: dark ? ink : Colors.white,
    );
  }

  final String text;
  final Color fill;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(10)),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: textColor, fontWeight: FontWeight.w800)),
    );
  }
}

// --- Highlights ------------------------------------------------------------

class _Highlights extends StatelessWidget {
  const _Highlights({required this.product, required this.panels});

  final Map<String, dynamic> product;
  final PanelMap panels;

  static String _names(Object? tags) => ((tags as List?) ?? [])
      .map((t) => (t as String).replaceFirst(RegExp(r'^\w+:'), '').replaceAll('-', ' '))
      .join(', ');

  @override
  Widget build(BuildContext context) {
    final analysis = ((product['ingredients_analysis_tags'] as List?) ?? []).cast<String>();
    final additives = ((product['additives_tags'] as List?) ?? []).length;
    final allergens = _names(product['allergens_tags']);
    final traces = _names(product['traces_tags']);
    final addedSugars = panelTitleElement(panels, 'ingredients_added_sugars')?['title'] as String?;

    // Judgements (status colours) only where a standard exists; diet and
    // allergens are facts about the food, so they stay neutral.
    final facts = <(IconData, String, Evaluation?)>[
      if (analysis.contains('en:palm-oil')) (Icons.forest, 'Contains palm oil', Evaluation.bad),
      if (analysis.contains('en:may-contain-palm-oil'))
        (Icons.forest, 'May contain palm oil', Evaluation.caution),
      if (analysis.contains('en:palm-oil-free')) (Icons.forest, 'No palm oil', Evaluation.good),
      if (addedSugars != null)
        (Icons.cookie_outlined, addedSugars, panelEvaluation(panels, 'ingredients_added_sugars')),
      if (analysis.contains('en:vegan')) (Icons.eco_outlined, 'Vegan', null),
      if (analysis.contains('en:non-vegan')) (Icons.eco_outlined, 'Not vegan', null),
      if (analysis.contains('en:maybe-vegan')) (Icons.eco_outlined, 'Maybe vegan', null),
      if (!analysis.contains('en:vegan') && analysis.contains('en:vegetarian'))
        (Icons.spa_outlined, 'Vegetarian', null),
      if (analysis.contains('en:non-vegetarian')) (Icons.spa_outlined, 'Not vegetarian', null),
      if (allergens.isNotEmpty) (Icons.info_outline, 'Contains $allergens', null),
      if (traces.isNotEmpty) (Icons.info_outline, 'May contain $traces', null),
      if (additives > 0)
        (Icons.science_outlined, '$additives additive${additives == 1 ? '' : 's'}', null),
    ];
    if (facts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final (icon, label, eval) in facts) _Fact(icon: icon, label: label, evaluation: eval)],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, this.evaluation});

  final IconData icon;
  final String label;
  final Evaluation? evaluation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = evaluation;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(e?.icon ?? icon,
              size: 18,
              color: e == null ? scheme.onSurfaceVariant : MorselColors.of(context).forEvaluation(e)),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

// --- Nutrition -------------------------------------------------------------

double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v');

class _Nutrition extends StatelessWidget {
  const _Nutrition({required this.product, required this.beverage, this.onReadLabel});

  final Map<String, dynamic> product;
  final bool beverage;

  /// Offered when the facts are missing.
  final VoidCallback? onReadLabel;

  // Open Food Facts' thresholds per 100 g (low below, high above), halved for
  // beverages — lib/ProductOpener/Food.pm, @nutrient_levels.
  static const _meters = [
    ('fat', 'Fat', 3.0, 20.0),
    ('saturated-fat', 'Saturated fat', 1.5, 5.0),
    ('sugars', 'Sugars', 5.0, 12.5),
    ('salt', 'Salt', 0.3, 1.5),
  ];
  static const _facts = [
    ('energy-kcal_100g', 'Energy', 'kcal'),
    ('fat_100g', 'Fat', 'g'),
    ('saturated-fat_100g', '  Saturated fat', 'g'),
    ('carbohydrates_100g', 'Carbohydrates', 'g'),
    ('sugars_100g', '  Sugars', 'g'),
    ('fiber_100g', 'Fibre', 'g'),
    ('proteins_100g', 'Protein', 'g'),
    ('salt_100g', 'Salt', 'g'),
  ];

  @override
  Widget build(BuildContext context) {
    final nutriments = (product['nutriments'] as Map<String, dynamic>?) ?? {};
    final levels = (product['nutrient_levels'] as Map<String, dynamic>?) ?? {};
    final meters = [
      for (final (id, label, low, high) in _meters)
        if (_num(nutriments['${id}_100g']) case final value?)
          _NutrientMeter(
            label: label,
            value: value,
            level: levels[id] as String?,
            low: beverage ? low / 2 : low,
            high: beverage ? high / 2 : high,
          ),
    ];
    if (meters.isEmpty) {
      const missing = Text('Nutrition facts are not available for this product yet.');
      if (onReadLabel == null) return missing;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          missing,
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onReadLabel,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Read the label'),
          ),
        ],
      );
    }
    final text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Column(
              children: [
                for (final meter in meters)
                  Padding(padding: const EdgeInsets.only(bottom: 16), child: meter),
              ],
            ),
          ),
          const Divider(),
          ExpansionTile(
            title: Text('All nutrition facts', style: text.bodyLarge),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              for (final (key, label, unit) in _facts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(label, style: text.bodyMedium)),
                      Text(
                        switch (_num(nutriments[key])) {
                          final v? => '${formatAmount(v)} $unit',
                          null => '—',
                        },
                        style: text.bodyMedium?.copyWith(fontFeatures: tabular),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A value placed on three equal zones (low · moderate · high). The zone comes
/// from Open Food Facts' own level, so the marker never contradicts the word.
class _NutrientMeter extends StatelessWidget {
  const _NutrientMeter({
    required this.label,
    required this.value,
    required this.level,
    required this.low,
    required this.high,
  });

  final String label;
  final double value;
  final String? level;
  final double low;
  final double high;

  static const _levels = {
    'low': ('Low', Evaluation.good, 0),
    'moderate': ('Moderate', Evaluation.caution, 1),
    'high': ('High', Evaluation.bad, 2),
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = MorselColors.of(context);
    final (word, evaluation, zone) = _levels[level] ?? ('Unknown', Evaluation.unknown, -1);
    // Position inside the zone: 0..low, low..high, high..2×high.
    final within = switch (zone) {
      0 => value / low,
      1 => (value - low) / (high - low),
      _ => (value - high) / high,
    };
    final position = zone < 0 ? null : (zone + within.clamp(0.04, 0.96)) / 3;
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: text.bodyLarge)),
            Text('${formatAmount(value)} g',
                style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600, fontFeatures: tabular)),
            SizedBox(
              width: 104,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(evaluation.icon, size: 16, color: colors.forEvaluation(evaluation)),
                  const SizedBox(width: 4),
                  Text(word, style: text.labelLarge),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ZoneTrack(position: position, color: colors.forEvaluation(evaluation)),
      ],
    );
  }
}

class _ZoneTrack extends StatelessWidget {
  const _ZoneTrack({required this.position, required this.color});

  /// 0..1 across the whole track, or null when the level is unknown.
  final double? position;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = MorselColors.of(context);
    final surface = Theme.of(context).colorScheme.surfaceContainerLow;
    final position = this.position;
    return SizedBox(
      height: 14,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.centerLeft,
          children: [
            Row(
              children: [
                for (final (i, zone) in [colors.good, colors.caution, colors.bad].indexed) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: zone.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (position != null)
              Positioned(
                left: position * constraints.maxWidth - 7,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: surface, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- Ingredients, sections, footer ----------------------------------------

class _Ingredients extends StatelessWidget {
  const _Ingredients({required this.panels, this.ownList, this.onReadLabel});

  final PanelMap panels;

  /// The list from the user's label, where Open Food Facts has none.
  final String? ownList;

  /// Offered when the list is missing.
  final VoidCallback? onReadLabel;

  @override
  Widget build(BuildContext context) {
    final list = _ingredientList(panels);
    if (ownList case final own?) {
      return Card(
        child: Padding(padding: const EdgeInsets.all(16), child: _OwnList(own)),
      );
    }
    if (list == null) {
      const missing = Text('The ingredient list is not available for this product yet.');
      if (onReadLabel == null) return missing;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          missing,
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onReadLabel,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Read the ingredients'),
          ),
        ],
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.all(16), child: PanelHtml(list)),
          if (panels.containsKey('ingredients_list')) ...[
            const Divider(),
            PanelTile(panels: panels, id: 'ingredients_list'),
          ],
        ],
      ),
    );
  }
}

/// An ingredient list from the user's label, allergens in bold as Open Food
/// Facts' panel shows them.
class _OwnList extends StatelessWidget {
  const _OwnList(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    var at = 0;
    for (final a in findAllergens(text)) {
      if (a.start < at) continue;
      spans
        ..add(TextSpan(text: text.substring(at, a.start)))
        ..add(TextSpan(text: text.substring(a.start, a.end), style: const TextStyle(fontWeight: FontWeight.bold)));
      at = a.end;
    }
    spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(TextSpan(children: spans), style: Theme.of(context).textTheme.bodyMedium);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
            if (trailing != null)
              Text(trailing!, style: text.bodySmall?.copyWith(color: MorselColors.of(context).inkMuted)),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.code, required this.product});

  final String code;
  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: MorselColors.of(context).inkMuted);
    final modified = (product['last_modified_t'] as num?)?.toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Data from ', style: style),
            InkWell(
              onTap: () => launchUrl(
                Uri.parse('https://world.openfoodfacts.org/product/$code'),
                mode: LaunchMode.externalApplication,
              ),
              child: Text('Open Food Facts',
                  style: style?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline)),
            ),
            if (modified != null)
              Text(' · updated ${formatDate(DateTime.fromMillisecondsSinceEpoch(modified * 1000))}',
                  style: style),
          ],
        ),
        const SizedBox(height: 2),
        Text('Barcode $code', style: style?.copyWith(fontFeatures: tabular)),
      ],
    );
  }
}

/// Where the label's facts came from, with the photo to check them against and a
/// way to fix a value.
class _LabelSource extends StatelessWidget {
  const _LabelSource({
    required this.label,
    required this.known,
    required this.fills,
    this.labelPhoto,
    this.onEdit,
  });

  final LabelEntry label;

  /// Open Food Facts knows the product, so only [fills] are the user's.
  final bool known;
  final ({bool nutrition, bool ingredients}) fills;
  final File? labelPhoto;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: MorselColors.of(context).inkMuted);
    final link = style?.copyWith(
        color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline);
    final photo = labelPhoto;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            switch ((known, fills.nutrition, fills.ingredients)) {
              (false, _, _) => 'From ',
              (true, true, true) => 'Nutrition facts and ingredients from ',
              (true, true, false) => 'Nutrition facts from ',
              _ => 'Ingredients from ',
            },
            style: style,
          ),
          if (photo == null)
            Text('your photo of the label', style: style)
          else
            InkWell(
              onTap: () => showPhoto(context, photo.path),
              child: Text('your photo of the label', style: link),
            ),
          Text(' · saved ${formatDate(label.savedAt)}', style: style),
          if (onEdit != null) ...[
            Text(' · ', style: style),
            InkWell(onTap: onEdit, child: Text('Edit', style: link)),
          ],
        ],
      ),
    );
  }
}

class _Barcode extends StatelessWidget {
  const _Barcode(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    return Text('Barcode $code',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: MorselColors.of(context).inkMuted, fontFeatures: tabular));
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, this.icon, this.art, this.body, this.action});

  final String title;

  /// With neither [icon] nor [art], a progress indicator shows instead.
  final IconData? icon;
  final Widget? art;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (art != null)
              art!
            else if (icon == null)
              const CircularProgressIndicator()
            else
              Icon(icon, size: 48, color: MorselColors.of(context).inkMuted),
            const SizedBox(height: 16),
            Text(title, style: text.titleMedium, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(body!, style: text.bodyMedium, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
