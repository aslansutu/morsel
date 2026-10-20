# Morsel — roadmap

The owner decides what's built next; nothing below "Next" is approved until they say so.

## Done

- **UI v1** — floating dock (History · Scan · Settings), opens on the scanner; product page
  with scores, highlights, nutrient meters, ingredients and Open Food Facts' knowledge panels;
  history on the device with undo; settings for country and "Remember scans".
- **Brand** — logo A2 (a barcode with eyes looking down), app icons on every platform, plum &
  oat palette (docs/DESIGN.md).
- **Label reading, step 1** (2026-10-18) — *Read the label* on products Open Food Facts doesn't
  know or has no nutrition for: the phone's document scanner or a photo, on-device text
  recognition, `lib/label_parser.dart`, a review form, saved on the phone; a product photo
  cut out onto white. Nutrition table only, no ingredients. How well it reads:
  docs/ARCHITECTURE.md. Verified on the iOS simulator end to end; on the S22 it's installed
  but its device test hasn't been run.
- **Label reading, step 2: ingredients and allergens** (2026-10-19), asked for as "lets go
  onto step 2 where we learn how to add the ingredients as well". The first cut is the one
  without a download: text recognition alone. The ingredient list comes from the label photo
  when it's there, or from another photo (*Read from another photo*), into the review form for
  the user to correct. Allergens are the EU's 14, found by their words in the list (Turkish,
  English and six more languages), with *may contain* kept apart. Offered wherever Open Food
  Facts has no ingredient list (*Read the ingredients* replaces that dead end). The product
  page shows the list with allergens in bold, and allergen chips. How well it reads:
  docs/ARCHITECTURE.md. Verified on the iOS simulator end to end (a list read from a
  second photo, saved and shown) and on its text recognition of all 39 corpus photos; the
  S22 hasn't run the device test.
