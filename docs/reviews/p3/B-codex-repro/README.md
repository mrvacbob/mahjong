# Package B review reproductions

Run from the repository root. The existing scenario runner enumerates the package's scenario directory, so copy the fixtures and probe into a temporary package.

```sh
scratch=$(mktemp -d /tmp/p3-b-codex.XXXXXX)
cp -R Package.swift Sources Tests scenarios tools "$scratch"
cp docs/reviews/p3/B-codex-repro/ReviewProbes.swift "$scratch/Tests/RiichiTests/"
cp docs/reviews/p3/B-codex-repro/*.scn "$scratch/scenarios/"
export CLANG_MODULE_CACHE_PATH="$scratch/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$scratch/swiftpm-module-cache"

python3.14 tools/scenario.py --check docs/reviews/p3/B-codex-repro/*.scn
swift test --package-path "$scratch" --disable-sandbox --disable-xctest --filter CodexReviewProbes
swift test --package-path "$scratch" --disable-sandbox --disable-xctest --filter ScenarioTests
```

The six Swift probes passed. The two finding probes assert the observed behavior so a pass reproduces the issue. In the scenario run the fourth-open-kan fixture failed at the owed `dora(7z)` event assertion. The two-tenpai fixture passed on both presets.

The original repository's Swift Testing run passed 58 tests with 10 known issues across the seven disputed scenarios. Package C scenarios were outside scope. The checkout's XCTest loader reported an error on the initial unfiltered invocation. The successful rerun used `--disable-xctest`; the package tests under review use Swift Testing.
