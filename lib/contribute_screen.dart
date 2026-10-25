import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'contributions.dart';
import 'format.dart';
import 'label_screen.dart';
import 'labels.dart';
import 'off_client.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'vision.dart';

/// The languages Morsel reads ingredient headings in.
const _languages = {
  'en': 'English',
  'tr': 'Turkish',
  'de': 'German',
  'fr': 'French',
  'es': 'Spanish',
  'it': 'Italian',
  'nl': 'Dutch',
  'pl': 'Polish',
  'ro': 'Romanian',
  'az': 'Azerbaijani',
  'ru': 'Russian',
};

/// The product's photos Morsel sends, by Open Food Facts' field name.
const _photoFields = [('front', 'Front'), ('ingredients', 'Ingredients'), ('nutrition', 'Nutrition')];

double? _amount(Object? v) => v is num ? v.toDouble() : double.tryParse('$v');

/// What the user sends Open Food Facts about one product: newer photos, and
/// the fields they fill in or correct. The form starts from what Open Food Facts
/// has, the saved label filling its gaps, and only what differs is sent; the
/// page says what that is, and whose name it goes under, before anything goes.
class ContributeScreen extends StatefulWidget {
  const ContributeScreen({
    super.key,
    required this.code,
    required this.product,
    required this.queue,
    required this.labels,
    this.label,
    this.vision = const Vision(),
  });

  final String code;

  /// The product as Open Food Facts has it; null when it doesn't.
  final Map<String, dynamic>? product;
  final ContributionQueue queue;
  final LabelStore labels;

  /// The user's saved label, for what Open Food Facts lacks.
  final LabelEntry? label;
  final Vision vision;

  @override
  State<ContributeScreen> createState() => _ContributeScreenState();
}

