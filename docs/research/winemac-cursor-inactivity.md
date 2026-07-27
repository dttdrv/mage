# Cursor visibility after alt-tab (borderless mouselook games) — root cause + fix

Date: 2026-07-22. Fix: `toolchains/wine-mage-11.13/patches/winemac-cursor-inactivity-gate.patch`
(supersedes the removed `winemac-cursor-reactivation.patch`).

## Symptom

Borderless DOOM: first Cmd-Tab back into the game leaves the macOS cursor
visible over mouselook; a second fast Cmd-Tab cycle hides it.

## Root cause (empirically established on macOS 27, build 26A5378n)

Measured OS contract for NSCursor hide/unhide across deactivation:

- Hide while active, do nothing → macOS force-shows while inactive but
  **auto-restores the hidden state on activation**.
- **Any `unhide` while inactive permanently destroys that hidden state** —
  cursor stays visible after reactivation.
- Hide/unhide calls at willBecomeActive/didBecomeActive do take effect.

Failure chain in winemac.drv: while the app is inactive, the game's
focus-loss reaction (and/or DefWindowProc class-cursor via WM_SETCURSOR
from tracking-area mouse events, which winemac delivers even while
inactive) makes the effective Win32 cursor non-NULL → `unhideCursor`
(`cocoa_app.m`) → `[NSCursor unhide]` while inactive → hidden state
destroyed. The wineserver only re-sends WM_WINE_SETCURSOR when the
effective cursor *changes*, and the game sees no change of its own state,
so nothing ever re-hides. The second fast Cmd-Tab cycle has no
inactive-period mouse traffic and outruns the game's deactivate reaction,
so the OS auto-restore path survives — hence the observed pattern.

## Why the first patch failed (and was harmful)

`winemac-cursor-reactivation.patch` re-baselined `cursorHidden`/
`cursorIsCurrent` and forced `updateCursor:TRUE` in
applicationWillBecomeActive. But `updateCursor:` only hides when
`clientWantsCursorHidden` is set — the flag that was legitimately cleared
while inactive — so it hid nothing. Worse, in the benign case it issued an
extra `[NSCursor hide]`, leaking the count: one later unhide would leave
the cursor stuck hidden.

## Fix (shipped in winemac.so, 10:09)

1. `updateCursor:` returns early when `![NSApp isActive]` — NSCursor is
   never touched while inactive, so the hide count cannot drift and the OS
   auto-restore contract holds. Desired state is still recorded in
   `clientWantsCursorHidden`/`cursor` by the callers.
2. `applicationDidBecomeActive:` calls `[self updateCursor:TRUE]` once to
   apply any deferred change, balanced.
3. Old re-baseline removed.

All four state combinations (hidden/shown × changed/unchanged while
inactive) converge to correct visibility with balanced counts.

## Verification

Needs unlocked screen + real Cmd-Tab cycles (synthetic app-switching does
not reproduce the user's timing): in borderless mouselook, Cmd-Tab out/in
once — cursor must be gone. Repeat fast cycles — same. Pause menu must
still show the cursor (guard against the opposite regression).
