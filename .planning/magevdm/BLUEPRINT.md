# MageVDM Architecture and Execution Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use the Mage stack engineering,
> architecture-first engineering, evidence-gated engineering, and ponytail
> workflows. Use subagent-driven development or executing-plans only after the
> start gate below is open. Every implementation task needs its own red/green
> evidence and review before integration.

**Status:** Reviewed architecture plan. Graphics implementation is blocked by
the mechanical start gate below. The independent Wiage/FEX reconstruction may
continue in its own worktree because it does not depend on MageVDM graphics.

**Mechanical start gate:** Begin MageVDM graphics implementation only when all
of the following are recorded in this document's evidence ledger:

- the exact MoltenVK ray-tracing candidate commit is pushed;
- every required MoltenVK and SPIRV-Cross patch is published in the repository
  that owns it;
- all author-resolvable review feedback has been answered in code or with
  evidence;
- CI, focused regressions, CTS coverage where available, and local hardware
  witnesses are attached to the candidate;
- the candidate worktrees contain no unpublished tracked implementation;
- every remaining action belongs to a maintainer, reviewer, or CI system.

“Mostly complete,” an unpublished local improvement, or an unanswered action
for the author keeps this gate closed.

**Current gate verdict: CLOSED.** This ledger is updated during Phase 0; a row
may become `MET` only when its exact reference and evidence are filled. The
gate becomes `OPEN` only when every row is `MET`.

| Condition | Exact commit/URL | Evidence | Status | Current action owner |
|---|---|---|---|---|
| MoltenVK RT candidate pushed | Not recorded | Candidate diff and remote commit proof required | UNMET | Author |
| Required MoltenVK patches published | Not recorded | Owning-repository submission URLs required | UNMET | Author |
| Required SPIRV-Cross patches published, or recorded as none | Not recorded | Submission URLs or reviewed no-dependency finding required | UNMET | Author |
| Author-resolvable review feedback exhausted | Not recorded | Review ledger mapped to code/evidence required | UNMET | Author |
| CI, focused regressions and applicable CTS attached | Not recorded | Exact runs, logs and failures required | UNMET | Author |
| Hardware witnesses attached with scope | Not recorded | Device/OS/build/library proof required | UNMET | Author |
| No unpublished tracked implementation remains | Not recorded | Status for every candidate worktree required | UNMET | Author |
| Remaining actions are external only | Not recorded | Named maintainer/reviewer/CI owner per action required | UNMET | Author |

**Goal:** Build one coherent Apple-silicon Windows gaming graphics stack that
automatically accepts Vulkan and Direct3D 7 through 12, uses Wiage as its
Windows runtime, converges on one maintained Metal backend, and ultimately owns
its shader translation path.

**Architecture:** The first executable stack reuses proven Vulkan translators
to establish end-to-end behavior quickly. The long-term stack progressively
replaces opaque or slow dependencies behind explicit Mage-owned contracts; it
does not begin by rewriting every frontend or compiler. Native Vulkan remains a
first-class frontend throughout.

**Initial technology:** Wiage, Mage, MageVK, DXVK, vkd3d-proton, SPIRV-Tools for
SPIR-V parsing and validation, SPIRV-Cross as a temporary output oracle and
fallback, Vulkan, Metal 3/4, MSL, and Apple's supported Metal compiler tools.

## 1. Product Definition

MageVDM is the graphics and integration program. Mage remains the user-facing
launcher and installer. Wiage remains the Windows runtime. MageVK remains the
Vulkan frontend and Metal backend. Vulkan is the only executable graphics
convergence contract in the baseline.

The product experience is:

1. The user selects a Windows game in Mage.
2. Before launch, Mage selects one complete route from executable inspection,
   a signed compatibility profile, and a user override when supplied.
3. Mage atomically installs the route's architecture-correct DLL set and Wine
   overrides into an isolated prefix, then Wiage starts the process.
4. Loaded-module telemetry verifies the selected route; it may correct the
   next launch but never switches graphics implementations in a live process.
5. During bootstrap, D3D frontends translate source semantics to Vulkan and
   MageVK translates Vulkan to Metal. Native Vulkan enters MageVK directly.
6. Covered shaders use the Mage compiler; uncovered shaders use the explicitly
   counted SPIRV-Cross fallback until the retirement gate passes.
7. Wiage owns the macOS window while MageVK owns Vulkan presentation and Metal
   drawable handling under the presentation contract below.
8. One diagnostic bundle records every component revision, selected route,
   capability profile, cache identity, memory budget, and failure.

The CPU execution path is equally explicit:

```text
Current:  x86/x64 Windows code -> x86_64 Wiage -> Rosetta -> macOS
Target:   x86/x64 Windows code -> FEX -> arm64 Wiage -> macOS
```

FEX is not bundled as an unrelated emulator. It is Wiage's planned guest-code
engine. Wiage continues to own the Windows ABI, processes, synchronization,
windowing and module boundary around it.

Examples:

- DOOM: The Dark Ages: Vulkan -> MageVK -> Metal.
- Cyberpunk 2077: D3D12/DXR -> vkd3d-derived frontend -> Vulkan -> MageVK -> Metal.
- A D3D11 title: D3D11 -> DXVK-derived frontend -> Vulkan -> MageVK -> Metal.
- A 32-bit D3D7 title: D3D7 -> Wiage wined3d Vulkan renderer -> winevulkan -> MageVK -> Metal.

"Automatic" means the user does not install DLLs, choose an API translator, or
assemble component versions manually. It does not mean every game is assumed
compatible. Unsupported behavior must fail with a named missing capability,
not a fake feature bit or unexplained crash.

## 2. Non-Negotiable Constraints

- Wiage is the runtime. GPTK and D3DMetal are compatibility/performance
  references and development tools, not required distributable components.
- FEX is the target x86/x64 CPU execution engine for native arm64 Wiage. The
  existing Rosetta route remains the correctness and performance oracle until
  the FEX route meets its replacement gates.
