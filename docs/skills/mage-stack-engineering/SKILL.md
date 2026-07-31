---
name: mage-stack-engineering
description: Use for any non-trivial change to the Mage stack — the app, bin/mage, recipes, the Wiage runtime, MageVK/DXage forks, Steam integration, or bottle management; when chasing game performance, rendering correctness, or launch behavior; when a fix could plausibly belong to more than one layer.
---

# Mage Stack Engineering

Adapted from `architecture-first-engineering` (main project) for Mage:
Windows games on macOS through Wiage (Wine), DXage, winevulkan, and
MageVK (MoltenVK) on Metal, under Rosetta.

**Core rule:** no source edit until the layer that owns the behavior is
named, the end-to-end path is traced, and the smallest causal change is
identified. For performance work: no "optimization" without a before
measurement and a named bottleneck.

## Repository Boundaries (Hard Rules)

| Path | Owner | Rule |
|---|---|---|
| `mage/` (app, bin, recipes, runtimes, tools, docs) | Mage | Edit freely, commit and push. |
| `mage/magevk` | Mage fork of MoltenVK | Our shipped MoltenVK. Commits here are fine. |
| `mage/sources/*` | Build trees | May hold uncommitted experiments. Never delete; check provenance before building from one. |
| `mage/vendor/MoltenVK` | Main-project PR workspace | NEVER touch. GPT's live upstream work. |
| `../MoltenVK`, `../upstream` | Main project | NEVER touch from Mage work. |
| `../toolchains/wine-mage-11.13` | Wiage runtime | Rebuild per its BUILD.md; note the macOS 26 deployment-target rule. |

Every shipped MoltenVK binary must be traceable: which repo, which
commit, which dirty files. Record provenance next to the artifact
(deployments live in `mage/dist/`).

## The Stack Layers (Ownership Map)

1. Windows game (Vulkan-native, D3D9-12, DirectDraw/D3D7, GDI).
2. Wiage: winemac driver, wineserver (+msync), ntdll, wined3d, winevulkan.
3. DXage (DX translation), when present.
4. MageVK: Vulkan on Metal, SPIRV-Cross MSL generation.
5. Metal / Apple GPU driver.
6. Rosetta (x86_64 translation, AVX advertisement).
7. macOS presentation (IOSurface, winemac window path) and input.
8. Steam client inside the prefix (CEF wrapper, silent flags).

Map every symptom to exactly one owning layer before fixing. A rendering
artifact is not a performance bug; a Steam window issue is not a Wine
issue; a MoltenVK capability gap is not a Wine bug.

## Game Variant Matrix

Classify the game before diagnosing:

| Variant | Example | Path | Typical bottleneck |
|---|---|---|---|
| Vulkan-native | DOOM 2016, Dark Ages | winevulkan → MageVK | state finalization, shader compile, present pacing |
| D3D11/12 | most modern games | DXVK/DXage → MageVK | translation overhead, sync |
| D3D9 and older | many 2000s games | wined3d → GL or Vulkan | wined3d backend choice, CPU blits |
| DirectDraw/2D | Sudden Strike 2 | wined3d or GDI | software rendering, palette conversion, present path |

One game proves only that game, that renderer, that prefix, that machine.

## Performance Protocol

1. **Name the workload.** Exact game, scene, settings, resolution.
2. **Measure before.** FPS + frame-time (Metal HUD), plus a layer signal
   (wineserver CPU, shader-compile count, present intervals). Record the
   exact binary provenance.
3. **Form one causal hypothesis** tied to a layer, with evidence.
4. **Try to falsify it** with the cheapest experiment (env flag, config
   toggle, A/B build).
5. **Change one thing.** Rebuild, redeploy, record provenance.
6. **Measure after**, same workload. Keep or revert on evidence.

Rationalizations to reject: "it feels faster", "more tweaks can't hurt",
"CrossOver does X so copy X blindly", "the dip must be the GPU".

## Mage-Specific Rules

- Tuning lives in recipe data (`mage/recipes/*.json`); `bin/mage` and the
  app only author/execute that data. Universal env requires A/B evidence.
- User-facing surfaces stay simple: new knobs go to Advanced, with a
  toggle, never raw key=value when a known setting exists.
- Keep Steam invisible: `-silent` family flags everywhere the client is
  launched; `MAGE_APP_NAME` set for every launched step.
- Never strand the user: every long operation has a timeout, a cancel
  path, or a dismiss affordance.
- README and user-facing text: professional, terse, no AI-isms.
- Commit style: short imperative subject; provenance notes for binaries.

## Quick Decision Record

```markdown
Observation:
Owning layer:
Workload + before measurement:
Hypothesis:
Cheapest falsifier:
Smallest valid delta:
Provenance of new binaries:
After measurement:
Excluded scope:
```

## Stop Conditions

- The fix belongs in a layer Mage does not own (upstream Wine, Metal,
  Rosetta) — document and work around, do not fork silently.
- The change needs `mage/vendor/MoltenVK` or the main project — stop.
- The measurement contradicts the hypothesis — do not ship the change.
- A dirty experiment's provenance is unknown — do not build from it.
