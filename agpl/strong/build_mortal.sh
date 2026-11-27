#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copies upstream Mortal sources from ../../../3p/Mortal (read-only) into ./build/
# and compiles libriichi as a CPython extension module for the uv venv on /Volumes/Psyche.
set -eu

DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
UPSTREAM="$(CDPATH= cd -- "$DIR/../../../3p/Mortal" && pwd)"
STRONG_ROOT="${STRONG_ROOT:-/Volumes/Psyche/mahjong/strong}"
VENV="$STRONG_ROOT/.venv"
BUILD="$DIR/build"

mkdir -p "$STRONG_ROOT/weights" "$STRONG_ROOT/uv-cache" "$STRONG_ROOT/uv-python" "$STRONG_ROOT/cargo-home"

if [ ! -x "$VENV/bin/python" ]; then
    UV_CACHE_DIR="$STRONG_ROOT/uv-cache" \
    UV_PYTHON_INSTALL_DIR="$STRONG_ROOT/uv-python" \
    uv venv --python 3.12 "$VENV"
    UV_CACHE_DIR="$STRONG_ROOT/uv-cache" \
    uv pip install --python "$VENV/bin/python" torch numpy
fi

mkdir -p "$BUILD/mortal"
cp "$UPSTREAM/Cargo.toml" "$UPSTREAM/Cargo.lock" "$BUILD/"
rm -rf "$BUILD/libriichi" "$BUILD/exe-wrapper"
cp -R "$UPSTREAM/libriichi" "$UPSTREAM/exe-wrapper" "$BUILD/"
cp "$UPSTREAM/mortal/model.py" "$UPSTREAM/mortal/engine.py" "$BUILD/mortal/"

CARGO_HOME="$STRONG_ROOT/cargo-home" \
PYO3_PYTHON="$VENV/bin/python" \
cargo build --manifest-path "$BUILD/Cargo.toml" -p libriichi --lib --release --locked

cp "$BUILD/target/release/libriichi.dylib" "$BUILD/mortal/libriichi.so"
echo "Built $BUILD/mortal/libriichi.so"
