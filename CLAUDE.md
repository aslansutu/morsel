# Morsel

Scan a food barcode and see how healthy it is; photograph a nutrition label and read it on
the phone. One Flutter codebase for iOS, Android and a web companion. Product data comes
from Open Food Facts; label reading runs on the phone. A personal project: the owner tests
on a Galaxy S22 Ultra and the iOS simulator, and decides what gets built next.

## Where to find things

| What | Where |
|---|---|
| What the app does, stack, data flow, Open Food Facts API facts, how label reading works and how well it reads | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Palette (plum & oat), status colours, contrast, UI rules, UX rules, every screen | [docs/DESIGN.md](docs/DESIGN.md); tokens in `lib/theme.dart` |
| Logo and app icons | docs/DESIGN.md "Brand", `tool/brand_icons.py`, `assets/brand/`; concepts in `docs/brand/` |
| Test rules, why each test exists, negative tests still to write | [docs/TESTING.md](docs/TESTING.md) |
| What's done, what's next, decisions waiting on the owner | [docs/ROADMAP.md](docs/ROADMAP.md) |
| Run and build commands | [README.md](README.md) |

## Code map

- `lib/main.dart` — app shell and the floating dock (History · Scan · Settings).
- `lib/scanner_screen.dart` — camera barcode scanning and the type-a-barcode sheet.
- `lib/off_client.dart` — Open Food Facts lookups; `lib/panels.dart` renders its knowledge panels.
- `lib/product_screen.dart` — the product page; fills in a saved label where Open Food Facts lacks nutrition or ingredients.
- `lib/history_screen.dart`, `lib/settings_screen.dart`, `lib/settings.dart` (Settings, History, ScanRecord).
- `lib/vision.dart` — the `morsel/vision` channel: document scanner, text recognition, subject
  cut-out, the app's folder, photos made ready to send (`forUpload`), `Secrets`. Native sides:
  `ios/Runner/AppDelegate.swift` (Apple Vision, VisionKit, Keychain),
  `android/app/src/main/kotlin/dev/atakanonol/morsel/LabelVision.kt` (ML Kit) and `Secrets.kt`
  (Keystore).
- `lib/label_parser.dart` — recognised text → nutrition values; `lib/ingredients.dart` —
  recognised text → the ingredient list, and the allergens a list names;
  `lib/label_screen.dart` — the review form; `lib/labels.dart` — LabelStore, saved labels on
  the device.
- `lib/contribute_screen.dart` — what goes to Open Food Facts, checked before it's sent;
  `lib/contributions.dart` — the queue that sends it; `lib/account.dart` — the user's own Open
  Food Facts account, signed in or created in the app (`SignUpScreen` in
  `lib/settings_screen.dart`). Writes go to the staging server (`offWriteHost` in
  `lib/off_client.dart`) until the owner says production. Sending without an account, through
  one Morsel account, is pending: docs/ROADMAP.md.
- `lib/brand.dart` (mascot, scan glyph), `lib/theme.dart`, `lib/format.dart`, `lib/countries.dart`.

## Rules

**Code**
- Hand-formatted at about 100 columns. Never run `dart format` on existing files: the project
  doesn't follow it and it rewrites every line. Match the code around you.
- UI and UX follow docs/DESIGN.md. The ones most easily broken: green, amber and red mean
  food verdicts only; never colour alone; every dead end has a next step; undo over "are you sure?".
- Private by default: nothing leaves the phone except Open Food Facts lookups and what the user
  chooses to send to Open Food Facts, shown before it goes. History and saved labels stay on the
  device. Photos are sent through `forUpload` (none of the original's metadata, so no location).
  The user's Open Food Facts password lives in the Keychain or Keystore, never in preferences.
- No secret ships in the app. Anything in the APK or IPA, a `--dart-define`, native resources or
  obfuscated code can be read in a teardown, and the repo is public. A credential the app would
  use on behalf of every user (a shared Open Food Facts account) lives on a server that adds it,
  never in the binary or the repo.
- Native features go through the `morsel/vision` channel, not plugins that need CocoaPods.
- No plugins built on JNI or FFI: `flutter pub deps --style=compact | grep -E '^- (objective_c|jni) '`
  must print nothing. JNI crashed Android release builds (why `shared_preferences_android`
  is pinned to 2.4.28), and FFI build hooks break the iOS build on this Mac (why there's no
  `path_provider`).

**Tests** — details in docs/TESTING.md
- `flutter analyze` clean and `flutter test` green before calling anything done.
- Every new test gets a line in docs/TESTING.md saying why it exists.
- After changing `lib/label_parser.dart`, `test/label_corpus_test.dart` must stay at ≥ 75 %
  right and ≤ 5 % wrong for every recogniser. An empty value beats a wrong one. After
  changing `lib/ingredients.dart`, `test/ingredient_corpus_test.dart` must pass: no list
  from elsewhere on the pack, no invented allergen.
- Device tests (`integration_test/`) launch the app, and the runner may uninstall it
  afterwards. On the owner's phone that wipes their history: ask first.

**Before pushing** the `off-contributions` work (or anything that writes to Open Food Facts):
create an Open Food Facts account on the server it writes to (staging today), sign in with it on
a phone, and send one of each case. docs/ROADMAP.md, "Sending to Open Food Facts: what's left".

**Build and run** — commands in README.md
- iOS: prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  (`xcode-select` still points at the Command Line Tools). Plugins resolve through Swift
  Package Manager.
- iOS simulator: "iPhone 17 Pro" on the iOS 26.5 runtime, UDID
  `CCCE5A39-ACE9-40D8-8298-27716F5CBB23` (the iOS 27.1 runtime and its "iPhone Duo" were removed
  on 2026-10-20 to free disk). Xcode 27's simulator app is DeviceHub. It has no camera, so no
  document scanner; Vision's cut-out failed on the iOS 27.1 simulator ("Could not create
  inference context"). Screenshots: `xcrun simctl io <udid> screenshot`.
- Don't run other `flutter` commands while an iOS build runs: they regenerate
  `ios/Flutter/ephemeral` and the build fails on missing files.
- Android: the owner's Galaxy S22 Ultra, adb id `R5CT60CS8KE`, over USB, or over wireless
  debugging when the owner turns it on (it connected on 2026-10-20; `adb mdns services` lists
  it). Build with `flutter build apk --release --target-platform android-arm64`,
  install with `adb install -r` (keeps data), and don't launch it over what the owner is doing.
- Android SDK: `/opt/homebrew/share/android-commandlinetools`, JDK 21, both set via `flutter config`.
- Web: `flutter build web --no-wasm-dry-run`.
- The Mac's disk is tight. After big builds, delete `build/app/intermediates`, `build/ios` and
  `~/Library/Developer/Xcode/DerivedData/Runner-*`; they regenerate.
