# Perf gold mines — round 3 (2026-07-21)

Three parallel deep-research passes: (A) render-server/native-renderer re-evaluation
after the A/B invalidation, (B) wineserver recv-flood patch design, (C) web-wide hunt.
Prior rounds: `perf-goldmines.md`. Frame budget at baseline: ~89 FPS unlocked,
CPU-bound (CPU ~13.5 ms vs GPU ~10 ms; ~90% of CPU is Rosetta game code;
wineserver ~12% CPU ≈ 4% of frame).

## A. Render server re-evaluation — still NO-GO, but ranking changed

- winevulkan thunk is already lean: zero heap allocs in vulkan_thunks.c, 2 KB stack
  conversion context, no injected waits, 1:1 with host calls. **<1% available — skip.**
- gfxstream (guest encoder → arm64 render server): only viable native-renderer shape
  on macOS (proven on macOS hosts via Android Emulator; drop-in x86_64 libvulkan.dylib,
  no wine fork). BUT blocking calls (DOOM's 2 query readbacks/frame) become cross-process
  round-trips — worse for exactly this game. Realistic net +0.5–1.5 ms/frame
  (**+4–10%**, possibly negative), weeks of work, presentation bridge unsolved.
  Deferred with a measurable gate: revisit only if post-patch traces show
  >1.5 ms/frame residual in-process MoltenVK CPU (perf-goldmines.md:1117-1120).
- Venus/virgl: wrong guest shape (Linux kernel virtio driver, no userspace client) — dead end.
- KosmicKrisp: arm64-only, one public datapoint *slower* than MoltenVK — no.
- FEX/Hangover hybrid: strategic only (Rosetta ends after macOS 27); no macOS port exists.
- **Absolute ceiling for the entire Vulkan-path category: ~+12%** (deleting all of it
  leaves GPU 10 ms → ~100 FPS). The doubled-FPS ask is unreachable by universal levers;
  ~90% of the CPU frame is Rosetta-translated engine code.
- The invalidation promotes the **in-process x86_64 query-patch A/B to the #1 lever**
  (+5–15%, range 0–25% — genuinely unknown until measured; microbench −84% of the
  blocking wait, 18.9 → 2.96 ms). x86_64 baseline & patched+gate builds are staged at
  `upstream/MoltenVK/build/cmake-release-x86_64-{baseline,patched}/`.

## B. recv_socket flood — inline-recv fast path (PATCH IN PROGRESS)

- Verified: every data-ready overlapped WSARecv = exactly 2 server requests
  (`recv_socket` ALERTED + `set_async_direct_result`); A3 histogram: 324,402 pairs 1:1.
  Upstream master is byte-identical — **this patch is ahead of upstream.**
- Design: in `ntdll/unix/socket.c` `sock_recv()`, pre-check with `try_recv` +
  `MSG_DONTWAIT`; on success complete inline via `file_complete_async`
  (0 requests for APC/hEvent sinks, 1 for IOCP sinks — down from 2). On EWOULDBLOCK
  fall through unchanged. Edge cases: OOB/PEEK/multi-buffer excluded or handled;
  same-process read_q reordering guarded (restrict to single-buffer or counter);
  spurious FD_READ benign (legal on Windows).
- Impact: halves wineserver CPU (~6–20% of one core at observed flood rates);
  honest FPS range **0–5%, most likely 1–3%, mostly via 1% lows**.
- **Runtime-verified (2026-07-21):** overlapped-WSARecv probe (`/tmp/recvtest.c`,
  throwaway prefix, installed ntdll) passes all legs — TCP data-ready inline
  completion, TCP pending→arrival server path, UDP overlapped recvfrom. ALL PASS.
- **Attribution RESOLVED (2026-07-21, live `sample` on the running session):** DOOMx64vk
  itself (pid 83320) has threads blocked in `sock_recv` at both socket.c:940
  (recv_socket request) and :957 (set_async_direct_result) — 7 wine_server_call
  samples in 3 s; the CEF network-service helper (pid 83274) shows zero. The flood
  reaches game-process threads (likely the UDP :27016 Steam/matchmaking socket),
  which pushes expected impact toward the high end of the range.

## C. Web hunt — new findings

1. **MoltenVK submit/prefill 2×2 matrix** (not single legs): SYNCHRONOUS_QUEUE_SUBMITS
   interacts with PREFILL_METAL_COMMAND_BUFFERS — with prefill=0 all Metal encoding is
   inside vkQueueSubmit, so async submits move the whole block off the calling thread.
   Test (0,0)/(1,1)/(1,0)/(0,1). Minutes per leg. DOOM has no descriptor indexing →
   prefill compatible (its earlier −32% was likely a different interaction; retest).
2. **Port Proton's `WINE_CPU_TOPOLOGY`** (not upstream, WineHQ bug 56667): universal
   core-topology cap/remap env var; targets engine worker-pool oversubscription across
   M-series speed tiers — a mechanism none of the disproven levers addressed.
   Speculative 0–10%, needs same-scene A/B. ~½ day port, default-off.
3. **macOS 27 Golden Gate** = perf-focused release, last with full Rosetta: re-baseline
   on each beta seed; free gains. Zero cost.
4. `MVK_USE_METAL_PRIVATE_API=1` at MoltenVK build time: compat freebie (provoking
   vertex, depth-bounds, etc.), **not a perf lever** — don't A/B it for FPS.

### Veins now PROVABLY closed (with evidence)

- **All ROSETTA_* env vars enumerated from the macOS 27 runtime binary** (`strings
  /usr/libexec/rosetta/runtime`): ADVERTISE_AVX is the only perf knob; others are
  debug/fatal toggles, live-probed dead. Plus undocumented `CAMBRIA_` prefix alias.
  **No hidden Rosetta knobs exist — closed with certainty.**
- Allocator injection (mimalloc/tcmalloc): Wine 11.13 ntdll heap already has LFH
  frontend + buckets; no lever. Closed.
- CrossOver 26.x: nothing new for CPU-bound Vulkan titles (26.x is D3D-path work;
  NTSync Linux-only). GPTK 4 gains are D3DMetal/Metal-4 side. Parity conclusion stands.
- ntsync on macOS: no port path (Linux kernel module; only macOS attempt is an
  untested prototype). msync remains the vehicle.
- Thread-priority→QoS: double-closed (Apple guidance + local −2.1% A/B).
- MoltenVK pin: 1.4.2 == latest upstream; no MTL4 command-queue path yet (issue #2560).
- Kegworks/Gcenx scene: nothing we lack (Staging 11.x + msync is our base+).

## Current ranked levers (post round 3)

1. x86_64 MoltenVK query-patch in-scene A/B (staged; +5–15% expected) — after user's session.
2. MoltenVK submit/prefill 2×2 env matrix (same sessions).
3. ntdll inline-recv fast path (in progress; +1–3% via lows; ahead of upstream).
4. WINE_CPU_TOPOLOGY port (speculative 0–10%; ½ day).
5. Re-baseline on macOS 27 seeds (hygiene).
6. gfxstream render server: gated NO-GO (see A).
