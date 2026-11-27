#!/bin/sh
# Build ./mj from clean with plain ghc (boot packages only).
set -e
cd "$(dirname "$0")"
mkdir -p build
ghc -O2 -Wall -isrc -outputdir build -o mj src/Main.hs
