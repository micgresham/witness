#!/bin/sh
# Check a Witness program, with the checker the seed holds and nothing but node.
#
#   ./check.sh program.wtn [host|embedded|mcu|esp32]
#
# The checker is compiler/check.wtn, compiled into seed/compiler.wasm with the rest of the
# compiler. It prints a line for each finding -- `error NAME RULE`, `warning NAME RULE`, or
# `unread NAME WHY` for something it does not read yet -- and then the verdict, and exits
# with it: 0 accepted (with or without warnings), 1 rejected, 3 not read. A program that
# imports by hash is not read yet: resolving an import needs the codebase (README.md).
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

# The reader recurses deeply, hence the stack, as in build.sh.
exec sh -c "ulimit -s unlimited 2>/dev/null; exec \"$NODE\" --stack-size=200000 \"$here/tools/wasmc.js\" \"$here/seed/compiler.wasm\" \"\$0\" - $entry" "$1"
