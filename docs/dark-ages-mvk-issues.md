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

## 2026-07-31: launcher GPU gate fully mapped and passed

idTechLauncher ("Raytracing Incompatible GPU" dialog) gates on Vulkan data
only. Its full probe: vkCreateInstance + device extension enumeration +
vkGetPhysicalDeviceProperties x2, then vkDestroyInstance and the dialog.
No DXGI, no registry GPU reads, no feature queries. Four separate blockers
were found and fixed, in order:

1. winevulkan loader returned NULL from vkGetDeviceProcAddr for device
   functions whose extension is not enabled on that device. Real drivers
   return non-NULL thunks regardless. The game resolves the RT procs on an
   8-extension probe device, caches them in .data globals, and later calls
   through NULL during streaming (both minidumps: call [rip+0x3cc1e70] at
   exe RVA 0xc84112, 0xc0000005). Fixed in wiage: loader.c falls back to
   wine_vk_get_device_proc_addr with a WARN. 329 device functions resolved
   for the game on the next boot, including the full RT set.
2. wine was loading a stale Jul-28 libMoltenVK: install/lib/libMoltenVK.dylib
   was never updated when dist/runtime-ray-icb was, and
   install/lib/libMoltenVK.1.dylib was a real file (1.4.2) shadowing the
   canonical install name. Both now point at the current build. Deploy
   MoltenVK to BOTH dist/runtime-ray-icb/lib and the wine install lib.
3. VkPhysicalDeviceProperties gate fields: vendorID/deviceID/deviceName/
   driverVersion spoofed via MAGE_VK_* (magevk, post-init so Metal feature
   detection stays Apple); deviceType must be DISCRETE (dedicated-VRAM
   check), set via MAGE_VK_DEVICE_TYPE=2; sparseBinding and
   sparseResidency* features + sparseProperties reported with
   MAGE_MVK_ENABLE_PRIVATE_SPARSE_BUFFERS=1 (the game requests sparseBinding
   and sparseResidencyBuffer at vkCreateDevice).
4. wine itself replaced deviceName: win32u get_physical_device_properties2
   overwrites it from the display-device list ("Apple M5 Pro"), discarding
   the MoltenVK spoof. win32u/vulkan.c now honors MAGE_VK_DEVICE_NAME.
   This was the last gate: with it the launcher saw vendor 0x1002,
   device 0x744C, discrete, driver 0x800156, "AMD Radeon RX 7900 XTX",
   sparse residency reported.

Build gotcha that cost one cycle: overwriting a loaded dylib in place with
cp invalidates its cached code signature (kernel: rejecting invalid page,
cs_mtime != mtime, process killed: 9). Re-sign after in-place deploys:
codesign --sign - --force <dylib>.

## 2026-08-01 — RT gate root-caused and passed; game boots and presents

The launcher's "Raytracing Incompatible GPU" dialog had one final, non-obvious
condition: after checking the 5 required device extensions (deferred_host_operations,
pipeline_library, ray_tracing_pipeline, acceleration_structure, ray_query), it calls
vkGetPhysicalDeviceFormatProperties2 for VK_FORMAT_R16G16B16A16_UNORM (91) and
requires bufferFeatures bit 29 — VK_FORMAT_FEATURE_2_ACCELERATION_STRUCTURE_VERTEX_BUFFER_BIT_KHR.
Windows drivers set that bit on the UNORM formats; magevk only mapped the six
spec-legal AS vertex formats, so the bit read 0 and the launcher bailed.
Fix: magevk commit 54f381b8 (branch mage-rt-rayquery) maps R16G16_UNORM and
R16G16B16A16_UNORM to MTLAttributeFormatUShort{2,4}Normalized.

With that, the launcher passes the gate, spawns DOOMTheDarkAges.exe, and the game
creates a device with acceleration_structure + ray_query + ray_tracing_pipeline
enabled, submits work, and presents frames (vkQueuePresentKHR). One non-fatal
warn: the game asks for the 5th VkPhysicalDeviceRayTracingPipelineFeaturesKHR flag
(rayTracingPipelineTraceRaysIndirect) which magevk does not expose; the game
continues without it.

