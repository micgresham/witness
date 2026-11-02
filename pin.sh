#!/bin/sh
# Re-pin after an edit, with nothing but node and git.
#
#   ./pin.sh
#
# A module imports by content hash, so an edit that changes a definition leaves its importers
# naming a hash that no longer exists, and so on through everything after them in
# compiler/ORDER. tools/pin.wtn reads the modules as they were committed, to know what each
# old hash was, and the modules as they are now, and gives every stale import the hash its
# definition has now; only the hashes in the text change. tools/conform.wtn and tools/pin.wtn
# import from compiler/ too, and are re-pinned with it. Then ./build.sh builds the result.
set -eu

cd "$(dirname "$0")"
NODE=${NODE:-node}

fail() { printf 'pin.sh: %s\n' "$1" >&2; exit 1; }
command -v "$NODE" >/dev/null 2>&1 || fail "no node on the path; set NODE= to one (18 or newer)"
git rev-parse HEAD >/dev/null 2>&1 || fail "pin.sh needs the git history, to read the modules as they were"

run() {
    sh -c "ulimit -s unlimited 2>/dev/null; exec \"$NODE\" --stack-size=600000 tools/wasmc.js \"$1\" \"$2\" \"$3\" $4"
}

TOOLS="tools/conform.wtn tools/pin.wtn"
mkdir -p build

# The pinner, built from the committed modules its own imports name.
{
    echo "(modules"
    for f in $(git show HEAD:compiler/ORDER) tools/pin.wtn; do git show "HEAD:$f"; echo; done
    echo ")"
} > build/pin_modules.wtn
run seed/compiler.wasm build/pin_modules.wtn build/pin.wtn drive_flatten || fail "the seed could not flatten tools/pin.wtn"
run seed/compiler.wasm build/pin.wtn build/pin.wasm drive || fail "the seed could not compile tools/pin.wtn"

# Every module as it was, then as it is, a record each, NUL between them.
{
    first=yes
    for f in $(git show HEAD:compiler/ORDER) $TOOLS; do
        if git cat-file -e "HEAD:$f" 2>/dev/null; then
            [ "$first" = yes ] || printf '\000'
            printf 'old %s\n' "$f"; git show "HEAD:$f"
            first=no
        fi
    done
    for f in $(cat compiler/ORDER) $TOOLS; do
        printf '\000new %s\n' "$f"; cat "$f"
    done
} > build/pin_in.txt
run build/pin.wasm build/pin_in.txt - drive_files || fail "an import names a hash nothing holds"
