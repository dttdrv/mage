# Mage Performance Packet

Living document, governed by `docs/skills/mage-stack-engineering`.
Measure first, one causal change, record provenance. Update this file at
every session boundary.

## Observations (user-reported, unmeasured)

| # | Game | Symptom | Suspected layer |
|---|---|---|---|
| O1 | DOOM 2016 (Vulkan-native) | FPS dips in congested areas | MageVK / shader compile / sync |
| O2 | DOOM 2016 | FPS cap set but dips persist | presentation pacing, not cap |
| O3 | Sudden Strike 2 (DirectDraw/D3D7, 2002) | very slow overall | wined3d backend / CPU path |
| O4 | DOOM 2016 | black spots on enemies at times | MageVK rendering correctness |
| O5 | DOOM 2016 | macOS cursor reappears over the game | winemac input/window path |

## Deployed binary provenance (verified 2026-07-31)

| Component | Artifact | Source |
|---|---|---|
| Wiage runtime | toolchains/wine-mage-11.13/install-macos12-freetype | local build, Wine 11.13 + staging + msync |
| MoltenVK (default runtime) | toolchain lib/libMoltenVK.1.4.2.dylib (Jul 28) | has 2788, frame cap, FAKE flags (strings-verified) |
| MoltenVK (RT runtime) | mage/dist/runtime-ray-icb/lib (rebuilt Jul 31) | mage/magevk @ 0a071fc9: 2771 head + 2788 + frame cap + FAKE flags |
| RT rollback | libMoltenVK.1.4.3.dylib.sparse-experiment-20260729 | ray-icb tree + uncommitted sparse emulation |

## Work in flight

- 2026-07-31: RT runtime MoltenVK rebuilt from magevk HEAD and deployed
  (was: pre-0a071fc9, so frame cap and FAKE flags were no-ops there).
  Default runtime unchanged (already current).

## Next measurements (need an unlocked, idle machine)

1. DOOM 2016 baseline: fixed save/scene, Metal HUD on, 60 s capture of
   FPS + frame-time, with and without MVK_CONFIG_FRAME_RATE_CAP=60.
   Also capture wineserver CPU (msync on vs off) in a congested fight.
2. Sudden Strike 2: identify the actual render path first (WINEDEBUG=
   +wined3d one launch, check GL vs Vulkan backend; look for GDI/DirectDraw
   fallback). Then frame-rate or mission-load timing baseline.
3. O4 (black spots): note map/encounter, screenshot, check against
   MVK_CONFIG_FAKE_GEOMETRY_SHADER on/off. Correctness before tuning.
4. O5 (cursor): reproduce, note whether it follows Cmd-Tab or timed
   re-grab failure in winemac.

## Findings

- 2026-07-31 (O3, static): the Wiage toolchain's wined3d has only the GL
  backend (no wined3d Vulkan: strings show wined3d_adapter_gl_* and GL
  context fallback paths only). Sudden Strike 2 therefore renders via
  wined3d → macOS OpenGL (4.1, deprecated) under Rosetta — a known-slow
  path for 2D-era games with heavy surface locks/blits. DXVK/DXage does
  not cover DirectDraw. Candidate remedies, cheapest first: (a) Wine
  registry renderer/GDI toggles as an A/B experiment; (b) a recipe-managed
  DDraw wrapper (cnc-ddraw is open source; dgVoodoo2 redistribution needs
  a license check) translating to D3D11 → DXVK → MageVK. No change made
  yet — needs the render-path confirmation from measurement step 2 first.

## Falsified / rejected

(none yet)

## Explicit prohibitions

- No changes to mage/vendor/MoltenVK or the main project from Mage work.
- No speculative env-var piles in recipes without an A/B measurement.
- No building from mage/sources/* trees without recording which dirty
  files went into the binary.
