# Mage launch stack — 2026-08-01 handoff

Scope: how Mage launches Windows games via Steam + Wine on macOS 26/27,
what broke today, what the verified-correct mechanisms now are. Audience:
GPT/Codex working on magevk + winevulkan. Nothing here touches upstream
MoltenVK or the main wine work.

## 1. Process-presence gating (Dock/Dock icon/alt-tab)

Goal: exactly one foreground macOS app per game (plus at most one "Steam"
UI). Everything else (wine plumbing, steam helpers, crash reporters) must
never promote to a foreground app.

History in one paragraph: per-step `MAGE_APP_EXE` allowlist → game
re-spawned by Steam missed the list → headless (no Dock, no alt-tab,
window stuck on top at window-layer 26+, uncloseable except by kill).
Recipe-wide union fixed that, but the model still failed CLOSED: any
missing exe entry = headless game. It bit twice in one day (doom2016
`app_exes` dropped in a recipe edit; TDA via a stale /Applications build).
2026-08-01 late: replaced with a **denylist**.

Current mechanism (wine `dlls/ntdll/unix/loader.c`, `loader_exec`):
- `MAGE_BACKGROUND_EXE` — `:`-separated, case-insensitive exe-basename
  denylist, matched on `argv[2]`. Listed exes get `MAGE_BACKGROUND=1`.
- `winemac.drv/cocoa_app.m transformProcessToForeground:` returns early
  when `MAGE_BACKGROUND` is set → process keeps windows but never becomes
  a foreground app.
- Everything else defaults to **foreground**, and the loader derives the
  app name from the exe basename (`DOOMTheDarkAges.exe` → sibling loader
  `DOOMTheDarkAges` → Dock/menu bar show that name; sibling loaders are
  loader copies with a patched embedded Info.plist, made by
  `mage/tools/wine-app-name/patch-wine-loader-name.py`,
  `bin/mage ensure_app_launcher`).
- `MAGE_APP_EXE` strict allowlist mode still honored if set (debug only).
- `MAGE_DEBUG_LOADER=1` → `mage-loader: argv[2]=... allowlist=... denylist=...`
  on stderr for every process. This is the fastest way to see what Steam
  actually spawns.

Denylist contents: steam.exe, steamservice, steamerrorreporter(64),
steamsysinfo, hardwareupdater, *driverquery*, steam_monitor,
steambootstrapper, streaming_client, gameoverlayui, conhost, explorer,
services, svchost, rpcss, plugplay, winedevice, wineboot, rundll32,
msiexec, regsvr32, tabtip, winemenubuilder, winecfg, control, notepad.

Critical: **steamwebhelper_real.exe must stay foreground.** In the
single-process CEF wrapper configuration, that process IS the Steam UI.
When it was background, winemac never promoted it and Steam's watchdog
fired "steamwebhelper is not responding", which also silently killed
`steam.exe -applaunch`. MageCore shows it as "Steam" (display-name
sibling loader); steam.exe itself is a windowless orchestrator on the
denylist.

Verified 2026-08-01: Doom 2016 via applaunch → window owner "DOOMx64vk",
60fps at menu. TDA → window owner "DOOMTheDarkAges", normal layer,
alt-tab in/out works.

## 2. applaunch vs direct exe launch

Doom 2016 direct (`wine DOOMx64vk.exe`) dies at `SteamAPI_Init` → game
prints `FATAL ERROR: Steam failed to initialize` and throws a C++
exception (`e06d7363`). This happens even with `SteamAppId`/`SteamGameId`
env set and CWD = exe dir: Steam injects its full client environment only
into children it launches itself. Conclusion: for Steam games, launch via
`steam.exe -applaunch <appid> [game args...]` (what CrossOver does).
Direct launch remains fine for non-Steam exes (TDA's idTechLauncher works
because it self-handoffs to DOOMTheDarkAges.exe).

Also: DOOM 2016's Vulkan exe is `DOOMx64vk.exe`; `DOOMx64.exe` is the GL
exe. Steam's applaunch for 379720 spawns both processes (one exits); both
are in the recipe's app_exes so both get named loaders.

## 3. Known open issue: TDA flicker / loading stall

Symptoms (2026-08-01): window correct (owner/layer/focus all fine), but
the game sits black at loading until the user alt-tabs to it, then
flickers heavily on interaction. Two independent suspect groups:

a) GPU-side corruption (documented in `docs/dark-ages-mvk-issues.md`):
   menu UI renders pixel-perfect while the 3D scene corrupts into
   spreading blocky garbage. Suspects: private sparse buffers (mandatory
   — game dies at vkCreateBuffer without them, so no A/B), BLAS
   `nativeSize` growth → `retainCurrentGeneration` nullptr.
b) Presentation/focus (new variable today): foreground promotion enables
   winemac's display-capture fullscreen path
   (`cocoa_app.m` line ~895, `CGCaptureAllDisplays`). Before the denylist
   the TDA window was headless/composited. If the flicker changed
   character today, this is why. A/B: HKCU\Software\Wine\Mac Driver
   "Capture Displays"=n, or windowed mode.

MoltenVK perf logging needs BOTH `MVK_CONFIG_PERFORMANCE_TRACKING=1` and
`MVK_CONFIG_PERFORMANCE_LOGGING=1`
(`MVK_CONFIG_PERFORMANCE_LOGGING_FRAME_COUNT=300`); logging alone prints
nothing (TDA recipe has all three).

## 4. Proton-route blocker (for D3D games)

Steam overlay / any D3D path currently loads prefix DXVK, which rejects
the magevk device: `VK_EXT_robustness2`'s `nullDescriptor` feature is
missing → "Failed to initialize DXVK". Recipes must not set `d3d11=n;
dxgi=n` blindly (that was another silent-kill landmine for Doom 2016).
nullDescriptor on magevk is the gate for the whole Proton route.

## 5. Process detection (ps shows nothing)

Wine PE processes clobber argv/environ on macOS 26+: `ps eww` shows a
Windows-style command line and NO environment. Do not match on WINEPREFIX
from ps. Pin processes to a prefix via open files (`lsof +D`-style probe)
— `bin/mage stop` and `MageCore.refreshRunning` both do this. The GUI's
running-state needles must include each launch step's `appExes`, not just
`program`, or a launcher→game handoff drops the running state when the
launcher exits (fixed 2026-08-01, MageCore.swift).

## 6. Housekeeping rule (user-enforced, hard)

After EVERY test run: kill steam/wine/game processes and verify
`ps aux | grep -iE 'wine|steam|doom|idtech' | grep -v grep | wc -l` == 0.
Steam idle processes otherwise accumulate (20+ at one point) and later
runs inherit a dirty wineserver.
