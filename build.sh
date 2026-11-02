#!/bin/sh
# Build Witness from compiler/ and its seed, with nothing but node.
#
#   ./build.sh          build, and check the fixpoint
#   ./build.sh seed     and then make what was built the seed
#
# seed/compiler.wasm is the compiler, compiled. It reads every module of compiler/, in the
# order compiler/ORDER gives, resolves each one's imports by content hash and splices them in
# (compiler/link.wtn), and writes the compiler as one module: build/compiler.wtn. When
# compiler/ is what the seed was built from, that text is seed/compiler.wtn, and compiling it
# gives the seed back byte for byte. When compiler/ has changed, the compiler it describes is
# built instead, and is held to the same standard: compiled by itself it gives the same bytes
# again, and it flattens compiler/ to the same text. That is the fixpoint -- the compiler as
# it is written is the compiler as it runs -- and anyone can check it with a WebAssembly
# runtime and nothing of ours.
#
# seed/SHA256 records both seed files.
set -eu

cd "$(dirname "$0")"
NODE=${NODE:-node}

fail() { printf 'build.sh: %s\n' "$1" >&2; exit 1; }
say() { printf '== %s\n' "$1"; }

command -v "$NODE" >/dev/null 2>&1 || fail "no node on the path; set NODE= to one (18 or newer)"
case "${1:-}" in ""|seed) ;; *) fail "usage: ./build.sh [seed]" ;; esac

sha() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# A compiled compiler run on a source. The reader recurses deeply -- most of all over every
# module of compiler/ at once, comments and all -- hence the stack.
run() {
    sh -c "ulimit -s unlimited 2>/dev/null; exec \"$NODE\" --stack-size=600000 tools/wasmc.js \"$1\" \"$2\" \"$3\" $4" \
        || fail "$1 failed on $2"
}

say "the seed is the one recorded"
for f in compiler.wtn compiler.wasm; do
    want=$(awk -v f="$f" '$2 == f { print $1 }' seed/SHA256)
    [ -n "$want" ] || fail "seed/SHA256 has no line for $f"
    [ "$(sha "seed/$f")" = "$want" ] || fail "seed/$f is not the file seed/SHA256 records"
done

mkdir -p build
{
    echo "(modules"
    for f in $(cat compiler/ORDER); do cat "$f"; echo; done
    echo ")"
} > build/modules.wtn

say "the seed flattens compiler/"
run seed/compiler.wasm build/modules.wtn build/compiler.wtn drive_flatten
if cmp -s build/compiler.wtn seed/compiler.wtn; then
    same=yes
    say "compiler/ is the seed's own source"
else
    same=no
    say "compiler/ has changed since the seed: building the compiler it describes"
fi

say "stage 2: the seed compiles it"
run seed/compiler.wasm build/compiler.wtn build/stage2.wasm drive
if [ "$same" = yes ]; then
    cmp -s seed/compiler.wasm build/stage2.wasm || fail "stage 2 differs from the seed: not a fixpoint"
fi

say "stage 3: and the result does again"
run build/stage2.wasm build/compiler.wtn build/stage3.wasm drive

say "stage 4: and that result once more"
run build/stage3.wasm build/compiler.wtn build/stage4.wasm drive
cmp -s build/stage3.wasm build/stage4.wasm || fail "stage 4 differs from stage 3: not a fixpoint"

say "the compiler built flattens compiler/ to the text it was built from"
run build/stage3.wasm build/modules.wtn build/again.wtn drive_flatten
cmp -s build/compiler.wtn build/again.wtn || fail "the built compiler flattens compiler/ differently; run ./build.sh seed, then ./build.sh"

say "fixpoint: $(sha build/stage4.wasm)"

if [ "${1:-}" = seed ]; then
    cp build/compiler.wtn seed/compiler.wtn
    cp build/stage4.wasm seed/compiler.wasm
    (cd seed && for f in compiler.wtn compiler.wasm; do printf '%s  %s\n' "$(sha "$f")" "$f"; done) > seed/SHA256.new
    mv seed/SHA256.new seed/SHA256
    say "the seed is now what was built"
fi
