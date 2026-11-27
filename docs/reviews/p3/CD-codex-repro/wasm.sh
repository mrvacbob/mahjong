#!/bin/sh
set -eu
cd "$(dirname "$0")/../../../.."
out="$PWD/.build/codex-cd-review"
repro="$PWD/docs/reviews/p3/CD-codex-repro"
mkdir -p "$out/cache"
export CLANG_MODULE_CACHE_PATH="$out/cache"
cd "${SOURCE_ROOT:-$PWD}"
target=wasm32-unknown-wasip1
conf=$(swift sdk configure --show-configuration "${WASM_SDK:-swift-6.4.3-RELEASE_wasm}" "$target")
sdk=$(printf '%s\n' "$conf" | sed -n 's/^sdkRootPath: //p')
resources=$(printf '%s\n' "$conf" | sed -n 's/^swiftStaticResourcesPath: //p')
clang_resources="$out/clang-resources"
mkdir -p "$clang_resources/lib/$target"
ln -sf "$resources/clang/lib/wasip1/libclang_rt.builtins-wasm32.a" \
    "$clang_resources/lib/$target/libclang_rt.builtins.a"
swiftc -O -swift-version 6 -target "$target" -sdk "$sdk" -resource-dir "$resources" \
    -Xclang-linker -resource-dir -Xclang-linker "$clang_resources" \
    Sources/Riichi/*.swift "$repro/Flow.swift" -o "$out/flow.wasm"
"$out/flow" > "$out/flow.native.txt"
node "$repro/wasi.cjs" "$out/flow.wasm" > "$out/flow.wasm.txt"
cmp "$out/flow.native.txt" "$out/flow.wasm.txt"
echo 'Native and wasm32 flow and wall vectors match byte for byte.'
if node "$repro/wasi.cjs" "$out/flow.wasm" overflow > "$out/overflow.wasm.txt" 2>&1; then
    echo 'Expected custom-rules overflow on wasm32' >&2
    exit 1
fi
rg 'RuntimeError: unreachable' "$out/overflow.wasm.txt"

wasm_modules="$out/wasm-modules"
mkdir -p "$wasm_modules"
for module in Riichi RiichiMjai; do
    swiftc -O -swift-version 6 -target "$target" -sdk "$sdk" -resource-dir "$resources" \
        -whole-module-optimization -parse-as-library -module-name "$module" \
        -emit-module -emit-module-path "$wasm_modules/$module.swiftmodule" \
        -I "$wasm_modules" -emit-object Sources/"$module"/*.swift -o "$wasm_modules/$module.o"
done
swiftc -O -swift-version 6 -target "$target" -sdk "$sdk" -resource-dir "$resources" \
    -Xclang-linker -resource-dir -Xclang-linker "$clang_resources" \
    -I "$wasm_modules" "$wasm_modules/Riichi.o" "$wasm_modules/RiichiMjai.o" \
    Sources/mj/Bots.swift Sources/mj/Driver.swift Sources/mj/Legality.swift \
    "$repro/PortableReplay.swift" -o "$out/portable.wasm"
"${NATIVE_SWIFTC:-swiftc}" -O -swift-version 6 -I "$out" -L "$out" -lRiichiMjai -lRiichi \
    Sources/mj/Bots.swift Sources/mj/Driver.swift Sources/mj/Legality.swift \
    "$repro/PortableReplay.swift" -o "$out/portable"
"$out/portable" > "$out/portable.native.txt"
node "$repro/wasi.cjs" "$out/portable.wasm" > "$out/portable.wasm.txt"
cmp "$out/portable.native.txt" "$out/portable.wasm.txt"
echo 'Eight native and wasm32 traces, replayed logs and legality exports match byte for byte.'
