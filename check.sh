#!/bin/sh
# Check a Witness program, with the checker the seed holds and nothing but node.
#
#   ./check.sh program.wtn [host|embedded|mcu|esp32]
#
# The checker is compiler/check.wtn, compiled into seed/compiler.wasm with the rest of the
# compiler. It prints a line for each finding -- `error NAME RULE`, `warning NAME RULE`, or
# `unread NAME WHY` for something it does not read yet -- and then the verdict, and exits
# with it: 0 accepted (with or without warnings), 1 rejected, 3 not read.
#
# A program that imports by hash is resolved first against the modules of compiler/, as the
# compiler's own imports are (compiler/link.wtn): what it imports is spliced in and checked
# with it. A hash none of them holds is `unresolved-import`.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
NODE=${NODE:-node}

[ $# -ge 1 ] || { echo "usage: check.sh program.wtn [host|embedded|mcu|esp32]" >&2; exit 2; }
case "${2:-host}" in
    host) entry=drive_check ;;
    embedded|mcu|esp32) entry=drive_check_$2 ;;
    *) echo "check.sh: the profiles are host, embedded, mcu and esp32" >&2; exit 2 ;;
esac
command -v "$NODE" >/dev/null 2>&1 || { echo "check.sh: no node on the path; set NODE= to one (18 or newer)" >&2; exit 2; }

run() {
    sh -c "ulimit -s unlimited 2>/dev/null; exec \"$NODE\" --stack-size=600000 \"$here/tools/wasmc.js\" \"$here/seed/compiler.wasm\" \"\$0\" \"\$1\" \$2" "$@"
}

src=$1
if grep -q '(use ' "$src"; then
    mkdir -p "$here/build"
    {
        echo "(modules"
        for f in $(cat "$here/compiler/ORDER"); do cat "$here/$f"; echo; done
        cat "$src"
        echo ")"
    } > "$here/build/check_modules.wtn"
    if ! run "$here/build/check_modules.wtn" "$here/build/check_flat.wtn" drive_flatten 2>"$here/build/check_flat.err"; then
        sed -n 's/^error unresolved \(wtn:[0-9a-f]*\).*/check.sh: nothing in compiler\/ holds \1/p' "$here/build/check_flat.err" >&2
        printf 'error module unresolved-import\nreject\n'
        exit 1
    fi
    src=$here/build/check_flat.wtn
fi
run "$src" - "$entry"