- All supported Apple-silicon machines are product targets. Code gates on
  queried capabilities and contracts, never on marketing chip names.
- 32-bit Windows applications remain supported.
- Native Vulkan is not routed through a Direct3D layer.
- A frontend owns source-API semantics. The Metal backend owns Apple resource,
  command, synchronization, presentation, and hardware behavior.
- The shader compiler owns accepted-input policy, semantic interpretation,
  internal IR, lowering, MSL generation and shader-cache identity. It reuses
  pinned SPIRV-Tools parsing and validation; runtime code does not grow a
  second private compiler.
- SPIRV-Cross is a bootstrap/fallback dependency, not the end-state owner of
  MageVDM shader behavior.
- DXVK and vkd3d-proton are bootstrap codebases and sources of proven behavior.
  Their permanent surface is decided component by component, with license and
  maintenance cost recorded.
- No per-game hack when a general mechanism exists. Compatibility profiles may
  choose routes or standards-compliant behavior; they may not conceal an
  invalid backend contract.
- No performance claim without the exact game, scene, settings, component
  manifest, cache state, frame-time distribution, and before/after evidence.
- No public feature exposure until every required operation has a valid path.
- No proprietary Apple component is included in a distributable build without
  an explicit license review permitting that exact use.
- One dirty worktree has one writer. Mage, MageVK, Wiage, compiler, and
  frontend changes keep independent branches and evidence ledgers.
- Online games with anti-cheat, DRM drivers, or integrity enforcement are not
  compatibility targets unless their vendor explicitly supports the runtime.
  Mage warns before launch and never disguises Wiage, FEX, or translated DLLs.

## 3. What Exists Already

The project does not start cold:

Every input is tagged `reproducible`, `committed-local`, `published`,
`dirty-reconstruction`, `aspirational`, or `retracted`. A later state never
gets inferred from a document or a successful process launch.

| Asset | Current owner | Evidence state | Qualifier/provenance | Reuse |
|---|---|---|---|---|
| Launcher, recipes, runtime selection, diagnostics | Mage | published | Public Mage baseline | Product shell and prelaunch route selection |
| Windows execution and winevulkan baseline | Wiage | published | Public Wiage baseline | Runtime; no second Wine distribution |
| Additional local Wiage runtime work | Wiage | dirty-reconstruction | Exact commits and dirty files must be audited before reuse | Evidence source only until reconstructed |
| Native arm64 Wine groundwork and FEX-facing loader work | Wiage local BUILD ledger | dirty-reconstruction | Documented patches; no standalone FEXCore checkout in the audited workspace | Reconstruct into a clean branch before use |
| Vulkan-to-Metal baseline | MageVK | published | Public MageVK/MoltenVK-derived baseline | Vulkan frontend and Metal backend |
| Current RT candidate work | MageVK/MoltenVK work | dirty-reconstruction | Gate must replace this label with exact committed/published state | RT foundation and Vulkan correctness evidence |
| D3D8-11 semantics and game knowledge | DXVK | published | Third-party pinned source | Seed frontend and oracle only after requirements pass |
| D3D12/DXR semantics and game knowledge | vkd3d-proton | published | Third-party pinned source | Seed frontend and oracle only after requirements pass |
| SPIR-V parsing and validation | SPIRV-Tools | published | Third-party pinned source | Reused input boundary |
| SPIR-V-to-MSL baseline | SPIRV-Cross | published | Third-party upstream/fork baseline | Temporary output oracle and fallback |
| Local SPIR-V RT candidate work | SPIRV-Cross work | dirty-reconstruction | Gate must record exact owning submission or no dependency | Evidence source only until pinned |
| Persistent MSL/pipeline-cache work | MageVK | dirty-reconstruction | Exact local state must be pinned | Seed for coordinated cache policy |
| Unified-memory budgeting experiments | MageVK | dirty-reconstruction | Experimental local evidence | Seed for telemetry and budget policy only |
| GPTK/D3DMetal evaluation environment | Apple | reproducible | Local proprietary reference under Apple terms | Comparison only; never infer redistribution permission |

Current upstream facts that shape the first build:

- DXVK currently implements D3D8, D3D9, D3D10, D3D11 and DXGI over Vulkan.
- vkd3d-proton implements D3D12 over Vulkan and shares DXGI with DXVK.
- Modern versions of both expect a capable Vulkan 1.3 driver with substantial
  descriptor and synchronization support. MageVK must pass a requirements
  probe before either frontend is treated as supported.
- SPIRV-Cross can emit MSL, but Mage's RT work has demonstrated an ownership
  and review bottleneck for large new shader semantics.
- Apple's public GPTK material presents its Windows environment as an
  evaluation path. Packaging permission is a separate question and is not
  inferred from technical availability.

Primary references:

- https://github.com/doitsujin/dxvk
- https://github.com/doitsujin/dxvk/wiki/Driver-support
- https://github.com/HansKristian-Work/vkd3d-proton
- https://github.com/KhronosGroup/SPIRV-Cross
- https://developer.apple.com/games/game-porting-toolkit/
- https://developer.apple.com/metal/availability/

## 4. System Shape

### 4.1 Bootstrap shape

The first vertical slice uses Vulkan as the convergence boundary because that
path already exists and is independently testable:

```text
Vulkan game ---------------------------------------------+
D3D7 -> Wiage wined3d Vulkan renderer -> winevulkan -----+
D3D8/9/10/11 -> DXVK seed -------------------------------+--> MageVK --> Metal
D3D12/DXR -> vkd3d-proton seed --------------------------+
```

This is a milestone, not the permanent dependency promise. It establishes
game behavior, captures real shader and API workloads, and provides an oracle
for later replacement work.

### 4.2 Deferred backend experiment

