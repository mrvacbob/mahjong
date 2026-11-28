#!/usr/bin/env python3
"""Copy the pinned Mortal crate and expose its Rust arena API."""
import shutil
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent
mortal = root / "../../../3p/Mortal"
revision = "0cff2b52982be5b1163aa9a62fb01f03ce91e0d2"
if subprocess.check_output(["git", "-C", mortal, "rev-parse", "HEAD"], text=True).strip() != revision:
    raise SystemExit(f"Expected Mortal checkout at {revision}")
destination = root / "mortal/libriichi"
for relative in ("Cargo.toml", "build.rs"):
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(mortal / "libriichi" / relative, destination / relative)
for relative in ("src", "benches"):
    shutil.copytree(mortal / "libriichi" / relative, destination / relative, dirs_exist_ok=True)
lib = destination / "src/lib.rs"
lib.write_text(lib.read_text().replace("\nmod arena;\n", "\npub mod arena;\n"))
arena = destination / "src/arena/mod.rs"
arena.write_text(arena.read_text().replace("pub use board::Board;", "pub use board::{Board, Poll};"))
