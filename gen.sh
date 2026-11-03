#!/bin/sh
# Make the backends that are made from the RISC-V one, with nothing but node.
#
#   ./gen.sh
#
# native_riscv32.wtn, native_thumb.wtn, native_armv6m.wtn, native_xtensa.wtn, native_xtensa_s3.wtn,
# native_esp32p4.wtn, native_esp32s31.wtn and native_rv32e.wtn are the RV64 backend (compiler/native_riscv.wtn)
# with another machine behind it, made by tools/gen.wtn from it and from riscv.wtn, thumb.wtn
# and xtensa.wtn. Edit those and tools/gen.wtn, then run this; the seed compiles the generator
# and runs it. What is written is compiler/'s, so `git diff` shows what changed.
set -eu

cd "$(dirname "$0")"
NODE=${NODE:-node}

fail() { printf 'gen.sh: %s\n' "$1" >&2; exit 1; }
command -v "$NODE" >/dev/null 2>&1 || fail "no node on the path; set NODE= to one (18 or newer)"

run() {
    sh -c "ulimit -s unlimited 2>/dev/null; exec \"$NODE\" --stack-size=600000 tools/wasmc.js \"$1\" \"$2\" \"$3\" $4" \
        || fail "$1 failed on $2"
}

mkdir -p build
{ echo "(modules"; cat compiler/rtlib.wtn; echo; cat tools/gen.wtn; echo; echo ")"; } > build/gen_modules.wtn
run seed/compiler.wasm build/gen_modules.wtn build/gen.wtn drive_flatten
run seed/compiler.wasm build/gen.wtn build/gen.wasm drive

# An entry, the backend it writes, and what it is made from, joined by NUL bytes.
made() {
    entry=$1 target=$2
    shift 2
    first=yes
    for s in "$@"; do
        [ "$first" = yes ] || printf '\000'
        cat "compiler/$s"
        first=no
    done > build/gen_in.txt
    run build/gen.wasm build/gen_in.txt "compiler/$target" "$entry"
    printf '== made compiler/%s\n' "$target"
}

made riscv32 native_riscv32.wtn native_riscv.wtn riscv.wtn
made thumb native_thumb.wtn native_riscv.wtn thumb.wtn
# Made from the Cortex-M3 one, so after it.
made armv6m native_armv6m.wtn native_thumb.wtn
made xtensa native_xtensa.wtn native_riscv.wtn xtensa.wtn
made xtensa_s3 native_xtensa_s3.wtn native_riscv.wtn xtensa.wtn
# These three are made from the RV32 one, so after it.
made esp32p4 native_esp32p4.wtn native_riscv32.wtn
made esp32s31 native_esp32s31.wtn native_riscv32.wtn
made rv32e native_rv32e.wtn native_riscv32.wtn
