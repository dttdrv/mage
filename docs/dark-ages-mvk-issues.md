# DOOM: The Dark Ages - launch findings (MoltenVK / SPIRV-Cross)

Captured 2026-07-29, first verbose launch via `bin/mage run doom-the-dark-ages`
(WINEDEBUG=err+all,+vulkan, MVK_CONFIG_LOG_LEVEL=4).
Raw log: $TMPDIR/mage-doom-the-dark-ages.log.

## Fatal: game aborts on GPU vendor, then NULL write crash

Sequence in log: vkCreateInstance OK (MoltenVK 1.4.2, Vulkan 1.4.357) ->
physical device enumeration OK -> game shows "no GPU vendor recognized" ->
`wine: Unhandled page fault on write access to 0x0 at 0x1409EB7F2 (thread 056c)`.

id Tech 8 maps VkPhysicalDeviceProperties.vendorID to an internal vendor enum
(NVIDIA 0x10DE, AMD 0x1002, Intel 0x8086). MoltenVK reports Apple (0x106B),
which hits no table entry; the game then writes through the NULL entry and dies.
This is worked around Wine-side (MAGE_VK_* property spoof in winevulkan), but
the underlying "Apple is not a recognized vendor" problem applies to every
MoltenVK title with a hardcoded vendor table.

## Hard blocker: ray tracing extensions absent

id Tech 8 requires hardware ray tracing at all quality levels. Missing from
the host device extension list:

- VK_KHR_ray_tracing_pipeline
- VK_KHR_ray_query
- VK_KHR_acceleration_structure

(VK_KHR_deferred_host_operations is already present.)

Launching past the vendor check is impossible until Mage MoltenVK exposes RT
(work in progress upstream: KhronosGroup/MoltenVK PR 2771).

## winevulkan filters extensions MoltenVK exposes

Host (MoltenVK) list contains these, but winevulkan reports them
"not supported" and hides them from the game:

- VK_KHR_portability_subset - REQUIRED by spec for MoltenVK devices; games that
  enable it on principle will fail device creation. Wine's vulkan spec copy
  needs this extension wired through.
- VK_EXT_metal_objects - low impact, rarely requested by games.
- VK_GOOGLE_display_timing - low impact.
- VK_MVK_moltenvk (instance) - low impact; some engines use it to detect
  MoltenVK and pick code paths.

## Also absent (noted for future titles)

- VK_EXT_mesh_shader
- VK_KHR_fragment_shading_rate

## SPIRV-Cross

Not reached. The crash happens before any shader module is created, so no
MSL conversion diagnostics exist yet. Re-run this capture after RT lands.

## Staged RT validation

Captured 2026-07-29 from the single staged-runtime launch with
`MVK_CONFIG_LOG_LEVEL=2` and `WINEDEBUG=err+all,+vulkan`.

The unchanged staged probe identified MoltenVK 1.4.3, exposed all four required
RT extensions, created the device, and resolved 23/23 required procedures. The
game log then exposed `VK_KHR_acceleration_structure`,
`VK_KHR_deferred_host_operations`, `VK_KHR_ray_query`, and
`VK_KHR_ray_tracing_pipeline` to `DOOMTheDarkAges`, so the old
`No ray tracing hardware GPU found` gate did not recur.

The game then deliberately aborted before `vkCreateDevice`. Steam recorded
`DOOMTheDarkAges.exe`, followed six seconds later by `BsSndRpt64.exe`. The
resulting `TitanSteam7CBT5OV6.dmp` contains:

```text
FATAL ERROR: Please update your driver: Could not find support for required subgroup stages
```

The exception is the game's forced null-write fatal path. Disassembly shows
that it requires vertex, fragment, and compute subgroup stages:

```text
(supportedStages & 0x31) == 0x31
```

The failed staged runtime reported `0x32`, so vertex was the only missing stage.
The following required subgroup-operation and storage-buffer-alignment checks
already pass. The minidump module list independently confirms that the game
loaded `mage/dist/runtime-ray-icb/lib/libMoltenVK.1.4.3.dylib`.

## Vertex-subgroup regression on the rt-minimal line (2026-07-31)

