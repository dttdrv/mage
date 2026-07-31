# Mage

Free, open-source CrossOver alternative for Apple silicon. Runs Windows
games through a custom stack, with a native macOS app on top.

The stack, all mapped to Mage:

- Wiage: custom Wine build (patched for macOS 26+ and Apple silicon)
- MageVK: custom MoltenVK build (Vulkan on Metal, ray tracing work)
- DXage: custom DXVK build (Direct3D on Vulkan, planned)

Requires macOS 26 or later.

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

## Layout

- `app/` SwiftUI app, built with plain swiftc
- `bin/` CLI runner
- `tools/` Steam bridge (library and achievement queries over the Steam
  Web API), steamwebhelper wrapper, Wine app-name patcher
- `docs/` state ledger, design guidelines, research notes
