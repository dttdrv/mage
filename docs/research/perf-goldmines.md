# Perf gold mines — consolidated research (2026-07-20)

Consolidation of four deep-research agents covering: (1) alternative x86→arm64
execution engines / hybrid architectures, (2) graphics-boundary architectures,
(3) Wine sync/IPC overhead, (4) measurement/profiling of Rosetta-translated
processes.

Baseline (from STATE.md): DOOM 2016 in-game ~73 FPS at 2560×1600 Ultra,
CPU-bound (HUD: CPU 13.5 ms, GPU 10.1 ms). wineserver ~56% of one core.
Stack: Wine 11.13 wow64 entirely under Rosetta 2 — game, Wine PE DLLs, Wine
Unix libs, and x86_64 MoltenVK all translated; only Apple frameworks native.
Current mage tree `toolchains/wine-mage-11.13/src` already carries upstream
`inproc_sync` + an msync backend (`dlls/ntdll/unix/msync.c`, `server/msync.c`,
`server/mach.c`).

Legend: **[V]** verified against cited primary source or local tree;
**[I]** inference; **[U]** unverified (self-reported or unreproduced).

---

## 1. Execution engines & hybrid architectures

### 1.1 CodeWeavers is building the hybrid for macOS right now **[V]**

- CrossOver 27 will ship **native ARM64 Mac builds that run x86_64 Windows
  games without Rosetta 2**: Wine wow64 + **ARM64EC builtins + FEX** as the
  emulator. Motivation is existential: "Rosetta 2 will be largely discontinued
  with macOS 28 in 2027."
  https://www.codeweavers.com/blog/mjohnson/2026/6/11/whats-in-and-whats-out-for-crossover-27
- Corollary: **macOS 27 is the last macOS with full Rosetta 2**; macOS 28
  keeps only a subset for legacy games.
  https://www.macrumors.com/2026/06/10/macos-golden-gate-last-to-support-intel-apps/
- Wine 10.0 shipped full ARM64EC support (needs LLVM 21 for ARM64EC codegen).
  CodeWeavers' Linux ARM64 preview shipped Nov 2025 (Cyberpunk 120 fps on
  Ampere Altra); Mac ARM64 "in development."
  https://www.codeweavers.com/blog/mjohnson/2025/11/6/twist-our-arm64-heres-the-latest-crossover-preview
  https://www.phoronix.com/news/CrossOver-Linux-ARM64
- **FEX upstream already contains a Wine WOW64/ARM64EC PE module**
  (`Source/Windows/{ARM64EC,WOW64,UnixLib}`) — FEX-as-a-DLL inside a
  native Wine process is an upstream-supported configuration.
  https://github.com/FEX-Emu/FEX
- Impact for mage: architectural ceiling — wineserver, all Wine PE DLL
  internals, Unix libs, and (potentially) native arm64 MoltenVK stop paying
  translation; only game code is emulated. Caveat: FEX is slower than Rosetta
  on the game code itself (~20% typical, §1.3), so net win depends on the
  game-vs-Wine split of the 13.5 ms.
- Everything underneath CrossOver is upstream (Wine wow64/ARM64EC, LLVM 21,
  FEX WOW64 module). CodeWeavers' macOS work lands in Wine/FEX upstream over
  time — **track WineHQ for the macOS page-size/ARM64EC patches; they are the
  key enabler for any third-party hybrid on macOS.**

### 1.2 Hangover 11.0 — the open-source reference hybrid **[V]**

- Wine wow64 where emulator DLLs (`libarm64ecfex.dll` = FEX, `wowbox64.dll` =
  Box64) emulate **only the application**; all Windows/Wine syscalls and
  everything Unix executes natively. 64-bit uses ARM64EC ABI + FEX; ships
  DXVK in ARM64EC and aarch64 builds. Hangover 11.0 (Jan 2026, on Wine 11.0)
  **removed QEMU support** — FEX/Box64 only.
  https://github.com/AndreRH/hangover
  https://www.phoronix.com/news/Hangover-11.0-Released
  https://github.com/AndreRH/hangover/tree/master/benchmarks
- Maturity: actively released, tracks Wine 11.x; Linux-only; "expect issues."
- What blocks it on macOS:
  1. FEX is Linux-only upstream ("We don't support MacOS" —
     https://github.com/FEX-Emu/FEX/discussions/5049). CodeWeavers' Mac port
     proves it's feasible.
  2. **4K vs 16K pages**: XNU gives native arm64 processes 16K pages; only
     Rosetta-launched processes get 4K. FEX wants 4K host pages (this is why
     muvm exists on Asahi).
     https://docs.fedoraproject.org/es/fedora-asahi-remix/x86-support/ **[V
     for the Asahi side; macOS-side severity is I]**

### 1.3 Alternative engines on macOS

- **FEX** — Linux-only upstream; Valve-funded since inception, ships in Steam
  Frame (Snapdragon ARM64 + Proton); Fedora 42+ and an Ubuntu ARM64 Steam beta
  build on it. Monthly releases. Perf vs Rosetta **[V]**: Geekbench 6
  single-core under FEX/muvm < half of Rosetta; real-world apps **~8–45%
  slower than Rosetta (most ~20%)** on M2 Max. Both exploit Apple CPUs'
  hardware TSO mode.
  https://gist.github.com/jankais3r/8662956dd57e02a3b75f0500e86025ea
  Transferable ideas without porting: per-app skip of memory-model emulation,
  persistent JIT code cache, thunklib forwarding to native libraries.
