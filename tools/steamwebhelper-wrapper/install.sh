#!/bin/bash
# Install/uninstall the mage steamwebhelper wrapper into a Steam-inside-Wine
# prefix. The wrapper forces CEF into --single-process --disable-gpu so the
# Steam UI renders under Wine (no cross-process present, which Wine lacks).
#
# Steam self-heals modified binaries on launch (package verification), so the
# installed wrapper is locked with chflags uchg. CAVEAT: a Steam CLIENT UPDATE
# will fail to replace steamwebhelper.exe while locked — run this script with
# "unlock", let Steam update, then "install" again.
#
# Usage: install.sh <prefix> [install|uninstall|unlock|status]

set -euo pipefail

PREFIX="${1:?usage: install.sh <wine-prefix> [install|uninstall|unlock|status]}"
MODE="${2:-install}"
CEF="$PREFIX/drive_c/Program Files (x86)/Steam/bin/cef/cef.win64"
HERE="$(cd "$(dirname "$0")" && pwd)"
WRAPPER="$HERE/steamwebhelper.exe"

case "$MODE" in
  install)
    [ -f "$CEF/steamwebhelper.exe" ] || { echo "no steamwebhelper.exe in $CEF"; exit 1; }
    chflags nouchg "$CEF/steamwebhelper.exe" 2>/dev/null || true
    # keep Valve's binary exactly once — and NEVER back up a wrapper build
    # (a wrapper as _real makes the wrapper exec itself in a fork loop)
    if [ ! -f "$CEF/steamwebhelper_real.exe" ]; then
      if strings "$CEF/steamwebhelper.exe" | grep -q MAGE-STEAMWEBHELPER-WRAPPER; then
        echo "ERROR: steamwebhelper.exe is already a wrapper and no Valve backup exists." >&2
        echo "Restore Valve's binary as steamwebhelper_real.exe first." >&2
        exit 1
      fi
      cp "$CEF/steamwebhelper.exe" "$CEF/steamwebhelper_real.exe"
    fi
    if strings "$CEF/steamwebhelper_real.exe" | grep -q MAGE-STEAMWEBHELPER-WRAPPER; then
      echo "ERROR: steamwebhelper_real.exe is a wrapper build — restore Valve's binary." >&2
      exit 1
    fi
    cp "$WRAPPER" "$CEF/steamwebhelper.exe"
    chflags uchg "$CEF/steamwebhelper.exe"
    echo "wrapper installed + locked (uchg) in $CEF"
    ;;
  unlock)
    chflags nouchg "$CEF/steamwebhelper.exe"
    echo "unlocked — let Steam update, then re-run: install.sh <prefix> install"
    ;;
  uninstall)
    chflags nouchg "$CEF/steamwebhelper.exe" 2>/dev/null || true
    [ -f "$CEF/steamwebhelper_real.exe" ] || { echo "no steamwebhelper_real.exe to restore"; exit 1; }
    cp "$CEF/steamwebhelper_real.exe" "$CEF/steamwebhelper.exe"
    echo "restored Valve steamwebhelper.exe"
    ;;
  status)
    ls -laO "$CEF" | grep steamwebhelper || true
    ;;
  *)
    echo "unknown mode: $MODE" >&2; exit 1
    ;;
esac
