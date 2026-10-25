# Morsel — tests

## Rules

1. **Every test has a reason**, written in the table below. A test whose reason no one can
   state is noise; a new test gets its row here when it's written.
2. **Name a test as the behaviour it protects**, as a sentence: "a missing product is not an
   error", not "test404".
3. **`flutter test` needs no network and no device.** Open Food Facts is faked with
   `MockClient` and response shapes copied from real calls (dated in the file); the phone's
   camera and text recognition are faked by subclassing `Vision`.
4. **A fixed bug gets a test that failed before the fix**, with a comment saying what broke
   (the dock that once covered the whole screen).
5. **Label reading prefers empty to wrong.** An empty field costs the user some typing; a
   wrong one costs trust. The corpus test holds every recogniser to ≥ 75 % of values right
   and ≤ 5 % wrong. Ingredient lists: none from elsewhere on the pack, allergens never
   invented.
6. **Device tests** (`integration_test/`) need a phone or simulator and network. They launch
   the app, and the runner may uninstall it afterwards, so on the owner's phone ask first.
7. **Test what can go wrong, not only what should go right.** Negative tests still missing
   are listed at the end; take one when touching that code.

## Running

```sh
flutter analyze && flutter test        # everything that runs on the Mac (~5 s)
flutter test test/label_corpus_test.dart   # after any change to lib/label_parser.dart
flutter test test/ingredient_corpus_test.dart   # after any change to lib/ingredients.dart
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  flutter test integration_test/label_test.dart -d C7FFE678-DB2A-440F-B880-237C322CD1D1   # iOS simulator
```

## The label corpus

`test/fixtures/labels/<barcode>.json` holds 24 real nutrition label photos from Open Food
Facts — not the photos, only what text recognition read from them (`lines`, keyed by
recogniser) — and the values the photo shows (`truth`). Open Food Facts' own values were
wrong for 8 of them (another recipe, per serving, a front photo filed as the label); `note`
says what was corrected, and `skip` marks a photo with no readable table.

To add a recogniser's reading, run `integration_test/label_test.dart` on that device: it
prints `OCR <barcode> <lines as JSON>` for each label; store them under a new key
(`mlkit-android` for the S22). `vision-macos` comes from `tool/vision_ocr.swift`, the iOS
app's request run on a Mac. Check any new label's `truth` against its photo before trusting it.

## The ingredient corpus

`test/fixtures/ingredients/<barcode>.json` holds 39 Open Food Facts ingredient photos, most
of them whole backs of packs, as text recognition read them (`lines`, by recogniser). `truth`
is the list Morsel should read, checked against the photo (the English one when the label
has it); `contains` and `traces` the allergens it names. Open Food Facts' own text is often
another recipe, another language, or leaves out the "may contain" line; `note` says where
the truth was corrected to the photo. A null `truth` is a photo with no
list to read (sideways, cut off, the wrong side): reading nothing is right there.

To add a recogniser's reading, run `integration_test/label_test.dart` on that device: it
prints `INGREDIENTS <barcode> <lines as JSON>` for each photo. `vision-macos` comes from
`tool/vision_ocr.swift`; `vision-ios-simulator` from that test on the iOS 27.1 simulator.

## Every test and why

### test/widget_test.dart — Open Food Facts, product page, history, settings, dock

| Test | Why it's needed |
|---|---|
| returns the product when status is 1 | Every lookup depends on reading Open Food Facts' "found" answer. |
| a missing product (HTTP 404, status 0) is not an error | OFF answers an unknown barcode with HTTP 404. Taken as an error, the user would see "Couldn't reach Open Food Facts" instead of "Not in Open Food Facts yet" and its *Read the label* button. |
| server errors throw | A 5xx must reach the error screen with *Try again*, not pass as a missing product. |
| asks for the app language, the country and the knowledge panels | Dropping a query parameter fails silently: product text in another language, the wrong country, or empty Ingredients and Details sections. |
| shows scores, highlights, meters and ingredients | Guards every section of the product page at once, and the rule that every status has a word, not colour alone. |
| an unknown barcode says so | The not-found dead end needs a message, not an error or a blank page. |
| a repeat scan moves to the top instead of duplicating, and survives a restart | History is one row per barcode, newest first, kept across launches. |
| opening a scan records the lookup when remembering is on | History learns the product's name once it's looked up. |
| nothing is recorded when remembering is off | Privacy: "Remember scans" off must mean nothing is stored. |
| turning off "Remember scans" deletes history, and Undo brings it back | Turning history off forgets it (private by default), with undo instead of a confirmation (UX rule 10). |
| the country picker finds Türkiye by typing "turk" | People type without Turkish letters; search must ignore diacritics. |
| the dock switches between tabs | The app's only navigation. |
| the dock stays a compact bar, even at 2× text size | A stretching child once made the floating dock cover the whole screen; also keeps large system text usable. |
| formatting | Rounding (0.107 → 0.11), "Today/Yesterday", flags and diacritic folding are used on every screen. |