The executable baseline has one convergence point: Vulkan at MageVK. There is
no generic Mage GPU API and no second Vulkan-like contract. Phase 5 may reopen
a smaller private backend-primitives experiment only if two direct frontends
exist, duplicated work is measured, and extraction wins an A/B test. Failure
deletes the experiment and keeps Vulkan as the runtime boundary.

## 5. Component Contracts

### 5.1 Mage

Owns:

- component manifest and exact combo version;
- installation and updates;
- game detection and route selection;
- compatibility database;
- user-visible settings;
- log collection and support bundle creation;
- cache location and lifecycle policy;
- launch-time memory-budget policy.

Route selection is complete before process creation. Its manifest records PE
bitness, prefix, every DLL source and destination, Wine override, expected
loaded module and rollback generation. Installation is atomic: prepare a new
generation, validate hashes and bitness, then switch one manifest pointer.
Failure restores the previous generation without deleting user prefix data.
`system32` and `syswow64` mappings are explicit and never inferred from host
directory names.

Does not own:

- D3D or Vulkan semantics;
- shader transformations;
- Metal object lifetime;
- hidden feature lies.

### 5.2 Wiage

Owns:

- PE execution and Windows ABI;
- 32/64-bit runtime selection;
- Rosetta path and the future arm64/FEX contingency;
- DLL loading and per-prefix isolation;
- Windows synchronization and process lifecycle;
- macOS window, input and focus integration;
- winevulkan/DXGI handoff.

The first MageVDM build uses Wiage unchanged except for the smallest required
frontend installation and logging hooks. Graphics redesign does not become an
excuse for a simultaneous Wine rewrite.

FEX work remains an active Wiage stream before MageVDM implementation starts.
It follows its own one-variable-at-a-time evidence ledger and does not edit
MageVK, the shader compiler or D3D frontends to make an early CPU test pass.

#### FEX execution contract

FEX owns:

- decoding and translating x86/x64 guest instructions;
- guest CPU state, exceptions and self-modifying-code coherency;
- translated-code cache identity and invalidation;
- guest memory-order behavior required by Windows code;
- transfer between guest execution and Wiage's native runtime boundary.

Wiage owns:

- Windows process, thread and module semantics;
- the `xtajit64`/ARM64EC-facing integration surface selected by the existing
  Wine architecture;
- syscall and Unix-call transitions;
- native macOS threads, windows, files and synchronization;
- selection and rollback between FEX and Rosetta runtimes.

The FEX boundary contains no graphics-specific commands. A Vulkan or D3D call
must cross the normal Wiage module boundary after guest execution; graphics
frontends remain independently testable. That sentence is a target, not yet a
proven ABI. Before integration, the Wiage branch must fill this table with
actual artifacts and witnesses:

| Module boundary | PE type | Mach-O architecture | Execution engine | Call bridge | Pointer/address owner | Callback direction | Exception owner |
|---|---|---|---|---|---|---|---|
| x64 game -> Wiage builtin | to prove | to prove | FEX | to prove | to prove | both | to prove |
| Wiage builtin -> Unix module | to prove | arm64 target | native | Unix-call target | to prove | both | to prove |
| winevulkan -> MageVK | to prove | arm64 target | native | Vulkan ABI target | Vulkan/MageVK split | debug callback returns to guest | to prove |

Smallest ABI proof: an x64 console PE calls an ARM64EC/builtin Wiage module,
crosses into an arm64 Unix-side module, and returns while testing pointer-rich
structures, TLS, SEH/unwind, atomics, JIT/self-modifying code and a reverse
callback. Smallest graphics proof: a headless x64 Vulkan compute PE reaches
arm64 winevulkan and MageVK, then verifies `pNext`, dispatchable and
non-dispatchable handles, mapped memory, queue/fence completion, output bytes
and a guest debug callback. Signing, hardened runtime, `MAP_JIT`, entitlements
and notarization are recorded for both development and distributable builds.

### 5.3 Graphics frontends

Each frontend must provide:

- source API object and lifetime semantics;
- source synchronization interpretation;
- feature and format mapping;
- pipeline/shader input plus complete reflection metadata;
- deterministic errors for unsupported operations;
- correlated trace identifiers attached to backend work;
- no Apple hardware branching except through backend capabilities.

The frontend uses Vulkan internally during bootstrap. No direct Metal/backend
path is part of the executable baseline.

### 5.4 Metal backend

Owns:

- Metal feature discovery and capability profile;
- resource allocation and placement;
- unified-memory pressure response;
- command encoders, queues and submission ordering;
- Metal synchronization;
- pipeline creation and archive interaction;
- native acceleration structures and ray dispatch;
- presentation and drawable lifetime;
- Metal validation and capture hooks.

Metal 4 paths are optional accelerators selected by capability. The Metal 3
path remains correct where the required operation exists. Missing operations
have an explicit fallback or remain unexposed.

#### Presentation contract

Wiage owns the native window/view, lifecycle, focus, input, backing-scale and
fullscreen transitions. MageVK owns the Vulkan surface and swapchain, Metal
layer/drawable acquisition, present ordering and GPU completion. The boundary
must specify:

- which thread may create, resize and destroy the native view and surface;
- logical-size, pixel-size and scale-factor propagation;
- drawable starvation, occlusion and minimized-window behavior;
- SDR/HDR colorspace and display migration, including external displays;
- fullscreen enter/exit and resize ordering without holding GPU locks;
- present feedback and frame pacing returned to Wiage;
- teardown ordering when the guest, window or GPU fails first.

No frontend owns an `NSWindow`, `CAMetalLayer`, Metal drawable, or AppKit event.

## 6. Mage Shader Compiler Program

The compiler is the hardest independent project and is treated as such. "Own
compiler" means Mage owns the shader-language semantics through MSL emission
and cache identity. Apple's supported Metal compiler still performs MSL to GPU
machine-code compilation; MageVDM does not attempt to reverse engineer Apple
GPU ISA.

