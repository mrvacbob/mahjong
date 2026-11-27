#!/bin/sh
# Builds ./mj (Swift engine CLI) and crosscheck/mercury/mj. Exits non-zero on failure.
set -e
cd "$(dirname "$0")"
swift build -c release --product mj
cp "$(swift build -c release --show-bin-path)/mj" ./mj
if command -v mmc >/dev/null; then sh crosscheck/mercury/build.sh; fi
