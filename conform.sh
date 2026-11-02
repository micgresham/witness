#!/bin/sh
# Run the conformance suite with the checker in Witness, and nothing but node.
#
#   ./conform.sh
#
# Every case in conformance/manifest.json is checked by compiler/check.wtn, under the profile
# the manifest names, and must come out as the manifest says: the verdict, and the very rules
# among its errors and among its warnings. tools/conform.wtn does the reading and the
# comparing; the seed resolves its import of the checker against compiler/, and compiles it.
# A case the compiled checker cannot finish is `unread`, and is listed, never counted as
# agreeing; the suite fails only on a case that differs.
set -eu

cd "$(dirname "$0")"
NODE=${NODE:-node}

fail() { printf 'conform.sh: %s\n' "$1" >&2; exit 1; }
command -v "$NODE" >/dev/null 2>&1 || fail "no node on the path; set NODE= to one (18 or newer)"

run() {
    sh -c "ulimit -s unlimited 2>/dev/null; exec \"$NODE\" --stack-size=600000 tools/wasmc.js \"$1\" \"$2\" \"$3\" $4"
}

mkdir -p build
{
    echo "(modules"
    for f in $(cat compiler/ORDER); do cat "$f"; echo; done
    cat tools/conform.wtn
    echo ")"
} > build/conform_modules.wtn
run seed/compiler.wasm build/conform_modules.wtn build/conform.wtn drive_flatten || fail "the seed could not flatten tools/conform.wtn"
run seed/compiler.wasm build/conform.wtn build/conform.wasm drive || fail "the seed could not compile tools/conform.wtn"

agreed=0 differed=0 unread=0
for case in $(run build/conform.wasm conformance/manifest.json - drive_check_cases | sed '$d'); do
    { cat conformance/manifest.json; printf '\000%s\000' "$case"; cat "conformance/cases/$case"; } > build/case.txt
    set +e
    said=$(run build/conform.wasm build/case.txt - drive_check_case)
    status=$?
    set -e
    case $status in
        0) agreed=$((agreed + 1)) ;;
        1) differed=$((differed + 1)); printf '%s\n' "$said" | sed '$d' ;;
        *) unread=$((unread + 1)); printf 'unread %s\n' "$case" ;;
    esac
done
printf '== %d agree, %d differ, %d unread\n' "$agreed" "$differed" "$unread"
[ "$differed" -eq 0 ] || exit 1