### 6.1 Inputs

The first and only committed input is SPIR-V because native Vulkan and both
bootstrap D3D frontends already converge there. The input boundary reuses
SPIRV-Tools for binary parsing, validation and grammar data. Mage owns the
reflection, semantic IR, lowering, MSL generation and cache identity needed by
its supported subset.

Direct DXBC or DXIL is not an initial requirement. It becomes a separate
proposal only after a direct frontend exists and a captured workload proves
that bypassing SPIR-V fixes a semantic loss or materially improves compile
latency or memory. Replacing one mature compiler dependency with three private
parsers would fail the project's ownership goal.

### 6.2 Internal representation

The initial Mage Shader IR contains only what the accepted compute milestone
needs. Later stages add representation only with a fixture that requires it:

- typed scalar, vector, matrix and aggregate values;
- structured control flow plus SSA-like value identity;
- address spaces and memory access semantics;
- compute entry point, workgroup size and built-ins;
- storage/uniform buffers, images, samplers and minimal binding metadata;
- specialization constants;
- atomics and memory barriers;
- source-location and trace metadata.

It must preserve source semantics before optimizing them. An optimization pass
is admitted only with a corpus case that proves its transformation and a
representative measurement that justifies its cost.

### 6.3 Compiler stages and gates

#### C0: Corpus and oracle

Deliverables:

- authored and generated legal SPIR-V fixtures for the proposed first subset;
- fixture manifest records source API/stage, specialization values, expected
  binding map, expected output and provenance;
- deduplicated content-addressed corpus with explicit custody labels:
  redistributable, local-only captured, derived-but-publishable, or prohibited;
- differential runner compares the new compiler with the current production
  route without treating either output as automatically correct.

Exit gate:

- the first compute subset and ownership boundary are reviewed and accepted;
- synthetic fixtures cover every accepted operation;
- failed and passing fixtures reproduce outside a game;
- no new compiler repository exists before this gate passes.

#### C1: SPIR-V boundary and reflection

Deliverables:

- pinned SPIRV-Tools parser/validator with explicit version and capability
  policy;
- reflection sufficient to reproduce MageVK's resource and stage interfaces;
- no code generation yet;
- differential reflection tests against the production path and Vulkan rules.

Exit gate:

- all first-corpus modules either parse to a stable IR or fail with a named
  unsupported capability;
- malformed input is rejected by the reused validator or a named Mage subset
  rule; Mage does not duplicate the binary parser.

#### C2a: Compute MSL

Implement the smallest legal compute subset and pass it to Apple's supported
Metal compiler. Apple's compiler remains the mandatory final MSL-to-GPU-code
compiler in development and release builds.

Exit gate:

- MSL compiles under the minimum selected language version;
- output bytes match authored compute fixtures under Metal validation;
- compile latency and peak memory are recorded against SPIRV-Cross;
- unsupported operations fall back per shader with a named counter.

#### C2b: Vertex, fragment and resource binding

Add vertex/fragment interfaces, interpolation, specialization, argument
buffers and the descriptor shapes demanded by the accepted fixtures.
Tessellation, geometry emulation, bindless breadth, subgroups and advanced
memory-model behavior remain separate additions rather than implied scope.

Exit gate:

- MSL compiles under the minimum supported Metal language version;
- synthetic output tests pass under Metal validation;
- a deterministic graphics sample renders equivalently;
- cold compile median/p95 and peak memory are recorded, not guessed.

#### C2c: Full-session shadow mode

Run the Mage compiler beside SPIRV-Cross for complete representative sessions,
compare reflection and compilation outcomes, and publish fallback counts. The
game still consumes production output until every covered stage is green.

Exit gate:

- one Vulkan and one D3D-derived sample complete with zero unexplained output
  differences for the accepted subset;
- representative game sessions produce bounded, attributable fallback lists;
- calibrated performance measurements show whether primary use is justified.

#### C3: Ray tracing

RT is four gated additions, not one feature claim:

1. ray query and acceleration-structure references;
2. ray-generation/miss/hit/callable stages, payloads and shader binding tables;
3. position fetch;
4. pipeline-library and maintenance1 shader semantics where the compiler owns
   any required lowering.

Each addition needs authored cross-stage fixtures, Metal validation, output
comparison, pipeline-creation time and peak-memory evidence before becoming
primary. Q2RTX and DOOM: The Dark Ages are late end-to-end witnesses, not the
first tests. Software RT is neither promised nor advertised here; hardware
without the required Metal operation returns an honest unsupported capability
until a separate measured design is approved.

#### C4: Optional direct DXBC or DXIL ingestion

This gate remains closed until a direct frontend exists. A proposal may reuse
audited parser code when its license and boundary are acceptable; it must not
land merely to make the architecture diagram look independent.

Exit gate:

- source bytecode to Mage IR is differential-tested against the bootstrap
  frontend path;
- direct ingestion is shipped only when it fixes a demonstrated semantic gap
  or improves representative cold compile time/memory;
- the Vulkan/SPIR-V route remains the native Vulkan path.

#### C5: Production compiler

Required properties:

- thread-safe and reentrant;
- bounded memory and explicit cancellation;
- stable serialized cache key containing compiler revision, target capability
  profile, options, specialization data, frontend ABI and backend ABI;
- deterministic output for identical inputs;
- structured diagnostics with source-operation ownership;
- no global game-name branches;
- fuzzed input boundary;
- offline corpus runner and in-game shadow mode;
- persistent negative cache for deterministic unsupported shaders;
- atomic cache publication and corruption recovery.

Apple's supported Metal compiler is always the final compiler. Mage owns MSL
generation and orchestration, not Apple GPU machine-code generation.

SPIRV-Cross retirement gate:

- every advertised SPIR-V shader operation and capability passes its positive,
  negative and supported-hardware conformance corpus;
- release games pass as supplemental end-to-end evidence rather than defining
  the advertised compiler contract;
