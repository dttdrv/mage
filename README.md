# Mage

Windows games, native on Apple silicon. Mage is a free, open-source
macOS app that installs and runs Windows games through its own
compatibility stack.

Requires macOS 26 or later.

## Repositories

- [mage](https://github.com/dttdrv/mage) — this repo: the app, the
  CLI, recipes
- [magevk](https://github.com/dttdrv/magevk) — Vulkan on Metal,
  MoltenVK fork for gaming
- [magevk-spirv-cross](https://github.com/dttdrv/magevk-spirv-cross) —
  MSL shader translation for MageVK
- [wiage](https://github.com/dttdrv/wiage) — Wine for Apple silicon

## Components

Each component works on its own. You do not need the Mage app to use
MageVK or Wiage.

### MageVK — Vulkan on Metal

Repository: https://github.com/dttdrv/magevk
MSL shader translation: https://github.com/dttdrv/magevk-spirv-cross

A MoltenVK fork focused on modern game workloads. Contents, on top of
upstream MoltenVK:

- Metal-backed ray tracing: ray queries and ray tracing pipelines
  (the work proposed upstream in KhronosGroup/MoltenVK#2771), plus
  MSL emission for it in the SPIRV-Cross fork — a native `traceRay`
  fast path, ray query support, ray tracing position fetch, and
  subgroup builtins in vertex functions.
- Sparse memory: MTL4 placement-based sparse buffers and sparse
  images, including `VkSparseImageFormatProperties` and sparse queue
  binds. Engines with virtual texturing (id Tech 8) require this.
- GPU identity spoofing (`MAGE_VK_VENDOR_ID`, `MAGE_VK_DEVICE_ID`,
  `MAGE_VK_DEVICE_NAME`, `MAGE_VK_DRIVER_VERSION`,
  `MAGE_VK_DEVICE_TYPE`). Some launchers hard-gate on vendor tables.
- `MAGE_VK_HEAP_SIZE_MB`: caps the advertised device-local heap and
  the `VK_EXT_memory_budget` budget. On unified memory, reporting all
  of system RAM as VRAM makes engines over-commit and starve the OS.
- `MAGE_MVK_RGB9E5_BLEND`: restores render-target and blend caps for
  `RGB9E5Float`, which upstream disables on macOS. Engines that blend
  HDR effects into that format (fire, particles, bloom) silently lose
  them otherwise.
- `MAGE_MVK_ALLOW_UNSUPPORTED_FEATURES`: advertises feature bits an
  engine hard-requires at device creation.
- Acceleration-structure lifetime and generation fixes for streamed
  geometry (empty-geometry BLAS, grown generations).
- `MVK_CONFIG_FRAME_RATE_CAP`: present pacing at the Vulkan level.

Build (Xcode 27 or later, CMake, network access for the remaining
dependencies):

    git clone https://github.com/dttdrv/magevk
    git clone https://github.com/dttdrv/magevk-spirv-cross
    cmake -S magevk -B build \
      -DCPM_SPIRV-Cross_SOURCE="$PWD/magevk-spirv-cross" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0
    cmake --build build --parallel

Result: `build/MoltenVK/libMoltenVK.dylib` (universal).

### Wiage — Wine for Apple silicon

Repository: https://github.com/dttdrv/wiage

Wine 11.13 plus wine-staging v11.13 (121 patchsets), plus:

- Rosetta 2 support ported from the CrossOver 26.2 sources
  (CodeWeavers publishes no standalone patch series): gs-base
  switching, MXCSR save/restore, CET NOP and XGETBV emulation, debug
  register shims, the wow64cpu `lretq` workaround, and the wow64 LDT
  guard.
- msync: fast in-process synchronization (marzent's implementation as
  forward-ported by CodeWeavers). Enable with `WINEMSYNC=1`.
- winemac work for macOS 26+: display-mode faking (games never capture
  the physical display), a single Dock presence per game, window
  activation and cursor fixes.
- winevulkan loader: `vkGetInstanceProcAddr`/`vkGetDeviceProcAddr`
  return thunks for known functions the way real drivers do, instead
  of NULL. Games that resolve extension procs on probe devices crash
  without this.
- Windows-side GPU identity: device name override in win32u and the
  D3DKMT WDDM 2.7 caps query, both used by launchers' GPU checks.
- Builtin `nvngx.dll` and `nvapi64.dll`: NVIDIA/Streamline
  identification so DLSS code paths engage. MetalFX-backed evaluation
  is in progress.
- Assorted crash fixes (DWARF divide-by-zero in crash reporters, 0x0
  monitor modes, Rosetta address-space probing).

Building Wine from source needs llvm-mingw, autoconf 2.72, bison, and
an Xcode 27 SDK. The prebuilt runtime on the Releases page is the
practical way to test it. Rosetta 2 is required either way
(`softwareupdate --install-rosetta`).

### DXage — Direct3D on Vulkan

Planned. The intended long-term path is Vulkan-only translation for
all games.

## App

Mage shows your Steam library, installs and launches games, and tracks
playtime and achievements. Steam sign-in happens in a browser sheet, so
no Steam window is needed to browse the library or start a game.
Per-game settings (HUD, framerate cap, runtime options) sit behind an
Advanced panel.

Build and install:

    make -C app
    make -C app install

## CLI

`bin/mage` drives the same recipes the app uses. System python3, no
dependencies.

    bin/mage list
    bin/mage install <recipe>
    bin/mage run <recipe> [--dry-run]
    bin/mage doctor <recipe>

Recipes live in `recipes/<id>.json`: environment variables, file
checks, launch steps. Runtimes in `runtimes/<id>.json` register Wine
builds by reference. Performance tuning belongs in recipe data, not in
code.

## Testing: DOOM The Dark Ages

Current state: boots, passes the launcher GPU gates, reaches the menu,
loads the campaign, renders with effects. Slow and not yet stable.
Testers welcome.

You need: an M-series Mac on macOS 26+, Rosetta 2, the game owned on
Steam.

1. Download `wiage-runtime.tar.gz` and `magevk-lib.tar.gz` from the
   latest release and extract them into this repository:

       mkdir -p dist/magevk/lib
       tar xzf wiage-runtime.tar.gz -C dist
       tar xzf magevk-lib.tar.gz -C dist/magevk/lib

2. Register the runtime and the recipe:

       cp runtimes/mage-wine-11.13-rt.example.json runtimes/mage-wine-11.13-rt.json
       cp recipes/doom-the-dark-ages.example.json recipes/doom-the-dark-ages.json

3. Install Steam and the game (headless, downloads through Steam's
   servers):

       bin/mage install doom-the-dark-ages

4. Run:

       bin/mage run doom-the-dark-ages

Notes:

- The recipe spoofs an AMD Radeon RX 7900 XTX. An NVIDIA spoof hits a
  separate launcher gate (NVIDIA-only Vulkan extensions) and is not
  recommended.
- First boot compiles shaders; the intro is slow and then speeds up.
- Useful overlays: `MTL_HUD_ENABLED=1` (Metal performance HUD) can be
  added to the recipe's `env` block.
- Report results in GitHub issues: GPU, macOS version, and whether the
  launcher gate passed are the most useful facts.

## Layout

- `app/` SwiftUI app, built with plain swiftc
- `bin/` CLI runner
- `tools/` Steam bridge (library and achievement queries over the Steam
  Web API), steamwebhelper wrapper, Wine app-name patcher
- `recipes/` per-game launch recipes (JSON)
