#!/bin/sh
set -eu
DIR=$(cd "$(dirname "$0")" && pwd)
rm -rf "$DIR/build" "$DIR/mj"
mkdir -p "$DIR/build"
ghc --make -O2 -Wall -outputdir "$DIR/build" -i"$DIR/src" -o "$DIR/mj" "$DIR/src/Main.hs"