class _ContributeScreenState extends State<ContributeScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, dynamic> _off = widget.product ?? const {};
  late final LabelEntry? _label = widget.label;

  // What Open Food Facts has; '' or absent where it has nothing.
  late final _offName = productName(_off) ?? '';
  late final _offBrand = (_off['brands'] as String?) ?? '';
  late final _offQuantity = (_off['quantity'] as String?) ?? '';
  late final _localList = (_off['ingredients_text_$appLanguage'] as String?) ?? '';
  late final _offList = _localList.isNotEmpty ? _localList : (_off['ingredients_text'] as String?) ?? '';
  late final _offValues = {
    for (final (id, _, _, _) in nutrientFields) id: ?_amount(((_off['nutriments'] as Map?) ?? {})['${id}_100g']),
  };

  /// The pack's main language, for the name and the photos.
  late final String _packLanguage = (_off['lang'] as String?) ?? _label?.ingredientsLanguage ?? appLanguage;
  late final _offListLanguage = _localList.isNotEmpty ? appLanguage : _packLanguage;

  /// The name goes back to the field the product page shows it from.
  late final _nameKey = ((_off['product_name_$appLanguage'] as String?) ?? '').isNotEmpty
      ? 'product_name_$appLanguage'
      : 'product_name_$_packLanguage';

  late final _name = TextEditingController(text: _offName.isNotEmpty ? _offName : _label?.name);
  late final _brand = TextEditingController(text: _offBrand);
  late final _quantity = TextEditingController(text: _offQuantity);
  late final _list = TextEditingController(text: _offList.isNotEmpty ? _offList : _label?.ingredients);
  late var _listLanguage = _offList.isNotEmpty ? _offListLanguage : _label?.ingredientsLanguage ?? _packLanguage;
  late final _values = {
    for (final (id, _, _, _) in nutrientFields)
      id: TextEditingController(
          text: switch (_offValues[id] ?? _label?.values[id]) { final v? => plainAmount(v), null => '' }),
  };

  /// Open Food Facts' basis where it has one; else the label's, or whether it's a drink.
  late final bool _perMl = switch (_off['nutrition_data_per']) {
    '100ml' => true,
    '100g' => false,
    _ => _label?.perMl ?? ((_off['categories_tags'] as List?) ?? []).contains('en:beverages'),
  };

  /// New photos to send, by field. The label's photos come along where they
  /// back up what the label fills in, so others can check it against the pack.
  late final Map<String, String?> _photos = {
    'front': _off['image_front_url'] == null ? widget.labels.productPhoto(widget.code)?.path : null,
    'ingredients': _label?.ingredients != null && _offList.isEmpty
        ? (widget.labels.ingredientsPhoto(widget.code) ??
                // A list with a language was read from a photo: the label's, when it has none of its own.
                (_label?.ingredientsLanguage != null ? widget.labels.labelPhoto(widget.code) : null))
            ?.path
        : null,
    'nutrition': _label != null && _label.values.isNotEmpty && _offValues.isEmpty
        ? widget.labels.labelPhoto(widget.code)?.path
        : null,
  };
  var _sending = false;

  @override
  void dispose() {
    for (final c in [_name, _brand, _quantity, _list, ..._values.values]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _nutritionChanged => nutrientFields.any((f) => parseAmount(_values[f.$1]!.text) != _offValues[f.$1]);

  /// The product edit form's fields: what differs from Open Food Facts. Text is
  /// only added or corrected, never emptied; a nutrient can be emptied, since an
  /// empty value beats a wrong one.
  Map<String, String> get _fields {
    final name = _name.text.trim();
    final brand = _brand.text.trim();
    final quantity = _quantity.text.trim();
    final list = _list.text.trim();
    return {
      if (name.isNotEmpty && name != _offName) _nameKey: name,
      // Open Food Facts asks for add_brands beside none, and a whole list only
      // when the user has seen the old one, as here.
      if (brand.isNotEmpty && brand != _offBrand) _offBrand.isEmpty ? 'add_brands' : 'brands': brand,
      if (quantity.isNotEmpty && quantity != _offQuantity) 'quantity': quantity,
      if (list.isNotEmpty && (list != _offList || _listLanguage != _offListLanguage))
        'ingredients_text_$_listLanguage': list,
      if (widget.product == null && list.isNotEmpty) 'lang': _listLanguage,
      // The whole table the user saw, so the values Open Food Facts keeps for
      // this basis are all from the same pack.
      if (_nutritionChanged) ...{
        'nutrition_data_per': _perMl ? '100ml' : '100g',
        for (final (id, _, unit, _) in nutrientFields)
          if (parseAmount(_values[id]!.text) case final v?) ...{
            'nutriment_$id': plainAmount(v),
            'nutriment_${id}_unit': unit,
          } else if (_offValues.containsKey(id))
            'nutriment_$id': '',
      },
    };
  }

  /// One upload per file: the label photo can be both the nutrition and the
  /// ingredients photo, and Open Food Facts refuses the same image twice.
  List<({String path, Map<String, String> selected})> get _uploads {
    final byPath = <String, Map<String, String>>{};
    for (final MapEntry(key: field, value: path) in _photos.entries) {
      if (path != null) (byPath[path] ??= {})[field] = field == 'ingredients' ? _listLanguage : _packLanguage;
    }
    return [for (final MapEntry(key: path, value: selected) in byPath.entries) (path: path, selected: selected)];
  }

  /// What will be sent, in words; null when nothing would be.
  String? get _summary {
    final fields = _fields;
    final photos = _photos.values.whereType<String>().length;
    final parts = [
      if (photos > 0) photos == 1 ? 'a photo' : '$photos photos',
      if (fields.containsKey(_nameKey)) 'the name',
      if (fields.containsKey('brands') || fields.containsKey('add_brands')) 'the brand',
      if (fields.containsKey('quantity')) 'the quantity',
      if (fields.containsKey('nutrition_data_per')) 'the nutrition facts',
      if (fields.keys.any((k) => k.startsWith('ingredients_text_'))) 'the ingredient list',
    ];
    if (parts.isEmpty) return null;
    return parts.length == 1 ? parts.first : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }

  Future<void> _pick(String field) async {
    // Flat things read best from the document scanner; the front is a photo.
    final path = field == 'front'
        ? await pickPhoto(context, widget.vision)
        : await pickLabelImage(context, widget.vision);
    if (path != null && mounted) setState(() => _photos[field] = path);
  }

  Future<void> _signIn() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AccountScreen(account: widget.queue.account, client: widget.queue.client)));

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    final summary = _summary;
    if (summary == null) return;
    setState(() => _sending = true);
    try {
      await widget.queue.add(widget.code,
          fields: _fields, photos: _uploads, summary: summary, comment: 'Morsel: $summary');
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text("Couldn't get a photo ready to send: ${e.message}")));
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = MorselColors.of(context).inkMuted;
    final account = widget.queue.account;
    Widget heading(String title) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        );
    return Scaffold(
      appBar: AppBar(title: Text(widget.product == null ? 'Add to Open Food Facts' : 'Improve on Open Food Facts')),
      body: Form(
        key: _form,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.paddingOf(context).bottom),
          children: [
            Text(
              widget.product == null
                  ? "Open Food Facts doesn't have this product yet. Check what goes, then send it."
                  : "Fix what's wrong or missing, or add a newer photo. Only what you change is sent.",
              style: text.bodyMedium,
            ),
            const SizedBox(height: 24),
            heading('Photos'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, (field, label)) in _photoFields.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _PhotoSlot(
                      label: label,
                      photo: _photos[field],
                      url: _off['image_${field}_url'] as String?,
                      onPick: () => _pick(field),
                      onRemove: () => setState(() => _photos[field] = null),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 28),
            heading('Product'),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _brand,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Brand', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _quantity,
              decoration: const InputDecoration(labelText: 'Quantity', hintText: '500 g', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 28),
            heading(_perMl ? 'Per 100 ml' : 'Per 100 g'),
            NutrientFields(controllers: _values),
            const SizedBox(height: 28),
            heading('Ingredients'),
            Semantics(
              label: 'Ingredients',
              child: TextFormField(
                controller: _list,
                minLines: 3,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'As printed on the label', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Language of the list', style: text.bodyMedium)),
                DropdownButton<String>(
                  value: _listLanguage,
                  onChanged: (v) => setState(() => _listLanguage = v!),
                  items: [
                    for (final code in {..._languages.keys, _listLanguage})
                      DropdownMenuItem(value: code, child: Text(_languages[code] ?? code)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),
            ListenableBuilder(
              listenable: Listenable.merge([_name, _brand, _quantity, _list, ..._values.values, account]),
              builder: (context, _) {
                final summary = _summary;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      summary == null ? 'Change something above to send it.' : 'Sends $summary.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: !account.canSend ? _signIn : (summary == null || _sending ? null : _send),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      child: Text(account.canSend ? 'Send to Open Food Facts' : 'Sign in to send'),
                    ),
                    const SizedBox(height: 12),
                    if (account.user case final user?)
                      Text('Sent as $user.', style: text.bodySmall?.copyWith(color: muted))
                    else if (account.canSend)
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text("Sent through Morsel's account, not under your name. ",
                              style: text.bodySmall?.copyWith(color: muted)),
                          InkWell(
                            onTap: _signIn,
                            child: Text('Sign in to be credited',
                                style: text.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                    decoration: TextDecoration.underline)),
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Open Food Facts publishes it for anyone to use: data under the Open Database '
                      'License, photos under CC BY-SA. Send only photos you took.'
                      '${offWriteHost == 'world.openfoodfacts.net' ? " While Morsel is tested, it goes to Open Food Facts' test server." : ''}',
                      style: text.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the product's photos: the new one to send, or what Open Food Facts shows now.
class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.label,
    required this.photo,
    required this.url,
    required this.onPick,
    required this.onRemove,
  });

  final String label;

  /// The new photo's file.
  final String? photo;

  /// Open Food Facts' photo.
  final String? url;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = MorselColors.of(context).inkMuted;
    final placeholder = Icon(Icons.image_outlined, color: muted);
    final photo = this.photo;
    final url = this.url;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white, // product photos sit on white in both themes
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: photo != null
                ? Image.file(File(photo), fit: BoxFit.contain)
                : url != null
                    ? Image.network(url, fit: BoxFit.contain, errorBuilder: (_, _, _) => placeholder)
                    : placeholder,
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: text.bodyMedium),
        Text(
          photo != null ? 'New' : (url != null ? 'On Open Food Facts' : 'None yet'),
          style: text.bodySmall?.copyWith(color: muted),
        ),
        if (photo != null)
          TextButton(onPressed: onRemove, child: const Text('Remove'))
        else
          TextButton(onPressed: onPick, child: Text(url != null ? 'Replace' : 'Add')),
      ],
    );
  }
}

/// Where a contribution stands: sending, waiting, refused, or sent.
class ContributionStatus extends StatelessWidget {
  const ContributionStatus({super.key, required this.contribution, required this.onRetry});

  final Contribution contribution;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = contribution;
    final server = offWriteHost == 'world.openfoodfacts.net' ? "Open Food Facts' test server" : 'Open Food Facts';
    final gaveUp = c.attempts >= ContributionQueue.maxAttempts;
    final (icon, message, retry) = switch (c.state) {
      ContributionState.sent => (
          Icons.check_circle_outline,
          'Sent to $server on ${formatDate(c.sentAt!)}: ${c.summary}.',
          false
        ),
      ContributionState.refused => (Icons.error_outline, "Open Food Facts didn't take it: ${c.error}", true),
      ContributionState.waiting when c.error == null => (Icons.schedule, 'Sending to Open Food Facts…', false),
      ContributionState.waiting when gaveUp => (Icons.schedule, '${c.error}', true),
      ContributionState.waiting => (Icons.schedule, '${c.error} Morsel will try again.', false),
    };
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Neutral: green, amber and red are for food verdicts only.
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: text.bodyMedium),
              if (retry) TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ],
    );
  }
}
