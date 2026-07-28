# mage state ledger

Status: DOOM 2016 campaign playable — ~73 FPS in-game, ~95 FPS menu,
2560x1600 all-Ultra borderless (user-verified screenshots). CPU-bound:
CPU 13.5 ms vs GPU 10.1 ms (id HUD). Research phase done, see
`docs/research/perf-goldmines.md`.
Date: 2026-07-20 (night)

## What mage is

Free, open-source CrossOver alternative for Apple silicon. No proprietary
components. First game target: DOOM 2016 (Steam appid 379720).
Direction (user decision): build on OSS Wine (Gcenx/upstream), NOT the
CodeWeavers CX 26.2 fork.

HARD RULE (user, stated twice): every optimization must be UNIVERSAL —
all Apple silicon (M1 and later), never tuned to one machine. No
per-machine core counts, no M5-only tricks, no per-game engine hacks.
Machine facts (e.g. core topology) may inform analysis but never gate
a feature.

## Working recipe (verified 2026-07-20)

- Runtime: `SharedSupport/wine.gcenx-11.13` (Gcenx Wine Staging 11.13).
- Game dir: replace `CChromaEditorLibrary.dll` with Riesi's OSS build
  (github.com/Riesi/CChromaEditor releases, 64-bit; original kept as
  `.bak`). Never just delete/rename it — the game calls through the null
  module handle and AVs at EIP=0.
