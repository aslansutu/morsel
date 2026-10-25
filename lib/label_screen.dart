import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'ingredients.dart';
import 'label_parser.dart';
import 'labels.dart';
import 'theme.dart';
import 'vision.dart';

/// Asks how to get the label — the document scanner or a photo already taken —
/// and returns the image file, or null if the user backed out.
Future<String?> pickLabelImage(BuildContext context, Vision vision) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _SourceSheet(
      cameraLabel: 'Scan the label',
      cameraIcon: Icons.document_scanner_outlined,
    ),
  );
  if (source == null || !context.mounted) return null;
  try {
    return source == ImageSource.camera
        ? await vision.scanDocument()
        : await vision.pickPhoto(ImageSource.gallery);
  } on VisionUnavailable {
    if (context.mounted) _say(context, "This device can't scan. Choose a photo instead.");
  } on PlatformException catch (e) {
    if (context.mounted) _say(context, "Couldn't open that: ${e.message}");
  }
  return null;
}

/// Asks whether to take a photo or choose one, and returns the image file, or
/// null if the user backed out.
Future<String?> pickPhoto(BuildContext context, Vision vision) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _SourceSheet(cameraLabel: 'Take a photo', cameraIcon: Icons.photo_camera_outlined),
  );
  if (source == null || !context.mounted) return null;
  try {
    return await vision.pickPhoto(source);
  } on PlatformException catch (e) {
    if (context.mounted) _say(context, "Couldn't open that: ${e.message}");
  }
  return null;
}

/// Shows a photo full screen, pinch to zoom.
Future<void> showPhoto(BuildContext context, String path) => Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
          body: InteractiveViewer(maxScale: 6, child: Center(child: Image.file(File(path)))),
        ),
      ),
    );

