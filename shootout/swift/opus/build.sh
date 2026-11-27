#!/bin/sh
# Builds ./mj from clean. Exits non-zero on failure.
set -e
cd "$(dirname "$0")"
swift build -c release --product mj
cp "$(swift build -c release --show-bin-path)/mj" ./mj
