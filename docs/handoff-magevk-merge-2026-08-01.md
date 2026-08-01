# MageVK merge from main-tree MoltenVK (2026-08-01)

Handoff for the main-project (GPT) work: what was merged into magevk, what
conflicted, and the diagnostics behind each decision. Also useful to avoid
re-learning the git pitfall at the end.

## What was merged

Source: `upstream/MoltenVK-ray-as-minimal` working tree (uncommitted, 42
dirty files vs `eefe7375` — AS serialization rewrite, MVKSync/MVKQueue
refactor). Patch: `git diff eefe7375..worktree`.

Key discovery: magevk's 2026-07-31 import (`079dd0c8` "Import ray-as-minimal
working tree") already contained almost all of that dirty tree. After
per-file 3-way merges, **the real delta was 3 files**:

- `MVKInstance.mm` — `vkCmdTraceRaysIndirect2KHR` entry point now registered
  as available when *either* `VK_KHR_ray_tracing_maintenance_1` or
  `VK_KHR_ray_tracing_pipeline` is enabled (was: maintenance1 only). Games
  enabling only the pipeline extension can now resolve the proc.
- `MVKPipeline.mm` — MSL options archive now covers the new
  `ray_tracing_*` buffer-index/stage-depth fields (intersection, callable,
  recursive function, recursive intersection, instance metadata, AS address
  table, stage depth, pipeline-emulation toggle, raygen-visible). Cache
  correctness for RT pipeline libraries depends on this.
- `vulkan.mm` — `vkCmdTraceRaysIndirect2KHR` error wording now matches
  upstream.

Result: `mage/magevk` commit `96a02ddc` on branch `mage-rt-rayquery`
(pushed). SPIRV-Cross pin `6fea186f` was already an ancestor of
`mage/sources/SPIRV-Cross-ray` HEAD (`5265d501`), no change needed.

## Conflicts and resolutions (6 files)

All conflicts were Mage fixes colliding with the upstream refactor. Decisions
and why:

1. `MVKAccelerationStructure.mm` — **kept Mage version.** Upstream's new
   `retainFullWriteGeneration` grows native capacity only while
   `requiredNativeSize <= _size` and still hard-fails on metadata growth.
   DOOM: The Dark Ages compacts a BLAS then CLONE-copies into a destination
   sized to the *compacted* query result; the clone needs the source's
   uncompacted native size (measured 43648 vs 27904, ~1.56x), which exceeds
   `_size`. Upstream's version returns VK_ERROR_OUT_OF_DEVICE_MEMORY for
   exactly this flow (611 failures per boot before the Mage fix). Mage
   version grows both capacities; overflow storage is privately allocated,
   only in-budget generations use placement in the game's buffer. This is a
   behavioral superset of upstream's — candidate for upstreaming (see
   `docs/upstreaming-mage-fixes.md`).
2. `MVKInstance.mm` — took upstream (see delta above).
3. `MVKPipeline.h` / `MVKPipeline.mm` — **kept Mage version** of the
   `MTLFunctionOptions` plumbing (`rtFuncOptions`):
   `MTLFunctionOptionCompileToBinary | MTLFunctionOptionPipelineIndependent`
   per RT stage, linked via `MTLLinkedFunctions.binaryFunctions` (macOS 26+).
   Rationale: AIR-linking all stages of an idTech8 RT pipeline (~72
   functions, ~236k lines of MSL) trips a fatal LLVM error in the AGX
   compiler backend. Per-stage GPU binaries + binary link is the only way
   The Dark Ages creates its RT pipelines at all. Upstream currently has no
   equivalent — important upstreaming candidate with this diagnostic.
   Third conflict in the same file (archive fields): took upstream addition.
4. `MVKQueue.mm` — **kept Mage version** (MTL4 sparse-event submission
   path from `e64dfeb7`/`b7f54a76`; upstream refactor did not cover private
   sparse buffers).
5. `vulkan.mm` — took upstream wording to minimize divergence.

## Diagnostics worth carrying upstream

- The compact-then-clone capacity failure (values above) is deterministic in
  idTech8 and will hit any MoltenVK RT user doing
  VK_QUERY_TYPE_ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR + CLONE copies.
- The AGX AIR-link crash on very large RT pipelines is reproducible with The
  Dark Ages' pipeline set; the binaryFunctions path avoids it and also
  shortens pipeline creation (Metal links pre-compiled GPU binaries).
- `requiredSubgroupSizeStages = 0` makes idTech8 kill itself deliberately
  (`mov dword ptr [0], 0x12345678` fatal stub) — it *requires* wave-size
  control for compute. Mage advertises ALL_GRAPHICS|COMPUTE; Metal ignores
  the requested size (execution width 32) which is spec-acceptable.

## Tooling pitfall (cost a full redo)

`git apply --3way` (Apple Git 2.54.0) is effectively atomic-except-conflicts:
if any file conflicts, the cleanly-merged files are **not** persisted to
worktree or index, while it still prints "Applied patch to '...' cleanly".
A commit made after resolving the markers silently contains only the
conflicted files. Workaround used: apply per-file with
`git apply --3way --include=<path>` in a loop (no conflict in an invocation
means the result persists), then resolve the conflicted files.

## Verification

- `cmake --build mage/build/MoltenVK-rt-rayquery` clean (no xcodebuild;
  that path lacks External xcframeworks).
- Deployed `libMoltenVK.1.4.3.dylib` (13351184 bytes) to
  `toolchains/wine-mage-11.13/install-macos12-freetype/lib/libMoltenVK.dylib`
  and `mage/dist/runtime-ray-icb/lib/libMoltenVK.dylib` (ad-hoc resigned).
- Mage fixes verified present in merged source: binaryFunctions link, AS
  capacity grow, requiredSubgroupSizeStages.
- In-game retest pending (see `docs/dark-ages-mvk-issues.md` section 5 for
  the open white-window / present-starvation blocker).
