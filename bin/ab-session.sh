#!/bin/bash
# ab-session.sh <label>
# One-command headless DOOM A/B session on mage-wine: launch -> auto-continue
# into Foundry -> 60s ps sampling -> HUD screenshot -> clean shutdown.
# Extra env (MVK_CONFIG_*, ROSETTA_*, MVK_CONFIG_TRACE_VULKAN_CALLS for a
# traced session) is inherited from the caller — set it BEFORE invoking.
# Evidence lands in mage/docs/testing/measure-20260721/<label>-*.
set -u
LABEL="$1"
OUT=/Users/dttdrv/Projects/macgaming/mage/docs/testing/measure-20260721
S="/Users/dttdrv/Applications/DOOM 2016.app/Contents/SharedSupport"
W=/Users/dttdrv/Projects/macgaming/toolchains/wine-mage-11.13
STEAM="$S/prefix/drive_c/Program Files (x86)/Steam/steam.exe"

caffeinate -u -t 3600 &
CAFF=$!
cleanup() {
  pkill -f DOOMx64vk 2>/dev/null; pkill -f steam.exe 2>/dev/null; sleep 2
  "$W/install/bin/wineserver" -k 2>/dev/null; kill $CAFF 2>/dev/null
}
trap cleanup EXIT

export WINEPREFIX="$S/prefix"
export DYLD_FALLBACK_LIBRARY_PATH="$W/install/lib"
export WINEDLLOVERRIDES='mscoree=d;mshtml=d'
export WINEDEBUG=-all WINEMSYNC=1 WINEESYNC=0 MTL_HUD_ENABLED=1
export ROSETTA_ADVERTISE_AVX="${ROSETTA_ADVERTISE_AVX:-1}"

pkill -f DOOMx64vk 2>/dev/null; pkill -f steam.exe 2>/dev/null; sleep 1
"$W/install/bin/wineserver" -k 2>/dev/null; sleep 2

: > "$OUT/$LABEL-steam.log"
"$W/install/bin/wine" "$STEAM" -offline -noverifyfiles -nobootstrapupdate \
  -skipinitialbootstrap -cef-disable-gpu -cef-disable-sandbox >>"$OUT/$LABEL-steam.log" 2>&1 &
sleep 75
"$W/install/bin/wine" "$STEAM" -applaunch 379720 \
  +com_SkipIntroVideo 1 +r_renderAPI 1 +r_fullscreen 0 +jobs_numThreads 8 >>"$OUT/$LABEL-steam.log" 2>&1 &

DPID=""
for i in $(seq 1 24); do
  DPID=$(pgrep -f DOOMx64vk | head -1)
  [ -n "$DPID" ] && break
  sleep 5
done
if [ -z "$DPID" ]; then echo "$LABEL: DOOM did not start" | tee "$OUT/$LABEL-FAILED"; exit 1; fi
SPID=$(pgrep -f "wine-mage-11.13.*/wineserver" | head -1)
echo "$LABEL: DOOM pid $DPID wineserver pid ${SPID:-none}"

# settle into the auto-continued scene, then sample
sleep 45
: > "$OUT/$LABEL-ps.log"
for i in $(seq 1 12); do
  ps -o %cpu=,time=,comm= -p "$DPID" >> "$OUT/$LABEL-ps.log"
  [ -n "${SPID:-}" ] && ps -o %cpu=,time=,comm= -p "$SPID" >> "$OUT/$LABEL-ps.log"
  sleep 5
done

screencapture -x "$OUT/$LABEL-hud.png" 2>/dev/null || true
echo "$LABEL: done"