### test/label_parser_test.dart — reading a nutrition table from recognised text

| Test | Why it's needed |
|---|---|
| an English EU table: first column is per 100 g, %RI ignored | The standard EU layout; the reference-intake column must never be read as an amount. |
| a Turkish table: decimal commas, kJ/kcal pairs, capital İ | The owner's main market: "30,9", "2252/539" and "LİF", which lowercases to i plus a combining dot. |
| a German table skips unsaturated fats and reads Eiweiß | Unsaturated fats share words with saturated fat and must be skipped; ß needs its own fold. |
| a linear label in one paragraph, wrapped mid-value | Small packs print nutrition as a sentence; commas separate nutrients but also mark decimals. |
| a US label is per serving: basis unknown, sodium becomes salt | Per-serving values must trigger the form's warning; sodium in mg must become salt in g. |
| energy: kcal on the next line beats kJ, kJ alone is converted | Energy comes in four layouts; a kcal printed anywhere beats one worked out from kJ. |
| an ingredient list in the same photo does not leak into the table | "fat-reduced cocoa 7.4%" must not become the fat value. |
| misreads: o for 0, values over 100 g dropped, mg converted | Common recognition errors, and the rule that nothing has more than 100 g in 100 g. |
| a photo with no nutrition table reads nothing | The wrong photo must give an empty form, not invented values. |

### test/ingredients_test.dart — the ingredient list and its allergens

| Test | Why it's needed |
|---|---|
| reads the list after "İçindekiler:" up to the storage line | The owner's market's heading, and the list ending where the label moves on. |
| a bilingual label gives the English list, without the Turkish warning | Turkish packs print each list, then each warning; one language per screen. |
| a misread heading counts with its colon; "see ingredients in bold" is no heading | Recognition garbles the heading; UK labels say "ingredients" in a sentence. |
| another column beside the list stays out | "Net 500 g" and "Made in Turkey" sit beside lists, level with them. |
| beside a heading alone on a short line, the next column stays out | The iOS simulator read a cheese label's nutrition table into its list. |
| Arabic text ends the list: it is always another language | Turkish export packs end with an Arabic list, which joined the Turkish one. |
| a word broken at the end of a line joins up | "Stabi-" "liser" must read as one word. |
| a photo without a list heading, or with text running sideways, reads nothing | Empty beats text from the wrong part of the pack. |
| Turkish suffixes and capitals: FINDIĞI, sütlü, yumurtalı | Turkish adds endings to every allergen; the whole word is marked bold. |
| coconut, cocoa butter, nutmeg and plant milks are not allergens | Words that look like nuts or milk and aren't. |
| peanuts and tree nuts are told apart | "Yer fıstığı" and "Antep fıstığı" are different allergens. |
| "may contain" is a trace, also without a full stop before it | Labels run "may contain" on from the list, and recognition may keep only "traces of"; a Turkish verb ends a sentence. |
| "gluten-free", "laktozsuz" and "içermez" do not count | Saying an allergen is absent must not list it. |
| ammonia caramel and maltodextrin are not sulphites or gluten | E150d and maltodextrin contain the words, not the allergens. |
| a food that contains something is not also listed as may contain it | "Fındık… Eser miktarda fındık" is one allergen, contained. |
| allergens marked with underscores, as Open Food Facts writes them | "_süt_" hid the word start; a real miss found on 90 Turkish lists. |
| the list comes with its heading's language | Open Food Facts keeps each language's list apart; a Turkish list sent as English would be filed wrong. |

