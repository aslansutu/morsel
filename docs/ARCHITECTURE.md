# Morsel — architecture

Scan a food barcode → see how healthy it is. Photograph a nutrition label → extract the
numbers on-device → send them to Open Food Facts if you like. iOS, Android and a web companion.

## One Flutter codebase

```
lib/            shared Dart: UI, Open Food Facts client, health summary, (later) model runner
android/ ios/   platform shells; Swift/Kotlin platform channels go here when a native API
web/            beats the cross-platform one (e.g. Apple Foundation Models, Gemini Nano)
```

Why one codebase instead of three native apps: every listed capability has a mature
cross-platform package, and the exceptions plug in as platform channels inside this repo.
Three native apps would build and test every feature three times.

| Capability            | Package                       | Android      | iOS          | Web         |
|-----------------------|-------------------------------|--------------|--------------|-------------|
| Barcode scanning      | `mobile_scanner`              | ML Kit       | Apple Vision | ZXing (JS)  |
| Product data          | Open Food Facts API v2        | ✓            | ✓            | ✓ (CORS `*`) |
| On-device LLM (later) | `flutter_gemma` (LiteRT-LM), blocked: ROADMAP | Gemma 4 / 3n | Gemma 4 / 3n | WebGPU |
| Label scan, OCR, cut-out | own `morsel/vision` channel | ML Kit       | Apple Vision + VisionKit | — |
| Photo picking         | `image_picker`                | ✓            | ✓            | —           |
| Sending to Open Food Facts | API v3 photo upload, v2 edit form | ✓      | ✓            | —           |
| Password storage      | own `morsel/vision` channel   | Keystore     | Keychain     | —           |
| Settings + history    | `shared_preferences`          | ✓            | ✓            | ✓           |
| Panel HTML            | `flutter_widget_from_html_core` | ✓          | ✓            | ✓           |

UI, palette and UX rules: [DESIGN.md](DESIGN.md).

## Data flow

**Barcode** — camera → EAN/UPC → `GET world.openfoodfacts.org/api/v2/product/{code}`
with `lc` (app language) and `cc` (Settings → Country) → one response carries the scores,
nutrients, ingredient analysis, allergens, additives and the **knowledge panels** —
Open Food Facts' own localized explanations, which the Ingredients and Details sections
render directly instead of re-deriving them.

**Nutrition label** — offered when Open Food Facts doesn't know a barcode, or knows it
without nutrition facts. The system document scanner (VisionKit; ML Kit's, which also
imports from the gallery) or a photo → the phone's text recognition (Apple Vision; ML
Kit's Latin model from Google Play services, downloaded on first use: bundled, it tripled
the APK to 103 MB) → `lib/label_parser.dart` rebuilds the
table rows from the line boxes and reads the per 100 g column (English, Turkish, German,
French, Spanish, Italian, Dutch) → the user checks every value against the photo → saved
on the device. A product photo is cut out onto white (Vision's foreground mask, iOS 17+;
ML Kit subject segmentation, downloaded by Google Play services on first use). Later:
Gemma 4 for messy labels, then upload.

How well it reads, measured on 24 Open Food Facts label photos (`test/fixtures/labels`,
scored by `test/label_corpus_test.dart` per recogniser, values checked against each photo):
Apple Vision as the iOS app asks for it, on a Mac, reads 116 of 147 values right and 2
wrong; most of the rest were never recognised. The iOS simulator's Vision reads worse
(60 of 76, 3 wrong). What it took:

- Vision's accurate mode skips short numbers alone in a cell ("25", "0,2"), whatever the
  settings; a second, fast pass fills in where accurate found nothing.
- Lines are levelled by their median slope before rows are rebuilt, and number cells join
  the nearest row: photos are taken at an angle and values rarely sit level with names.
- The per 100 g column is the one under a "100 g" heading (not "%RI per 100 g"); without
  a readable heading, the ratio between two columns and the portion size decide. Turkish
  labels often print per portion first.
- Names in several languages run over several lines, sometimes with the value on the
  last; a block's extra value moves up to the empty name above it.
