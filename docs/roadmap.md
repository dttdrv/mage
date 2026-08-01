# mage roadmap

Pinned items, in priority order. Status tracked per release in STATE.md.

## 1. D3D translation layer (DX8/9/10/11/12/12U)

Goal: full Direct3D coverage without relying on WineD3D. Layered plan:

- **D3D12 / 12U (incl. DXR):** vkd3d-proton -> Vulkan -> magevk. DXR maps
  onto VK_KHR_ray_tracing_pipeline / acceleration_structure, which magevk
  already implements; the Dark Ages work is the proving ground for the RT
  half. Status: untested end to end.
- **D3D11:** DXMT (OSS, D3D11 -> Metal direct, ships in CrossOver's ARM64
  preview) evaluated against DXVK -> magevk; keep whichever wins per
  workload class, but only one ships as default. DXVK remains the fallback.
- **D3D8/9/10:** DXVK covers 9/10/11; D3D8 via dgVoodoo2-style D3D8->11
  wrapping in front of the same path.
- **D3DMetal / GPTK4:** evaluate only if Apple's redistribution terms allow
  bundling; no proprietary dependency will become the default. Tracked as
  the compatibility bar to match, not as a component.

## 2. ARM64 Wine + FEX (replace Rosetta 2)

Rosetta 2 is largely discontinued in macOS 28 (announced). CodeWeavers
shipped the proof point: CrossOver Preview ARM64 builds (2026-07-31) run
Windows x86-64 under FEX on macOS 26.5+, with ARM64 DXMT, no D3DMetal yet.

Plan:
- Build wiage as native ARM64 (the wine-cx-26.2 tree already carries
  ARM64EC/arm64 work from the CrossOver Linux ARM64 cycle).
- Integrate FEX for x86-64 game code; target per-game performance >=
  Rosetta 2 before making it the default runtime. FEX on Apple silicon
  benefits from TSO hardware and fast atomics paths Rosetta cannot use.
- Keep the x86-64 + Rosetta runtime as a selectable fallback (advanced
  per-game runtime switch already exists).
- Prereq: macOS 26.5+ for the ARM64 runtime; older supported floors stay
  on Rosetta.

## 3. 32-bit Windows app support is kept

No dropping 32-bit. Older games (Sudden Strike 2 class) are a supported
class, not legacy baggage. Whatever the emulation stack becomes (FEX
handles i386 alongside x86-64), 32-bit Windows binaries remain
first-class. A regression in 32-bit support blocks releases.

## 4. Vulkan RT parity and upstreaming

Continue the magevk RT line (ray query, RT pipeline, AS) and upstream the
generally-applicable fixes per `docs/upstreaming-mage-fixes.md`. Doom: The
Dark Ages playable is the acceptance test.
