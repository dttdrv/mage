# mage

Free, open-source CrossOver alternative for Apple silicon. Patched wine
runtime + MoltenVK/Metal, driven by declarative per-game recipes.
Universal optimizations only (all M-series); no per-game perf logic in
code — tuning lives in recipe data.

## 0.1 alpha — CLI

Requires: macOS on Apple silicon, system python3 (3.9+, no dependencies).

```
mage/bin/mage list                                    # recipes + bottles
mage/bin/mage install doom2016                        # fresh bottle (wineboot)
mage/bin/mage install doom2016 --import-prefix PATH   # adopt existing prefix
mage/bin/mage run doom2016 [--dry-run]                # launch per recipe
mage/bin/mage doctor doom2016                         # diagnostics tarball
```

- Recipes: `recipes/<id>.json` — env, file checks, launch steps.
- Runtimes: `runtimes/<id>.json` — versioned wine builds, registered by
  reference. The current `mage-wine-11.13` install is experimental; the
  release build targets macOS 26 (Tahoe floor, nothing below is supported)
  and uses the clean vendored MoltenVK branch.
- Bottles: `prefixes/` for mage-created; imported prefixes stay in place
  (registered in `prefixes/imported.json`, marker `.mage-bottle.json`).
- Logs: `/private/tmp/mage-<name>.log` (or `$TMPDIR`). Diagnostics:
  `docs/testing/diagnostics/`.

Flagship recipe: **DOOM (2016)** — Steam applaunch, msync, AVX advertise,
Chroma DLL check. Launch env/flags are the A/B-verified set from
`docs/testing/GOAL-LEDGER.md`.

Design spec: `docs/specs/2026-07-21-mage-0.1-alpha-design.md`.
State ledger + research: `docs/STATE.md`, `docs/research/`.

## 0.2 — SwiftUI app

`mage/app/` builds a thin SwiftUI shell (`Mage.app`) over the CLI core with
plain swiftc (no Xcode needed; builds against the macOS 26 SDK because the
27 SDK's `@State` macro needs Xcode's SwiftUIMacros plugin):

```
make -C mage/app          # → mage/app/.build/Mage.app
make -C mage/app run      # build + open
```

The app reads recipes/runtimes/bottles from the same JSON the CLI uses and
shells out to `bin/mage` for install/run/doctor, streaming output into an
in-app log panel. Dry Run and Doctor verified against the doom2016 bottle;
live Run via the GUI is still unverified (same pending item as the CLI).

## 0.3 — Library redesign

Requires macOS 26 (Liquid Glass). The app is now a library that sits on
top of Steam: it scans each bottle prefix for Steam `appmanifest_*.acf`
files and shows every installed game as an art card (capsule art from
Steam's `appcache/librarycache/`; Steamworks Common Redistributables is
filtered out). Per game:

- With a mage recipe: Run / Dry Run / Doctor, streaming console, quick
  toggles on the game page (Metal HUD, msync, Advertise AVX — saved
  straight back to the recipe), and an Advanced editor — runtime picker,
  wine-prefix change (imported prefixes), feature toggles, raw env table
  for everything else, ordered launch steps with reorder/add/delete. Save
  writes back to `recipes/<id>.json`; tuning stays in recipe data, never
  in code.
- Without a recipe: "Play via Steam" (sends a `steam://` URL to the
  prefix's Steam) and "Set up with Mage" (generates a recipe template and
  imports the bottle via the CLI).

Bottles are an implementation detail, not a UI concept: one prefix holds
Steam + the games, and prefix management lives in Advanced (per game) and
the CLI. Verified in-GUI (0.3): library grid, game detail, quick-toggle
round trip, Advanced editor, Dry Run console streaming. Live Run still
unverified.

Roadmap: DXVK/VKD3D routing when a DX title becomes a target.

`mage/bin/build-moltenvk.sh` builds and stages a universal arm64/x86_64
MoltenVK runtime with a macOS 26 deployment target.