- Misreadings worth handling: "(g)" as "(0)", "0 g" as "09", "0,2" as "02", "Yağ" as
  "vag", unit lists like "(г/g/q/გ)" as "8", Georgian as digit strings.

**Ingredient list** — offered when Open Food Facts has no ingredient list for a product, in
the same review form. The label photo is read once, for the table and the list; a list
printed elsewhere on the pack comes from another photo. `lib/ingredients.dart` finds the
list after its heading, in the app's language when the label has several, and follows the
paragraph down its column until the label moves on. Allergens are words matched in the
list the user checked, so they follow every correction, and they feed the same allergen
chips as Open Food Facts' tags.

How well ingredient lists read, on 39 Open Food Facts ingredient photos, mostly whole
backs of packs (`test/fixtures/ingredients`, scored by `test/ingredient_corpus_test.dart`):
with Apple Vision on a Mac, 24 of 31 lists come out at least 90 % alike to the label, 5
more roughly (a creased wrapper, glare, a curved cup), none wrong, and 2 not at all (no
heading text recognition can read). The 8 photos without a list read nothing, as they
should. Of the 121 allergens the lists name, 107 are found and none invented; the misses
are misread words. The iOS simulator's Vision: 23 close, 5 rough, 1 wrong (a cheese label
it reads as noise), 2 missed; 104 allergens found, none invented. What it took:

- The heading is the anchor: "İçindekiler", "Ingredients", "Zutaten" and seven more,
  allowing misreadings ("Içindokller:", "(indekler:") only with their colon. An English
  "ingredients" inside a sentence ("see ingredients in bold") is no heading.
- Turkish packs print the list in two or more languages, then each allergen warning. The
  English list is read (the app is in English), without the Turkish "may contain".
- The list ends at the sentence that moves on: storage, dates, origin, the maker,
  nutrition, "no pork", the next language ("EN Milk Chocolate, Ingredients: …"), or
  Arabic text.
- Lines overlap in tightly cropped photos, so a row is only lines side by side; a column
  beside the list ("Net 500 g", "Made in Turkey", a nutrition table) stays out unless it
  says what the food may contain.
- Allergens: Turkish suffixes ("fındığı", "sütlü"); coconut, cocoa butter, nutmeg and
  plant milks aren't; peanuts ("yer fıstığı", "fıstık ezmesi") aren't tree nuts ("Antep
  fıstığı"); "glutensiz", "gluten-free" and "içermez" don't count; ammonia caramel isn't a
  sulphite. On 90 more Turkish ingredient texts from Open Food Facts, every disagreement
  with its allergen tags was Open Food Facts' own (milk left untagged, "may contain" tagged
  as contains) except one, now fixed: allergens written "_süt_".

`morsel/vision` is a small channel in `ios/Runner/AppDelegate.swift` and
`android/…/LabelVision.kt` rather than the `google_mlkit_*` plugins: on iOS those pull
Google's ML Kit pods through CocoaPods, while Apple's Vision is built in and this project
resolves iOS plugins through Swift Package Manager. The same channel tells Dart where the
app's own folder is, so Morsel doesn't need path_provider, whose current platform
packages bring JNI on Android (the family behind the shared_preferences_android crash)
and an FFI build step on iOS that fails while `xcode-select` points at the Command Line
Tools.

**Sending to Open Food Facts** — on the product page, *Send to Open Food Facts* (where a saved
label fills something in) or *Improve on Open Food Facts* (anything else) opens one form,
`lib/contribute_screen.dart`: three photo slots (front, ingredients, nutrition), name, brand,
quantity, the nutrition table and the ingredient list with its language. It starts from what Open
Food Facts has, the label filling the gaps, and the label's photos come along where they back up
what it fills in. Only what differs from Open Food Facts is sent, and the form says what that is
and whose name it goes under before anything goes. `lib/contributions.dart` keeps it on the phone
until Open Food Facts confirms it: photos first, then the fields, each step marked done so a retry
never sends a photo twice; network errors, 429 and 5xx retry with backoff (30 s doubling to
30 min, eight tries, then *Try again*); any other answer is shown and not retried.

What goes, and how (checked against the live API spec and the staging server on 2026-10-25):

