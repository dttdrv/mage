# Steam (CEF) black window on mainline Wine/macOS — root cause and structural fix

Status: **mitigation SHIPPED 2026-07-22** (single-process wrapper, below). Root cause confirmed (external source, matches our symptoms exactly). IOSurface bridge remains the structural fix on the roadmap.
Date: 2026-07-22

## Symptom

Steam's window appears but the client area is pure black, even with `-cef-disable-gpu
-cef-disable-sandbox`. All processes stay alive, JS loads, no crash — the frames just
never reach the window. Affects every CEF-based UI, not only Steam (Battle.net, Epic, EA).

DOOM is unaffected: the game renders its own window through MoltenVK, not CEF.

## Root cause (why flags cannot fix it)

Modern SteamUI forces `--enable-chrome-runtime` (compiled into SteamUI.dll, not
overridable by command line). chrome-runtime always runs GPU compositing (Viz) in a
separate `--type=gpu-process`. So:

- the frames are drawn by the GPU process,
- the window is owned by the browser process,

and presenting one process's composited frame into another process's window —
**cross-process present** — is simply not implemented in mainline Wine. On native
Windows, DXGI handles this. All three present paths are blocked:

1. GPU multi-process (default): cross-process swapchain unsupported → no/black window.
2. `-cef-in-process-gpu`: ignored, chrome-runtime respawns a gpu-process anyway.
3. `-cef-disable-gpu`: falls back to software present — window appears but black or
   degraded (our current state).

This is exactly a mainline-Wine-vs-CrossOver boundary: CrossOver ships its own
implementation of this path; mainline has none.

## Fix architecture (universal, matches mage's capability-emulation charter)

Bridge producer → consumer with **IOSurface**, macOS's cross-process GPU buffer:

1. Producer (GPU process, in the D3D→Metal translation layer): when the swapchain
   target is cross-process, render the composited backbuffer into an IOSurface-backed
   Metal texture instead of presenting to an invisible CAMetalLayer. Publish the global
   `IOSurfaceID` (minimal: a file `/tmp/cxpresent-<hwnd>.id`; proper: mach port).
   Key by **root HWND** (`GetAncestor(hWnd, GA_ROOT)`) — CEF renders into a child
   window, winemac.drv displays the parent; child-keyed publish makes lookup miss
   (this is the #1 real-world gotcha).
2. Consumer (winemac.drv, browser process): `IOSurfaceLookup(id)` → assign to the
   visible layer's `contents`. A ~60 Hz poll timer must call `setNeedsDisplay:YES`
   because the producer cannot trigger Cocoa redraws cross-process.
3. The IOSurface must be created with `IOSurfaceIsGlobal = YES` or cross-process
   `IOSurfaceLookup` returns NULL. Long term: move ID handoff to mach ports
   (bootstrap register), since global IDs may be deprecated.

## Fit with mage

- Universal per charter: fixes Steam *and* every other CEF launcher in one blow.
- Squarely the "capability-emulation layer for Windows features macOS does not expose"
  from the project vision; also the winemac.drv side we already patch (fullscreen
  mode-switch race fix lives in the same driver).
- Dependency note: the CEF GPU process renders D3D11. Our bottle currently has no
  D3D11→Metal layer on the Steam side (MoltenVK only serves DOOM's Vulkan). The
  producer half therefore needs a D3D11→Metal component (DXMT-style) or a wined3d
  path that can blit to IOSurface. Scope before scheduling.

## Source

- [WineでCEFアプリ（Steam等）が真っ黒になる理由と、cross-process presentの自作](https://zenn.dev/niixolabs/articles/wine-cef-cross-process-present)
  (2026-06, Japanese). Architecture fully described in the article; complete patch +
  build recipe is paywalled (¥800 book), author states source is on GitHub (link in
  the book). Verified conceptually against our symptoms and against the known
  chromium-runtime behavior; not yet independently reproduced by us.
- Supporting: [Steam UI Black Unless Ran Using -cef-disable-gpu (ValveSoftware/steam-for-linux#10561)](https://github.com/ValveSoftware/steam-for-linux/issues/10561)

## Interim mitigations (cheap, unverified)

- Try adding `-cef-disable-gpu-compositing` alongside `-cef-disable-gpu`.
- Restart `steamwebhelper.exe` after boot; toggle small mode.
- None of these address the root cause; expect at best a slow software-rendered UI.

## SHIPPED mitigation (2026-07-22): steamwebhelper single-process wrapper

External proof of concept: [ramiabih/play-windows-steam-on-mac](https://github.com/ramiabih/play-windows-steam-on-mac)
(active, Wine+DXMT project) fixes the same black UI by wrapping
`steamwebhelper.exe` and appending `--disable-gpu --single-process
--disable-features=IsolateOrigins,site-per-process,SpareRendererForSitePerProcess`.
`--single-process` collapses CEF into ONE process — no gpu-process, no
cross-process present, root cause sidestepped entirely (exactly the
"-cef-in-process-gpu" idea, but enforced at the helper level where
chrome-runtime cannot override it).

Our implementation: `mage/tools/steamwebhelper-wrapper/steamwebhelper-wrapper.c`
(independent minimal version of the same idea), built with the project
llvm-mingw (`-O2 -municode`), installed 2026-07-22 10:39 into all three
`prefix/drive_c/Program Files (x86)/Steam/bin/cef/cef.win*/` dirs:
Valve's binary preserved as `steamwebhelper_real.exe` alongside it.

Rollback: `mv steamwebhelper_real.exe steamwebhelper.exe` in each dir.
Caveats: a Steam client update restores Valve's binary (reinstall the
wrapper); `--single-process` CEF is less crash-isolated (acceptable for a
launcher UI); store checkout/payment iframes need site isolation, which we
disable — offline single-player use is unaffected.
Verification: process-level = steamwebhelper cmdline contains
`--single-process`; visual = Steam window renders (needs unlocked screen).
