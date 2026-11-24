# Prototype look (foo-native-web-test)

Captured 2026-11-23 from the Expo / React Native prototype (`~/git/foo-native-web-test`,
`npx expo start --web`), 430x932 portrait viewport, "New Drafting / Strength UI" (V2) toggles on.
Colours are tallied from `src/` hex literals (count = how often each appears).

| Shot | What |
|---|---|
| `01-main-menu.png` | Title: full-bleed pixel-art Challenge (Hydra) + 40% brown scrim, 2x2 button grid, Cinzel title with drop shadow |
| `02-player-setup.png` | Parchment form: bordered cards, round 1/2/3 count chips, toggles |
| `04-drafting-v2.png` | Drafting: header, round/phase + Strength (red) / Sharpness (blue) Challenge tiles, Sharpen bar, market, player rows |
| `05-ingredient-detail.png` | Ingredient tap -> modal (off-theme: slate + Tailwind blue, the one dark surface) |
| `06-drafting-mid.png` | Drafted Ingredients shown on each player row; "BOB IS THINKING..." status box |
| `07-strength-unrolled.png` | Strength challenge: Sharpness preview tile, opponent VP chips, red Challenge banner, collapsible Ingredients, Roll |
| `08-strength-rolled.png` | After roll: FAILED in Challenge banner, die tile, Reactions row of Ingredient icons |

## Overall feel
- **Light parchment, not dark.** Tan/cream paper backgrounds with near-black brown ink and thick dark
  outlines. Reads like a printed board game. (Ours is currently dark purple; this is the biggest difference.)
- **Square, boxed, ruled.** Every region is a rectangle with a 2 px `#2B1D14` border; sections stack as
  full-width bands separated by thick rules. Almost no rounding (buttons `rounded-lg` on menus only;
  in-game is square). No gradients, no glow; flat fills.
- **Colour = meaning.** Red = Strength / primary action / cost; blue = Sharpness; green = dice gained /
  reserved; purple = Reserve phase. Everything else is brown-on-parchment.
- Pixel-art icons on cream tiles (`#E6D4B2`) with a dark 2 px border, nearest-scaled.

## Palette
| Hex | Uses | Role |
|---|---|---|
| `#2B1D14` | 93 | Ink: text, all borders/outlines, rules |
| `#E6D4B2` | 64 | Cream: page bg, icon tile bg, light text on red/dark buttons |
| `#8B7355` | 37 | Muted brown: secondary text, subtitles, inactive chips, toggle thumb |
| `#9A2B2B` | 23 | Oxblood: primary buttons, Strength tile, Sharpen bar, Challenge banner |
| `#D1B88F` | 21 | Tan: panel / in-game surface (one step darker than cream) |
| `#C0322C` | 17 | Bright red: AP-cost badge, negative dice badge, active player chip |
| `#3C3426` | 17 | Dark umber: secondary buttons, chip fill, outer frame |
| `#72B05C` | 13 | Green: +dice badge, positive text, reserved border |
| `#2C4A82` | 13 | Navy: Sharpness tile, "off" toggle track |
| `#C2A36B` | 1 | Ochre: dice tray / action area under the banner |
| `#FFFFE3` | 1 | Ivory: die face |
| `#8B4A9C` | 3 | Purple: Reserving phase accent |
| `#C0D4E8` | 6 | Pale blue: body text inside the (dark) tooltip |
| `#722B2B` | 2 | Dark red: bevel (right/bottom border) on End Game button |
| `rgba(43,29,20,.4)` | | Scrim over title art |

Light ramp (lightest -> darkest surface): `#E6D4B2` cream -> `#D1B88F` tan -> `#C2A36B` ochre -> `#8B7355` -> `#3C3426` -> `#2B1D14`.

## Type
Same fonts we already ship (`assets/fonts`):
- **Cinzel** (Bold / SemiBold) for display: title, section headers ("AI PLAYERS"), player names, phase,
  button labels in-game, small-caps feel ("ROUND 1 / DRAFTING" with phase in muted brown underneath).
- **Source Serif 4** (Regular / SemiBold) for body: rules text, descriptions, menu button labels (uppercase, semibold).
- Uppercase for buttons and headings; sentence case for card text.
- Light text on dark/red is cream `#E6D4B2`, never pure white (except the leftover Tailwind bits).

## Layout patterns worth keeping
- **Header band**: game title left, square settings button right.
- **Round strip**: "Round N" + phase label on the left, then the two Challenge cards as solid colour
  tiles (red Strength, blue Sharpness) with the pixel art centred. Tap -> detail.
- **Big Sharpen bar**: full-width oxblood bar, label left, "+1" right.
- **Market**: wrapped row of 64 px square icon tiles. Badges: red circle top-right = AP cost, green
  (or red) rounded rect bottom-right = dice modifier. Unaffordable/locked tiles fade to ~60%.
- **Player rows**: full-width ruled rows; name in Cinzel, a stat line "0 VP • 3 AP • 0d6" below,
  drafted Ingredient icons to the right.
- **Status box**: outlined, unfilled "BOB IS THINKING..." in place of the action area during CPU turns.
- **Challenge screen**: red banner = Challenge art + its rule text + result word (NOT ROLLED muted / FAILED
  pink-red); opponent chips (letter in a circle + VP); collapsible "All Ingredients (n)" bar with VP on the
  right; ochre dice tray with ivory square dice and a Reactions row of Ingredient icons.
- **Title**: art fills the screen with a brown scrim; buttons as a compact 2x2 grid (primary red, rest umber).

## Things not to copy
- Detail modal / tooltip uses a dark slate panel and a Tailwind blue `Close` button: off-palette.
- Bright Tailwind red Roll Dice / End Game buttons (`#DC2626`-ish, system font) and the duplicate
  "End Game Early" footer: leftovers.
- Long hint text ("Long press: Effects & modifiers | Tap: Apply reactions"): against our terse-text rule.
- Mostly-empty lower half on the challenge screen; content doesn't fill the portrait height.

## Mapping onto `scripts/ui_kit.gd` (applied 2026-11-23)
| FoUI const | now | prototype |
|---|---|---|
| `BG_TOP` / `BG_BOTTOM` | dark plum gradient | flat `#E6D4B2` (or `#D1B88F`) |
| `PANEL` / `PANEL_LIGHT` | dark purples | `#D1B88F` / `#E6D4B2` |
| `EDGE` | `#61506B`-ish | `#2B1D14`, 2 px |
| `INK` | near-white | `#2B1D14` (and `#E6D4B2` on coloured fills) |
| `MUTED` | lilac grey | `#8B7355` |
| `RED` | coral | `#9A2B2B` fills, `#C0322C` badges |
| `MAGIC` (blue) | sky | `#2C4A82` |
| `RESERVE` | teal | `#72B05C` (or `#8B4A9C` for the Reserve phase) |
| `GOLD` / `KEPT` | amber | `#C2A36B` ochre tray; keep a gold for highlights |