- fallback counters remain zero through complete representative sessions;
- two release cycles can run with fallback disabled;
- the retained parser/headers/licenses are explicitly enumerated;
- removing the SPIRV-Cross binary/library does not change the shipped route.

## 7. Frontend Ownership and Dependency Reduction

No frontend is built before a read-only requirements probe compares one exact,
pinned frontend revision with one exact MageVK build. The report lists every
mandatory Vulkan feature, extension, limit, format and semantic guarantee;
records MageVK's real answer; and preserves RED results. Selecting an older
frontend is a new pinned probe, not an assumption that old means compatible.

Current DXVK requirements include capabilities such as depth-clip control,
transform feedback and robust buffer behavior. Current vkd3d-proton imposes a
substantially broader descriptor-indexing and robustness surface. These are
examples to verify from the pinned source, not feature bits to spoof.

### 7.1 D3D7-11

D3D7 initially remains Wiage-owned: wined3d's Vulkan renderer -> winevulkan ->
MageVK. The first sample proves the legacy API route only. A later x86/WOW64
D3D7 sample must independently prove 32-bit packaging and execution.

Bootstrap from DXVK because it already carries D3D8-11 and DXGI behavior.
Fork only after its exact requirements probe is green and the unmodified route
has a reproducible sample result.

Replacement order:

1. Mage-owned build, logging, capability negotiation and cache handoff;
2. eliminate Linux-only assumptions and unsupported driver guesses;
3. route shader compilation through Mage compiler shadow mode;
4. make Mage compiler primary with fallback telemetry;
5. extract shared frontend/runtime pieces only where the diff proves they are
   stable Mage contracts;
6. propose a separate two-consumer backend-primitives experiment only after
   the Vulkan path is a measured bottleneck.

The end-state can remain recognizably descended from proven open-source code.
The requirement is coherent ownership and independence from external release
timing—not rewriting correct D3D semantics for cosmetic originality.

### 7.2 D3D12 and DXR

Bootstrap from vkd3d-proton and its shared DXGI arrangement with DXVK.

Early blocker probe records:

- Vulkan version and required extensions;
- descriptor indexing limits;
- update-after-bind counts;
- buffer device address;
- timeline and synchronization2 support;
- sparse/tiled resource behavior;
- ray-tracing and mesh/task shader requirements;
- format and typed-UAV requirements.

MageVK exposes only genuinely implemented capabilities. Missing requirements
become MageVK/compiler milestones or explicit unsupported results; they are not
spoofed through device creation.

DXR first reuses Vulkan RT to validate D3D12 semantics against MageVK. A direct
backend path is later work and must preserve vkd3d-proton's observed behavior.

### 7.3 Native Vulkan

MageVK remains an independent usable Vulkan implementation. Backend extraction
must not make MageVK depend on Wine or a D3D frontend. Vulkan conformance,
extension exposure, loader behavior and application-visible synchronization
remain Vulkan-owned.

## 8. Cross-Cutting Services

### 8.1 Combo manifest

Every launch writes a content-addressed manifest containing:

- Mage, Wiage, frontend, MageVK/backend and compiler revisions;
- dirty-state marker and build identifier;
- executable hashes and architecture;
- macOS build, Metal device/capabilities and memory size;
- selected graphics route and compatibility profile revision;
- cache namespace and warm/cold state;
- enabled experimental features.

A bug report without this manifest is incomplete but still collectable by the
launcher with one click.

### 8.2 Correlated trace bus

Use one trace envelope rather than one logging framework forced into every
project. Required fields:

- monotonic timestamp;
- process/thread;
- component and revision;
- launch/session ID;
- frontend object/command ID;
- backend submission ID;
- shader and pipeline content IDs;
- severity, category and structured payload.

Components may keep native logging internally. Mage collection normalizes
their output into one session bundle. Cross-process ordering is treated as a
clock-correlation problem, not inferred from line order.

### 8.3 Cache pipeline

One root directory does not mean one file format. Ownership is:

- frontend cache: source API state and translated shader identity;
- compiler cache: input + target profile -> MSL/reflection;
- Metal cache: MSL/function/pipeline artifacts supported by public APIs;
- application Vulkan pipeline cache: application-owned bytes;
- manifest index: maps the layers without merging their formats.

Writes are atomic. Keys include every semantic option before lookup. Cache
corruption falls back to recompilation. Cold and warm measurements are always
reported separately.

### 8.4 Memory telemetry and budget policy

The policy layer observes:

- physical memory and current pressure;
- Metal recommended working-set information;
- MageVK/backend allocations and heaps;
- frontend residency estimates;
- game-advertised budget and actual use;
- compiler/cache transient allocations;
- Wiage/Steam process pressure.

The first implementation only reports and sets an honest Vulkan budget. It is
not a universal allocator or a claim that one layer owns all unified memory.
Central eviction, sparse residency or streaming intervention is added only
after a captured pressure trace proves which owner can act without violating
API semantics.

### 8.5 Synchronization

Each frontend translates source synchronization into one backend dependency
model. Required invariants:

- source submission order is preserved;
- binary semaphore reuse cannot consume an earlier signal generation;
- timeline values remain monotonic and type-correct;
- resource lifetime extends through every consuming submission;
- cross-process transport, if introduced, has explicit completion and failure
  semantics;
- CPU waits do not silently become queue-idle waits.

FEX guest CPU memory ordering is a separate CPU/runtime contract verified by
litmus and ABI tests. Passing it does not validate Vulkan/Metal queue ordering,
and passing GPU synchronization tests does not validate x86 guest atomics.

## 9. Archived No-Go: Native Render Service

Do not build a render-service IPC layer. Reassess only if the native arm64
Wiage/FEX ABI proof succeeds and profiling still demonstrates an otherwise
unremovable process-architecture bottleneck large enough to justify a separate
proposal, failure model and latency budget.

