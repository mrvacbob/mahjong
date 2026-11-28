#!/bin/sh
# Build ./mj from clean with the Mercury compiler.
set -e
cd "$(dirname "$0")"
mmc --make -O4 mj
test -x ./mj
