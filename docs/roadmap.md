# mage roadmap

Pinned items, in priority order. Status tracked per release in STATE.md.

## 1. Proton route: everything translates to Vulkan

Direction: follow Proton's model. All Direct3D versions go through
Vulkan translators into magevk — one graphics backend, one place to
optimize. Where Proton carries code we can use (translators, per-game
workarounds, winevulkan-adjacent fixes), integrate it rather than
reinventing.

- **D3D12 / 12U (incl. DXR):** vkd3d-proton -> Vulkan -> magevk. DXR
  maps onto VK_KHR_ray_tracing_pipeline / acceleration_structure, which
  magevk already implements; the Dark Ages work is the proving ground
  for the RT half. Status: untested end to end.
- **D3D9 / 10 / 11:** DXVK -> Vulkan -> magevk. Mature, Proton's default,
  and its per-game config database ships with it.
- **D3D8:** D8VK (DXVK-family D3D8 -> Vulkan) where it fits; otherwise a
  D3D8 -> 11 wrapper in front of the same DXVK path.
- **Proton integration:** evaluate building against Proton's wine fork
  or cherry-picking its game-fix patchset (protonfixes-style per-game
  tweaks become recipe entries). Long-term goal: a game that runs under
  Proton on Linux runs under mage on macOS with no extra work.
- **DXMT (D3D11 -> Metal direct):** benchmark against DXVK -> magevk
  for the D3D11 class; it ships as default only if it wins clearly, and
  even then only for D3D11. It breaks the one-backend rule, so the bar
  is high.
- **D3DMetal / GPTK4:** evaluation only, and only if Apple's
  redistribution terms allow bundling. Proprietary; will never be the
  default. Tracked as the compatibility bar to match.

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