## 10. Execution Phases

### Phase 0: Finish the RT foundation

Entry: current work continues in the existing MoltenVK/SPIRV-Cross project.

Deliverables:

- exact reviewed RT candidate commit and branch;
- explicit compact and legacy compiler profiles;
- legal semaphore reuse and transitive synchronization regression evidence;
- ray query, full pipeline, maintenance1, pipeline library, TLAS serialization
  and memory findings recorded;
- required upstream submissions published in their owning repositories with
  user approval;
- MageVK import plan that does not copy an untraceable main-tree binary.

Exit: every item in the mechanical start gate at the top is recorded. The only
remaining work belongs to reviewers, maintainers or CI. If any unpublished
implementation or author-resolvable review action exists, Phase 0 remains open.

### Parallel Track F: FEX and native arm64 Wiage

This existing Wiage program may proceed while Phase 0 is open. Its writer uses
Wiage/FEX worktrees and does not modify MageVK, the compiler, or D3D frontends.

Milestone order:

1. Reconstruct the documented three-patch FEX-facing Wiage groundwork from
   `toolchains/wine-mage-11.13/BUILD.md` into an isolated clean Wiage branch;
   prove the diff against the intended Wine base and do not build from the
   existing dirty source reconstruction.
2. Select and pin a clean FEX source revision; record its URL, commit, license,
   toolchain and expected artifact architecture in the dependency lock/SBOM.
3. Build FEXCore for macOS arm64 and pass standalone instruction, exception,
   memory-order and self-modifying-code tests.
4. Complete the module-architecture table in section 5.2 from those built
   Wiage and FEX artifacts.
5. Pass the smallest ABI proof: x64 console PE -> ARM64EC/builtin Wiage module
   -> arm64 Unix module -> guest callback and return.
6. Pass 64-bit Windows API smoke programs. Treat x86/WOW64 as a separate gate,
   not an implied consequence of x64 success.
7. Pass the headless Vulkan compute proof with exact evidence that guest code
   uses FEX while winevulkan, MageVK and Metal execute as arm64.
8. Run one Vulkan graphics sample, then DOOM 2016 A/B/A against Rosetta with
   identical MageVK, settings, cache state and scene.
9. Add a D3D-derived sample only after native Vulkan isolates the CPU/runtime
   boundary from frontend correctness.

Replacement gate:

- ABI, exception, TLS, callback, memory-order and code-cache tests pass;
- required x64 and separately approved x86/WOW64 smoke suites pass;
- signing, `MAP_JIT`, entitlement and notarization requirements are documented;
- Vulkan samples and one real game complete without runtime-only corruption;
- process RSS and translated-code-cache growth are bounded;
- Rosetta/FEX benchmark noise is calibrated before any regression threshold is
  chosen; the recorded threshold then governs release decisions;
- crash reports identify guest and host frames sufficiently to debug failures;
- Rosetta remains a selectable rollback until two release cycles pass.

### Phase 1: Lock, capability probe and route contract

Deliverables:

- handwritten dependency lock and SBOM pin Mage, Wiage, MageVK, compiler
  fallback and candidate frontends by URL, commit, license, patch provenance,
  toolchain, architecture and artifact hash;
- one read-only probe compares the exact MageVK build against one pinned
  frontend's mandatory requirements and preserves every RED result;
- existing `bin/mage doctor` is extended only if its current output cannot
  record that probe; no `magevdm-doctor` is created;
- a prelaunch route manifest specifies DLL bitness, locations, overrides,
  expected loaded modules, atomic installation and rollback;
- failure records use the schema in the first work packet.

Exit:

- the chosen frontend's mandatory matrix is honestly green, or the phase stops
  with a named MageVK requirement rather than building the frontend;
- route installation can be reviewed without mutating a user prefix;
- license, corpus-custody and anti-cheat policies are accepted;
- no new orchestrator exists. One is considered only after two manual builds
  expose the same repeated, error-prone steps.

### Phase 2: Native Vulkan, legacy route, then one frontend

Reference ladder:

1. Vulkan sample -> MageVK;
2. D3D7 sample -> Wiage wined3d Vulkan renderer -> winevulkan -> MageVK;
3. fresh-prefix repeat proving route installation and rollback;
4. one next frontend, likely the smallest D3D11 slice, only after its exact
   requirements matrix is green;
5. source-API sample for that frontend;
6. engine-representative title only after samples pass;
7. D3D12 is a later independent probe and slice, not bundled into D3D11 work;
8. DOOM: The Dark Ages and Cyberpunk 2077 remain late gates, not smoke tests.

Exit:

- native Vulkan, D3D7 and one probed modern route launch from the same Mage
  build on fresh prefixes;
- prelaunch selection is recorded and overrideable;
- every route emits the same manifest and trace envelope;
- no feature is enabled by spoof alone;
- failures identify the owning layer;
- x64 passes first; x86/WOW64 has its own installation and ABI gate.

### Phase 3: Compiler C0-C2

Deliver the corpus, parser/reflection and conventional graphics/compute path.
Production remains on SPIRV-Cross while the new compiler runs in shadow mode.

Exit:

- one Vulkan title and one D3D-derived title complete representative sessions
  with the Mage compiler primary for covered stages;
- fallback is per-shader, counted and diagnosable;
- benchmark variance is calibrated before a regression limit is adopted.

### Phase 4: Compiler RT and advanced semantics

Phase 4 is a queue of independently accepted, corpus-driven work packets; it
is not one aggregate implementation:

1. ray query;
2. ray pipelines and shader binding tables;
3. position fetch;
4. pipeline-library semantics;
5. maintenance1 shader semantics, if any;
6. mesh/task shaders;
7. subgroup/wave operations;
8. 64-bit atomics policy;
9. complex descriptor models;
10. sparse/tiled resource shader metadata.