### test/ingredient_corpus_test.dart — real ingredient photos

| Test | Why it's needed |
|---|---|
| the allergen words find what real labels name, and nothing else | The allergen list on 31 checked labels, exactly: no misses, nothing invented. |
| reads real ingredient lists as *recogniser* recognises them | One per recogniser. Synthetic tests missed every real layout problem (overlapping line boxes, columns, bilingual warnings). Holds lists from elsewhere to ≤ 1, read lists to ≥ 80 %, allergens found to ≥ 85 % with ≤ 2 extra. |

### test/label_flow_test.dart — the label feature through the UI, with a fake camera

| Test | Why it's needed |
|---|---|
| an unknown barcode: read the label, check it, save it, edit it | The whole feature: values reach the form, a new product needs a name, saved facts show on the product page and in history, survive a restart, and can be edited. |
| a known product without nutrition facts gets them from the label | The second entry point: Open Food Facts' name and scores stay, only nutrition comes from the label. |
| no scanner on this device: says so and offers a photo | The simulator and phones without the scanner still have a way forward. |
| an impossible value is caught before saving | Typed values are checked; nothing is saved until they make sense. |
| the ingredient list beside the table is read too, its allergens shown | One photo gives both; allergens reach the form and the product page's chips; the list and its language survive a restart. |
| a product with nutrition facts but no ingredient list gets only the list | The third entry point: the form asks only what Open Food Facts lacks, and its nutrition stays. |
| no list on the label photo: one is read from another photo | Lists are often on another side of the pack; that photo is kept apart from the label's. |
| an empty form says what to enter, and saves nothing | Nothing half-saved, and the message names what's missing. |

### test/label_corpus_test.dart — real labels

| Test | Why it's needed |
|---|---|
| reads real nutrition labels as *recogniser* recognises them | One per recogniser in the fixtures. Synthetic tests missed most real-world failures: the first parser that passed them read 61 of 187 real values right and 37 wrong. Keeps accuracy from sliding when the parser changes. |

### test/contribute_test.dart — sending to Open Food Facts

| Test | Why it's needed |
|---|---|
| a photo goes to the staging server, selected for each field in its language, with who sent it | An upload that isn't selected doesn't show where a photo already is; writes must stay on staging until production is chosen; Open Food Facts asks apps to say who they are. |
| product fields go through the edit form, with who sent them | The one write that takes nutrition, and Open Food Facts asks apps to name themselves on every write. |
| what Open Food Facts refuses is not retried; what it can't answer is | Open Food Facts' rule for apps. Its refusals come in three shapes (403 HTML, 200 with status 0, 400 with "failure"), copied from staging. |
| a contribution waits on the phone until Open Food Facts confirms it, sending no photo twice | Nothing is lost to a dropped connection or a restart, and a retry after the photos went doesn't upload them again (Open Food Facts refuses a duplicate image). Also checks every upload went through `forUpload`, which strips location. |
| a refusal is shown and not retried until the user tries again | A wrong password must reach the user, not loop in the background. |
| signing in checks the password with Open Food Facts and keeps it in secure storage, not preferences | Preferences are plain files that backups copy. |
| a wrong password stores nothing, and nothing can be sent without signing in | A failed sign-in mustn't half-sign the user in, and the app has no account of its own to fall back on. |
| creating an account sends Open Food Facts' sign-up form, then signs in to confirm it | Open Food Facts pretends to accept sign-ups that look like spam, so only the sign-in proves the account exists; the email must not be kept on the phone. |
| a refused sign-up says why and signs nothing in | Staging's Keycloak refuses with an HTTP 500 page holding JSON (copied from 2026-10-25); read as a server error, the user would never learn their email was the problem. |
| a label for an unknown product goes as one upload for both of its photos, then its facts | The whole flow from the product page: the label's photos and facts, the pack's language, `add_brands` beside none, the whole nutrition table, and the status line afterwards. |
| only what the user changes is sent: a corrected brand, and nutrition as the whole table | Sending a field the user didn't touch would overwrite someone else's work with a stale copy. |
| without an account to send with, it asks the user to sign in first | Sending needs the user's own account: the button must lead to sign-in, not be dead. |
| an account made in the app needs the terms agreed, then sends straight away | Open Food Facts' terms must be agreed and its username rules met before anything is sent; afterwards the user is back where sending needed an account, signed in. |

