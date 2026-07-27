# Mage App — Design Guidelines

Living document. Any UI change to `mage/app` should be checked against this
before it ships. The goal: Mage should feel like a first-class macOS 26
(Tahoe) citizen and a *game launcher*, not a developer console.

## What we benchmark against

| App | What to copy | What to avoid |
|---|---|---|
| **CrossOver** | One obvious "play" action per bottle; diagnostics tucked away; friendly naming ("bottle"→game) | Their installer wizards bury the user in modal steps |
| **Heroic** | Game grid with big cover art, hero banner + logo on the game page, play button as the visual anchor | Dense settings pages with 30 toggles at once |
| **Steam (Big Picture)** | Art-first library; metadata is secondary to the artwork | Desktop Steam's cluttered chrome and ad rows |
| **Apple HIG / Tahoe** | Liquid Glass materials, capsule controls, SF Symbols, progressive disclosure, standard keyboard shortcuts | Custom-drawn chrome that fights the system look |

## Non-negotiable rules

1. **One primary action per screen.** On a game page that action is *Play* —
   glass-prominent, capsule, large, anchored on the hero art. Everything else
   is `.glass` secondary or lives in a menu.
2. **Toggles, not commands.** If a setting is a boolean or a small enum, it
   is a `Toggle` or `Picker` with a plain-language title and a one-line hint.
   Raw `KEY=value` editing is allowed only in the Advanced sheet, as the
   escape hatch — never the main path.
3. **Progressive disclosure.** Three tiers:
   - *Game page:* Play, status, progress info (play time, achievements).
     No settings controls at all — user decision 2026-07-28.
   - *Advanced sheet:* per-game title/runtime/prefix, ALL env toggles
     (HUD, msync, AVX, logging, FPS cap), other variables, launch steps,
     save/cancel.
   - *Settings sheet (sidebar gear, bottom-left):* app-global things —
     Mage directory, maintenance (kill Wine processes), about/version.
   If a control doesn't change per game, it does not belong on the game page.
4. **The console is not the product.** Hidden by default; appears while a
   task runs and can be toggled from the status bar. Errors must surface as
   inline warnings (orange, plain language), not only as log text.
5. **No dead ends.** Every visible control does something. Sidebar entries
   navigate; buttons act; pickers persist immediately to the recipe.
6. **Universal behavior in code, per-game behavior in recipes.** The app
   never hardcodes a game-specific workaround; that lives in the recipe JSON.
7. **Tahoe floor.** We target macOS 26+ only. Use `glassEffect`,
   `GlassEffectContainer`, `.buttonBorderShape(.capsule)`, symbol effects.
   Do not add pre-Tahoe fallbacks or custom materials that imitate glass.
8. **Scrolling beats clipping.** Detail content lives in a `ScrollView` with
   the status bar pinned below a divider. Nothing may be cut off at the
   minimum window size (1080×680).

## Visual checklist for review

- Hero: 210pt, 20pt continuous corners, logo bottom-left, Play bottom-right,
  running badge top-trailing.
- Buttons: capsule glass; exactly one `glassProminent` per view.
- Chips for metadata (runtime, size, AppID); secondary color, below actions.
- Prefix paths: caption size, secondary, middle-truncated, selectable.
- Spacing: 14pt section gaps inside 20pt padding; grid cards 150–190pt.
- Language: sentence case, no jargon on the main surface ("Advertise AVX"
  gets a hint line; "MSYNC=1" never appears).

## Smell tests — reject the change if…

- A user must type a command or edit a var to do something common.
- A new screen has more than one prominent button.
- A diagnostic tool (doctor, dry run, logs) is at the same visual level as
  Play.
- A setting appears in two places with different labels.
- Anything only works when the window is bigger than the minimum.