Each packet needs its own accepted fixtures, IR delta, fallback counter,
supported-hardware witness, memory/compile measurements and rollback. A later
packet does not block release of an earlier complete subset and cannot borrow
another packet's evidence.

RT end-to-end gates after the relevant packets pass:

- Q2RTX and DOOM: The Dark Ages satisfy their playability gates on declared
  supported hardware;
- a DXR sample and selected D3D12 title execute through the same RT backend;
- unsupported hardware receives an honest capability result. A software path
  requires a separate approved design and performance target.

### Phase 5: Dependency retirement and backend decision

Deliverables:

- SPIRV-Cross retirement gate evaluated;
- direct DXBC/DXIL ingestion evaluated with measurements;
- external frontend forks reduced to the code Mage actually owns and ships;
- update cadence no longer depends on an unpinned external release.

A private backend-primitives experiment may be proposed only if two real
direct frontends now exist and profiling shows duplicated Vulkan translation
as a material cost. It starts with the smallest shared private primitive,
compares against the Vulkan baseline, and is deleted if the measured benefit
does not justify its API and maintenance surface.

Exit:

- release build is reproducible from Mage-owned pins and forks;
- compiler fallback can be disabled for the release ladder;
- backend architecture is chosen from evidence, not diagram preference;
- third-party provenance remains visible even when code is heavily modified.

### Phase 6: Hardware and runtime coverage

Matrix:

- Apple7, Apple8, Apple9 and Apple10 capability profiles where supported by the
  selected macOS/Metal floor, without using family names as behavior tests;
- minimum supported macOS and current macOS;
- native arm64 host tools, Rosetta x64, FEX x64 and separately FEX x86/WOW64;
- Metal 3 baseline and capability-gated Metal 4 paths;
- hardware RT present and absent;
- explicit 8 GB product decision plus 16 GB, 24 GB and higher memory classes;
- internal/external display, SDR/HDR, scale change, resize and fullscreen.

Exit:

- capability-driven paths pass without chip-name branching;
- release gates include both architectures and memory-pressure recovery;
- every declared supported Apple GPU-family profile has at least one physical
  device witness on a supported OS with exact build/library proof;
- a profile without an available physical witness remains explicitly
  `unvalidated` and is not listed as supported;
- one local M5 Pro result is never represented as universal proof.

### Phase 7: Product hardening

Deliverables:

- single installer/update channel;
- compatibility database signed and versioned independently from binaries;
- rollback to previous combo version;
- cache inspection/reset without deleting unrelated user data;
- crash recovery and support-bundle UI;
- documented contributor boundaries and upstream policy.

## 11. Quality Gates

### Correctness ladder

Every new path advances through:

1. synthetic operation test;
2. API sample;
3. deterministic captured workload;
4. engine-representative title;
5. AAA gate;
6. second hardware/OS witness;
7. one physical witness for every capability profile claimed as supported.

Passing a later game does not waive an earlier conformance failure.

### Playable

A title is "playable" only when a recorded 30-minute representative session
has:

- correct rendering through gameplay, video and UI;
- stable frame production without repeated multi-second stalls after warmup;
- working shader/texture streaming;
- no device loss, GPU recovery or unbounded memory growth;
- correct input, focus, resize and fullscreen/window transitions for the tested
  mode;
- recoverable exit and relaunch;
- no abandoned Wine, Steam or game processes;
- exact loaded-component proof.

Performance targets are title-specific baselines recorded separately. The word
"playable" alone is not a performance comparison.

### Performance protocol

- First run repeated identical baseline legs to measure natural variance,
  warmup length and sample duration for that workload and machine.
- Set acceptance/regression thresholds only after that calibration; record the
  chosen statistic and confidence/variance basis beside the result.
- Then run repeated interleaved A/B/A cycles with the same scene, settings,
  resolution, manifest and cache state until the selected confidence/noise
  criterion is met; one cycle cannot support a release claim.
- Record ambient/SoC temperature where available, power source and power mode,
  display and refresh rate, frame cap/VSync, fan state where observable, and
  foreground/background process load.
- Report median, p95 and p99 frame time; CPU and GPU frame time; peak resident
  memory; pipeline/shader compile counts; cache state.
- First-run and warm-run numbers are separate products.
- A microbenchmark establishes only the mechanism it executes.
- A change that wins one route must run regression legs on the other established
  routes before becoming a default.

### Memory protocol

- Record per-process and aggregate RSS for Mage, Wiage, FEX, frontend helpers
  and the game, plus Metal allocated size, advertised Vulkan budget, backend
  resource accounting, compressed memory, swap and system pressure.
- Test normal exit, device destruction, cache destruction and forced process
  death.
- A lower advertised budget is not proof of lower real memory use.
- Canonical Vulkan serialization or compatibility storage is removed only if
  the public contract remains satisfiable.

### Supply chain, licensing and corpus custody

Before any distributable or game-derived test artifact is shared:

- the SBOM records source URL, exact revision, license, local patch provenance,
  build toolchain, architecture, artifact hash and redistribution decision;
- third-party notices and corresponding-source obligations are generated from
  the pinned manifest, not reconstructed at release time;
- shader captures, traces and game assets carry explicit custody labels and
  never enter a public repository without permission;
- generated fixtures identify their generator and seed;
- proprietary Apple tools may be invoked only under their permitted local use
  and are never silently bundled;
- online/anti-cheat titles remain excluded unless vendor support is explicit.

## 12. Repository and Branch Model

Long-term repositories:

| Repository | Responsibility |
|---|---|
| `dttdrv/mage` | product, launcher, manifests, compatibility DB, packaging |
| `dttdrv/wiage` | Windows runtime and macOS integration |
| `dttdrv/magevk` | Vulkan frontend and Metal backend |
| `dttdrv/mage-shader` | compiler, IR, MSL backend, corpus runner |
| `dttdrv/mage-dx` | D3D8-11 frontend, initially an audited DXVK-derived fork |
| `dttdrv/mage-d3d12` | D3D12/DXR frontend, initially vkd3d-proton-derived |