- **Box64** — Linux/*BSD only; no macOS path
  (https://github.com/ptitSeb/box64/discussions/954). 7-zip on M1: Box64 ≈
  57% of native vs Rosetta 71% (https://box86.org/2022/03/box86-box64-vs-qemu-vs-fex-vs-rosetta2/).
  Not a Rosetta replacement; idea worth stealing is native-library wrapping.
- **QEMU-user (TCG)** — slowest (~16% of native; 12 s/frame OpenArena),
  removed from Hangover 11.0, no macOS host support. **Verified dead end.**
- **Blink** — Hangover lists integration as "started," not in-tree; runs on
  macOS arm64 **[I]** but interpreter-class perf. Not competitive at 73 FPS.

### 1.4 GPTK evaluation environment — no secret engine **[V]**

- GPTK's Wine is built from CrossOver 22.1.1 sources + Apple patch
  (https://github.com/Apple/homebrew-apple/blob/main/Formula/game-porting-toolkit.rb).
  Differences: (1) it bundles a **newer internal Rosetta build** ("Rosetta
  v0.2" badge in HUD); (2) D3DMetal (irrelevant for native-Vulkan games);
  (3) compat patches. GPTK 3 (macOS 26) added Metal 4 + customizable Metal
  Performance HUD. No CPU-side technique mage doesn't already have.

### 1.5 VM-based hybrid (muvm-on-macOS)

- libkrun/krunkit runs microVMs on macOS via Hypervisor.framework with
  **virtio-gpu Venus → host MoltenVK** (Vulkan in guest, native arm64 Metal
  on host); proven in production by Podman's GPU-accelerated AI containers.
  https://developers.redhat.com/articles/2025/06/05/how-we-improved-ai-inference-macos-podman-containers
  https://github.com/libkrun/libkrun
- Rosetta-inside-libkrun-Linux-VM is **not viable** (Apple's Rosetta-for-
  Linux needs virtiofs support libkrun lacks —
  https://github.com/tnk4on/podman-fex). So the VM path = arm64 Linux guest +
  Hangover (FEX+Wine, all native arm64) + Venus→MoltenVK.
- All components exist and are individually proven; **nobody has assembled it
  for gaming** — presentation, input latency, wineserver-in-VM unbuilt.
  Assemble-it-yourself spike (weekend-to-months), not a product.
  Same perf split as Hangover: everything-but-game native, game on FEX
  (~20% slower than Rosetta), plus VM-boundary overhead.

### 1.6 OS-level levers (cheap, additive)

- **Game Mode** **[V]**: macOS gives games highest CPU/GPU priority and
  suppresses background tasks; gated on `LSApplicationCategoryType =
  public.app-category.games` + native fullscreen. For a CPU-bound title with
  wineserver competing for cores this is a free lever — mage's launcher
  identity should claim it.
  https://github.com/electron/electron/issues/42588
- **AOT cache hygiene** [I]: Rosetta AOT translations are cached per-binary
  in `/var/db/oahd`; keeping game/Wine binaries content- and location-stable
  preserves warm translation. (Mechanism verified via Champollion; tuning
  payoff unverified.)
- **Page sizes**: XNU per-process page size is *why* Rosetta needs no muvm —
  and conversely the trap for any native-arm64-Wine + emulator port.

### 1.7 Correction to a prior assumption

In a Rosetta process, Apple system frameworks do **not** run as plain native
ARM — Apple ships pre-translated AOT artifacts (`/var/db/oahd`,
`aot_shared_cache` next to the dyld cache). Still arm64 code, but
translation-produced. (Apple Platform Security; FFRI Champollion;
https://i.blackhat.com/Asia-23/AS-23-Koh-Dirty-Bin-Cache-A-New-Code-Injection-Poisoning-Binary-Translation-Cache.pdf)

---

## 2. Graphics boundary: moving driver CPU work out of the translated process

Bottom line: the target architecture — a serialized Vulkan stream from the
x86 wine process to a **native arm64 render server** running
MoltenVK/KosmicKrisp — has production-grade prior art (gfxstream, used
exactly this way on macOS by the Android Emulator). The insertion point is a
drop-in `libvulkan.dylib` replacement (Wine's unix side just `dlopen`s it);
**no Wine fork required for a prototype**. The genuinely unsolved piece is
presentation. Nothing found in 2025–2026 builds a native arm64 Vulkan ICD
for Wine-on-macOS.

### 2.0 Constraints verified against local tree **[V]**

- winevulkan per-call path (Wine 11): every Vulkan function incl. hot-path
  `vkCmdDraw` packs a params struct → `UNIX_CALL` → `__wine_unix_call` →
  indirect call through `__wine_unix_call_dispatcher` (`dlls/ntdll/loader.c`)
  — **no kernel syscall for 64-bit apps**. Fixed per-call cost: params pack +
  indirect call + thunk + Wine handle-unwrapping (every VkCommandBuffer etc.
  converted to host handles) + dispatch-table call into host libvulkan.
  **No batching, no command stream, no fast path** — one hop per call, 1:1.
- Host library loading: `dlls/win32u/vulkan.c` plain `dlopen(libvulkan)`;
  cx builds have a `CX_LIBVULKAN` env override (CW HACK 25909). **This is the
  insertion point.**
- **D3DMetal does not avoid translation**: CrossOver's D3DMetal hooks are
  `#if defined(__x86_64__)` (`dlls/winemac.drv/d3dmetal.c:24`); D3DMetal.
  framework loads as x86_64 into the translated process and crosses the same
  PE→unix hop. GPTK/CrossOver have no fast path mage lacks.
  (cf. https://carette.xyz/posts/deep_dive_into_crossover/)
- **Rosetta processes cannot load arm64 code** (except Apple frameworks) —
  in-process native driver is impossible; **out-of-process + shared memory is
  the only architecture available** on macOS. macOS has no ARM64EC
  equivalent. [Apple Rosetta docs + I]
- Metal shader JIT is already native (arm64 `MTLCompilerService` daemons);
  what runs translated is MoltenVK's API-side validation/encoding, not
  shader compilation. [I]
- MoltenVK CPU overhead is a known native-side complaint too
  (https://github.com/KhronosGroup/MoltenVK/issues/1409,
  https://github.com/KhronosGroup/MoltenVK/issues/1749 — old debug-era
  builds, directional only).

### 2.1 gfxstream (Google) — strongest match **[V]**

- Codegen'd Vulkan/GLES serializer: guest encoder writes to a **ring
  buffer**; host decodes 1:1 thread per guest encoder thread, forwards
  verbatim to a real host Vulkan driver after handle/memory remapping.
  Designed for process-to-process IPC and network, not just VMs.
  https://github.com/google/gfxstream
  https://www.phoronix.com/news/Mesa-Gfxstream-Merged
- **macOS host is production-proven**: the Android Emulator on macOS runs
  gfxstream's host renderer over MoltenVK (`ANDROID_EMU_VK_ICD=moltenvk`).
  Walkthrough: https://github.com/aospbooks/android-emulator-internal-book/blob/main/13-host-rendering.md
  UTM's maintainer upstreamed macOS fixes
  (https://github.com/google/gfxstream/pull/74/files). Google sponsors
  KosmicKrisp precisely to accelerate Android emulation on macOS
  (https://www.phoronix.com/news/KosmicKrisp-Merged-Mesa-26.0).
- Guest-side pieces ship as ordinary client libraries (Linux/macOS/Windows
  vk/gles libs); Mesa 24.3+ has a gfxstream guest Vulkan driver.
- **How it plugs into mage**: build the gfxstream guest encoder as an
  x86_64 `libvulkan.dylib`, point Wine's `dlopen` at it (via
  `CX_LIBVULKAN`/`SONAME_LIBVULKAN`). winevulkan thunks/handle wrapping stay
  in-process (cheap-ish); all MoltenVK encoding moves to a **native arm64
  render server** (gfxstream host lib is a standalone dylib with a small
  `Renderer` API — the same lib serves QEMU and crosvm).
- Maturity: production (every Android Emulator host on macOS). Reusability:
  moderate — Bazel/CMake AOSP-heritage build; reuse codegen + transports,
  write the Wine-facing libvulkan shim and the presentation bridge.
- Expected win [I]: serialization into a lock-free ring is far cheaper than
  executing MoltenVK translated; driver CPU work runs native (~20–40% faster
  than translated, typical Rosetta penalty) *and* off the game's threads.
  If winevulkan+MoltenVK is ~3–4 ms of the 13.5 ms CPU frame, realistic gain
  ~1.5–3 ms → ~85–95 FPS, potentially GPU-bound at ~100 FPS. **Unverified
  projection — no public benchmark isolates translated-vs-native MoltenVK.**

### 2.2 Venus / virtio-vulkan — design validation, wrong wire shape

- Mesa Venus guest driver + virglrenderer host; "thin layer… often close to
  host performance"; the only virglrenderer context already running in an
  isolated host process (`virgl_render_server`).
  https://www.collabora.com/news-and-blog/blog/2025/01/15/the-state-of-gfx-virtualization-using-virglrenderer/
- Already runs on macOS natively over KosmicKrisp
  (https://github.com/startergo/homebrew-virglrenderer); krunkit/libkrun
  ships Venus→MoltenVK for macOS VMs; QEMU ≥9.2 has `venus=on`; UTM notes
  **no Windows-guest support exists** (https://github.com/utmapp/UTM/issues/4551).
- Venus's guest half is a Mesa kernel-virtio driver (Linux guests only); no
  userspace-socket client library like gfxstream's. Take Venus as proof that
  thin Vulkan forwarding ≈ near-native and isolated render servers work on
  macOS — not as code to adopt. [I]

### 2.3 Hangover/FEX/Steam Frame — validates the perf model

Hangover breaks out of emulation at the wine unix-call level, so
winevulkan's unix side and the real Vulkan driver run native while only game
code is emulated; same architecture as Valve's Steam Frame (FEX + Proton).
Existence proof that "game translated, driver native" is the winning split.
On macOS it can't be done in-process → the out-of-process render server is
the macOS-equivalent form. [I]

### 2.4 Prior art for DIY pieces

- **WineD3D command stream** **[V, local]**: `dlls/wined3d/cs.c` queues ops
  for a separate driver thread — the template if building a minimal custom
  serializer instead of adopting gfxstream.
- **GFXReconstruct** (LunarG): full-Vulkan-call capture/serialization at
  acceptable runtime cost; paired with KosmicKrisp work
  (https://vulkan.org/user/pages/09.events/vulkanised-2026/1545-Richard-Wright-LunarG.pdf).
  Evidence a homegrown serializer at the `vk_funcs` table boundary (the
  table Wine fills via `__wine_get_vulkan_driver`) is feasible. [I]
- DXVK-native: concept analog only; nothing to reuse for a render server.

### 2.5 KosmicKrisp status **[V]**

Merged in Mesa 26.0 (Oct 2025), Vulkan 1.3 CTS-conformant, **MoltenVK
feature parity as of Feb 2026** (https://www.phoronix.com/news/KosmicKrisp-Parity).
Possibly lower CPU overhead than MoltenVK due to Mesa framework
(https://lobste.rs/s/fgz5oa [I]). Ideal host driver for the render server —
and what Google's gfxstream-on-macOS will converge on.

### 2.6 The hard, unsolved part: presentation

All VM-world designs present host-side; mage's window is an NSView/
CAMetalLayer created by translated `winemac.drv` code
(`macdrv_view_create_metal_view`). A native render server cannot take over
that layer. Options [I]:
(a) server renders into an **IOSurface** shared cross-process; wine side
    composites into the CAMetalLayer (cheap GPU copy, ≤~0.5 ms);
(b) server creates its own CALayer sub-window over the wine window
    (gfxstream already does Cocoa sub-windows: `native_sub_window_cocoa.mm`);
(c) swapchain emulation: `vkQueuePresentKHR` blits through a shared Metal
    texture.
Budget one extra surface sync either way.

---

## 3. Wine sync & IPC: true state of the art

### 3.1 Upstream in-process sync (merged, Wine 10.15 → 11.0) **[V]**

Elizabeth Figura's design (MR !7226,
https://gitlab.winehq.org/wine/wine/-/merge_requests/7226; v2 cover letter on
the wine-gitlab list): every waitable server object carries an `inproc_sync`
child object backing a primitive (ntsync on Linux); signal/wait tries the
`inproc_*` path first, falls back to server on `STATUS_NOT_IMPLEMENTED`.

- `get_sync` is implemented for: events, semaphores, mutexes, **waitable
  timers** (server signals expiry through the inproc event), processes,
  threads, jobs, startup_info, **IOCP completions**, message queues,
  async-cancel, debug objects, all fd-based objects (files, sockets, pipes,
  mailslots, change notifications), file locks. Coverage in 11.13 is
  essentially total — broader than the MR review letters suggest (the "waits
  on internal handles delegated to server" caveat was obsolete by merge).
- Access flags validated client-side; handle close via client-side cache
  with atomic release. First touch of any handle costs one
  `get_inproc_sync_fd` server round-trip, then cached.
- Shipped: Wine 10.15 initial, complete in 11.0; CrossOver 26 ships 11.0.
  https://www.phoronix.com/news/Wine-10.15-With-NTSYNC
  https://9to5linux.com/wine-11-officially-released-with-ntsync-support-vulkan-h-264-decoding-and-more

**What still round-trips to wineserver per frame [V, from local tree]:**
- Object lifecycle: `NtCreate*/NtOpen*/NtDuplicateObject/NtClose`.
- `NtSetTimer`/`NtCancelTimer`/`NtQueryTimer` — timer *waits* are in-process,
  but *arming* is a server request (games that re-arm a pacing timer per
  frame hit this).
- `NtRemoveIoCompletion`/`NtPostIoCompletion` — IOCP queue ops still server
  requests (threadpool-heavy engines).
- Message-queue traffic (`GetMessage`/`PeekMessage`, window ops, hooks,
  clipboard).
- Registry, object-namespace lookups, named-pipe connect/disconnect.
- Any object without `get_sync` in a multi-wait forces a full server wait.

**Implication:** mage already ported the hard 80% (msync behind the same
inproc abstraction). The remaining eliminable traffic is the list above —
not the sync primitives themselves. And **`WINEESYNC=1` (listed in STATE.md
perf experiments) is dead — esync is superseded by inproc/msync in this
tree; drop that experiment.**

### 3.2 fsync/ntsync history (stop tracking)

- esync: eventfd-per-object; rejected upstream (fd burn).
- fsync: futex+`futex_waitv` (Linux 5.16); **never merged upstream**, lives
  in Proton/wine-tkg; superseded by ntsync (same author, done in-kernel).
- ntsync kernel driver: skeleton in Linux 6.10 ("broken"), complete in
  **6.14** (March 2025).
  https://www.osnews.com/story/139283/linux-6-10-to-merge-ntsync-driver-for-emulating-windows-nt-synchronization-primitives/
  https://www.phoronix.com/news/Linux-6.14-NTSYNC-Driver-Ready
- Community consensus: ntsync ≈ fsync in FPS; headline triple-digit gains
  are all **vs vanilla wineserver sync**, not vs a fast backend. Since mage
  runs msync, those deltas do not apply.
  https://discuss.cachyos.org/t/ntsync-in-latest-proton-cachyos-wine-cachyos/5254/34

### 3.3 No ntsync-equivalent for macOS exists or is proposed **[V]**

Upstream's inproc framework has exactly one backend (Linux ntsync). What
does exist:

- **WFUSync** (https://github.com/Alien4042x/Wine-NTsync-Userspace-macOS-backend)
  — userspace ntsync-style backend for Wine 11.12 on macOS: Event/Mutex/
  Semaphore ops, WaitAny + atomic userspace WaitAll, fallback to wineserver
  for hard cases (manual-reset WaitAll, contended cases, semaphore query).
  Uses `os_sync_wait_on_address`/`os_sync_wake_by_address` (new macOS),
  `__ulock_wait`/`__ulock_wake` fallback, `os_unfair_lock` client cache,
  POSIX shm for cross-process state. Self-reported microbenches **[U]**:
  ~0.00058–0.00119 ms/op, **~10–13% faster than CrossOver msync**; synthetic,
  not independently reproduced, no game FPS data. Experimental v5,
  single-author. The *design* is directly liftable into mage's inproc
  backend slot; the code is reference material, not a drop-in.
- **marzent/wine-msync README** (the msync mage ported): a kernel extension
  would be faster, but Apple has discouraged kexts since macOS 11 —
  canonical answer to "could a real ntsync kext happen on macOS":
  technically yes, practically no.
  https://github.com/marzent/wine-msync/blob/main/README.md

Could ntsync's design map to Darwin better than mach semaphores? [I] The
hard parts (atomic multi-object acquire incl. WAIT_ALL with
consume-on-acquire, alert events, owner-tracked mutexes with abandonment,
atomic pulse) have **no multi-object wait primitive on Darwin** — so any
Darwin ntsync-equivalent is necessarily a fsync-style shared-memory
userspace scheme on `os_sync_wait_on_address` — exactly what WFUSync is. Its
edge over msync comes from avoiding msync's per-wait semaphore
register/unregister server message. Whether that survives real workloads is
unverified; mage's remaining 0.6-core wineserver cost may be elsewhere
(§3.1 list).

### 3.4 Wineserver overhead reductions: proposed, not merged

- Fast userspace RPC ("single context switch"): floated by Figura at LPC
  2023 as a half-baked idea; never implemented.
  https://lpc.events/event/17/contributions/1517/attachments/1257/2549/lpc2023.pdf
- Multi-threaded / shared-memory wineserver: does not exist upstream, not on
  any roadmap. Upstream direction is consistently "shrink what needs the
  server." Wineserver remains a single-threaded poll loop. **[V]**

### 3.5 PE→Unix transition cost

- Mechanism: `__wine_unix_call` dispatch over per-DLL syscall tables (the
  wine-9/10 wow64 rewrite). Writeup: https://blog.hiler.eu/wine-pe-to-unix/
- **Wine 11 added %GS register swapping on macOS** — directly reduces TLS-
  transition cost on macOS, one of the most expensive parts of a PE↔Unix
  crossing under Rosetta. **[V that it exists; I that it's a large win — no
  public measurements.]**
- Wine 11.5 added Syscall User Dispatch — Linux-only, not hot-path.
  https://www.gamingonlinux.com/2026/03/wine-11-5-released-with-support-for-syscall-user-dispatch-on-linux/
- **No public benchmark of per-transition cost under Rosetta exists.** Gap
  mage would have to measure itself.

### 3.6 Benchmarks (all vs vanilla Wine, CPU-bound)

From Figura's ntsync series: Dirt 3 110.6→860.7 FPS (+678%), RE2 26→77,
Call of Juarez 99.8→224.1, Tiny Tina's 130→360; "usually 40–200%."
https://www.phoronix.com/news/Linux-6.10-Merging-NTSYNC
ntsync vs fsync ≈ parity. **No published msync-vs-anything game FPS numbers
exist** — the only msync comparison anywhere is WFUSync's synthetic
microbench. For mage: sync primitives are already near-optimal with msync;
residual wineserver load comes from §3.1 leftovers — profile the request mix
before investing in a new wait primitive.

---

## 4. Measurement: how to see where translated CPU time goes

Framing fact [V, mechanism; I for PE implication]: only **Mach-O x86_64
binaries** (Wine unix libs, wineserver, x86_64 MoltenVK) get on-disk AOT
translations in `/var/db/oah`. **PE code (game exe, Wine PE DLLs) is
runtime-generated from Rosetta's view → JIT path**, cached only in-memory in
the runtime's translation tree. This determines which techniques recover
symbols.
https://ffri.github.io/ProjectChampollion/part1/

### 4.1 Rosetta translation-cache introspection (Champollion/FFRI) — the gold mine

Koh M. Nakagawa fully reverse-engineered Rosetta 2: AOT file format,
`LC_AOT_METADATA` load command, `aot_shared_cache` format (incl. per-image
**branch data and instruction maps recording arm64↔x86_64 address
correspondences**), and the runtime's red-black tree
(`find_translation_in_tree_x86`) mapping x86_64 PCs to translated addresses
for JIT code.
- https://ffri.github.io/ProjectChampollion/part1/
- https://ffri.github.io/ProjectChampollion/part2/
- https://github.com/FFRI/ProjectChampollion (parser, Apache-2.0)

Why it matters: `sample`/Instruments record raw **arm64** PCs. For Mach-O
components, the AOT instruction map maps a sampled PC back to an x86_64 RVA
→ symbolicate against mage's own build symbols (we build these binaries).
For PE (JIT) frames the mapping lives only in the runtime's live translation
tree: attach LLDB at arm64 level and walk the tree, or correlate with
`ROSETTA_PRINT_IR`. Maturity: research-grade, 2021-era (parser tested only
on macOS 11.1 — **[U] on macOS 27**). This is the only path that turns
opaque "Rosetta JIT" samples into per-module/per-function attribution.
Small-team feasible: parser reuse + a small LLDB tool, days of work.

Caveat: `/var/db/oah` is SIP-protected, but the AOT files are *mapped into
the game process* — `vmmap <pid>` shows paths/extents without SIP changes;
a `task_for_pid` reader on our own process avoids disabling SIP. [I]

### 4.2 Rosetta runtime debug modes (built-in, zero tooling) [V, 2021-era; U on macOS 27]

- `ROSETTA_PRINT_IR=1` — dumps every x86_64 basic block as translated (left
  column = x86 PC): effectively a coverage trace of executed x86 code.
  Enormous volume; use for seconds.
- `ROSETTA_PRINT_SEGMENTS=1` — prints where `runtime`, each AOT file, and
  every aot_shared_cache image is mapped → the address table to bucket
  `sample` PCs by module ("this range = MoltenVK.aot").
- Also: `ROSETTA_ALLOW_GUARD_PAGES`, `ROSETTA_DISABLE_EXCEPTIONS`,
  `ROSETTA_AOT_ERRORS_ARE_FATAL`.
- Background: https://dougallj.wordpress.com/2022/11/09/why-is-rosetta-2-fast/

### 4.3 Metal boundary — works perfectly despite translation (driver is native)

- **Metal Performance HUD**: `MTL_HUD_ENABLED=1` env — FPS, frame interval,
  GPU ms per frame.
  https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance
- **Metal System Trace**: `xctrace record --template 'Metal System Trace'
  --attach <pid> --output mst.trace` — CPU-side command-buffer encoding
  intervals, driver thread activity, GPU scheduling. Apple explicitly
  recommends it for Windows games under the translation-based evaluation
  environment — exactly mage's scenario.
  https://developer.apple.com/games/game-porting-toolkit/
  https://developer.apple.com/videos/play/wwdc2024/10089/
  Likely the most actionable 1-day experiment: decomposes "MoltenVK encoding
  vs driver vs GPU."
- **Headless .gputrace from MoltenVK**: `MTL_CAPTURE_ENABLED=1` +
  `MVK_CONFIG_AUTO_GPU_CAPTURE_SCOPE=2` (first frame) or `3` (trigger via
  named pipe — capture on demand mid-gameplay) +
  `MVK_CONFIG_AUTO_GPU_CAPTURE_OUTPUT_FILE=~/cap.gputrace`.
  https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Configuration_Parameters.md

### 4.4 MoltenVK CPU-side timing (verified, official docs)

- **`MVK_CONFIG_TRACE_VULKAN_CALLS=5`** (or `6` incl. thread IDs) — **logs
  time spent inside every Vulkan function call**: a per-API-call CPU
  profiler for the translation layer. Directly answers "how much of 13.5 ms
  is vkCmd*/vkQueueSubmit/vkCreateGraphicsPipelines." Heavy volume; run
  briefly. Standout find.
- `MVK_CONFIG_PERFORMANCE_TRACKING=1` +
  `MVK_CONFIG_PERFORMANCE_LOGGING_FRAME_COUNT=100` — periodic
  `MVKPerformanceStatistics` counters. Low overhead.
- Note: `MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE` doc mentions MTLEvent
  caveats on "some NVIDIA GPUs and **Rosetta2**" — MoltenVK behaves
  differently under translation; check which semaphore path the mage build
  takes (affects sync cost).
  https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Configuration_Parameters.md

### 4.5 PE-side (Wine) measurement — the only route to "game code vs Wine PE DLLs"

- **winedbg as a poor-man's sampler** [I, DIY]: winedbg attaches to running
  Wine processes and walks **PE** stacks via dbghelp — it understands PE
  layout regardless of Rosetta. Script N iterations of `bt all`-style
  backtraces, collapse to folded/flamegraph format, bucket frames by PE
  module (game exe vs ntdll.dll vs winevulkan.dll vs winemac). Wine PE DLLs
  carry embedded DWARF so their frames symbolicate; the stripped game exe
  attributes at module granularity. **No off-the-shelf Wine sampling
  profiler exists — this is a small script to write once.** Caveat:
  winedbg 64-bit backtraces were historically flaky for MSVC targets
  (https://wine-devel.winehq.narkive.com/TFbOB79q/debugging-64-bit-wine-apps-with-winedbg)
  — verify on the mage build first.
- **wineserver is a separate PID** — `sample <wineserver-pid> 5` isolates
  the "wineserver waits" bucket directly; if it's an x86_64 Mach-O, §4.1
  symbolication applies to it too.
- **`WINEDEBUG=+timestamp,+server`** — timestamps every wineserver RPC;
  established way to nail server chatter
  (real-world: https://github.com/Frogging-Family/wine-tkg-git/issues/427).
  `+relay` is far too heavy.
- `fs_usage -w -f network <pid>` — syscall-level view of wineserver socket
  traffic; works with SIP on. [I]
- If DXVK is ever in the path: `DXVK_HUD=fps,frametimes,submissions,drawcalls,cs`.

### 4.6 System tracing with SIP on; PMU

- DTrace still SIP-locked for system binaries/kernel providers; partial for
  own processes. Not the right hammer.
  https://phlip9.com/notes/performance/dtrace%20on%20macOS/
- Endpoint Security Framework can observe oahd/oahd-helper translation
  activity and AOT cache misses with SIP on (how Champollion traced Rosetta).
- `os_signpost` works from translated processes but needs source
  instrumentation — practical only for code mage builds.
- **No Intel-style PMU emulation under Rosetta exists** (no RDPMC; treat as
  absent). Instruments **CPU Counters** template (`xctrace record
  --template 'CPU Counters'`) uses kpc; translated code runs as real arm64
  instructions so whole-core events (cycles, instructions, branch misses)
  should attribute per-process — **[U], needs a 10-minute experiment**.
- `xctrace export --input foo.trace --xpath ...` dumps raw samples as XML —
  the feed for the §4.1 symbolication pipeline.

---

## 5. Ranked gold mines (expected FPS impact × feasibility for mage)

| # | Gold mine | What it is | Expected gain | Effort / risk | Universality | First validation step |
|---|-----------|------------|---------------|---------------|--------------|----------------------|
| 1 | **Measurement pipeline** (§4.3–4.5) | Metal System Trace + `MVK_CONFIG_TRACE_VULKAN_CALLS=5` + `ROSETTA_PRINT_SEGMENTS` bucketing + winedbg sampler | 0 FPS itself, but tells us which of #2–#5 matters; without it every other row is a guess | 1–2 days / low | Universal (works for any game, any future runtime) | `xctrace record --template 'Metal System Trace' --attach <pid>` on DOOM + 30 s of `MVK_CONFIG_TRACE_VULKAN_CALLS=5`, histogram per-Vk-function time |
| 2 | **gfxstream render server** (§2.1) | x86_64 `libvulkan.dylib` guest encoder → native arm64 render server (MoltenVK today, KosmicKrisp later); all MoltenVK CPU work native + off game threads | [I] ~1.5–3 ms of 13.5 ms → ~85–95 FPS, possibly GPU-bound ~100 FPS. **Unverified** | Weeks; AOSP build baggage; presentation bridge is the unsolved piece | Universal (below the game, works for every Vulkan title; a D3D path could come later via DXVK) | Build gfxstream guest encoder as x86_64 libvulkan; insert via `CX_LIBVULKAN`/`SONAME_LIBVULKAN`; benchmark with IOSurface-blit presentation |
| 3 | **Profile & kill residual wineserver traffic** (§3.1) | msync already covers sync primitives; remaining per-frame server traffic is timer arming, IOCP post/remove, message queue, object lifecycle | Unknown until profiled; wineserver at 0.56 core during gameplay says something in this list is hot | Days to profile; per-item fix effort varies | Universal | `WINEDEBUG=+timestamp,+server` for 30 s in-game, histogram request types; `sample <wineserver-pid>` |
| 4 | **WFUSync-style userspace ntsync backend** (§3.3) | Replace mach-semaphore msync with `os_sync_wait_on_address` + POSIX shm in the existing inproc slot; avoids msync's per-wait server registration | [U] ~10–13% lower sync-op latency (author microbenches, not reproduced, no game data) — likely small FPS win since sync is already fast | Days (design lift, not code drop-in); correctness risk on WaitAll/alertable waits | Universal | A/B microbench against mage msync, then in-game HUD CPU avg; only if #3 shows wait ops still hot |
| 5 | **Game Mode entitlement** (§1.6) | `LSApplicationCategoryType = public.app-category.games` + fullscreen on mage launcher → macOS CPU/GPU priority, background suppression | [I] Small but free; helps wineserver compete less with background tasks | Hours / none | Universal | Add category to launcher Info.plist, verify Game Mode engages in fullscreen |
| 6 | **Hybrid ARM64EC Wine (Hangover-on-macOS / libkrun+Venus+Hangover)** (§1.1–1.5) | Everything but the game runs native arm64; game emulated by FEX | Architectural ceiling — but FEX runs game code ~20% slower than Rosetta, so net win only if >~40% of the 13.5 ms is non-game code (**measure first, #1**) | Months; blocked on FEX macOS port + 16K-vs-4K page problem that only CodeWeavers has solved so far | Universal | Don't start; track CrossOver 27 ARM64 preview + Wine upstream macOS ARM64EC/page-size patches, which will open the door |
| 7 | **Champollion symbolicator** (§4.1) | Map `sample`/xctrace arm64 PCs back to x86_64 RVAs via AOT instruction maps; LLDB tool for JIT-tree PE frames | 0 FPS itself; enables per-function attribution — the deep version of #1 | Days; format may have drifted since macOS 11.1 [U] | Universal | Verify `ROSETTA_PRINT_SEGMENTS=1` still works on macOS 27; run FFRI parser on a mage-built AOT file |

**Deliberately skipped / dead ends [V]:** QEMU-user (slowest, removed from
Hangover), box64-on-macOS (doesn't exist), GPTK internals (same Rosetta mage
has), esync/fsync tracking (superseded by inproc/msync; ntsync is
Linux-only), waiting for Apple (Rosetta winds down after macOS 27, not
improves), a macOS ntsync kext (kexts effectively closed since macOS 11).

**Contradictions of prior assumptions surfaced by this research:**
1. STATE.md lists `WINEESYNC=1` as a pending experiment — esync is dead in
   this tree; inproc/msync supersedes it. Drop it.
2. STATE.md frames msync as "the structural fix" still to be built — the
   mage 11.13 tree already has upstream inproc_sync **plus** the msync
   backend merged; the remaining wineserver cost is timer/IOCP/queue/
   lifecycle traffic, not sync primitives.
3. "Only Apple system frameworks run native" — more precisely they run as
   Apple-shipped AOT translations (still arm64 code, but translation-
   produced).
4. CrossOver/D3DMetal was suspected of having a smarter graphics path — it
   does not; D3DMetal is x86_64 in-process and crosses the same PE→unix
   hop. mage's stack is at parity with the commercial product at the
   graphics boundary.


---

# Round 2 (2026-07-21)

Second swarm, four areas: (A) MoltenVK/KosmicKrisp Apple-silicon tuning —
ground truth was the in-repo fork `upstream/MoltenVK` (1.4.2, identical to
upstream release of 2026-07-20) plus live upstream `main`; (B) Rosetta 2 /
macOS 27 / M5 Pro tuning, **verified locally on the target machine**
(macOS 27.0b 26A5378n, Mac17,9) — tagged [V-local]; (C) Wine CPU overhead
beyond sync (verified against `wine-mirror/wine` tag `wine-11.13`);
(D) presentation path (verified against `upstream/Wine-cx-26.2` and the
local MoltenVK fork).

## A. MoltenVK / KosmicKrisp tuning

### A.1 The Rosetta semaphore penalty — biggest single lever found **[V, local source]**

`MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE` (default `1`, "Metal events where
safe") contains a **hard-coded Rosetta fallback**: `MVKPhysicalDevice::
initVkSemaphoreStyle()` computes `isRosetta2 = isAppleGPU &&
!TARGET_CPU_ARM64` and, if true, **reverts to style 0 — Vulkan limited to a
single queue with implicit Metal ordering**. Verified at
`upstream/MoltenVK/MoltenVK/MoltenVK/GPUObjects/MVKDevice.mm:3685` (fork)
and `MVKDevice.mm:3616-3626` (live upstream main). **Every mage game
silently runs in the degraded single-queue mode by default.** Style 0
funnels multi-queue submission through one MTL queue; DOOM's renderer uses
multiple work streams, so the CPU pays per frame.
- Fix: `MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE=2` ("always MTLEvents").
  Minutes to test, zero patch.
- Why the fallback exists: macOS 12-era "GPU lost" crashes with
  MTLFence/MTLEvent on Rosetta/NVIDIA
  (https://github.com/KhronosGroup/MoltenVK/issues/1482, 2021–22). Never
  re-qualified for newer macOS — the 2026 code still carries the blanket
  revert. CrossOver-community reports from the era: forcing MTLEvents
  "works most of the time… performance boost is significant" **[U]**
  (https://www.applegamingwiki.com/wiki/CrossOver).
- Circumstantial safety evidence **[V]**: timeline semaphores always use
  `MTLSharedEvent` regardless of this setting, so shared events already run
  under Rosetta constantly (D3DMetal leans on them).
- mage's `Makefile:155` already sets `=2` for a probe binary, but
  `mage/bin/doom-experiment.sh` and `Sources/MacGaming.swift:87` do **not**
  set it for the game.

### A.2 Command-buffer prefill — spread Metal encoding across game threads

`MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS` (default `0`): with 0, **all
Metal encoding happens inside `vkQueueSubmit()`, on one thread, at the
worst time** [V]. `1` encodes at `vkEndCommandBuffer()` on the game's own
recording threads; `3` is immediate encoding (needs app-provided
autorelease pools — wine worker pthreads lack them, so `1` is the realistic
choice). Caveats [V, documented]: one MTLCommandBuffer per VkCommandBuffer
(may need to raise `MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE`,
default 64); no prefill for secondary CBs or simultaneous-use primaries;
only first submission benefits for reusable CBs; **ignored entirely if any
UpdateAfterBind feature is enabled** (DOOM 2016: no descriptor indexing —
compatible); reset-but-unsubmitted CBs still submit (ghost GPU work). No
published FPS numbers **[U]**. Design discussion:
https://github.com/KhronosGroup/MoltenVK/discussions/1548

### A.3 Async queue submission

`MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS` (default `1`) processes
`vkQueueSubmit`/`vkQueuePresentKHR` on the calling thread; `0` dispatches
submit processing (incl. all encoding when prefill=0) to a GCD queue whose
priority follows `pQueuePriorities` [V]. Offloads encode/commit from the
render thread at the cost of a thread hop + pipeline-depth risk [I]. A/B
only; likely redundant once prefill is on.

### A.4 Already-optimal in the 1.4.2 fork (no action)

- Argument buffers: default on since 1.2.10.
- **Descriptor state tracker rewrite + new descriptor pool: shipped in
  1.4.1 (Nov 2025)** — the descriptor-caching work already landed; mage's
  fork has it. Escape hatch if a game crashes on the stricter pool:
  `MVK_CONFIG_LIVE_CHECK_ALL_RESOURCES=1`.
- Residency sets since 1.3.0; `MVK_CONFIG_USE_MTLHEAP` default on
  where-safe. Command pooling default on. Redundant state-change
  elimination (1.1.11), parallel occlusion-query accumulation (1.4.1),
  deferred UINT8-index conversion (1.4.2) — all inherited.
  https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/Whats_New.md

### A.5 Present modes / display sync **[V, local source]**

Only `FIFO` and `IMMEDIATE` exist — **no MAILBOX**
(`MVKDevice.mm:2176-2199`); a game asking mailbox (DOOM does) silently
falls back to FIFO. IMMEDIATE maps to `CAMetalLayer.displaySyncEnabled=NO`
(`MVKSwapchain.mm:506`). `maximumDrawableCount` = swapchain image count
(clamped 2–3 by Core Animation). **FIFO's `nextDrawable` blocking
masquerades as CPU frame time** — confirm the game actually runs IMMEDIATE
(vsync off) before trusting "CPU-bound" numbers.
`MVK_CONFIG_PRESENT_WITH_COMMAND_BUFFER` is "obsolete, deprecated, and
ignored" (`mvk_private_api.h:215`).

### A.6 Shader compilation

- `MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION=1` (default 0) →
  `MTLDevice.shouldMaximizeConcurrentCompilation`, macOS 13.3+; faster
  MSL→binary compiles on many-core chips; kills hitch CPU spikes; zero
  risk; ~0 steady-state FPS effect. Set it.
- `MVK_CONFIG_FAST_MATH_ENABLED` default is enum `2` (on-demand); `=1`
  forces always — GPU-side only, skip while CPU-bound.
- Metal 4's modular/async compilation API is **not surfaced** through any
  MVK_CONFIG; 1.4.2 uses Metal 4 only for capability detection.

### A.7 KosmicKrisp verdict: blocked, two ways

Merged Mesa 26.0, Vulkan 1.3 CTS-conformant, claimed MoltenVK parity Feb
2026 — but **requires Metal 4 and Apple silicon only; ships as an arm64
dylib, which an x86_64 Rosetta process cannot load**
(https://www.lunarg.com/the-state-of-vulkan-on-apple-jan-2026/). Perf work
is explicitly still on the 2026 roadmap
(https://www.phoronix.com/news/KosmicKrisp-2026), and the one real-app
datapoint is negative: vkQuake reports KosmicKrisp "much slower than
MoltenVK" **[U]** (https://github.com/Novum/vkQuake/issues/814). Even
LunarG frames MoltenVK as relevant "for quite some time." Only usable as
the host driver of an out-of-process render server (round-1 §2), never
in-process under Rosetta.

## B. Rosetta 2 / macOS 27 / M5 Pro tuning [V-local unless noted]

### B.1 ROSETTA_* variables

- `ROSETTA_ADVERTISE_AVX=1` **still honored on macOS 27** — CPUID probe
  compiled and run locally: default AVX/AVX2/FMA all 0; with the var,
  OSXSAVE/AVX/FMA/F16C/AVX2/BMI1/BMI2 all 1; AVX512F stays 0. Semantics per
  Apple's GPTK 2.1 README: "does not modify the availability of the
  instruction set in Rosetta; it only controls whether the processor
  advertises its support." AVX translation exists since macOS 15; the var
  is purely the CPUID gate. `ROSETTA_ADVERTISE_AVX2` alone does **nothing**
  — not a real variable (forum cargo cult). Already set in
  `mage/bin/doom-run.sh` but **FPS delta never measured** — A/B it.
  Expected small (~0–3%) [I]; id Tech 6 runtime-dispatches SIMD paths.
- **`ROSETTA_PRINT_IR` / `ROSETTA_PRINT_SEGMENTS` are dead on macOS 27**
  (produced zero output locally; worked on macOS 11). **Round-1 levers #1
  (step) and #7 (Champollion pipeline step 1) must drop their dependence on
  these vars** — replace SEGMENTS-based bucketing with `vmmap`/AOT-file
  correlation (the AOT files still exist; only the debug printing is gone).
- No other ROSETTA_* var has primary-source evidence (`ROSETTA_NO_TSO` etc.
  = [U] folklore).
- **TSO is not a lever**: hardware TSO is mandatory for translation
  correctness, auto-enabled per translated thread; ~9% average cost vs
  weak ordering (TOSTING paper,
  https://www.sra.uni-hannover.de/Publications/2023/tosting-arcs23/wrenger_23_arcs.pdf);
  `kern.tso_enable` sysctl no longer exists on macOS 27.

### B.2 Game Mode / `gamepolicyctl` — the biggest free lever

- Wine games **never trigger Game Mode automatically** (wrapper processes,
  no game-category bundle + native fullscreen); still true in 2026
  (https://torqer.app/how-to-enable-game-mode-on-mac-for-crossover-sikarugir-and-wine-games/).
- **`gamepolicyctl game-mode set on` works on macOS 27** [V-local;
  `Xcode.app/Contents/Developer/usr/bin/gamepolicyctl`]. The
  "broken on Tahoe" claim is stale. Requires Xcode installed; global
  toggle — wrapper script sets `on` at launch, restores `auto` on exit.
- Effect [V, Howard Oakley measurements]: highest CPU+GPU priority,
  demoted background tasks, low-tier cores reserved for the game, doubled
  Bluetooth sampling (input latency).
- Clean no-Xcode alternative: per-game `.app` bundle with
  `LSApplicationCategoryType=public.app-category.games` +
  `LSSupportsGameMode=YES` + native fullscreen → auto-enablement
  (https://developer.apple.com/documentation/bundleresources/information-property-list/lssupportsgamemode).
  mage already ships an app bundle — test whether it engages.

### B.3 M5 Pro scheduling — the rules changed **[V-local]**

**This M5 Pro has NO efficiency cores**: `hw.nperflevels=2`, perflevel0 =
**"Super" ×5**, perflevel1 = **"Performance" ×10** (15-core binned SKU).
"Super cores" are the new top single-thread tier (Fusion Architecture,
https://www.apple.com/newsroom/2026/03/apple-introduces-macbook-pro-with-all-new-m5-pro-and-m5-max/).
**STATE.md's "10 P-cores + 5 'Super' E-cores" has it backwards — it's 5
super + 10 performance.** Consequences: old E-core-parking folklore is
moot (the low tier is fast), but only **5 super cores** exist and the
game's main/render threads + wineserver all want them — QoS steering
matters *more*, not less. Game Mode's "reserve E cores" semantics on the
Super/Performance tiers are undocumented [U] — local A/B needed.
Affinity APIs are a dead end: affinity tags are no-ops on Apple silicon;
`taskpolicy`/`setpriority()` can only demote. **QoS is the only signal.**

### B.4 Wine thread priorities never reach the macOS scheduler — patchable gap

**Zero QoS API usage in Wine-cx-26.2** [V-local]: thread priority handling
is `setpriority()` niceness in `server/thread.c:245-270` only. Non-root
can't negative-nice on macOS, so Windows `THREAD_PRIORITY_HIGH/
TIME_CRITICAL` are **no-ops or demote-only** — every Wine thread runs at
default QoS and the game cannot steer threads onto the 5 super cores.
Clean universal patch: map Windows priority → `pthread_set_qos_class_self_np()`
in ntdll's thread creation (TIME_CRITICAL/ABOVE_NORMAL →
`QOS_CLASS_USER_INTERACTIVE`, BELOW_NORMAL/IDLE → UTILITY/BACKGROUND) —
exactly what Apple's "Tune CPU job scheduling for Apple silicon games"
tech talk recommends (https://developer.apple.com/videos/play/tech-talks/110147/).
Effort ~1–2 days + A/B; plausible 5–15% on this 2-tier topology [I].
MoltenVK already maps `VK_QUEUE_GLOBAL_PRIORITY_*` to dispatch QoS
(`MVKQueue.mm:307-321`) — the gap is purely the Windows-thread side.

### B.5 GPTK practices; AOT cache discipline; Rosetta phase-out

- GPTK env: `D3DM_SUPPORT_DXR` (1 on M3+/macOS 26+), `ROSETTA_ADVERTISE_AVX`,
  `MTL_CAPTURE_ENABLED`; launcher script variants (`-no-hud`, `-no-esync`).
  D3DM shader cache at `$(getconf DARWIN_USER_CACHE_DIR)/d3dm/<GAME>/` —
  same warming/corruption semantics as mage's `shadercache.bin`.
- **GPTK 4 (WWDC26)**: Macworld-measured on M4 Pro — GTA V 106→176 fps
  (+66%), RDR2 60→75 (+25%) over GPTK 3, purely translation-layer
  improvements (https://www.macworld.com/article/3189951/apples-latest-game-porting-toolkit-beta-changed-how-i-think-about-mac-gaming.html).
  Mostly D3D-side (irrelevant for Vulkan-native DOOM), but its Wine base
  may carry Rosetta improvements — **diff its Wine version against 11.13**
  [U: base version unknown].
- AOT cache: keyed by SHA-256 of path+contents; any binary change/move/OS
  update → retranslation next launch. Discipline: warm-up run before
  benchmarking, never move/re-sign binaries between runs, expect slow
  first launch after every macOS update.
- Phase-out: Rosetta full through macOS 27; macOS 28 shrinks to a
  games-only subset. mage's x86_64-under-Rosetta architecture has a ~2–3
  year runway; needs a contingency note (round-1 hybrid work is the escape
  hatch).

## C. Wine CPU overhead beyond sync (verified against wine-11.13 mirror)

### C.1 Already solved upstream — do NOT re-implement **[V]**

- **wineserver already polls with kqueue on Darwin** (`server/fd.c`,
  `HAVE_KQUEUE` main-loop backend; `poll()` is only the fallback).
- **Message-queue polling is server-call-free when idle**: `peek_message()`
  checks server-mapped shared-memory queue bits first
  (`dlls/win32u/message.c:2913-3010`) — per-frame `PeekMessage` on an empty
  queue costs zero round-trips.
- **Virtual memory is in-process**: only 16 server requests in
  `ntdll/unix/virtual.c`, all mapping/section/cross-process;
  NtAllocate/Free/Protect/QueryVirtualMemory never touch wineserver.
- **TLS/FLS client-side**; wall-clock via mapped `_KUSER_SHARED_DATA`
  (refreshed every 16 ms); QPC is a unixcall → `mach_continuous_time()`.
- **Fast unixcall dispatcher** (wine ~9.x) skips the full syscall
  dispatcher path; paired call/ret for branch prediction
  (https://blog.hiler.eu/wine-pe-to-unix-update/).
- Upstream trend continues: 11.13 changelog — "Move window monitor DPI to
  shared memory", "Skip dispatching rawinput message when it is empty".

### C.2 In-process sync on macOS — status correction

Upstream inproc-sync is gated on `inproc_device_fd`, only handed out when
the **Linux ntsync driver** exists (`dlls/ntdll/unix/server.c:1699`) — on
macOS upstream inproc is inert; mage's msync remains the vehicle. Wine
11.13 already uses `__ulock_wait/__ulock_wake` for the tid-alert fast path
(`sync.c:3520-3618`) — proof the Darwin futex is a viable, already-used
primitive for further in-process wait work (supports the WFUSync-style
direction from round 1).

### C.3 What still hits wineserver per frame

Each request = `write()` + blocking `read()` on a socketpair + server
wake/handle/reply — ≥2 context switches (`server.c:178-292`).
- **Async file IO / IOCP — prime suspect**: per overlapped read a
  `register_async` request + completion delivery; **every
  `NtRemoveIoCompletion` costs ≥1 round-trip, a blocking empty dequeue
  costs 2; `NtRemoveIoCompletionEx` loops one request per entry — no
  batching** (`sync.c:2869-2920`). id Tech 6 streams assets continuously →
  plausibly the dominant per-frame class [per-game behavior: I].
- **Registry: one round-trip per value query, no caching** (`registry.c`).
- Waits on types msync doesn't cover: waitable timers, IOCP queues,
  thread/process handles, jobs [I].
- **Other processes in the prefix**: Steam client + steamwebhelper (CEF,
  many processes, chatty) wake the same single-threaded wineserver. Part of
  the observed wineserver load may be Steam chatter, not the game
  [mechanism V, attribution unverified].

### C.4 Structural facts

- Single-threaded by design; **no multithreaded-wineserver patchset exists,
  merged or rejected**; upstream direction is eliminating RPC, never
  parallelizing the server. No request batching in the protocol.
  **"esync2" does not exist.**
- **wineserver itself runs translated** under Rosetta: every request
  handler executes through Rosetta (~1.5–2.5× integer-code lore [U factor]),
  and every round-trip's latency is inflated on both wake and reply — a
  Rosetta-specific multiplier on all remaining server traffic that Linux
  analyses never mention [I mechanism].

### C.5 New levers from this area

1. **Native arm64 wineserver** — the single biggest untried lever. The
   server protocol is socket-based with fixed wire structs; shared pages
   (`KUSER_SHARED_DATA`) have a Windows-fixed layout; nothing requires
   wineserver to be the same ISA as clients. Removes the Rosetta multiplier
   from all server work + cuts round-trip latency game threads block on.
   If wineserver is ~13% translated, native ≈ 5–8% plus latency savings
   [I]. Effort medium-high: build-system hack + ABI audit of shared
   structs (LP64 both sides). **Nobody appears to have tried this.**
2. **Batch `NtRemoveIoCompletionEx`** — one round-trip for N completions;
   clean, universal, upstreamable wine patch. Effort medium.
3. **Extend msync coverage** to timers / IOCP waits / thread+process
   handles using `__ulock_wait` precedent. High effort per object type;
   do only after profiling says which is hot.
4. **Kill prefix noise** — disable Steam overlay/webhelper GPU processes;
   trivial, universal for any Steam game.
5. Client-side registry read cache — only with trace evidence.
6. wine-staging/Proton inventory: **nothing portable remains** — staging
   perf patchsets are correctness fixes or subsumed; Proton's CPU work
   (esync/fsync/ntsync, input/windowing shared memory) is Linux-only or
   already upstream.

## D. Presentation path

### D.1 How mage presents today **[V, local source]**

winemac creates a `WineMetalView` (NSView backed by CAMetalLayer), hands
the layer to MoltenVK via `VK_EXT_metal_surface`; **no extra blit** — the
game renders straight into CAMetalDrawables
(`Wine-cx-26.2/dlls/winemac.drv/vulkan.c:46-91`). Present is
`[drawable present]` from a command-buffer scheduled handler;
`presentAtTime:` only for nonzero `VK_GOOGLE_display_timing` (PR #1936
fixed presentAtTime implicitly vsyncing IMMEDIATE —
https://github.com/KhronosGroup/MoltenVK/issues/1925). Known Metal
regression: last 1–2 presents never complete; MoltenVK nudges drawableSize
as workaround (`MVKSwapchain.mm:288-296`).

### D.2 Composited vs direct-to-display

- mage's borderless window is always **composited**: WindowServer
  recomposites at the next vsync — GPU cost (scales with coverage; the
  macOS 26 Electron bug showed WindowServer alone at 80%+ GPU —
  https://github.com/desktop/desktop/issues/21057) plus **up to one extra
  display interval of latency** [I, standard model; Apple publishes no
  number].
- Direct-to-display requires **fullscreen Space + opaque RGB CAMetalLayer +
  Apple silicon**; then hardware composites "at a very low performance
  cost" (https://developer.apple.com/documentation/metal/managing-your-game-window-for-metal-in-macos).
  Metal HUD shows Direct vs Composited.
- **Adaptive-Sync (VRR) on macOS requires fullscreen mode** (WWDC21-10147);
  `NSScreen.minimumRefreshInterval`/`maximumRefreshInterval` report the
  VRR window (40–120 Hz). VRR would hide the 66–73 fps variance — panel
  presents each frame when done.
- Composited throughput is **not** capped at 60 Hz on ProMotion — the
  compositor runs up to 120 Hz when content demands; the penalty is
  latency + GPU cost, not a hard ceiling [I].

### D.3 The CX 26.2 WindowServer wedge — likely root cause **[I]**

winemac has three conflated mechanisms:
1. Cocoa fullscreen Space (`toggleFullScreen:`) — safe, standard, enables
   direct-to-display.
2. **Real display-mode switching**: `ChangeDisplaySettingsEx` →
   `find_best_display_mode` (requires exact width/height/**refresh** match,
   `display.c:757-762`) → `CGCaptureAllDisplays()` +
   `CGDisplaySetDisplayMode()` (`cocoa_app.m:926-1000`). Heavyweight
   WindowServer display-topology rebuild — the class of operation fragile
   on macOS 15→26 (watchdog kills: PlayCover#2105, Apple forums 719033).
   **Most plausible root of the CX wedge.** Side effect: a game requesting
   1920×1200@60 switches the panel into a physical 60 Hz mode for the
   session.
3. `CaptureDisplaysForFullscreen` registry key (default off) — same risk
   profile; ensure it stays `n`.

Safe approach = what mage does (borderless) or fullscreen Space **with no
mode change and no capture**.

### D.4 The 60 Hz question on a 120 Hz panel

Frame-rate gates in order of likelihood:
1. winemac mode switch to 60 Hz (above) — avoid mode changes.
2. **Refresh reported to the game**: `dmDisplayFrequency` comes from
   `CGDisplayModeGetRefreshRate`, **defaulting to 60 when it returns 0**
   (`display.c:169-171`); ProMotion adaptive modes can report 0 → the game
   sees a 60 Hz desktop and applies its own cap [V code; U what macOS 27
   actually reports — 5-line CoreGraphics probe answers it]. If 0/60:
   patch winemac to report `NSScreen.maximumFramesPerSecond` (120).
3. **FIFO vsync follows the display link, not 60** — vsync'd content runs
   at 120 fps on ProMotion (Unity IssueTracker confirms; CrossOver users
   report 90–120 fps borderless [U]). **No API needed for 120 Hz presents;
   the caps come from (1)/(2), not Metal.**
4. IMMEDIATE uncaps regardless; DOOM exposing IMMEDIATE is unlikely — a
   MoltenVK override patch would be diagnostic-only (tearing).
- `CAMetalLayer.wantsDisplayLinkEnabled`: **does not exist in the macOS 26
  SDK or online docs** [V]; possibly a macOS 27 SDK addition — re-check
  with the Xcode 27 SDK [U].

### D.5 What CrossOver/GPTK add at presentation: nothing

CX 26.2's winemac Metal-view/surface/fullscreen code is the same
architecture as upstream (verified file-by-file). For a Vulkan-native game,
CX/GPTK/mage present identically. Their additions (D3DMetal, MSync, bottle
tweaks) are proprietary, CPU-side, or irrelevant here. Note: presentation
work will not raise average FPS while CPU-bound — it buys latency (−8 to
−25 ms via direct-to-display + 120 Hz), frame pacing (VRR), and robustness.

---

## Merged re-ranked gold mines (supersedes round-1 ranking)

Round-2 research produced two things round 1 lacked: locally-verified
facts about this exact machine (macOS 27, M5 Pro 2-tier topology) and
levers with **minutes-to-hours cost** that attack the CPU frame directly.
The measurement levers stay near the top because two big round-2 levers
(semaphore style, wineserver attribution) are themselves "measure then
flip" items. What changed and why is noted per row.

| # | Gold mine | Expected effect | Effort / risk | First validation step |
|---|-----------|-----------------|---------------|----------------------|
| 1 | **`MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE=2`** (A.1) — bypass MoltenVK's hard-coded Rosetta single-queue fallback | Unknown but plausibly the largest single env-var win: restores multi-queue submission for every game; the only Rosetta-specific penalty in the driver. **[U] magnitude** | Minutes; risk = 2021-era GPU-lost reports, never re-qualified on modern macOS | Set env for DOOM, A/B HUD CPU ms in the same scene; watch for device-lost |
| 2 | **Force Game Mode** (`gamepolicyctl game-mode set on` wrapper, or `.app` bundle + `LSSupportsGameMode=YES`) (B.2) | Highest CPU/GPU priority, low-tier cores reserved for the game, background demotion, lower BT input latency. Largest *free* frame-time-consistency win [I] | Hours (script) / none; must restore `auto` on exit | `gamepolicyctl game-mode status` while DOOM runs + FPS A/B |
| 3 | **Measurement day** (Metal System Trace + `MVK_CONFIG_TRACE_VULKAN_CALLS=5` + `WINEDEBUG=+timestamp,+server` per-pid histogram + `sample wineserver`) (round-1 §4, C.3) | 0 FPS itself; decides #4/#5/#6 and confirms whether FIFO `nextDrawable` blocking is hiding in "CPU time" (A.5) | 1–2 days / low | Metal System Trace on DOOM + 30 s server-request histogram bucketed by type **and client pid** |
| 4 | **`MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS=1`** (A.2) | Moves Metal encoding off the submit thread onto the game's recording threads; up to the encoding share of the CPU frame if id Tech 6 records CBs multithreaded (it does). [U] magnitude | Minutes of env change + memory watch; ignored if UpdateAfterBind ever enabled | A/B with #1 already on; check `MVK_CONFIG_PERFORMANCE_TRACKING` submit/encode split |
| 5 | **Wine thread-priority → QoS patch** (B.4) | Game threads reach the 5 super cores; workers on performance cores. Plausible 5–15% on this topology [I]; zero QoS mapping exists in Wine today [V-local] | 1–2 days + A/B / moderate | Patch ntdll thread creation → `pthread_set_qos_class_self_np`; A/B HUD CPU ms |
| 6 | **Kill prefix noise** (Steam overlay/webhelper) (C.5.4) | Possibly a large share of the observed wineserver load if Steam chatter dominates [I] | Trivial / none | #3's per-pid histogram shows foreign-pid share; disable overlay, re-measure |
| 7 | **Native arm64 wineserver** (C.5.1) | Removes the Rosetta multiplier from all remaining server work + cuts round-trip latency; if wineserver is 13% translated → ~5–8% + latency savings [I]. Highest ceiling of the Wine-side levers; nobody has tried it | Medium-high (build hack + ABI audit) / unknown landmines | Feasibility spike: build wineserver arm64 from the same tree, connect x86_64 client |
| 8 | **Batch `NtRemoveIoCompletionEx`** (C.5.2) | Kills the per-completion round-trip loop in streaming-heavy engines [V mechanism]; scales with measured IOCP rate | Medium (wine patch, upstreamable) / low | Only after #3 shows IOCP hot; patch + A/B |
| 9 | **Presentation: fullscreen Space → direct-to-display + VRR; probe real refresh; never mode-switch** (D) | No avg-FPS change while CPU-bound, but −8 to −25 ms latency, VRR smooths the 66–73 fps band, and avoids the WindowServer wedge class. Also answers whether the game sees a 60 Hz desktop | Hours for probe + fullscreen test; ½-day winemac patches if needed | Metal HUD "Direct" check in fullscreen Space; CoreGraphics probe of `CGDisplayModeGetRefreshRate` |
| 10 | **gfxstream render server** (round-1 §2.1) | [I] ~1.5–3 ms → ~85–95 FPS, possibly GPU-bound. Unchanged analysis; KosmicKrisp confirmed **not** usable in-process (arm64-only, slower in the one datapoint) so the server would run MoltenVK arm64 for now | Weeks / presentation bridge unsolved | Unchanged: guest encoder as x86_64 libvulkan + IOSurface blit |
| 11 | **WFUSync-style backend / extend msync to timers+IOCP waits** (round-1 §3.3, C.5.3) | [U] ~10% lower sync-op latency in microbenches; wait coverage for the object types msync misses | Days–high per object type / correctness risk | Only if #3 shows waits (not IOCP/foreign traffic) still hot |
| 12 | **Hybrid ARM64EC Wine** (round-1 §1) | Architectural ceiling; FEX ~20% slower than Rosetta on game code; blocked on CodeWeavers' macOS port + 16K/4K pages | Months / blocked | Track CrossOver 27 ARM64 preview; Rosetta phase-out (macOS 28) makes this eventually mandatory |
| 13 | **Champollion symbolicator** (round-1 §4.1) | Per-function attribution of translated CPU time | Days / **partially broken**: `ROSETTA_PRINT_SEGMENTS` is dead on macOS 27 [V-local] — use `vmmap`/AOT-file correlation instead | Verify FFRI parser against a mage-built AOT file on macOS 27 |

**Dropped/demoted from round 1, with reasons:**
- Round-1 #1 (measurement) split into #3 (cheap, do now) and #13 (deep
  tooling); #13's plan revised because its bootstrap vars are dead on
  macOS 27.
- Round-1 #5 (Game Mode entitlement) → promoted to #2: round 2 verified
  `gamepolicyctl` works on macOS 27 and that Wine games never auto-trigger
  it, making it a concrete hours-long lever instead of a config nicety.
- Round-1 #2 (gfxstream) → demoted to #10: not because it's worse, but
  because round 2 found four levers (#1, #2, #4, #5) costing minutes-to-days
  that attack the same CPU frame; do them first, then reassess how much
  frame is left for the render server.
- Round-1 #4 (WFUSync) → #11: round 2 showed the residual wineserver cost
  is more likely IOCP/foreign-pid traffic than the wait primitive itself.
- Round-1 #6 (hybrid) → #12: unchanged thesis; Rosetta phase-out timeline
  (B.5) raises its *strategic* priority even as its tactical cost stays
  high.

**New contradictions of current practice (round 2):**
1. **We run default MoltenVK config → every game is silently in the
   degraded single-queue Rosetta semaphore mode.** Cheapest suspected big
   win; test first.
2. **STATE.md's core topology is backwards**: M5 Pro is 5 super + 10
   performance cores (not 10 P + 5 "Super E"); there are no E-cores. The
   `jobs_numThreads 8` experiment and "leave headroom" logic should be
   re-thought for a 5-super-core ceiling.
3. `WINEDEBUG=-all` is correct hygiene — keep it.
4. Borderless + 60 Hz: borderless costs ~1 frame of compositor latency and
   forgoes VRR; and winemac may be **reporting a 60 Hz desktop to the
   game** (`CGDisplayModeGetRefreshRate`→0→default 60) even though FIFO
   would follow the 120 Hz display link. Probe before assuming.
5. The CX 26.2 fullscreen wedge was likely **display capture / real mode
   switching** (`CGCaptureAllDisplays`), not generic fullscreen — Cocoa
   fullscreen Space is probably safe; avoid mode changes instead of
   avoiding fullscreen itself.
6. Round-1 assumption that Steam/foreign processes are minor: unverified —
   the wineserver load may be substantially Steam chatter; the per-pid
   histogram decides.

# Round 2 measurement verdicts (2026-07-21, mage/docs/testing/measure-20260721/RESULTS.md)

- MVK_CONFIG_VK_SEMAPHORE_SUPPORT_STYLE=2 (round-2 lever #1): DISPROVEN as a
  perf lever — MTLEvent confirmed active, safe, but FPS/CPU deltas are noise.
  Launcher left at default.
- wineserver: SOLVED for now — 39.7k req/s at 12.1% CPU (~3us/req, ~4% of
  total CPU); sync traffic trivial post-msync. Residual = async-IO plumbing
  (likely Steam/CEF chatter) + winemac window queries.
- NEW #1 MoltenVK lever: blocking vkGetQueryPoolResults — exactly 2 calls/
  frame (timestamp + occlusion), each blocking ~5.7ms under trace. Query
  readback stall, not semaphore style, is the in-process graphics CPU cost.
  See PATCH below.
- Frame decomposition: wineserver ~4% (HIGH), MoltenVK >= ~2ms + query waits
  (MEDIUM), game+wine PE+Rosetta ~90% (LOW confidence — Rosetta opaque to
  sample; documented dead-end).

## PATCH: query early availability (2026-07-21, branch `query-early-availability`)

Branch: `query-early-availability` in `upstream/MoltenVK` (local only, commit
`64c6d634`, on top of `agent/mesh-shader` @ `4fc3f6c1`; nothing pushed).

Root cause (from the spike): `VK_QUERY_RESULT_WAIT_BIT` blocked on a condvar
until a Metal command-buffer *completed handler* flipped query status
`DeviceAvailable → Available` (`MVKCommandEncoder::finishQueries`,
Commands/MVKCommandBuffer.mm) — i.e. every blocking readback waited for the
entire frame's command buffer to retire on the GPU, not just the queried
work. Timestamps on TBDR additionally cost one fence-serialized dummy BLIT
pass *per query* (sample batching was disabled, `maxMTLBlitPassSampleBuffers
= 1`).

What changed (5 MoltenVK files, +183/−11):

- `Commands/MVKCommandBuffer.mm` — STEP 0: timestamp stage-counter samples
  batched 4 per BLIT pass (all 4 `MTLBlitPassDescriptor` sample-buffer
  attachments), one `waitForFence` per pass; stale Xcode-13 comment removed.
- `GPUObjects/MVKQueryPool.{h,mm}` — per-pool lazily created
  `MTLSharedEvent` + token→covered-queries deque
  (`signalQueriesAvailability`), and `requestEarlyAvailability()` called
  from `getResults()` before the WAIT condvar: for each in-flight signal
  covering the requested range it registers an `MTLSharedEventListener`
  notification (or flips immediately if already signaled) that calls the
  existing `finishQueries()`. Token deque purged on pool reset; completed
  handler remains the fallback for uncovered queries; emulated
  (no-counter-buffer) pools never create the event.
- `Commands/MVKCommandBuffer.{h,mm}` + `Commands/MVKCommandEncoderState.mm`
  — signals are encoded: for timestamps right after each sample BLIT pass;
  for occlusion after the render-pass accumulation compute writes the
  pool's shared visibility buffer (queued in
  `_pendingOcclusionAvailabilitySignals`, flushed from
  `endCurrentMetalEncoding()` once all encoders are ended, so the signal
  is ordered after the accumulation pass).

Verification (no game launched — DOOM owned elsewhere):

- Build: `cmake --build upstream/MoltenVK/build/cmake-debug --target
  MoltenVK` clean (note: `build/cmake` is misconfigured for this branch —
  it points at the shared `upstream/SPIRV-Cross` checkout, currently on the
  ray branch; `build/cmake-debug`/`cmake-release` correctly point at
  `upstream/SPIRV-Cross-mesh`).
- CTS: `dEQP-VK.query_pool.*` (deqp-vk with
  `DYLD_FALLBACK_LIBRARY_PATH` → dir containing `libvulkan.dylib` symlink
  to the built `libMoltenVK.1.dylib`): patched 456 pass / 0 fail /
  18424 not-supported, **identical to the pre-change baseline**
  (logs: /private/tmp/mvk-query-test/query_pool_{baseline,patched_final}.qpa).
  The 882-line `occlusion_query` group runs and passes, exercising the new
  occlusion signal path.
- Microbenchmark `Tools/MoltenVKQueryWaitProbe.mm` (+ `QueryWaitProbe.comp`,
  `make mvk-query-wait-test`): per frame — 2 timestamps around a ~3ms
  compute "queried region", a blit copy (encoder boundary), then ~16ms of
  trailing compute, then WAIT readback of the mid-frame pair. Baseline
  (cmake-release, pre-change): early wait **18.9ms** avg (full frame).
  Patched: **2.96ms** avg (unblocks right after the queried region; ~6.4×).
  Timestamps valid and monotonic in both (`badTimestamps: 0`).

Deviation from the spike sketch: the planned GPU-side `resolveCounters`
into a per-pool `_resolvedTSBuffer` was dropped — CPU `resolveCounterRange`
is already valid once the sample pass completes, and the shared-event
signal guarantees exactly that ordering, so the extra buffer and its
mixed-coverage hazards were unnecessary.

Remaining verification: DOOM A/B (same Foundry checkpoint protocol as
measure-20260721) with this dylib swapped in for the gcenx one — expected
effect is on the occlusion readback (unblocks after the last culling render
pass instead of after present); end-of-frame timestamps gain little except
from the STEP-0 pass reduction. Also watch upstream issue #2698 (open UAF
in the same `finishQueries` completed-handler path); the new listener
callbacks take the same raw-pool-pointer pattern as the existing completed
handler, so they inherit that risk profile rather than adding to it.

# Decision log (2026-07-21, goal-mode)

## gfxstream render server: NO-GO for now (reassess triggers below)

Post-measurement analysis against the round-1 projection (~1.5-3ms recoverable):
- The dominant MoltenVK-side cost was the query-readback WAIT, which is
  game-thread blocking time, not MoltenVK CPU work. Moving MoltenVK to a
  native render server does NOT remove it — the same WAIT_BIT stall exists
  over any transport. The query early-availability patch (branch
  query-early-availability, 18.9->2.96ms microbench) removes it in-process
  at ~1% of the effort.
- What gfxstream uniquely recovers after the patch: MoltenVK's command
  ENCODING CPU (measured <2ms/frame aggregate under trace) times a
  native-arch speedup, minus its own wire serialization overhead — net
  likely <1ms/frame. Not worth weeks + AOSP baggage + the unsolved
  presentation bridge.
- KosmicKrisp confirmed arm64-only and not faster in the one datapoint, so
  the server would run translated-parity MoltenVK arm64 anyway.
Reassess triggers: (1) game goes GPU-bound (CPU work left is worthless to
move), (2) post-patch trace still shows >1.5ms/frame of in-process MoltenVK
CPU, (3) Rosetta phase-out forces architectural work anyway (then fold into
the hybrid plan, not standalone).

## sample-through-Rosetta artifact (2026-07-21, A-sample.txt analysis)

The leaf histogram in an in-game `sample` is dominated by a PARK STUB:
~25.9k of ~27.7k leaf samples sit at one translated address
(0x7ff89b372b80) — the Rosetta syscall stub under mach_msg2_internal
where idle threads park (NSEventThread, worker pools). It is idle time,
not compute; `sample` counts parked threads as on-CPU. Practical upshot:
to extract any signal, filter park stubs (that address, mach_msg paths,
psync waits) first. What remains (~1.7k samples) splits between Rosetta
JIT frames (translated wine PE code, 0x2xxxxxxxx range) and untracked
game code — still not function-attributable. Also noted: translated
stacks don't unwind (dispatcher frames repeat recursively), which is why
wine's PE-side call paths are invisible. Champollion/vmmap-AOT
correlation remains the only deep option.

## Presentation probe (2026-07-21, read-only CoreGraphics)

Builtin panel is live at 1512x982 @ 120 Hz ProMotion and
CGDisplayModeGetRefreshRate returns a REAL 120.0 (not the 0 that makes
winemac fall back to 60 Hz) — so the round-2 worry "the game may see a
60 Hz desktop" does not apply to the current mode. Available rates:
120/60/59.94/50/48/47.95. No artificial system-side 60 Hz cap; vsynced
games can target 120. Presentation lever remains latency-side
(direct-to-display vs Composited), not avg-FPS, while CPU-bound.

## MoltenVK Rosetta-conditional audit (2026-07-21)

Systematic grep of the fork for Rosetta/translated conditionals: exactly
two hits. (1) The semaphore-style fallback (MVKDevice.mm:3685) — already
A/B-tested, perf-neutral, left at default. (2) MVKDevice.mm:3200 device-ID
via GPU rather than build arch — the CORRECT Rosetta behavior, no
degradation. Conclusion: no other translated-mode penalties hide in
MoltenVK; the driver treats x86_64-under-Rosetta as first-class apart
from the (harmless) semaphore default.
