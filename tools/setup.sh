#!/usr/bin/env bash
# Reproduce the local toolchain (Linux x86_64, Debian/Ubuntu). Idempotent.
# Installs nothing system-wide except via the apt line printed below, which you
# run yourself with sudo. Everything else lands in .venv/ and .tools/ (gitignored).
set -euo pipefail
cd "$(dirname "$0")/.."

ASAR_TAG=v1.91
FLIPS_TAG=v198
MESEN_TAG=2.2.1

need_apt=()
command -v cmake >/dev/null      || need_apt+=(cmake)
command -v xvfb-run >/dev/null   || need_apt+=(xvfb)
python3 -c 'import venv, ensurepip' 2>/dev/null || need_apt+=(python3-venv)
ldconfig -p | grep -q 'libSDL2-2.0.so.0' || need_apt+=(libsdl2-2.0-0)
if [ ${#need_apt[@]} -gt 0 ]; then
  echo "Missing system packages. Run:  sudo apt-get install -y ${need_apt[*]}" >&2
  exit 1
fi

# Python venv
[ -d .venv ] || python3 -m venv .venv
.venv/bin/pip install -q --upgrade Pillow PyYAML

mkdir -p .tools/bin .tools/src

# asar (RPGHacker/asar), from source
if [ ! -x .tools/bin/asar ]; then
  [ -d .tools/src/asar ] || git clone -q --depth 1 --branch "$ASAR_TAG" https://github.com/RPGHacker/asar.git .tools/src/asar
  cmake -S .tools/src/asar/src -B .tools/src/asar/build -DCMAKE_BUILD_TYPE=Release \
        -DASAR_GEN_DLL=OFF -DASAR_GEN_EXE_TEST=OFF -DASAR_GEN_DLL_TEST=OFF >/dev/null
  cmake --build .tools/src/asar/build -j"$(nproc)" >/dev/null
  cp .tools/src/asar/build/asar/bin/asar .tools/bin/asar
fi

# flips (Floating IPS; github.com/Alcaro/Flips redirects to Sir-Walrus/Flips),
# CLI-only build from source. The release binary links GTK, which we don't want.
if [ ! -x .tools/bin/flips ]; then
  [ -d .tools/src/flips-src ] || git clone -q --depth 1 --branch "$FLIPS_TAG" --recurse-submodules \
        https://github.com/Sir-Walrus/Flips.git .tools/src/flips-src
  make -C .tools/src/flips-src TARGET=cli -j"$(nproc)" >/dev/null
  cp .tools/src/flips-src/flips .tools/bin/flips
fi

# MesenCE (nesdev-org/MesenCE) official Linux x64 release
if [ ! -x .tools/mesen/Mesen ]; then
  mkdir -p .tools/mesen
  curl -fsSL -o .tools/mesen/m.zip \
    "https://github.com/nesdev-org/MesenCE/releases/download/${MESEN_TAG}/Mesen_${MESEN_TAG}_Linux_x64.zip"
  unzip -q -o .tools/mesen/m.zip -d .tools/mesen && rm .tools/mesen/m.zip
  chmod +x .tools/mesen/Mesen
fi

.tools/bin/asar --version | head -1
.tools/bin/flips --help | head -1
echo "MesenCE ${MESEN_TAG} at .tools/mesen/Mesen"
echo "ok"