Do not create the last three repositories before their first deliverable is
ready. Until then, design artifacts stay in the Mage planning branch and code
experiments stay in isolated worktrees.

Each combo version pins commits rather than floating branches. Cross-repository
changes use a compatibility matrix; they do not merge histories into a
monorepo. API-neutral fixes remain upstream candidates. Apple-specific product
policy remains in Mage-owned forks.

## 13. Risk Register and Stop Conditions

| Risk | Earliest falsifier | Response |
|---|---|---|
| MageVK lacks mandatory modern DXVK/vkd3d features | requirements probes before game integration | implement honestly, select older compatible frontend temporarily, or mark unsupported |
| Compiler scope overwhelms project | C0 fixtures and one compute milestone | keep per-shader fallback; do not begin direct bytecode or RT work simultaneously |
| New IR loses source semantics | differential reflection/execution fixtures | add missing semantic representation before optimization |
| A backend experiment becomes a second Vulkan | two-direct-consumer and measured-benefit gate | retain Vulkan boundary and delete speculative API |
| D3D frontend forks become unmergeable | monthly upstream-diff and owned-delta report | upstream generic work; keep patches causal; vendor only pinned releases |
| GPTK redistribution is disallowed | written license inventory | use only for local evaluation and comparison |
| FEX integration changes Windows behavior or loses Rosetta performance | console, API sample and game A/B ladder | retain Rosetta fallback and fix the owning CPU/runtime layer |
| Memory policy breaks application expectations | pressure trace plus Vulkan validity tests | limit first version to honest telemetry and budget reporting |
| Software RT scope leaks into baseline | unsupported-hardware capability test | return honest unsupported status; require a separate approved proposal |
| Rosetta availability contracts | Wiage arm64/FEX milestone | keep runtime architecture independent from graphics contracts |
| One game drives global hacks | second-engine counterexample | move policy to compatibility profile or reject mechanism |
| Online title rejects translation or anti-cheat | vendor policy and clean-prefix launch | exclude it; never evade integrity mechanisms |

Stop implementation and write an evidence report when:

- a required semantic conversion has no valid representation;
- a dependency license does not permit the intended distribution;
- a frontend needs a feature MageVK falsely advertises;
- the compiler accepts a feature it cannot lower correctly;
- a cross-process representation lacks bounded lifetime or failure behavior;
- a hardware claim has only one-machine evidence;
- the next phase would require simultaneous unreviewable rewrites in more than
  one owning repository.

## 14. First Work Packet After the Start Gate Opens

This packet creates no compiler repository, frontend fork, build orchestrator,
game test, or new doctor command.

1. Archive the now-passed gate-ledger snapshot: exact candidate commit,
   PR/submission URLs, CI and focused-test evidence, hardware witnesses,
   tracked-worktree state, and the external owner of every remaining action.
2. Handwrite the dependency lock/SBOM with URL, revision, license, patch
   provenance, toolchain, target architecture and artifact hash. Do not
   automate a format that has not survived one manual build.
3. Read the exact mandatory requirements of one pinned frontend revision and
   compare them with the exact MageVK build. Extend existing `bin/mage doctor`
   only for missing reusable evidence fields.
4. Preserve the RED matrix. Do not build the frontend until every mandatory
   requirement is real. Narrowing means pinning a different frontend/version,
   rerunning its complete mandatory probe, and obtaining a green matrix before
   any build.
5. Specify the prelaunch route manifest: executable bitness, DLL source and
   destination, `system32`/`syswow64` mapping, Wine overrides, expected loaded
   modules, atomic generation switch and rollback.
6. On fresh prefixes, prove a native Vulkan sample and the D3D7 -> wined3d
   Vulkan -> winevulkan -> MageVK route, including loaded-binary evidence.
7. Select one next frontend—likely the smallest D3D11 slice—only after its
   requirements matrix is green. Do not start D3D12 in the same packet.
8. Gate x64 first. Record x86/WOW64 packaging, ABI and execution as a separate
   work packet rather than inferring it from x64; that packet must include an
   x86 D3D7 sample before claiming 32-bit packaging support.
9. Approve license/SBOM, anti-cheat and captured-artifact custody policies
   before any game-derived material is collected or distributed.
10. Author legal C0 SPIR-V fixtures and review the first supported subset. Do
    not create `mage-shader` until that scope and ownership boundary pass.
11. Store each failure as: manifest ID, exact command or launch, expected
    result, observed result, owning layer, first failing invariant, artifacts,
    counterexample attempted, current evidence state, and next permitted step.

Review after each numbered item. A RED result changes or stops the next item;
it is not worked around with feature spoofing or a game-specific branch.

## 15. Definition of Done

MageVDM is complete when:

- one Mage installation automatically launches supported Vulkan and D3D7-12
  games through Wiage and one maintained Metal backend;
- DOOM: The Dark Ages and Cyberpunk 2077 satisfy recorded playability gates on
  their supported capability variants;
- the Mage shader compiler is primary for the full release ladder and
  SPIRV-Cross is absent from the required runtime path;
- component pins, caches, logs, memory policy and compatibility profiles are
  coordinated but retain clear ownership;
- cold-start slowness is bounded, visible and improved release by release;
- warm performance stays within calibrated release thresholds for established
  reference titles;
- 32-bit games remain supported;
- missing hardware behavior is handled by a validated fallback or an honest
  unsupported result;
- every release can be reproduced, rolled back and diagnosed without a coding
  agent;
- every shipped route appears in a versioned support matrix containing frontend
  ABI/version, source APIs, PE architecture, Wiage execution mode, mandatory
  MageVK capability profile, license obligations and required sample/game
  tests;
- a new frontend ships only after adding one reviewed row to that matrix and
  passing its declared gates without source-API-specific Metal branches.