- Launch: `steam.exe -applaunch 379720 +com_SkipIntroVideo 1 +r_renderAPI 1`
  (Steam offline mode flags work; skip-intro per Proton issue #566).
- `DOOMConfig.local`: `r_renderAPI "1"`, `r_fullscreen "0"` (windowed while
  debugging; exclusive fullscreen is untested since the fixes).
- Result: main menu fully rendered, 60 FPS (vsync), GPU 6.4 ms, frame
  counter advancing, zero access violations. Campaign load not yet tested
  (needs input).

## Root causes found today

- "Hang" before menu = Razer Chroma SDK spin (Proton #896): two threads
  pinned at ~80% CPU forever. Fixed by Riesi's DLL (above).
- CX 26.2 build crashes DOOM in `superscriptx64!SwitchToFiber(0x8ff)`:
  on macOS gs != TEB (gs = pthread struct, only 3 TEB fields mirrored in
  `ntdll/unix/signal_x86_64.c:init_syscall_frame`); FiberData @0x20 was
  never mirrored, so `GetCurrentFiber()` read pthread garbage. Patched
  `dlls/kernelbase/thread.c` (mirror on Convert*/SwitchToFiber) and
  `signal_x86_64.c` (4th mirror) in `upstream/Wine-cx-26.2`; verified with
  fibertest.exe (gs:[0x20] correct). Patched binaries installed in
  `SharedSupport/wine` (originals saved as `.orig`).
- CX 26.2 win32u/macdrv wedges WindowServer when DOOM presents (black
  screen, needed hard power-off), even windowed. gcenx 11.13 does not.
  This plus the fiber bug is why the CX fork is shelved for now.
- Gcenx runtime shows game windows with owner `wine`, and windows may
  open behind the terminal; `screencapture -o -l<winid>` captures them.

## Assets

- Active runtime: `SharedSupport/wine.gcenx-11.13`.
- CX 26.2 runtime (fiber-patched, display-wedged): `SharedSupport/wine`.
- Game prefix: `SharedSupport/prefix` (~72 GB, Steam + DOOM).
- Run scripts: `/private/tmp/mage-doom-gcenx-run.sh` (watchdogged;
  NOTE: /private/tmp is wiped by hard power-offs).
- Game logs: `prefix/drive_c/users/crossover/Saved Games/id Software/DOOM/base/`.

## Perf facts (measured 2026-07-20, user playing)

- In-game ~73 FPS / 13.5 ms at 2560x1600 borderless, all-Ultra: **CPU-bound**
  (HUD: CPU 13.5 ms, GPU 10.1 ms). Menus ~95 FPS.
- wineserver burns ~56% of a core during gameplay: sync/IPC overhead.
  gcenx 11.13 has **no** esync/msync client side (no WINE*SYNC env strings
  in ntdll.so) — a mage runtime built from upstream wine-staging + the OSS
  Kegworks msync patch is the structural fix.
- Fixed worker counts and machine-specific topology overrides are rejected.
  Threading stays application- and scheduler-owned.
- The semaphore-style and command-buffer-prefill overrides were measured and
  rejected. They are not Mage defaults.
  wine thread-priority→QoS patch — DONE 2026-07-21 in mage-wine (upstream's
  server-side Mach policies already worked; the real gap was the pthread
  QoS class, now mapped and probe-verified — see toolchains/wine-mage-11.13/
  BUILD.md; DOOM A/B still pending);
  native arm64 wineserver (novel, removes Rosetta from server traffic).
- Rosetta translated stacks are opaque to `sample` (all time lands in
  ntdll.so frames) — use the in-game HUD CPU ms as the metric.

## Perf experiments (one at a time, same scene, read HUD "CPU avg")

- `ROSETTA_ADVERTISE_AVX=1` launches cleanly; FPS delta not yet measured.
- Disable Steam overlay for DOOM (Steam > game Properties).
- GPU side has headroom; do not lower settings until CPU < GPU.
- ~~`WINEESYNC=1`~~ dead: esync is superseded in our tree — mage-wine
  11.13 has upstream inproc sync + the msync backend merged (client and
  server strings verified in the build). Use `WINEMSYNC=1`.

## mage-wine (own runtime, VALIDATED 2026-07-21 evening incl. DOOM)

- Built at `toolchains/wine-mage-11.13/install`: wine-11.13 + staging
  v11.13 + CX msync port + upstream `_thread_set_tsd_base` gsbase model
  (rebased off the fragile CX gs-mirror port — see A/B #2 below).
  Reproduction steps in `toolchains/wine-mage-11.13/BUILD.md`;
  debugging narrative in `toolchains/wine-mage-11.13/DEBUG-NOTES.md`.
- Verified: `wineboot --init` exit 0 with WINEMSYNC=1 ("msync: up and
  running."), `winecfg -v win10` OK, `explorer /desktop=x notepad.exe`
  runs, zero seh errors; non-msync path also clean.
- CAVEAT: wineboot needs `WINEDLLOVERRIDES=mscoree=d;mshtml=d` on this
  machine — without cached wine-mono, install_mono shows a download
  prompt and blocks wineboot forever.
- Root-cause fix #1 (macOS 27 platform change): libsystem tzcode keeps
  its per-thread localtime() buffer at gs:0x60 — the exact slot the
  CX/mrpippy gs-mirror uses for teb->Peb. localtime() scribbled a
  `struct tm` over the PEB (zeroed LdrData/ProcessParameters/
  ProcessHeap) → AV in kernelbase!init_startup_info, kernel32 load
  c0000135. gs:0x20 is libsystem-reserved too. Fix: swap gs:0x20/0x60
  to saved libsystem values on PE→unix transitions and back on return
  (signal_x86_64.c; asm swaps in the syscall/unix-call dispatchers +
  call_user_mode_callback). gs:0x30/0x58 stay permanently mirrored.
  CX 26.2 itself very likely hits this on macOS 27 — worth reporting
  upstream. v1 limitation: unix signal handlers for PE faults run with
  mirrors active.
- Root-cause fix #2 (latent upstream win32u bug): fresh
  explorer-virtual-desktop monitor reports 0x0 modes →
  monitor_get_dpi → make_ratio(0,0) → SIGFPE in NtUserSetThreadDesktop.
  Fix: skip scale ratios when current mode is 0x0 (win32u/sysparams.c).

## Research (persistent docs)

- `docs/research/perf-goldmines.md` — consolidated deep research:
  execution engines, graphics boundary, sync/IPC, profiling. Ranked
  mines + contradictions of earlier assumptions.
- Top findings: (1) measure first (Metal System Trace +
  MVK_CONFIG_TRACE_VULKAN_CALLS=5 + WINEDEBUG=+server histogram);
  (2) gfxstream render server = guest Vulkan encoder as
  `libvulkan.dylib` (via existing dlopen hook) → native arm64 MoltenVK
  renderer, moves MoltenVK CPU work out of the translated process;
  (3) remaining wineserver traffic is timer/IOCP/queue/lifecycle, not
  sync; (4) macOS 27 is the last macOS with full Rosetta — hybrid
  ARM64EC (Hangover-style) becomes mandatory long-term.

## A/B #1 result (2026-07-21, mage/docs/testing/ab-20260721/RESULTS.md)

- gcenx baseline (menu): DOOMx64vk.exe ~160% CPU, wineserver ~28% CPU,
  Metal HUD 60 FPS.
- mage-wine: Steam + steamwebhelper run (msync confirmed up), but DOOM
  dies 2-5s after applaunch — ~10 game threads fault simultaneously on
  `movq %gs:0x58` → 0 plus wild jumps. NOT msync, NOT the overlay.
  The gs-mirror model is fundamentally fragile on macOS 27 (Rosetta or
  libsystem writes pthread TSD slots outside every covered swap path).
- Fixed along the way: gs:0x58 swap extension (steam.exe startup),
  dbghelp DWARF div-by-zero SIGFPE (our unstripped llvm-mingw PEs).

## A/B #2 result (2026-07-21 evening, same RESULTS.md) — gsbase rebase WINS

- mage-wine rebased from CX gs-mirror onto upstream 11.13's
  `_thread_set_tsd_base` gsbase-switching model (PE threads run with the
  real TEB as gs base). Kept only msync + the CX Rosetta hacks; removed
  all mirror machinery incl. the 3 loader.c TLS-mirror pokes.
- DOOM NOW RUNS: booted via Steam applaunch straight into the campaign
  (auto-continued save), windowed 1512x982, alive 155s+. Metal HUD:
  **66 FPS in-game, CPU 12.30 ms avg, GPU 8.53 ms, Vulkan 1.0.357**.
- 60s sampling (in-game, n=12): DOOMx64vk.exe 260.1% CPU,
  **wineserver 12.9% vs gcenx's 28.4% — msync halves wineserver CPU**.
  Screenshot: ab-20260721/mage-menu2.png.
- Separate non-gs fix required: Vulkan discovery. Our win32u dlopens bare
  `libvulkan.1.dylib` but our build lacks gcenx's `@loader_path/../../`
  rpath, and DYLD_FALLBACK_LIBRARY_PATH doesn't reliably reach
  Steam-spawned games → vkCreateInstance VK_ERROR_INITIALIZATION_FAILED
  (was also the real cause of this morning's mirror-era DOOM deaths).
  Fixed via libvulkan.1.dylib symlink inside win32u.so's rpath
  (install/lib/wine/x86_64-unix/). Proper build fix = follow-up.
- Launch note: dttdrv DOOMConfig.local had no r_fullscreen line; applaunch
  now uses `+r_fullscreen 0` (windowed only — exclusive fullscreen still
  untested/unsafe with winemac).

## Native arm64 wineserver (spike DONE 2026-07-21, toolchains/wine-mage-11.13/ARM64-WINESERVER.md)

- FEASIBLE + working: 634/634 protocol records byte-identical x86_64 vs
  arm64 (fixed-width wire format, LP64 LE both sides). One 1-hunk patch:
  server/registry.c init_supported_machines() must present [AMD64, I386]
  (else image mapping rejects every exe).
- Build: out-of-tree build-arm64/ (arm64-apple-darwin configure),
  `make server/wineserver` + nls. Integration: pre-start per-prefix
  (`wineserver -p`); server and clients must agree on WINEMSYNC.
- Bench (srvbench, 3×1.5M op-pairs): server CPU −6.8%; client op
  latency unchanged (IPC-bound). Removes one Rosetta process per
  session; expect low-single-digit total-CPU effect in games.
- OPEN: one-time crash under load — mach_vm_map KERN_NO_SPACE in
  msync.c get_shm() → SIGSEGV (MACH_CHECK_ERROR falls through; latent
  in x86_64 server too). Root-cause before productizing.

## Open items

- ~~Mage productization: launcher identity, recipe packaging~~ DONE
  2026-07-21: 0.1 alpha CLI (`mage/bin/mage`, stdlib-only python3) with
  JSON recipes (`recipes/doom2016.json`), runtime registry
  (`runtimes/mage-wine-11.13.json`), prefix import, `--dry-run`, and
  `doctor` diagnostics. Spec: docs/specs/2026-07-21-mage-0.1-alpha-design.md.
  Remaining: live `mage run` verification (dry-run matches doom-run.sh
  exactly; untested live while the user was playing).
- ~~mage 0.2 SwiftUI GUI~~ DONE 2026-07-23: `mage/app/` — thin SwiftUI shell
  (`Mage.app`) over the CLI core, built with plain swiftc against the macOS
  26 SDK (27 SDK's `@State` macro requires Xcode's SwiftUIMacros plugin;
  CLT-only). Reads the same JSON, shells out to `bin/mage` for
  install/run/doctor with streaming log panel. Verified in-GUI: bottle/recipe
  list, detail view, Dry Run, Doctor. Live Run via GUI still unverified.
- ~~mage 0.3 library redesign~~ DONE 2026-07-24: Whisky/Heroic-style library
  on top of Steam — ACF manifest scan per prefix, art-card grid from Steam
  librarycache, per-game detail with Run/Dry Run/Doctor + Advanced editor
  (runtime picker, imported-prefix change, env table, ordered launch steps;
  Save writes `recipes/<id>.json`). Recipe-less Steam games get Play via
  Steam (`steam://` URL into the prefix's Steam) and Set up with Mage
  (recipe template + CLI import). Steamworks Common Redistributables
  (appid 228980) filtered. Requires macOS 26 (Liquid Glass). Verified
  in-GUI: grid, detail, Advanced round trip, Dry Run streaming, Bottles
  list. Live Run and Set-up-with-Mage on a second bottle still unverified.
- mage 0.3.1 UI correction (user feedback 2026-07-24): bottles removed
  from the UI surface — sidebar is Library-only, prefix management lives
  in Advanced + CLI (user: "we were going to do this without bottles").
  All glass buttons switched to capsule border shape. Known env settings
  are now toggles, not key=value rows: quick row on the game page (Metal
  HUD, msync, Advertise AVX — auto-saves to the recipe) + full set in a
  Features section in Advanced (adds Silence Wine logging); the raw env
  table remains for anything else. Toggle round trip verified against
  doom2016.json.
- mage 0.3.2 (2026-07-24): deployment floor raised to macOS 26 everywhere
  (build-moltenvk.sh, BUILD.md, runtime notes — user decision, nothing
  below Tahoe). Framerate cap option: FPS cap picker on the game page and
  in Advanced (Off/30/60/90/120/144), stored as MVK_CONFIG_FRAME_RATE_CAP
  in recipe env — UI round trip verified; MoltenVK-side throttle DONE in
  mage/vendor/MoltenVK (43-line, 5-file diff: frameRateCapFPS config
  member + usleep clamp in MVKQueue::submit(VkPresentInfoKHR)), built
  universal at the 26.0 floor → mage/dist/runtime/lib/libMoltenVK.1.4.2.dylib
  (env string verified in binary). STILL TO DO: stage that dylib into the
  live runtime (toolchains/wine-mage-11.13/install-*/lib + libvulkan.1.dylib
  symlink) and A/B the cap in-game — deliberately not staged mid-session.
  Steam black-window work: added -cef-disable-gpu
  and -cef-disable-gpu-compositing to the doom2016 Steam launch step —
  takes effect on the next fresh Steam launch (running client was NOT
  restarted; hard rule). Text rendering still broken is a separate known
  issue (freetype/fontconfig are OFF in the current wine build — see
  BUILD.md dependency tradeoff; likely related).

- ~~Rebase mage-wine on upstream gsbase model, then redo DOOM A/B.~~ DONE
  2026-07-21 evening — DOOM runs in-game at 66 FPS (A/B #2 above).
- Build and package the clean `mage/vendor/MoltenVK` branch at a macOS 26
  deployment target (floor raised from 12 → 26 on 2026-07-24, user decision:
  nothing below Tahoe is supported, same for mage-wine — BUILD.md updated)
  so the runtime does not depend on external worktrees or
  absolute libvulkan symlinks.
- ~~Measurement day: xctrace Metal System Trace +
  MVK_CONFIG_TRACE_VULKAN_CALLS=5 + WINEDEBUG=+timestamp,+server
  histogram — decompose the 13.5 ms CPU frame before building anything.~~
  DONE 2026-07-21 (mage/docs/testing/measure-20260721/RESULTS.md).
  In-game Foundry A/B: baseline 82–92 FPS, DOOM 280.3% CPU, wineserver
  12.1% (~4% of total — no longer the target); semaphore style=2 (MTLEvent)
  safe but no measurable benefit. Dominant MoltenVK-visible CPU cost =
  2 blocking vkGetQueryPoolResults/frame (GPU-timestamp/occlusion readback
  stalls the render thread, ~5.7 ms/call under trace), then vkQueueSubmit
  (~1 ms/call, 2/frame); cmd-buffer recording is noise. wineserver does
  ~39.7k req/s, almost all async-IO/window plumbing, not sync. Gaps:
  xctrace impossible (no Xcode), sample can't see through Rosetta, id perf
  overlay renders only in some sessions (cause unknown). Also found:
  new-campaign "The UAC" load silently kills the game process (graceful
  exit, no crash log) — slot-2 Foundry continue is the reliable path in.
- Exclusive fullscreen / alt-tab behavior (Proton #583; CX wedge may
  also exist in gcenx fullscreen — untested).
- Next game session must capture: (1) per-PID +server histogram (residual
  33k/s recv_socket/set_async_direct_result traffic — attribute to
  Steam/CEF vs game), (2) MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS=1 A/B
  (untested lever, minutes), (3) ROSETTA_ADVERTISE_AVX=1 A/B — CPUID
  probe VERIFIED on macOS 27 (AVX/AVX2/OSXSAVE bits flip on, XCR0 has
  XMM+YMM; AVX512 stays off), but translated AVX can be slower than SSE
  (NEON-pair emulation) so it needs a real FPS A/B, not assumption,
  (4) vkCreateSwapchainKHR params from the trace: B1 log shows only 2
  swapchain images (double-buffered); check presentMode (FIFO vs
  mailbox) — double-buffer FIFO is a potential frame-pacing limiter.
- gfxstream render server: NO-GO for now — decision + reassess triggers
  documented in docs/research/perf-goldmines.md "Decision log".
- Query early-availability patch (MoltenVK 64c6d634): menu-only A/B done
  2026-07-21 (screen locked; no input path into Foundry — boot +commands
  map/devmap/loadGame all dropped). Patched Release dylib == baseline at
  menu (CPU within noise, same 2 benign mvk-errors, no device-lost).
  Decisive in-scene query-blocking A/B still pending an unlocked machine;
  protocol + builds staged in
  docs/testing/measure-20260721/QUERYPATCH-RESULTS.md.

## 2026-07-27: Steam UI fully working (wrapper + fontconfig)

- Steam library/store UI renders WITH text: steamwebhelper wrapper
  (mage/tools/steamwebhelper-wrapper, --disable-gpu --single-process)
  + fontconfig in mage-wine (deps-macos26; see toolchains/wine-mage-11.13/BUILD.md
  "Fonts / fontconfig"). Wrapper must be chflags-uchg'd or Steam self-heal
  deletes it — use the install.sh in the wrapper dir.
- Full saga + matrix: docs/research/2026-07-26-moltenvk-external-memory-fd.md §12-13.

## UX roadmap (from user feedback 2026-07-27)

- Onboarding flow: first-run setup (locate mage root, detect/install Steam
  into a managed bottle, offer Steam sign-in or API key, import existing
  prefixes). Currently the app assumes a working setup.
- Native macOS control polish: buttons should follow current macOS HIG
  (rounded/prominent styles per mage/docs/design-guidelines.md) — several
  views still use ad-hoc squared buttons.
- Window hygiene: one visible window per app (Steam xor game + legit
  popups); stray helper windows (console wrappers etc.) must never appear —
  GUI-subsystem steamwebhelper wrapper is the pattern.
- winemac app naming (in progress): menu bar/Dock show the Windows app name
  instead of "Wine".

## 2026-07-27: Mage.app installed + icon pipeline

- `/Applications/Mage.app` now installed via `mage/app/Makefile` `install`
  target (ditto; no sudo needed). First launch needs the mage root:
  `defaults write app.mage.runner MageRootOverride -string <path-to-mage>`
  (already set on this machine; onboarding will own this properly later).
- Icon pipeline: source = `mage/app/Resources/Icon/icon-light.png` +
  `icon-dark.png` (1024x1024). DROP-IN SWAP: replace those two PNGs, run
  `make build install` — the Makefile regenerates all catalog sizes with
  sips and recompiles with actool (needs DEVELOPER_DIR pointed at the
  Xcode 27 beta; CLT's actool refuses). Placeholder art is from
  `tools/render-icons.swift` (only runs when PNGs are missing — never
  overwrites user art). User may replace artwork (Codex-generated).
- KNOWN: actool silently drops mac dark-appearance entries from the
  appiconset (verified: Assets.car has light renditions only). Proper
  Tahoe adaptive icons (light/dark/tinted) need an Icon Composer `.icon`
  file — adopt once final artwork exists.

## 2026-07-27: per-app Dock/menu-bar names ("Steam" instead of "Wine")

Root cause (two layers): (1) wine's loader binary embeds an Info.plist
(__TEXT,__info_plist, loader/wine_info.plist.in) with CFBundleName "Wine" —
Launch Services uses it at checkin and NSProcessInfo setProcessName CANNOT
override it (agent-7's winemac setProcessName patch was verified ineffective,
reverted). (2) ntdll re-execs the loader by the fixed name "wine"
(dlls/ntdll/unix/loader.c loader_exec), so renaming the binary alone fails.

Fix (verified: Dock tile + menu bar show "Steam", lsappinfo name "Steam"):
- mage-wine ntdll patch: loader_exec honors MAGE_APP_NAME — if a same-named
  executable sibling of lib/wine/x86_64-unix/wine exists, it is exec'd as the
  final loader instead of "wine".
- mage/tools/wine-app-name/patch-wine-loader-name.py: creates that sibling —
  a copy of the loader with CFBundleName/CFBundleExecutable/CFBundleIdentifier
  rewritten in the embedded plist (Mach-O section size patched; section has
  file slack). Idempotent (mtime check).
- bin/mage run: derives the app name from each launch step's program
  (steam.exe -> "Steam"), ensures the loader copy, sets MAGE_APP_NAME.
  Per-game names come free when a recipe launches the game exe directly.

Note: the "Steam" loader copy lives in the install tree (not rebuilt by
make install; regenerate with the tool if the loader is ever relinked).

## 2026-07-28: steamwebhelper fork-loop incident (DOOM launch broken)

Symptom: "cmd window appears, no game, resources strained" — ~37 wine
processes, all steamwebhelper_real.exe with the wrapper's flag block
appended dozens of times, 90 MB of log spam in one minute.

Root cause: the tools wrapper was rebuilt (GUI-subsystem, 13:01) while the
prefix still had the OLD wrapper build installed. At the next `mage run`,
ensure_steam_wrapper saw byte mismatch and "backed up" the OLD WRAPPER as
steamwebhelper_real.exe (destroying the real Valve binary). Wrapper execs
_real → _real is a wrapper → execs itself with flags appended → fork loop,
~25 generations in one second.

Fix (three layers):
1. Recovered Valve's binary from Steam-client-backup-1417 → _real.
2. Wrapper now embeds MAGE-STEAMWEBHELPER-WRAPPER-v1 marker and REFUSES to
   exec a _real that contains it (exits 2 with a message instead of looping).
   Also rebuilt with CREATE_NO_WINDOW — kills the stray console window titled
   "steamwebhelper_real.exe" (the "cmd" the user saw). Auto-deploys at next
   mage run via ensure_steam_wrapper.
3. ensure_steam_wrapper (bin/mage) + install.sh are marker-based now: a file
   with the marker is NEVER backed up as _real; a _real WITH the marker is
   quarantined (steamwebhelper_real.CORRUPT-do-not-use.exe) / errors out.

Verified after fix: 9 wine processes total, Steam UI + Special Offers
render, DOOMx64vk launches and plays (~58 FPS in menu). DOOM + Steam
windows register as "Steam" in Dock/menu bar (MAGE_APP_NAME).

## 2026-07-27 (late): ENOMEM mmap-spam patch (perf-dip suspect)

Symptom: `$TMPDIR/mage-doom2016.log` grows by ~95 lines/sec from ONE thread
(0488), all identical: `err:virtual:try_map_free_area mmap() error Cannot
allocate memory, range 0x7ffffffe0000-0x7fffffff0000, unix_prot 0x3`
(62,796 lines in one session). Not a retry loop — one failed probe per
top-down VirtualAlloc by that thread.

Root cause: under Rosetta, fixed mmaps at/above macOS's max user address
fail with ENOMEM, not EEXIST. Upstream `try_map_free_area` treats only
EEXIST as "natively occupied" (→ staging's native-exclusion machinery
removes the range from the free list). ENOMEM instead prints ERR and the
range stays "free", so every subsequent top-down allocation re-probes it:
failed mmap syscall + log line + virtual_mutex churn, ~95×/sec — a plausible
contributor to the transient FPS dips the user reported.

Patch (mage, `dlls/ntdll/unix/virtual.c`): on `__APPLE__`, treat ENOMEM
like EEXIST in try_map_free_area. First alloc detects the range as native,
excludes it from the free list; spam and re-probing stop. Documented in
toolchains/wine-mage-11.13/BUILD.md "mage patches".

Status: DEPLOYED 2026-07-28 01:00 — `ntdll.so` copied into
`install-macos12-freetype/lib/wine/x86_64-unix/` (backup `ntdll.so.pre-enomem`).
Verify next session: log should contain at most a handful of
try_map_free_area lines (first probe only).

Cursor fix (winemac, also DEPLOYED 2026-07-28 01:00, backup
`winemac.so.pre-cursorfix`): root cause was two defects in
`dlls/winemac.drv/cocoa_app.m` making the hidden-cursor state non-sticky —
(1) `updateCursor:`'s else branch unconditionally set the arrow cursor and
unhid it whenever the pointer was over a foreign window (state after any
alt-tab), and DOOM never re-sends SetCursor, so it stayed visible;
(2) `applicationDidBecomeActive:` only re-applied cursor state if a
cursorUpdatePending flag happened to be set, but AppKit auto-unhides on
resign-active. Patch: `updateCursor:` honors `clientWantsCursorHidden` in
that branch, and activation always re-syncs cursor state. Built and
deployed to the install tree; verify next session: cursor must stay hidden
after alt-tabbing away and back while playing.

Still open from user report: (a) remaining FPS dips —
A/B levers in docs/research/perf-goldmines.md (PREFILL_METAL_COMMAND_BUFFERS,
swapchain present-mode check, ROSETTA_ADVERTISE_AVX off-test);
(c) black spots on enemies — suspect MVK_CONFIG_FAKE_NULL_DESCRIPTOR,
already removed from recipe, awaiting user confirmation.

## 2026-07-28: GitHub repo + 0.4.0 (updates, headless installs)

- Repo live: github.com/dttdrv/mage (mage/ only; vendor, prefixes,
  docs/testing, venvs, steam-bridge/auth gitignored — auth holds the
  live Steam session token, never commit it).
- 0.4.0: Updater.swift checks the latest GitHub release on launch
  (silent) and from Settings; downloads the zip asset, trashes the old
  /Applications/Mage.app, installs the new one, relaunches, restores
  the old app from Trash on failure. Releases: zip via
  `ditto -c -k --keepParent /Applications/Mage.app`, `gh release create`.
- Headless installs: `bin/mage steam-install <bottle> <appid>` starts
  Steam with -silent (+nobootstrapupdate/-skipinitialbootstrap/
  -noverifyfiles/-cef-disable-gpu*), waits for the ActiveProcess
  registry pid, forwards `+app_install <appid>` (second-process
  single-instance IPC; first forward can time out while the client
  warms — retry), polls appmanifest_<id>.acf StateFlags (4 = installed)
  plus steamapps/downloading/<id> size, streams JSON progress lines.
  Verified live with appid 379720: no Steam window, no leftover wine
  processes. App game pages show Install + progress for owned games.
