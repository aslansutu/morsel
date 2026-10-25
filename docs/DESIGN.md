# Morsel — design

Tokens live in `lib/theme.dart`. Contrast below was measured on 2026-10-18 with the
dataviz skill's `contrast()` (WCAG 2 ratios).

## Palette: plum & oat

Green, amber and red are reserved for health verdicts, so the brand takes a hue outside
the traffic light: **plum** (berries, aubergine). Warm **oat** surfaces keep it feeling
like food rather than a lab report.

| Role | Light | Dark | Used for |
|---|---|---|---|
| surface | `#FAF7F2` | `#141114` | page background |
| card | `#FFFFFF` | `#1E1A1E` | cards |
| container | `#F1ECE4` | `#272227` | dock, chips |
| outline | `#DDD5CA` | `#3B353B` | card borders, dividers |
| ink | `#1E1A1F` | `#EEE8EE` | primary text |
| ink-secondary | `#5F5862` | `#BDB4BD` | secondary text |
| ink-muted | `#6F6872` | `#A39AA3` | captions, metadata |
| brand | `#6A3D8F` | `#CFAEEA` | scan button, selection, links, primary buttons |
| on-brand | `#FFFFFF` | `#34174A` | text and icons on brand |

**Status scale — reserved for food evaluations only**

| Role | Light | Dark | Word |
|---|---|---|---|
| good | `#1F8A3B` | `#5CCB7A` | Good / Low |
| caution | `#B86E00` | `#F0B44A` | Moderate |
| bad | `#D23C32` | `#FF7B6E` | Poor / High |
| unknown | `#857E89` | `#958D98` | Unknown |

**Nutri-Score** keeps its official fills (A `#038141`, B `#85BB2F`, C `#FECB02`,
D `#EE8100`, E `#E63E11`) because people recognise them. The letter colour is measured,
not copied: white fails on B, C and D (2.30, 1.53, 2.70), so those take ink.

**Measured floors:** text ≥ 4.5:1 everywhere (lowest: ink-muted on light surface, 5.04);
status marks ≥ 3:1 (lowest: caution on light surface, 3.73); score letters ≥ 3:1 as large
text (lowest: white on Nutri-Score E, 4.15); brand button labels 7.8:1.

## Brand

The logo is concept A2 from the logo canvas: a barcode rising out of a scanner frame,
its lower half running out past the frame, two eyes on top looking down at the bars.
Plum tile, lilac (`#CFAEEA`) frame, oat bars, white eyes with ink pupils.

One geometry, every variant: `tool/brand_icons.py` writes `assets/brand/*.svg` and renders
the PNGs; `dart run flutter_launcher_icons` installs them.

| File | Used for |
|---|---|
| `icon` | iOS (full bleed; iOS rounds it) and the web |
| `icon-rounded` | Android 7 and older |
| `icon-foreground` + plum background | Android 8+ adaptive icon (art fits the 66 dp safe circle) |
| `icon-monochrome` | Android 13+ themed icon |
| `icon-dark`, `icon-tinted` | iOS 18+ dark and tinted appearances |

In the app: `MorselMark` draws the mascot natively (it follows light and dark), and
`ScanGlyph` is the frame and bars alone for the scan button. The scanner window uses the
logo's rounded corner brackets. Splash screens are plum.

**The mascot appears only where there is nothing to judge** — empty history, a barcode
Open Food Facts doesn't know. Never next to a verdict, so it never seems to be the one
judging the food.

## UI rules

1. Flat and calm: cards are white on oat with a 1 px outline and no shadow. Radius 16 for
   cards, 12 for photos, 10 for badges, pill for chips.
2. Spacing on a 4 pt grid: 8 inside a group, 16 page gutter, 24–28 between sections.
3. System fonts (Roboto, SF Pro). Numbers use tabular figures so values line up.
4. Text is always ink. Status colours go on marks — dots, icons, badges, meter zones —
   never on text.
5. Product photos sit on white in both themes; they are shot on white.
6. Touch targets ≥ 48 dp; the scan button is 56 dp.
7. Nothing has a fixed height that holds text, so layouts survive large system text.

## UX rules

1. **The app opens ready to scan.** Scan is the centre of the dock, one tap from anywhere.
2. **Answer first, detail on demand.** Scores at the top, then highlights, nutrients,
   ingredients; explanations collapse into Details.
3. **Green, amber, red mean health verdicts only.** The brand colour never means good or
   bad, and destructive actions (delete, clear) stay neutral.
4. **Never colour alone.** Every status carries a word and an icon, letter or number.
5. **Judge only where a standard exists** — Nutri-Score, NOVA, Open Food Facts' nutrient
   thresholds, Green-Score. Diet (vegan, vegetarian) and allergens are facts, shown
   neutral, until the user tells us what matters to them.
6. **Be honest about uncertainty.** Unknown is a grey "?", never good. Every product shows
   its source and when it was last updated.
7. **One language per screen.** Product text is requested in the app's language.
8. **Confirm a scan** with a haptic tick, and pause the camera while a product is open
   (battery, and no second barcode firing).
9. **Every dead end has a next step:** no camera → type the barcode; not found → read
   the label, scan another, or add it to Open Food Facts; no scanner → choose a photo; network error → try again.
10. **Undo over "are you sure?"** for removing a scan, clearing history, and turning
    history off.
11. **Private by default.** History stays on the device; turning it off forgets it. Nothing
    goes to Open Food Facts unless the user sends it, after seeing what goes and under whose name.

## Screens

