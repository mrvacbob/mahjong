# Phase 3 final review reproductions

From the repository root, run:

```sh
sh Docs/Reviews/p3/final-codex-repro/run.sh
```

The runner uses Swift 6.4 and Python 3.14. It compiles the two libraries and the
actual mjai adapter into a temporary directory, builds deterministic walls
using the checked-in test helpers, and runs the same adapter delivery order
as the game driver. It needs no scenario directory, network, package installation
or prebuilt executable.

The Swift probes assert observations at the reviewed HEAD. A pass for the
chained-kan adapter, terminal fold, or contradictory reply cases reproduces the
behavior described in the review. The Python harness expects signals from the
isolated honba, score and timeout probes and prints them. The other assertions
cover the successful engine cases and are useful controls.