### integration_test/ — on a phone or simulator

| Test | Why it's needed |
|---|---|
| lookup_test: a typed barcode is looked up on Open Food Facts | The real network call and the app shell on a device: what the unit tests fake. |
| label_test: text recognition reads real nutrition labels | The phone's own text recognition through the channel, scored on 10 labels; prints what it read, for the corpus. |
| label_test: text recognition reads real ingredient lists | Reads the 39 ingredient photos and prints the lines, for the ingredient corpus, which scores them. |
| label_test: the subject cut-out returns the product on white | The native cut-out works; on the iOS simulator it expects the known "inference context" failure. |
| label_test: the whole flow on the device | Real UI, recognition and file storage together, an ingredient list from a second photo included. Pauses on each screen (`SHOT` lines) so screenshots can be taken. |

## Negative tests to add

Already covered: server errors, unknown barcodes, history off, a photo without a table, an
ingredient list beside the table, recognition misreads, no scanner, an impossible value, a
new product without a name, an empty form, photos without an ingredient list. Still missing:

**Open Food Facts client and product page**
- No connection, DNS failure or timeout → "Couldn't reach Open Food Facts", and *Try again*
  retries and recovers.
- HTTP 200 whose body isn't JSON (OFF serves an HTML "Page temporarily unavailable" page;
  seen from its search endpoint) → the error screen, not a crash.
- Status 1 with fields missing (no name, no nutriments, no knowledge panels) → the page
  renders with placeholders.

**History and settings**
- Corrupted history or settings JSON in preferences → the app starts with empty history.
- More than 200 scans → the oldest is dropped.

**Saved labels**
- Corrupted `labels` JSON → the app starts; products show without the saved label.
- A saved photo deleted from disk → product page and history show the placeholder, no exception.
- Saving fails (disk full) → a message, the form stays, nothing half-saved.

**Label parser**
- No lines at all; only non-Latin text (Arabic, Georgian); a photo turned 90°; lines of zero
  height; the same line twice (the accurate and fast passes overlapping).
- Energy over 950 kcal and negative-looking values ("-5") are dropped.
- Two tables in one photo (per 100 g and "as prepared").

**Review form**
- Text that isn't a number ("1,2,3") → "Not a number"; energy over 950 → "Too high".
- A nutrition-only form (Open Food Facts has the list) saved empty → "Enter at least one
  value from the label."
- Text recognition throws → the form opens with "No nutrition table found" and can be typed into.
- Backing out of the scanner, camera or photo picker → nothing changes.
- The cut-out fails → the photo is kept and the message shown (today only checked on a device).
- Text recognition throws on the ingredients photo → "No ingredient list found…", the typed
  list stays.

**Ingredient list**
- A label saved with only its nutrition facts, then edited to add the list (the saved
  values and photo must stay).
- Corrupted `ingredients` in a saved label, or a deleted ingredients photo → the form and
  product page still open.

**Sending to Open Food Facts**
- An HTTP 200 sign-in answer that is really an error page → not signed in.
- A contribution queued, then the user signs out → *Sign in to Open Food Facts to send this.*,
  and it goes once they sign in.
- A sign-up Open Food Facts answers with HTTP 200 but whose sign-in fails (taken for spam, or
  waiting for an email) → *Open Food Facts didn't sign the new account in…*, nothing stored.
- A username that's taken (Keycloak's "User exists with same username") → *That username is
  taken.*
- Eight failed tries → no more automatic tries, *Try again* shown.
- A saved photo deleted before it's sent → refused with "A photo is missing from the phone."
- The Keystore key gone after a backup restore → signed out, not a crash.
- `forUpload` fails → the form stays, with the message.

**Web**
- On the web the product page never offers *Read the label*, nor sending to Open Food Facts.