void _say(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

/// The nutrients a form asks for, in label order: id, name, unit, and whether
/// it's a sub-row ("of which sugars").
const nutrientFields = [
  ('energy-kcal', 'Energy', 'kcal', false),
  ('fat', 'Fat', 'g', false),
  ('saturated-fat', 'Saturated fat', 'g', true),
  ('carbohydrates', 'Carbohydrates', 'g', false),
  ('sugars', 'Sugars', 'g', true),
  ('fiber', 'Fibre', 'g', false),
  ('proteins', 'Protein', 'g', false),
  ('salt', 'Salt', 'g', false),
];

/// 30.9, 0.107, 12: the value as typed, without a trailing ".0".
String plainAmount(double v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

/// [text] as a number, with a decimal comma or point; null when it isn't one.
double? parseAmount(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

/// Why [text] can't be an amount in [unit] per 100 g; null when it can, or is empty.
String? checkNutrient(String? text, String unit) {
  if (text == null || text.trim().isEmpty) return null;
  final v = parseAmount(text);
  if (v == null) return 'Not a number';
  if (unit == 'g' && v > 100) return 'Over 100 g';
  if (unit == 'kcal' && v > 950) return 'Too high';
  return null;
}

/// The review form: what was read off the label, under the photo, for the user
/// to check before it's saved.
class LabelScreen extends StatefulWidget {
  const LabelScreen({
    super.key,
    required this.code,
    required this.labelImage,
    required this.store,
    required this.newProduct,
    this.nutrition = true,
    this.ingredients = true,
    this.vision = const Vision(),
    this.entry,
  });

  final String code;

  /// The label's image file.
  final String labelImage;
  final LabelStore store;

  /// Open Food Facts doesn't know the product, so ask for its name and a photo.
  final bool newProduct;

  /// What the form asks for: what Open Food Facts lacks.
  final bool nutrition;
  final bool ingredients;
  final Vision vision;

  /// The saved facts, when editing; otherwise the form is filled by reading [labelImage].
  final LabelEntry? entry;

  @override
  State<LabelScreen> createState() => _LabelScreenState();
}

class _LabelScreenState extends State<LabelScreen> {
  final _form = GlobalKey<FormState>();
  final _values = {for (final id in labelNutrients) id: TextEditingController()};
  late final _name = TextEditingController(text: widget.entry?.name);
  late final _ingredients = TextEditingController(text: widget.entry?.ingredients);
  late var _listLanguage = widget.entry?.ingredientsLanguage;
  late var _labelImage = widget.labelImage;
  late var _perMl = widget.entry?.perMl ?? false;
  late var _photo = widget.store.productPhoto(widget.code)?.path;

  /// The photo the ingredient list was read from, when it isn't the label's.
  late var _ingredientsImage = widget.store.ingredientsPhoto(widget.code)?.path;

  /// How many values the parser found, and whether it found the ingredient
  /// list; null when editing saved facts.
  int? _found;
  bool? _listFound;
  var _basis = Basis.per100g;
  var _reading = false;
  var _readingList = false;
  var _cutting = false;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    if (entry == null) {
      _read();
    } else {
      for (final MapEntry(:key, :value) in entry.values.entries) {
        _values[key]?.text = plainAmount(value);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _values.values) {
      c.dispose();
    }
    _name.dispose();
    _ingredients.dispose();
    super.dispose();
  }

  Future<List<TextLine>> _readText(String image) async {
    try {
      return await widget.vision.readText(image);
    } on PlatformException {
      return const [];
    }
  }

  /// Reads the label photo: the nutrition table, and the ingredient list when
  /// the photo has it. A list typed or read from another photo stays when
  /// this one has none.
  Future<void> _read() async {
    setState(() => _reading = true);
    final lines = await _readText(_labelImage);
    if (!mounted) return;
    final reading = parseLabel(lines);
    final list = readIngredientList(lines);
    setState(() {
      _reading = false;
      if (widget.nutrition) {
        _found = reading.values.length;
        _basis = reading.basis;
        _perMl = reading.basis == Basis.per100ml;
        for (final id in labelNutrients) {
          _values[id]!.text = switch (reading.values[id]) { final v? => plainAmount(v), null => '' };
        }
      }
      if (widget.ingredients && (list != null || _ingredients.text.trim().isEmpty)) {
        _listFound = list != null;
        if (list != null) {
          _ingredients.text = list.text;
          _listLanguage = list.language;
          _ingredientsImage = null;
        }
      }
    });
  }

  Future<void> _readList() async {
    final image = await pickLabelImage(context, widget.vision);
    if (image == null || !mounted) return;
    setState(() => _readingList = true);
    final list = readIngredientList(await _readText(image));
    if (!mounted) return;
    setState(() {
      _readingList = false;
      _ingredientsImage = image;
      _listFound = list != null;
      if (list != null) {
        _ingredients.text = list.text;
        _listLanguage = list.language;
      }
    });
  }

  Future<void> _retake() async {
    final image = await pickLabelImage(context, widget.vision);
    if (image == null || !mounted) return;
    setState(() => _labelImage = image);
    await _read();
  }

  Future<void> _addPhoto() async {
    final path = await pickPhoto(context, widget.vision);
    if (path == null || !mounted) return;
    setState(() => _cutting = true);
    String? cut;
    try {
      cut = await widget.vision.cutOut(path);
    } on PlatformException {
      cut = null;
    }
    if (!mounted) return;
    setState(() {
      _cutting = false;
      _photo = cut ?? path;
    });
    if (cut == null) _say(context, "Couldn't pick out the product, so the photo stays as it is.");
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final values = {
      for (final MapEntry(:key, :value) in _values.entries) key: ?parseAmount(value.text),
    };
    final list = _ingredients.text.trim();
    if ((!widget.nutrition || values.isEmpty) && (!widget.ingredients || list.isEmpty)) {
      _say(context, switch ((widget.nutrition, widget.ingredients)) {
        (true, true) => 'Enter at least one value or the ingredient list.',
        (true, false) => 'Enter at least one value from the label.',
        _ => 'Type the ingredient list, or read it from a photo.',
      });
      return;
    }
    // What the form didn't ask for stays as it was saved.
    final entry = widget.entry;
    setState(() => _saving = true);
    final saved = await widget.store.save(
      LabelEntry(
        code: widget.code,
        values: widget.nutrition ? values : entry?.values ?? const {},
        perMl: widget.nutrition ? _perMl : entry?.perMl ?? false,
        savedAt: DateTime.now(),
        name: widget.newProduct ? _name.text.trim() : null,
        ingredients: widget.ingredients ? (list.isEmpty ? null : list) : entry?.ingredients,
        ingredientsLanguage:
            widget.ingredients ? (list.isEmpty ? null : _listLanguage) : entry?.ingredientsLanguage,
      ),
      labelImage: _labelImage,
      productImage: widget.newProduct ? _photo : null,
      ingredientsImage: _ingredientsImage,
    );
    if (mounted) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = MorselColors.of(context).inkMuted;
    final found = _found;
    return Scaffold(
      appBar: AppBar(title: Text(widget.entry == null ? 'Check the label' : 'Edit the label')),
      body: Form(
        key: _form,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.paddingOf(context).bottom),
          children: [
            Semantics(
              button: true,
              label: 'Label photo, open full screen',
              child: InkWell(
                onTap: () => showPhoto(context, _labelImage),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 220,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Image.file(File(_labelImage), fit: BoxFit.contain),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_reading)
              Row(
                children: [
                  const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  Text('Reading the label…', style: text.bodyMedium),
                ],
              )
            else if (widget.nutrition && found != null) ...[
              Text(
                found == 0
                    ? 'No nutrition table found in this photo. Type the values, or try another photo.'
                    : 'Found $found of ${labelNutrients.length} values. Check each one against the photo.',
                style: text.bodyMedium,
              ),
              if (found > 0 && _basis == Basis.unknown) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "The photo doesn't say “per 100 g”. Make sure these aren't per serving.",
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ],
            ],
            // Also when editing: saved facts may lack the nutrition table.
            if (widget.nutrition && !_reading)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _retake,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try another photo'),
                ),
              ),
            if (widget.nutrition) ...[
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Per 100 g')),
                  ButtonSegment(value: true, label: Text('Per 100 ml')),
                ],
                selected: {_perMl},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _perMl = s.first),
              ),
              const SizedBox(height: 12),
              NutrientFields(controllers: _values, enabled: !_reading),
            ],
            if (widget.ingredients) ...[
              const SizedBox(height: 28),
              Text('Ingredients', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              if (_listFound case final listFound? when !_reading && !_readingList) ...[
                const SizedBox(height: 4),
                Text(
                  listFound
                      ? 'Found the ingredient list. Check it against the photo.'
                      : 'No ingredient list found in this photo. Type it, or read it from another photo.',
                  style: text.bodyMedium,
                ),
              ],
              const SizedBox(height: 10),
              Semantics(
                label: 'Ingredients',
                child: TextFormField(
                  controller: _ingredients,
                  enabled: !_reading && !_readingList,
                  minLines: 3,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'As printed on the label',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _reading || _readingList ? null : _readList,
                    icon: _readingList
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.document_scanner_outlined),
                    label: const Text('Read from another photo'),
                  ),
                  if (_ingredientsImage case final image?)
                    TextButton.icon(
                      onPressed: () => showPhoto(context, image),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('See that photo'),
                    ),
                ],
              ),
              ListenableBuilder(
                listenable: _ingredients,
                builder: (context, _) => _Allergens(_ingredients.text),
              ),
            ],
            if (widget.newProduct) ...[
              const SizedBox(height: 28),
              Text('Product', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                validator: (t) => t == null || t.trim().isEmpty ? 'Add a name' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white, // product photos sit on white in both themes
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: _cutting
                        ? const Center(
                            child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                        : _photo == null
                            ? Icon(Icons.image_outlined, color: muted)
                            : Image.file(File(_photo!), fit: BoxFit.contain),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Photo', style: text.bodyLarge),
                        Text('Morsel cuts the product out onto white.',
                            style: text.bodySmall?.copyWith(color: muted)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _cutting ? null : _addPhoto,
                              icon: const Icon(Icons.add_a_photo_outlined),
                              label: Text(_photo == null ? 'Add photo' : 'Change'),
                            ),
                            if (_photo != null && !_cutting)
                              TextButton(
                                onPressed: () => setState(() => _photo = null),
                                child: const Text('Remove'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _reading || _readingList || _cutting || _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('Save'),
            ),
            const SizedBox(height: 8),
            Text('Saved only on this phone.',
                textAlign: TextAlign.center, style: text.bodySmall?.copyWith(color: muted)),
          ],
        ),
      ),
    );
  }
}

