#!/usr/bin/env bash
# Clone the read-only reference disassemblies into vendor/ at pinned commits.
# vendor/ is gitignored: these repos are large, reference-only, and some have
# unclear licences, so they are fetched, never committed or submoduled.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p vendor
fetch() { # name url commit
  local name=$1 url=$2 commit=$3
  if [ ! -d "vendor/$name/.git" ]; then
    git clone --quiet "$url" "vendor/$name"
  fi
  git -C "vendor/$name" fetch --quiet origin "$commit" 2>/dev/null || git -C "vendor/$name" fetch --quiet --unshallow 2>/dev/null || true
  git -C "vendor/$name" checkout --quiet "$commit"
  echo "vendor/$name @ $commit"
}
# Line numbers in docs/ram_map.md refer to these commits.
fetch AsarUSALTTPDisassembly https://github.com/JaredBrian/AsarUSALTTPDisassembly.git 28cc91a20ca0bcf5c2afec55a0839c5bb830905b
fetch usdasm                 https://github.com/spannerisms/usdasm.git                bcdd96e96ee092824078754b6192a5b40f1f39ac
fetch alttp-disassembly      https://github.com/walkingeyerobot/alttp-disassembly.git 79207d1730c2af1c777bc5dc3f94538f779ea292