- Photos: `POST /api/v3/product/{code}/images`, base64, with `selected` naming each field and
  its language. One upload per file: the label photo can be both the nutrition and the
  ingredients photo, and Open Food Facts refuses an image it already has. The upload creates
  the product if needed; the old photo stays in the product's history. Before sending, the
  phone redraws each photo upright at up to 2400 px (`forUpload`), so none of the original's
  metadata goes: no location, camera or date. Android's encoder writes no EXIF at all; iOS's
  writes a fresh one with only orientation, resolution, colour space and pixel size (read back
  from the simulator on 2026-10-25).
- Fields: `POST /cgi/product_jqm2.pl`, the v2 edit form, the one write that takes nutrition
  (v3.5 reworks nutrition and is still unfinished). Name to the field the page shows it from
  (`product_name_en`, else `product_name_<lang>`); `add_brands` where Open Food Facts has no
  brand, `brands` only to replace a list the user has seen; `quantity`;
  `ingredients_text_<language>`, the language from the list's heading; `lang` for a new
  product. Nutrition goes as the whole table the form shows, `nutriment_<id>` with its unit and
  `nutrition_data_per` `100g` or `100ml`, whenever any value in it changed. The server keeps
  each basis as its own input set, so per-100 g values don't mix with a product's per-serving
  ones, and an empty value clears a nutrient.
- Every write: `user_id` and `password` (the username, never the email), `app_name`,
  `app_version`, a `comment` saying what was sent, and with the shared account an `app_uuid`
  (random, made once per install) so moderators can block one person without blocking Morsel.
- Answers: wrong credentials are HTTP 403 (HTML from v2, JSON from v3); v2 says
  `{"status": 0, "status_verbose": …}` with HTTP 200, v3 `"status": "failure"`. Sign-in is
  checked with `POST /cgi/session.pl` (200, or 403).

Accounts: the user's own, signed in under Settings → Open Food Facts (password in the iOS
Keychain, or encrypted with an Android Keystore key, through `morsel/vision`); otherwise
Morsel's shared account from `--dart-define-from-file`. A build without one asks people to sign
in. Not on the web: no camera, no secure storage.

**Storage** — no backend yet. Open Food Facts is the product database. Settings and the
scan history (newest first, capped at 200, one row per barcode) live in
`shared_preferences` on the device; so do the labels the user saved, with their photos in
the app's support folder (`LabelStore`). A label fills in only what Open Food Facts lacks:
nutrition facts, the ingredient list. A backend is added only when the web companion needs to sync history.

## Open Food Facts API facts (measured 2026-10-18)

- Send a `User-Agent: Morsel/<version>` — OFF asks API clients to identify themselves and
  recommends adding a contact email in parentheses (not set yet; your call which address).
  Browsers refuse to set the header, so the web build skips it.
- `access-control-allow-origin: *` — the web build calls the API directly, no proxy.
- Not found is two shapes, neither an error: missing product = **HTTP 404** + `status: 0`;
  invalid code = **HTTP 200** + `status: 0`. Branch on `status`, not on the HTTP code.
- Knowledge panels: 56 for Nutella, ~49 KB, translated per `lc` (Turkish exists). Text is
  HTML; allergens are pre-marked `<span class="allergen">`.
- `cc` (country) on a product lookup changes only the country-site host in links and the
  category comparison in the nutrition table. Country matters more for sources added
  later: USDA (US only), Open Prices, Türkiye's adulteration list.
- Names: prefer `product_name_<lc>` — Cristaline water's main `product_name` is "isabelle".
- The Green-Score grade is still in `ecoscore_grade`; drinks are `en:beverages` in
  `categories_tags`, and their nutrient thresholds are halved.
- The old search endpoint (`/api/v2/search`) returned 503 while product lookups worked;
  don't build features on it. search.openfoodfacts.org answered.
- Writes go to the staging server `world.openfoodfacts.net` until the flow is proven
  (`offWriteHost`). Staging has its own accounts and wants basic auth `off`/`off` on every
  request. Production edits are public and immediately visible. Reads stay on production,
  so what's sent to staging never shows on the product page.

## Open questions

In [ROADMAP.md](ROADMAP.md), with what's next.
