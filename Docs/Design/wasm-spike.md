# WebAssembly spike (2026-11-27)

Question: can the Swift engine run in a browser, so the teaching site needs no server?

**Yes.** The engine source builds for `wasm32-unknown-wasip1` with no changes and
passes the whole corpus (12,439 cases) under both wasmkit and Node's V8.

## How

Apple's Xcode toolchain cannot target WebAssembly; the swift.org toolchain can.

    brew install swiftly
    swiftly init --no-modify-profile --skip-install
    swiftly install 6.4.3
    export PATH="$HOME/.swiftly/bin:$PATH"
    swift sdk install https://download.swift.org/swift-6.4.3-release/wasm-sdk/swift-6.4.3-RELEASE/swift-6.4.3-RELEASE_wasm.artifactbundle.tar.gz --checksum <from swift.org>
    swift build -c release --swift-sdk swift-6.4.3-RELEASE_wasm

The SDK version must match the compiler version exactly.

## Measurements

| | native (arm64) | wasm in Node 24 (V8) |
|---|---|---|
| binary size | — | 7.9 MB, 2.2 MB gzipped |
| start-up | 7 ms | 197 ms (includes Node start and compile) |
| shanten, req/s after start-up | ~370k | ~71k |
| score | ~95k | ~20k |
| waits | ~51k | ~19k |
| legal | ~44k | ~5k |

Throughput is through the line protocol over a pipe on small samples, so treat it as
a rough ratio: wasm is about 3 to 9 times slower than native, and still far faster
than a web page needs.

## Not yet tried

- A real browser, and calling the engine as a library from JavaScript rather than
  through stdin/stdout (needs exported functions or JavaScriptKit).
- Size reduction: `-Osize`, `wasm-opt`, stripping, or the embedded Swift SDK (also
  installed by the bundle), which drops most of the runtime but restricts the
  language (no existentials, limited String/Unicode).
- Foundation. The engine does not import it; keeping it that way keeps the binary
  small.
