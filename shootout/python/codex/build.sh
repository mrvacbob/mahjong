#!/bin/sh
set -eu
entry=$(dirname "$0")
python3.14 - "$entry" <<'PY'
from pathlib import Path
import sys

entry = Path(sys.argv[1])
for name in ("main", "shapes", "scoring", "actions"):
    source = entry / (name + ".py")
    compile(source.read_bytes(), str(source), "exec")
PY
cat > "$entry/mj" <<'SH'
#!/bin/sh
exec python3.14 -E -s -B "$(dirname "$0")/main.py"
SH
chmod +x "$entry/mj"
"$entry/mj" </dev/null