The magevk `mage-rt-minimal` branch (2771 head + "Allow ray tracing without
placement heaps" eefe7375 + its dirty working tree + 2788 + Mage config)
launched the game past the vendor spoof (`mage: spoofing GPU identity`
confirmed in log) and died with the SAME subgroup-stage fatal, dump
`TitanSteam6OPL1SE3.dmp`:

```text
FATAL ERROR: Please update your driver: Could not find support for required subgroup stages
```

Root cause: the vertex-subgroup support never lived in the 2771/eefe7375
line. It exists only as (a) a 2-file change in the ray-icb experiment tree
(vertex bit in `populateSubgroupProperties`, fixed subgroup size for the
plain vertex stage) and (b) 12 uncommitted lines in
`sources/SPIRV-Cross-ray` on top of 62db8c83. The dirty rt-minimal import
had also re-pinned SPIRV-Cross to upstream 6c09849f, which cannot emit
vertex subgroups either.

Fix ported into Mage-owned trees (all local, main project untouched):

- magevk `mage-rt-minimal` @ 68cc22df: vertex stage bit (Apple GPU +
  simdPermute + simdReduction) and vertex `fixed_subgroup_size`, SPIRV-Cross
  pin restored to 62db8c83.
- SPIRV-Cross `mage-vertex-subgroups` @ a2713ce7 (pushed to mage/spirv-cross):
  the 12-line vertex subgroup emission change, committed with its test
  shaders. Build uses `-DCPM_SPIRV-Cross_SOURCE=mage/sources/SPIRV-Cross-ray`.

## Subgroup gate cleared; current gate is three features (2026-07-31)

With the vertex-subgroup build deployed, the game passes vendor spoof, RT
extension exposure, and the subgroup-stage check. vkCreateDevice then fails
on exactly three requested features (verified by dumping the full
requested/available feature arrays at the error site):

- sparseBinding
- sparseResidencyBuffer
- shaderBufferInt64Atomics

Everything else the game wants is covered: geometryShader and
shaderCullDistance via the Mage fake flags, wideLines via a
`MVK_USE_METAL_PRIVATE_API=ON` build (now the runtime default), and
shaderResourceMinLod natively (it was never missing; earlier suspicion was
a field-counting error during diagnosis, not a MoltenVK defect).

Notes for whoever implements the rest:

- shaderBufferInt64Atomics cannot be exposed honestly: Metal 4 on the
  M5 Pro does not compile `atomic_ulong` device ops (verified with a
  runtime-compiled MSL probe). It needs emulation in
  MoltenVK/SPIRV-Cross or a game-level workaround.
- sparseBinding/sparseResidencyBuffer: the 554-line vkQueueBindSparse
  emulation experiment in `mage/sources/MoltenVK-ray-icb` was a start but
  incomplete (the 2026-07-29 reviewed artifact still failed device
  creation on these two). Faking the feature bits without working sparse
  backing will crash the game at the first sparse operation.
- The 2026-07-29 feature list in this document is confirmed accurate
  (sparseBinding + sparseResidencyBuffer, not a minLod issue).

## Isolated vertex subgroup validation

The required basic, vote, arithmetic, ballot, shuffle, and shuffle-relative
operations compile in a Metal 2.3 vertex function on Apple GPU hardware. The
isolated MoltenVK source now includes vertex in `supportedStages` only for an
Apple GPU with SIMD permutation and reduction support.

The unchanged Windows probe moved from:

```text
SUBGROUP stages=0x32 operations=0x6ff size=32 required_stages=0 required_operations=1
```

to:

```text
SUBGROUP stages=0x33 operations=0x6ff size=32 required_stages=1 required_operations=1
```

The rebuilt universal staged runtime still passes the RT probe with device
creation and 23/23 procedures. A SPIR-V vertex shader exercising subgroup size,
local invocation ID, and every operation class in the advertised `0x6ff` mask
also passed
graphics-pipeline creation, one draw, queue submission, and GPU completion
through Wine, the pinned SPIRV-Cross, MoltenVK, and Metal. The live Mage runtime
was not changed.

## Reviewed vertex-subgroup launch

The reviewed staged artifact launched the game and cleared the subgroup-stage
fatal. The next failure is:

```text
FATAL ERROR: vkCreateDevice failed with error (VK_ERROR_FEATURE_NOT_PRESENT)
```

MoltenVK reported every unavailable feature requested by the game:

```text
VkPhysicalDeviceFeatures2:
  geometryShader
  wideLines
  shaderCullDistance
  sparseBinding
  sparseResidencyBuffer

VkPhysicalDeviceVulkan12Features:
  shaderBufferInt64Atomics
```

The first captured dump is `TitanSteamBLVL6CC4.dmp`. A second diagnostic launch
with only MoltenVK logging enabled reproduced the same six requests and produced
`TitanSteam951L0HL4.dmp`. The staged dylib remained
`e3526dfd987f9e80bde39d4b28d12f4299f200ebbf4c9fa9e3479c416579c0e8`; the live
dylib remained
`575c8e111a3d53bb733c646599de4c81c6e8ceffa8b050b2a2be4f82e9c3340a`.

After the launch, the unchanged staged RT probe still passed device creation and
23/23 procedures, and the subgroup probe still returned stages `0x33`,
operations `0x6ff`, and size 32. Steam and wineserver were not stopped. The
latest `BsSndRpt64.exe` reporter still owns AppID `3017860`; do not relaunch
until it exits normally.
