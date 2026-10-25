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

- **Sending to Open Food Facts** (2026-10-25), asked for as "if there is a missing product or a
  just wrong or missing information or just an out dated picture, our app should be able to
  give OFF the data they need to keep their systems updated the way they want." The product page
  offers *Send to Open Food Facts* for what a saved label fills in, and *Improve on Open Food
  Facts* for corrections and newer photos: front, ingredients and nutrition photos, name, brand,
  quantity, nutrition per 100 g or 100 ml, the ingredient list in its language. Only what
  differs from Open Food Facts is sent, the way Open Food Facts asks apps to (docs/ARCHITECTURE.md):
  selected photos, `add_` for tags beside none, a queue that retries only what the server
  couldn't answer, app name, version and per-install id, photos without metadata. Accounts are
  the owner's hybrid: "A user can open their own account, if not they can also continue
  anonymous using a predefined morsel account." Sign-in is optional (Settings → Open Food
  Facts; the password in the Keychain or Keystore); otherwise Morsel's shared account, built in
  from a file outside git. Writes go to the staging server. Verified by unit and widget tests
  with Open Food Facts faked; not yet sent to staging from a phone (needs the shared account,
  below).

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

## Sending to Open Food Facts: what's left

Built on 2026-10-25 (see *Done*); how it works is in docs/ARCHITECTURE.md. Before it counts as
proven:

- **A staging account for Morsel's shared account** (owner): sign up at
  `https://world.openfoodfacts.net/cgi/user.pl`, put it in `off_account.json` (README.md, kept
  out of git) and in the KB vault, build with `--dart-define-from-file=off_account.json`. Until
  then a build can only send after the user signs in, with a staging account of their own.
- **Try it on a phone against staging**: a new product from a label, a correction, a newer
  photo, a wrong password, airplane mode then back. Two things the tests can't show: that an
  empty `selected` entry (`{"front": {"en": {}}}`) selects an upload uncropped, and that
  `product_jqm2.pl` takes the form URL-encoded (the spec says multipart; both reached the
  server's credential check on 2026-10-25).
- **Production** (owner's call): `offWriteHost` → `world.openfoodfacts.org`, a production
  account for Morsel's shared one (staging accounts don't carry over), and Open Food Facts' API
  usage form. Production edits are public at once. Then reads show what was sent: the label no
  longer fills in what Open Food Facts now has.

**Later, asked for as "keep the rest in the roadmap and plan it out in the future"** — what
Open Food Facts takes that Morsel doesn't send yet, most useful first:

1. **Categories.** A new product gets no Nutri-Score or Green-Score without one. A search field
   on OFF's `GET /api/v3/taxonomy_suggestions?tagtype=categories&string=…&lc=en` (the same
   suggestions as its website), sent as `add_categories` beside none, or as the whole list when
   the user has seen and edited Open Food Facts'. Needs the product's `categories` read too.
2. **Serving size, and nutrition per serving.** `serving_size`, and the table per serving where
   the pack has no per-100 g column (US labels): `nutrition_data_per=serving`. The label parser
   already knows when a label is per serving (`Basis.unknown`) and only warns today.
3. **"No nutrition facts on the pack"** (`no_nutrition_data=on`): fresh produce, water, spices.
   Today the page asks for a label that doesn't exist.
4. **Labels** (organic, fair trade, vegan; `add_labels`) and **origins**: both feed the
   Green-Score. Same search field as categories, `tagtype=labels`.
5. **A packaging photo** (the fourth `selected` field), and later the structured packaging
   (`packagings_add` in v3: shape, material, recycling), the rest of the Green-Score.
6. **Generic name** (`generic_name_<lang>`, the legal name: "hazelnut spread with cocoa"),
   **stores** and **countries where sold** (`add_stores`, `add_countries`, from Settings →
   Country).
7. **Robotoff's questions** (`/api/v1/questions/{code}` on robotoff.openfoodfacts.org): yes/no
   checks of what its AI read from photos, a quick way to help with no typing.

## Decisions waiting on the owner

- What the web companion is for: history, editing, label upload from a desktop?
- A contact email in the Open Food Facts User-Agent: "Leave it out for now" (2026-10-25), so
  `Morsel/<version>`. Open Food Facts asks for one; worth adding before production.
- When writes move from staging to production, and the production account for Morsel's
  shared one (above).
- The version to start from. Proposed: 0.3.0, one minor version per *Done* milestone so far.
- Proposed and not approved: more sources when Open Food Facts has nothing (Open Beauty
  Facts / Open Products Facts, then USDA for the US); Open Prices; Türkiye's adulteration list.