**Dock** — a floating glass capsule (24 px blur, 78 % container fill, soft shadow) over
the content, so the camera shows through it on the scan tab. History · **Scan** ·
Settings: the side tabs are icon + label, the selected one sits in a primary-container
pill; the centre is a 56 dp plum circle with the logo glyph. Content and snackbars clear it
through `MediaQuery` padding.

**Scan** — live camera, everything outside a 280 × 168 window dimmed, "Point at a
barcode" hint, then *Type barcode* and torch. Reads EAN-13, EAN-8, UPC-A, UPC-E. Without a
camera (denied, simulator, desktop browser) the tab says why and offers *Type barcode*.

**Product**, top to bottom:
1. Photo, name in the app language, brand · quantity.
2. Three score tiles — Nutri-Score, Processing (NOVA), Green-Score: badge + word + name.
3. Highlight chips — palm oil and added sugars (judged); vegan/vegetarian, allergens,
   traces, additive count (neutral). Allergens come from the user's ingredient list where
   Open Food Facts has none.
4. *Per 100 g* (or *100 ml* for drinks) — fat, saturated fat, sugars, salt as meters,
   then *All nutrition facts*.
5. Ingredients from Open Food Facts' panel, allergens in bold, per-ingredient percentages
   on demand; or the list from the user's label, allergens in bold. Without either: *The
   ingredient list is not available for this product yet.* and *Read the ingredients*.
6. Details — how the Nutri-Score was calculated, why it's (ultra-)processed, additives,
   environment. Open Food Facts' own localized explanations.
7. A card for Open Food Facts (phones only): *Share what you read* with *Send to Open Food
   Facts* where the page shows facts from the user's label, else *Something wrong or missing?*
   with *Improve on Open Food Facts*. Under it, the last send for this product: *Sending…*,
   *Couldn't reach Open Food Facts. Morsel will try again.*, *Open Food Facts didn't take it:
   <reason>* with *Try again*, or *Sent to Open Food Facts on <date>: 2 photos and the
   nutrition facts.* Icons stay neutral: these aren't food verdicts.
8. Source line: *Data from Open Food Facts · updated <date>* and the barcode. Facts from
   the user's label say so — *Nutrition facts from your photo of the label · saved
   <date> · Edit*, or *Ingredients from…*, or *Nutrition facts and ingredients from…* — with
   the photo a tap away. A product only the label knows shows its name, photo, allergen
   chips, nutrition, ingredients and source, and no scores.

**Check the label** (after reading a label) — the label photo on top (tap for
full screen), then what was read: *Found 7 of 8 values. Check each one against the
photo.*, or that no table was found; a note when the photo never says "per 100 g" (likely
per serving). *Per 100 g | Per 100 ml*, then eight right-aligned fields with units, the
sub-rows indented as on the label. Values over 100 g in 100 g are refused. For a product
Open Food Facts doesn't know: a required name and an optional photo, cut out onto white.
Where Open Food Facts has no ingredient list, an *Ingredients* section: whether the photo
had one, the list as an editable paragraph, *Read from another photo* (and *See that photo*
once one is used), then the allergens the list names, rewritten as the user corrects it —
*Allergens: Contains milk, nuts. May contain peanuts.* — neutral, with an info icon. A form
for the ingredients alone has no nutrition part. *Save* needs a value or the list, and under
it *Saved only on this phone.*

**Improve on Open Food Facts** (*Add to Open Food Facts* for a product it doesn't have) — one
line on what the form is for, then *Photos*: three slots, Front · Ingredients · Nutrition, each
showing the new photo (*New*, *Remove*) or Open Food Facts' (*On Open Food Facts*, *Replace*) or
nothing (*None yet*, *Add*); the front is a photo, the other two use the document scanner.
*Product*: name, brand, quantity. *Per 100 g* or *Per 100 ml*: the label form's nutrient fields.
*Ingredients*: the list and *Language of the list*. Fields start from Open Food Facts, the saved
label filling its gaps. At the bottom, what will go — *Sends 3 photos, the name and the
nutrition facts.*, or *Change something above to send it.* — then *Send to Open Food Facts*
(*Sign in to send* when the build has no shared account), whose name it goes under (*Sent as
alice.*, or *Sent through Morsel's account, not under your name.* with *Sign in to be credited*), and the licences: data under the Open
Database License, photos under CC BY-SA, only photos you took. While writes go to the test
server, the page says so.

**Open Food Facts account** — signed out: why to sign in (credit; without it Morsel's account
sends), username (*Not your email*) and password with autofill, *Sign in*, which checks them with
Open Food Facts, *Create an account*, and where the password is kept. Signed in: the username,
*Sign out*, and what happens after.

**Nutrient meter** — three equal zones, low · moderate · high, using Open Food Facts'
thresholds per 100 g (fat 3/20, saturated fat 1.5/5, sugars 5/12.5, salt 0.3/1.5; halved
for drinks — `@nutrient_levels` in their `Food.pm`). The dot sits inside the zone Open Food
Facts assigned, so it can never contradict the word beside it. Zones are tinted at 30 %,
2 px apart; the dot is 14 dp with a 2 px surface ring.

**History** — grouped by day (Today, Yesterday, Mon 12 Oct), each row with photo, name,
brand · time and a small Nutri-Score badge. Swipe to delete, clear all, both with undo.
Separate empty states for "no scans yet" and "history is off".

**Settings** — *Country*: automatic from the device region, or a searchable list with
flags ("turk" finds Türkiye). *Remember scans*: on by default; off deletes history, with
undo. *Open Food Facts* → *Account*: who sends (phones only).
