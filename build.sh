#!/bin/sh
# Build Witness from its seed, with nothing but node.
#
#   ./build.sh
#
# seed/compiler.wasm is the compiler, compiled; seed/compiler.wtn is its source, every module
# of compiler/ and the runtime library put into one. The seed compiles that source, and what
# comes out must be the seed itself, byte for byte -- and compiling it once more must give
# the same bytes again. That is the fixpoint: the compiler as it is written is the compiler as
# it runs, and anyone can check it with a WebAssembly runtime and nothing of ours.
#
# seed/SHA256 records both files. They are made by witness-bootstrap's `witness bootstrap`,
# from the same commit of compiler/ that is here (see README.md).
set -eu

cd "$(dirname "$0")"
NODE=${NODE:-node}

fail() { printf 'build.sh: %s\n' "$1" >&2; exit 1; }
say() { printf '== %s\n' "$1"; }

command -v "$NODE" >/dev/null 2>&1 || fail "no node on the path; set NODE= to one (18 or newer)"

sha() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# A compiled compiler compiling the source. The reader recurses deeply, hence the stack.
compile() {
    sh -c "ulimit -s unlimited 2>/dev/null; exec \"$NODE\" --stack-size=200000 tools/wasmc.js \"$1\" seed/compiler.wtn \"$2\"" \
        || fail "$1 did not compile seed/compiler.wtn"
}

say "the seed is the one recorded"
for f in compiler.wtn compiler.wasm; do
    want=$(awk -v f="$f" '$2 == f { print $1 }' seed/SHA256)
    [ -n "$want" ] || fail "seed/SHA256 has no line for $f"
    [ "$(sha "seed/$f")" = "$want" ] || fail "seed/$f is not the file seed/SHA256 records"
done

mkdir -p build
say "stage 2: the seed compiles its own source"
compile seed/compiler.wasm build/stage2.wasm
cmp -s seed/compiler.wasm build/stage2.wasm || fail "stage 2 differs from the seed: not a fixpoint"

say "stage 3: and the result does again"
compile build/stage2.wasm build/stage3.wasm
cmp -s build/stage2.wasm build/stage3.wasm || fail "stage 3 differs from stage 2"

say "fixpoint: $(sha build/stage3.wasm)"
