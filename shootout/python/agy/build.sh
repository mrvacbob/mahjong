#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

rm -rf mjlib/__pycache__
python3.14 -m compileall -q -f mjlib
chmod +x "$DIR/mj"
python3.14 -c "import sys; sys.path.insert(0, '$DIR'); import mjlib.cli"