/// A field per nutrient in [nutrientFields], right-aligned with its unit, the
/// sub-rows indented as on the label.
class NutrientFields extends StatelessWidget {
  const NutrientFields({super.key, required this.controllers, this.enabled = true});

  /// By nutrient id.
  final Map<String, TextEditingController> controllers;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            for (final (id, label, unit, sub) in nutrientFields)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: sub ? 16 : 0),
                        // The field carries the name for screen readers.
                        child: ExcludeSemantics(child: Text(label, style: text.bodyLarge)),
                      ),
                    ),
                    SizedBox(
                      width: 136,
                      child: Semantics(
                        label: label,
                        child: TextFormField(
                          controller: controllers[id],
                          enabled: enabled,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                          textAlign: TextAlign.end,
                          style: text.bodyLarge?.copyWith(fontFeatures: tabular),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '—',
                            suffixText: unit,
                            border: const OutlineInputBorder(),
                          ),
                          validator: (t) => checkNutrient(t, unit),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The allergens the ingredient list names, as the user checks and corrects
/// it. Facts, not verdicts, so neutral (docs/DESIGN.md, UX rule 5).
class _Allergens extends StatelessWidget {
  const _Allergens(this.ingredients);

  final String ingredients;

  @override
  Widget build(BuildContext context) {
    if (ingredients.trim().isEmpty) return const SizedBox.shrink();
    final found = allergenTags(ingredients);
    String names(List<String> tags) => tags.map((t) => t.substring(3).replaceAll('-', ' ')).join(', ');
    final sentence = [
      if (found.contains.isNotEmpty) 'Contains ${names(found.contains)}.',
      if (found.traces.isNotEmpty) 'May contain ${names(found.traces)}.',
    ];
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            sentence.isEmpty ? 'No allergens named in this list.' : 'Allergens: ${sentence.join(' ')}',
            style: text.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.cameraLabel, required this.cameraIcon});

  final String cameraLabel;
  final IconData cameraIcon;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(cameraIcon),
            title: Text(cameraLabel),
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose a photo'),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
