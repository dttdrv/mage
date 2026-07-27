#!/bin/sh
set -eu

mage_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=${MAGE_MOLTENVK_BUILD_DIR:-"$mage_dir/build/MoltenVK-macos26"}

cmake -S "$mage_dir/vendor/MoltenVK" -B "$build_dir" \
  "-DCPM_SPIRV-Cross_SOURCE=$mage_dir/vendor/SPIRV-Cross" \
  -DCMAKE_BUILD_TYPE=Release \
  '-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64' \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DCMAKE_OBJC_FLAGS=-Werror=unguarded-availability-new \
  -DCMAKE_OBJCXX_FLAGS=-Werror=unguarded-availability-new \
  -DCMAKE_INSTALL_PREFIX="$mage_dir/dist/runtime"
cmake --build "$build_dir" --parallel "${MAGE_BUILD_JOBS:-2}"
cmake --install "$build_dir"
