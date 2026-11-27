#!/bin/sh
set -eu
entry=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec swiftc -swift-version 6 -O -module-cache-path "$entry/.build/module-cache" \
    "$entry/Tiles.swift" "$entry/Shape.swift" "$entry/Score.swift" \
    "$entry/Legal.swift" "$entry/main.swift" -o "$entry/mj"