The launcher also probes D3DKMT: D3DKMTEnumAdapters2 (matches the Vulkan
deviceLUID against KMT adapter LUIDs — wine's are consistent) and
D3DKMTQueryAdapterInfo(KMTQAITYPE_WDDM_2_7_CAPS=70), which wine did not implement
(STATUS_NOT_IMPLEMENTED; gracefully skipped by the launcher, but now implemented
in win32u/d3dkmt.c anyway).

Housekeeping: the recipe no longer sets WINEDEBUG=+vulkan /
MVK_CONFIG_TRACE_VULKAN_CALLS / MVK_CONFIG_SHADER_DUMP_DIR — the +vulkan trace
grew the mage log to 8.5 GB in one session and filled the disk mid-build.

## Post-launch crashes (2026-08-01)

### 1. Null call in TLAS build (0xc0000005 at exe+0xC84112)

After the RT pipeline links, the game builds its first TLAS and calls a global
function pointer that is NULL. Minidump walk (MemoryList stream 5; Breakpad
writes no Memory64List) shows `call qword ptr [rip+0x3cc1e70]` with a zero slot.
The call signature (device, buildType, pBuildInfo sType 1000150000,
pMaxPrimitiveCounts, pSizeInfo sType 1000150004) is
vkGetAccelerationStructureBuildSizesKHR. The game resolves RT procs through
vkGetInstanceProcAddr(instance, name); wine's GIPA returned NULL for any
device-level function (`is_available_instance_function` rejects the name and
the function returns NULL before reaching the device-table fallback). Real
drivers/loaders return device procs from GIPA. Fix: wiage `dlls/winevulkan/
loader.c` — when the instance-function check fails, fall through to
`wine_vk_get_device_proc_addr` (WARN + return thunk) before NULL. One boot
session then logged 1001 GIPA-fallback resolutions. The earlier GDPA
"extension not enabled" fallback remains needed for the 8-extension probe
device.

### 2. Deliberate fatal: requiredMinWaveSize / subgroup size control

Next crash was the game killing itself (`mov dword ptr [0], 0x12345678` at
exe+0x20AC70E, idTech fatal-error stub) with the message: "Could not ensure
that compute pipeline for render prog '%s' gets compiled using the
`requiredMinWaveSize` of `%d` because the hardware doesn't have support for
setting the required wave size for the compute shader stage". magevk
advertised `requiredSubgroupSizeStages = 0` (MVKDevice.mm). Fix: advertise
VK_SHADER_STAGE_ALL_GRAPHICS | COMPUTE. MoltenVK ignores
VkPipelineShaderStageRequiredSubgroupSizeCreateInfo at pipeline creation, so
any requested size is accepted; Metal's thread execution width is 32. Game
then survived past the previous crash window (alive 3+ min, 150-300% CPU).

### 3. fp64 in one compute shader (fixed via demotion)

One pipeline failed to compile: `program_source:293: error: 'double' is not
supported in Metal` (SPIR-V with Float64 capability — a single averaging
loop accumulating into a double, then converting back to float). Metal has
no fp64 at all. Fix: SPIRV-Cross-ray `spirv_msl.cpp` demotes fp64 to fp32
in MSL output — `type_to_glsl` maps SPIRType::Double to "float" and the
backend drops the `lf` literal suffix. Shader now compiles; precision loss
is negligible for this use. Note: the demotion does not cover doubles in
buffer blocks (MSL has no layout for them); none encountered so far.

### 4. AS compaction copy failures (611x per session)

`vkCmdCopyAccelerationStructureKHR(): The destination acceleration structure
has insufficient capacity` — instrumented values: `result=-2 dstGen=0x0
reqNative=43648 dstSize=27904 metaSize=0 mode=0`. idTech compacts a BLAS,
queries the compacted size, allocates a destination of exactly that size,
then CLONE-copies the source into it. The clone needs the source's native
(uncompacted) Metal size (~1.56x the compacted Vulkan size), so
`retainFullWriteGeneration` failed on the native capacity check before
allocating any generation. Two-part fix in `MVKAccelerationStructure::
retainFullWriteGeneration`: (a) native capacity grows to the required size
instead of failing — storage in excess of the Vulkan AS size is privately
allocated (only in-budget generations use placement in the game's buffer);
(b) `_metadataCapacity` likewise grows instead of failing (the
instance-metadata buffer is a separate device-private MTLBuffer, not bounded
by the Vulkan AS size). Verified: zero capacity errors afterwards, game
stays alive. Debug instrumentation in MVKCmdAccelerationStructure.mm was
removed after diagnosis.

### 5. Current blocker: white window, ~0.3 fps, presents never complete

With 1-4 fixed the game boots fully: creates its Saved Games config
(r_mode 21) and profile, builds all RT pipelines, opens a 1362x884 window —
then sits on a white screen at ~230% CPU. Findings (2026-08-01):

- Process samples show a live render loop: vkBeginCommandBuffer,
  vkCmdBuildAccelerationStructuresKHR, vkUpdateDescriptorSets,
  vkCmdBindPipeline/VertexBuffers, then vkWaitForFences/vkWaitSemaphores
  (84% of samples). Bink async decode threads exist.
- vkQueuePresentKHR is almost never sampled (once in 13s of sampling); the
  one captured stack sat inside client_surface_present ->
  MVKPresentableSwapchainImage::getCAMetalDrawable — i.e. blocked waiting
  for a free drawable. Metal HUD (MTL_HUD_ENABLED=1) initializes in-process
  but never draws, consistent with no present ever completing.
- GPU is genuinely busy: IOAccelerator PerformanceStatistics shows Device
  Utilization 74-78%, Renderer 74%, Tiler 18-22%, 13 GB allocated system
  memory; no GPU recovery events. Not a deadlock — pathologically slow
  frames (est. >=3 s/frame) with all 3 swapchain images in flight.
- Swapchain itself is healthy: 3 images, 1280x720, on the WineMetalView
  CAMetalLayer; no mvk-error in log after the fp64 fix.

Open hypotheses, untested:

1. Per-frame full AS rebuilds are pathological in our implementation (the
   game rebuilds/refits every frame; fine on native drivers, seconds here).
2. A GPU-side infinite/very long ray-traversal: if a grown generation
   (nativeSize > _size) is later referenced as an instance source,
   retainCurrentGeneration returns nullptr and the TLAS may encode a
   stale/empty AS reference, sending traversal into garbage. Would present
   exactly like this: GPU pegged, fences never signal, presents starved.
3. A game-side validation/readback loop (dispatch, fence, compare result,
   retry on mismatch) that our emulation can never satisfy.

Next diagnostic steps: trace per-frame AS build sizes/counts; check whether
any BLAS with nativeSize > _size ends up instanced into the TLAS; capture a
GPU frame (Metal capture under Wine is unproven) or add MVK logging around
acceleration-structure reference encoding.
