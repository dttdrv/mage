# Mage — operating rules (every rule here cost the user hours; do not relearn them)

These rules exist because each was violated at least once and the user paid
for it. Read them before ANY work in this tree. When you make a new mistake
that costs a test cycle or breaks the user's session, append the rule here
immediately — that is the mechanism that prevents repeats.

## Cleanup (violated 5+ times — the user's #1 rule)

- After EVERY test run: kill all steam/wine/game processes and verify
  `ps aux | grep -iE 'wine|steam|doom|idtech' | grep -v grep | wc -l` == 0.
  Not "probably dead" — run the command and read the 0. If you launched it,
  you reap it. Multiple Steam clients/wineservers from abandoned runs
  poison every later test (dirty wineserver, stolen applaunch, 20+ stray
  processes).
- Never leave background tasks running when reporting done.

## Verify before claiming (violated 3+ times)

- Never report "fixed/works/launched" without a command output or
  screenshot proving it in THIS session. "It should work" is a lie.
- After deploying a dylib: confirm the game actually loaded THAT file
  (`lsof -p <gamepid> | grep libMoltenVK` — check size/path). Deploys have
  silently not taken effect (stale install copy, DYLD path ignored).
- After `codesign`-less in-place dylib replacement the kernel kills the
  process (cs_mtime mismatch). Always `codesign --sign - --force` after cp.
- Distinguish done / partial / unverified / blocked in every status report.

## One variable at a time (violated 2+ times)

- The user has spent hours debugging regressions from batched changes.
  Change one thing, test, then the next. If a test breaks, the LAST change
  is the suspect — revert it before adding more.
- Keep a known-good backup before swapping anything live
  (`<file>.<what>-<date>.bak`), and say where it is.

## Universality (user's standing rule, stated many times)

- No per-game hacks when a mechanism exists. Fixes go in wine/magevk/bin
  defaults (denylisted gating, env defaults), not recipe tweaks. If you are
  about to add a per-game special case, stop and find the mechanism.
- All Apple silicon, never one machine. No M5-only gates.
- Mage must work without a coding agent babysitting it. A user clicks Play.

## Boundaries (violated once, nearly catastrophic)

- NEVER touch the main MoltenVK work: `/Users/dttdrv/Projects/macgaming/MoltenVK*`,
  `upstream/`, `mage/vendor/MoltenVK`. Mage's fork is `mage/magevk`.
  Copying a built dylib out of upstream build dirs is fine; editing is not.
- NEVER commit `mage/recipes/doom2016.json` or `doom-the-dark-ages.json`
  (user-owned working files — edit them, don't commit them).
- NEVER commit anything under `mage/` matching auth/secrets
  (steam-bridge auth holds a live Steam token).
- Commits: `git -c user.name="dttdrv" -c user.email="dttdrv@users.noreply.github.com" commit`.
- No git push / PR / issue actions unless the user asks that day.

## Hard-won technical facts (do not rediscover)

- Steam games launch via `steam.exe -applaunch <appid>` only; direct exe
  dies at SteamAPI_Init (Steam injects client env into applaunch children).
- steamwebhelper_real.exe IS the Steam UI in single-process CEF mode;
  backgrounding it = "steamwebhelper is not responding" + applaunch dies.
- macOS 26/27 drops ALL programmatic activation from detached processes
  (NSApp activate, activateWithOptions, System Events frontmost — all
  return success, no effect). Only gesture-proximate requests from a
  regular foreground app, or LaunchServices `open` launches, work.
- computer-use MCP on this machine: screenshots work, synthetic clicks/keys
  do NOT land. Headless UI verification is impossible; say so instead of
  claiming a UI fix is verified.
- Wine PE processes clobber argv/env on macOS 26+ (ps shows no env);
  pin processes to prefixes via lsof open-file probes.
- MoltenVK deploy targets: BOTH `mage/dist/<build>/lib/` AND
  `toolchains/wine-mage-11.13/install-macos12-freetype/lib/` — the
  toolchain copy is the real default when DYLD_LIBRARY_PATH doesn't stick.
- NEVER deploy a MoltenVK binary into Mage that was not built from
  `mage/magevk`. Main-project builds lack every Mage hook (spoof, sparse,
  fake features) by design. Before ANY deploy or test:
  `strings <dylib> | grep -c MAGE_VK_DEVICE_NAME` must be ≥1 (and
  MAGE_MVK_ENABLE_PRIVATE_SPARSE_BUFFERS). New upstream work goes in via
  git merge/cherry-pick into magevk + rebuild, never via binary copy.
  (2026-08-02: dropped GPT's main-tree build in raw; launcher GPU gate
  failed; a full test cycle wasted on a predictable artifact mismatch.)
- Display sleep mimics a black screen in screenshots: `caffeinate -u -t 1`
  before screencapture; ~110KB PNG = black screen, ~1MB+ = real content.

## Docs

- One current findings document per work period, not scattered files:
  today it is `docs/handoff-2026-08-01.md` (changes + errors + issues).
  `docs/STATE.md` is the ledger — one entry per work period, pointing at
  the findings doc. Wine patch details go in
  `toolchains/wine-mage-11.13/BUILD.md`.
