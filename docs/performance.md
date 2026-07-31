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

- 2026-07-31 (F1, toolchain Vulkan wiring, verified): the install tree's
  libvulkan.1.dylib symlinks (`lib/` and `lib/wine/x86_64-unix/`) point to
  the local fat (x86_64+arm64) libMoltenVK.dylib with 2788 + frame cap +
  FAKE flags. The BUILD.md warning about gcenx / arm64-only targets is
  stale. Pre-2788 backups sit alongside as `*.pre-2788`.
- 2026-07-31 (F2, msync, verified): msync is already Mage-default-on in
  both `dlls/ntdll/unix/msync.c` and `server/msync.c`
  (`WINEMSYNC=0` opts out), and the deployed ntdll.so / wineserver
  postdate that patch (build-tree == install-tree, cmp-verified).
  Recipes still set `WINEMSYNC=1` explicitly — harmless. Runtime probe
  (launch without the env, expect "msync: up and running.") pending an
  unlocked machine.
- 2026-07-31 (F3, wined3d, verified): wined3d.dll in the deployed
  toolchain DOES contain the Vulkan renderer (221 vk symbols,
  adapter_vk.c, wined3d_adapter_vk_create). The earlier GL-only claim
  below was wrong — see Falsified. SS2 can therefore be A/B tested on
  `HKCU\Software\Wine\Direct3D renderer=vulkan` (wined3d → winevulkan →
  MageVK) vs the default GL path, plus `HKCU\Software\Wine\DirectDraw
  renderer=gdi` for the 2D blit path. Registry-only, recipe-managed,
  no new DLLs. This is now the cheapest O3 experiment; measurement step 2
  stands.
- 2026-07-31 (F4, build flags): toolchain built with `-g -O2` (Wine
  default), llvm-mingw for PE, clang for unix. No -O3/LTO anywhere.
  Possible later experiment; not a first move.
- 2026-07-31 (F5, QoS patch): the thread-priority → pthread-QoS patch
  remains in the build tree but reverted from the install tree after
  measured no-gain (86.2 vs 88.0 FPS, noise). Do not redeploy without a
  new measurement case.
- 2026-07-31 (F6, DXVK/dxage): confirmed absent — the toolchain ships
  stock Wine PE d3d8-12/dxgi/ddraw. DXage does not exist yet. Any DXVK
  adoption is a future, separately-planned work item (per-game override
  via WINEDLLOVERRIDES, recipe-managed), not part of the current audit.

## Falsified / rejected

- 2026-07-31: "wined3d has only the GL backend" (earlier revision of the
  O3 finding). Falsified by full symbol scan — the Vulkan renderer is
  compiled in; only the default selection is GL. Corrected as F3.

## Explicit prohibitions

- No changes to mage/vendor/MoltenVK or the main project from Mage work.
- No speculative env-var piles in recipes without an A/B measurement.
- No building from mage/sources/* trees without recording which dirty
  files went into the binary.
