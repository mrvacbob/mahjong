#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p .build
ghc --make -O2 -Wall -Wcompat -hide-all-packages -package base -package containers -outputdir .build -o mj Main.hs
