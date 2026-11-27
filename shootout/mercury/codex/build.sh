#!/bin/sh
set -eu
cd "$(dirname "$0")"
exec mmc --make --grade hlc.gc --opt-level 4 mj