- **Git and GitHub** (2026-10-20) — first commit, pushed to the public repo
  [aslansutu/morsel](https://github.com/aslansutu/morsel) on `main`. Licence: PolyForm
  Noncommercial 1.0.0 (`LICENSE.md`), asked for as "ok with people taking the code, forking it
  and playing around with it [...] I dont think I want it to be distributed to other people or
  sold". No standard licence allows changes but bans sharing: Noncommercial bans commercial use
  and allows free sharing; PolyForm Strict bans sharing but also bans changes. The owner chose
  Noncommercial. Commits use atakan16@gmail.com, set in this repo's git config, since the Mac's
  global identity is the work address. From here: one commit per finished piece of work, and a
  tag per version once the starting version is picked. Open Food Facts credentials, once there
  are any, never go in the repo.

## Next: the on-device model (the rest of step 2), blocked on a decision

The plan from 2026-10-18: an optional *Label reader* download in Settings, Gemma 4 E2B
through `flutter_gemma` (LiteRT-LM), on both phones, Wi-Fi only, for what rules can't
read. Text recognition stays: numbers the model returns must appear in the recognised
text, or the field is flagged.

What it would fix, measured on the ingredient corpus: the 2 lists of 31 without a readable
heading (read nothing), lists from creased, glary or curved packs (62–90 % alike), and 14 of 121
allergens lost to misreads ("pearurs" for peanuts, "yemistığı" for yerfıstığı).

**Blocked by this repo's rules** (measured 2026-10-19): `flutter_gemma` 1.11.4 (2026-10-05)
depends on `path_provider` and on native build hooks (`hooks`, `code_assets`). Both are
banned in CLAUDE.md: path_provider brings JNI on Android and an FFI build hook on iOS, and
FFI build hooks fail while `xcode-select` points at the Command Line Tools. The owner's call:

- Point `xcode-select` at Xcode, then test whether JNI still crashes release builds (the
  `shared_preferences_android` crash was R8 renaming Kotlin types; keep rules may fix it).
  If both hold, `flutter_gemma` can come in as it is.
- Or run LiteRT-LM directly through the `morsel/vision` channel: Kotlin on Android; what
  iOS offers for LiteRT-LM is not checked yet.

Facts gathered on 2026-10-18. Re-check them before relying on them; this area moves monthly.

- Gemma 4 E2B: a 2.58 GB `.litertlm` file (E4B: 3.65 GB), Apache 2.0. Google measured E2B
  on an iPhone 17 Pro's GPU at ~56 tokens/s, first token in 0.3 s; nothing published for the S22.
  ([Google AI Edge](https://developers.google.com/edge/litert-lm/models/gemma-4))
- `flutter_gemma` documents Gemma 4 image input on Android, iOS and the web.
  ([pub.dev](https://pub.dev/documentation/flutter_gemma/))
- Apple's Foundation Models take images from iOS 27, on iPhone 15 Pro and every iPhone 16 or
  later, with no download; there's no Flutter plugin, so it would need a Swift channel.
  ([WWDC26 session 237](https://developer.apple.com/videos/play/wwdc2026/237/))
- The Galaxy S22 Ultra isn't on Google's Gemini Nano (ML Kit GenAI) device list, so on the
  owner's phone Gemma is the only on-device model. ([ML Kit GenAI](https://developers.google.com/ml-kit/genai))
- A 2.6 GB model in the iOS simulator would take most of the Mac's free disk: test on the S22
  first, where the model lands on the phone.

## Later

- **Step 3** — on iPhones with Apple Intelligence, Apple's built-in model instead of the download.
- **Upload** what was read, once the owner picks where to. Open Food Facts researched below.

Asked for on 2026-10-19, not started:

- **A version number, shown in Settings.** Two versions disagree today: `pubspec.yaml` says
  `1.0.0+1` (Flutter's default) and the Open Food Facts User-Agent hard-codes `Morsel/0.1.0`
  (`lib/off_client.dart`). Make `pubspec.yaml` the one source: Android and iOS already take
  their version from it, and the app reads it at runtime for Settings and the User-Agent. The
  usual place on both platforms: an *About Morsel* row at the bottom of Settings showing
  "Version 0.3.0 (4)", opening an About page with the logo, version and build, the Open Food
  Facts credit (today the Settings footer) and Flutter's built-in open-source licences page
  (`showLicensePage`). Reading the version: `package_info_plus` is the usual plugin but brings
  `ffi` and `win32`, so within this repo's rules the `morsel/vision` channel returns it (iOS
  `CFBundleShortVersionString`/`CFBundleVersion`, Android `versionName`/`versionCode`) and the
  web build reads the `version.json` that `flutter build web` writes. The build number goes up
  on every build that lands on a phone: Android refuses `adb install -r` over a higher
  `versionCode`. Each *Done* entry gets the version it shipped in.
- **Enlarge photos.** Tap a product photo to see it full screen, pinch to zoom. The review form
  already does this for label photos (`showPhoto` in `lib/label_screen.dart`); the product
  page's 88 px photo, whether from Open Food Facts or a saved label, doesn't. Enlarged, load
  the full-size Open Food Facts photo, not the 400 px one the page shows: same URL ending in
  `.full.jpg` instead of `.400.jpg` (checked 2026-10-19 on 3017620422003: 33 KB vs 257 KB).
  History rows stay as they are: the row already opens the product, and a second tap target
  inside a 48 px thumbnail would fight it. Open question: also show the ingredients and
  nutrition photos Open Food Facts has, which is how to check its data against the pack.

## Contributing to Open Food Facts (researched 2026-10-19, not started)

Asked for: adding products it doesn't have, adding missing information to products it has,
and updating what's there, such as the photo. From the API docs and the v3 OpenAPI spec on
2026-10-19. The v3 write API is marked "still under development": re-check before building.

Morsel already does the hard half. *Read the label* and *Read the ingredients* appear exactly
where Open Food Facts lacks data, read the user's own photos and keep the result on the phone.
Contributing is one more step: *Send to Open Food Facts* on a saved label.

**The three cases**, all against the staging server `world.openfoodfacts.net` until proven:

- *A product it doesn't have.* `POST /api/v3/product/{code}/images` with a photo (base64;
  JPEG, PNG, GIF or HEIC, at least 640×160 px) creates the product, and the same call can
  select the photo as the `front`, `ingredients` or `nutrition` photo for a language, with an
  optional crop. Then `PATCH /api/v3/product/{code}` with the name, quantity, language,
  ingredient text and categories. Nutrition values aren't in v3's write schema yet (v3.5 is
  reworking nutrition), so they go through the v2 form endpoint `POST /cgi/product_jqm2.pl`:
  `nutriment_<name>` and `nutriment_<name>_unit`, `nutrition_data_per=100g` or `serving`,
  `serving_size`, `no_nutrition_data=on` when the pack has none.
- *Missing information on a product it has.* Send only the fields that are empty, which Morsel
  already knows: they're what makes it offer *Read the label*. Never send back a field the user
  hasn't seen: in v2 a tag field without the `add_` prefix replaces what's there
  (`add_categories` appends), and in v3 `packagings` replaces while `packagings_add` merges.
- *A newer photo.* Upload it and select it in the same call. An upload alone isn't shown when a
  photo is already selected for that field. Selecting is non-destructive: the old photo stays
  in the product's history.

Photos alone help: Open Food Facts reads every upload with OCR, and its Robotoff bot proposes
ingredients, nutrition, brands and categories from them for people to confirm.

**Rules that come with writing:**

- Accounts: a username (never the email) and password on each write, or a session cookie that
  only works from one IP, which a phone doesn't keep. No OAuth yet (the docs say "in the
  future"). Staging and production have separate accounts; staging also needs basic auth
  `off`/`off`.
- Apps send `app_name`, `app_version` and `app_uuid` (a salted random id per user, so
  moderators can block one user without blocking the app), a User-Agent of the form
  `Morsel/<version> (<contact email>)`, and register on Open Food Facts' API usage form.
- Queue writes on the phone and drop them only when the server confirms; retry with backoff on
  network errors, 429 and 5xx, never on other 4xx. Writes have no rate limit; product reads
  are 15 a minute per IP.
- Photos are published under CC BY-SA and data under ODbL, and edits are public under the
  account's name. Only photos the user took, which Morsel's are.
- `PATCH /api/v3/product/test` checks a write without saving it: the first test for the flow.

**What it changes here.** CLAUDE.md's "nothing leaves the phone except Open Food Facts
lookups" gains "and what the user chooses to send": per label, never automatic, showing exactly
what goes. The password belongs in the iOS Keychain and Android Keystore through the app's own
channel, not in `shared_preferences`. The official Dart package `openfoodfacts` (3.31.0;
depends on `http`, `json_annotation`, `meta`, `path`; saves products, uploads and crops photos)
passes the no-JNI/FFI rule, but three calls also fit in `lib/off_client.dart` beside the reads.

Sources: [API introduction](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/),
[adding missing products](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/tutorials/adding-missing-products/),
[uploading photos](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/tutorial-uploading-photo-to-a-product/),
[v3 OpenAPI spec](https://github.com/openfoodfacts/openfoodfacts-server/blob/main/docs/api/ref/api-v3.yaml),
[API change log](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/ref-api-and-product-schema-change-log/).

## Decisions waiting on the owner

- Where uploads go: Open Food Facts (public and open-licensed, needs an account; writes go to
  the staging server `world.openfoodfacts.net` until the flow is proven) or a private store.
- What the web companion is for: history, editing, label upload from a desktop?
- A contact email in the Open Food Facts User-Agent (`Morsel/<version>` for now).
- Whose account sends to Open Food Facts: the owner's own (the only user today; edits are
  credited to them and no shared password ships in the app), or one Morsel account with an
  `app_uuid` per install (no sign-in for users, but its password is inside the app).
- The version to start from. Proposed: 0.3.0, one minor version per *Done* milestone so far.
- Proposed and not approved: more sources when Open Food Facts has nothing (Open Beauty
  Facts / Open Products Facts, then USDA for the US); Open Prices; Türkiye's adulteration list.
