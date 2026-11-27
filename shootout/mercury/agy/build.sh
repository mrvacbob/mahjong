#!/bin/sh
set -eu
cd "$(dirname "$0")"
rm -rf Mercury mj mj.err *.err *.mh
mmc --make --grade hlc.gc -O4 mj
