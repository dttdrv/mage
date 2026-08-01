# Mage fixes — upstreaming candidates for main MoltenVK

Each entry: what it is, the diagnostic that justifies it, and whether it can
go upstream as-is or needs reshaping. Ordered by value to upstream.

## 1. RT pipeline creation via per-stage GPU binaries (MVKPipeline/MVKShaderModule)

Mage: RT stage functions compile with
`MTLFunctionOptionCompileToBinary | MTLFunctionOptionPipelineIndependent`
(macOS 26+) and link through `MTLLinkedFunctions.binaryFunctions` instead of
AIR-linking one module.

Diagnostic: idTech8 RT pipelines (~72 functions, ~236k lines MSL) hit a
fatal LLVM error in the AGX backend when AIR-linked whole. Binary linking
avoids the crash and reduces pipeline-creation latency (Metal links
pre-compiled binaries).

Upstreamability: high, as a config-gated path
(`MVK_CONFIG_...`, default off, macOS 26+ only). No spec implications.

## 2. Acceleration-structure capacity grow on full-write retain (MVKAccelerationStructure)

Mage: `retainFullWriteGeneration` grows native and metadata capacities
instead of returning VK_ERROR_OUT_OF_DEVICE_MEMORY; overflow generations are
privately allocated (placement in the game's buffer only when in-budget).

Diagnostic: idTech8's compact-then-clone flow — compact BLAS, query
VK_QUERY_TYPE_ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR, allocate dst at
that size, CLONE-copy the source in — needs the source's uncompacted native
size (measured 43648 vs dst 27904, ~1.56x). Hard-fail produced 611 copy
errors per boot. The instance-metadata MTLBuffer is a separate
device-private allocation, so bounding it by the Vulkan AS size is
artificial.

Upstreamability: high; upstream's new variant (grow only while
`requiredNativeSize <= _size`) does not cover this flow. Point of discussion
for upstream: Vulkan sizes are what the app budgeted, so growing beyond
`_size` needs the private-allocation story documented in the PR.

## 3. requiredSubgroupSizeStages advertisement (MVKDevice.mm)

Mage: advertise `VK_SHADER_STAGE_ALL_GRAPHICS | VK_SHADER_STAGE_COMPUTE_BIT`.

Diagnostic: with 0, idTech8 executes a deliberate fatal
("Could not ensure that compute pipeline ... gets compiled using the
requiredMinWaveSize ... hardware doesn't have support"). MoltenVK ignores
VkPipelineShaderStageRequiredSubgroupSizeCreateInfo at creation, so any
requested size is accepted; Metal thread execution width is 32.

Upstreamability: high, low risk — it only promises the ability to *accept*
the create-info, which MoltenVK already does.

## 4. fp64 -> fp32 demotion in MSL emission (SPIRV-Cross-ray, spirv_msl.cpp)

Mage: `type_to_glsl` maps SPIRType::Double to `float`; backend drops the
`lf` literal suffix. Fixes a Dark Ages compute shader
(`'double' is not supported in Metal`).

Upstreamability: NOT as-is (silent precision loss is a policy decision).
Upstream shape would be a compiler option (`mslOptions.demote_fp64`) or
proper fp64 emulation via float-float (TwoSum-style) arithmetic. Mage keeps
the hard demotion — one averaging loop, visually negligible.

## 5. wine-side: GIPA/GDPA device-proc fallbacks (wiage, dlls/winevulkan/loader.c)

Mage wine: `vkGetInstanceProcAddr` and `vkGetDeviceProcAddr` fall back to
the device-proc table (with a WARN) instead of returning NULL when the
function-name checks reject a known device function.

Diagnostic: The Dark Ages resolves RT procs via GIPA(instance, name) and on
an 8-extension probe device, caches them in .data, then calls through the
pointer — real drivers/loaders return non-NULL. NULL caused 0xc0000005 at
the first TLAS build; 1001 fallback resolutions logged in one boot after the
fix.

Upstreamability: wine-side, not MoltenVK — relevant to Wine upstream /
CrossOver. Behavior matches real Windows drivers; worth a Wine merge
request. Note: it papers over games skipping extension enablement, which is
why real drivers all do it.

## 6. R16G16 UNORM as AS vertex format (magevk 54f381b8)

Advertise R16G16 UNORM variants among acceleration-structure vertex formats.
Small, self-contained; upstreamable if the format mapping is accurate
(verify against VK_KHR_acceleration_structure format requirements table).

## Mage-specific, not for upstream

- MAGE_VK_* device-identity spoof (vendor/device/driver): belongs in the
  wine layer or a config-only MoltenVK feature at most.
- MAGE_MVK_ENABLE_PRIVATE_SPARSE_BUFFERS / MTL4 placement sparse heaps:
  experimental, macOS 26.4+ private behavior; needs hardening first.
- MVK_CONFIG_FAKE_* feature flags (geometry shader, int64 atomics, cull
  distance): compatibility hacks by design.
- Frame-rate cap config: presentation policy, app-layer concern.
