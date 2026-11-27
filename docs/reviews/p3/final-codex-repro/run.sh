#!/bin/sh
set -eu
cd "$(dirname "$0")/../../../.."
repro=docs/reviews/p3/final-codex-repro
scratch=$(mktemp -d /tmp/p3-final-codex.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
export CLANG_MODULE_CACHE_PATH="$scratch/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$scratch/swiftpm"
swiftc -emit-library -static -emit-module -module-name Riichi \
    Sources/Riichi/*.swift -o "$scratch/libRiichi.a"
swiftc -emit-library -static -emit-module -module-name RiichiMjai -I "$scratch" \
    Sources/RiichiMjai/*.swift -o "$scratch/libRiichiMjai.a"
# Use the checked-in wall/step helpers, without importing the test module.
sed -n '/^func makeWall/,/^@Suite/{ /^@Suite/d; p; }' Tests/RiichiTests/RoundTests.swift > "$scratch/WallHelpers.swift"
sed -n '/^func t(/p; /^func t1(/p' Tests/RiichiTests/Helpers.swift >> "$scratch/WallHelpers.swift"
sed -i.bak '1i\
import Riichi
' "$scratch/WallHelpers.swift"
swiftc -I "$scratch" -L "$scratch" -lRiichi -lRiichiMjai \
    Sources/mj/MjaiBot.swift Sources/mj/Bots.swift "$scratch/WallHelpers.swift" \
    "$repro/Probes.swift" -o "$scratch/probes"
python3.14 "$repro/run.py" "$scratch/probes"
