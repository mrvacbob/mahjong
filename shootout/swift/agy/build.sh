#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
swift package clean
swift build -c release
cp .build/release/mj ./mj
