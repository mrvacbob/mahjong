#!/bin/sh
set -eu
cd "$(dirname "$0")/../../../.."
repro="$PWD/docs/reviews/p3/CD-codex-repro"
out="$PWD/.build/codex-cd-review"
mkdir -p "$out/cache"
export CLANG_MODULE_CACHE_PATH="$out/cache"
cd "${SOURCE_ROOT:-$PWD}"
swiftc -O -swift-version 6 -emit-library -static -emit-module -module-name Riichi \
    Sources/Riichi/*.swift -o "$out/libRiichi.a"
swiftc -O -swift-version 6 -emit-library -static -emit-module -module-name RiichiMjai \
    -I "$out" Sources/RiichiMjai/*.swift -o "$out/libRiichiMjai.a"
swiftc -O -swift-version 6 -I "$out" -L "$out" -lRiichiMjai -lRiichi \
    Sources/mj/*.swift -o "$out/mj"
swiftc -O -swift-version 6 -I "$out" -L "$out" -lRiichiMjai -lRiichi \
    Sources/mj/Bots.swift Sources/mj/Driver.swift "$repro/Review.swift" -o "$out/review"
"$out/review"
swiftc -O -swift-version 6 Sources/Riichi/*.swift "$repro/Flow.swift" -o "$out/flow"
"$out/flow"
"$out/flow" overflow
"${PYTHON:-python3}" "$repro/cli.py" "$out/mj" "$out"
