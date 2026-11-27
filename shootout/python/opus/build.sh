#!/bin/sh
# Byte-compile every module (fails on syntax errors) and make the wrapper executable.
set -e
cd "$(dirname "$0")"
python3.14 -m compileall -q -f . >/dev/null
python3.14 -c "import sys; sys.path.insert(0, '.'); import main"
chmod +x mj
