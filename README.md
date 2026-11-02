# Witness

A programming language designed to be written by AI and audited by people.

**The compiler tracks where data came from and where it is allowed to go**, and it
refuses to run anything it cannot check. Most serious production incidents are not
crashes; they are correct-looking code sending the right data to the wrong place.
Witness makes those compile errors.

Most languages optimise for how easily a human can type them. Witness optimises for how
hard it is to *lie silently*: no implicit conversions, no wildcard `match` arms, no hidden
effects, no unlabelled flow of secrets or model output into a sink. Where an AI author is
likely to guess, the language makes it say so, and where a person reviews the result, the
checker has already refused the failure modes that are easy to miss in review.

## This repository

Witness written in Witness: the compiler, its runtime, its backends and the kernel that
re-checks proofs, with nothing in any other language but a page of JavaScript that loads
a WebAssembly module. The Python prototype the language was settled with (Stage 0), and
the test suite that checks everything here against it, are in
[witness-bootstrap](https://github.com/micgresham/witness-bootstrap), which stays as the
reference implementation.

| Path | What |
|---|---|
| [compiler/](compiler/) | The compiler: reader, parser, type reader, verifier, intermediate representation, runtime, and backends for WebAssembly, x86-64, AArch64, RISC-V (RV64, RV32), Cortex-M, ESP32, ESP32-S3, ESP32-P4 and ESP32-S31; `driver.wtn` is the whole of it as one function |
| [kernel/](kernel/) | The trusted kernel, [reviewed line by line](kernel/REVIEW.md), that re-checks derivations, declarations, bounds and certificates |
| [seed/](seed/) | The compiler, compiled, and its source as one module: what `./build.sh` starts from |
| [tools/](tools/) | `wasmc.js` and `irc.js`, the node hosts that run a compiled compiler |
| [docs/](docs/) | The [primer](docs/PRIMER.md) (an AI author starts here), the [specification](docs/SPEC.md), the [design](docs/DESIGN.md), the [evidence](docs/EVIDENCE.md) a proof leaves, and the [roadmap](docs/ROADMAP.md) |
| [examples/](examples/), [conformance/](conformance/) | Programs, and the cases every implementation must accept, reject or warn about |

## Build

Node 18 or newer, nothing else:

```bash
./build.sh
```

The seed reads every module of [compiler/](compiler/) in the order
[compiler/ORDER](compiler/ORDER) gives, resolves each one's imports by content hash and splices
them in ([compiler/link.wtn](compiler/link.wtn), with the hashes of
[compiler/canon.wtn](compiler/canon.wtn)), and writes the compiler as one module. When
`compiler/` is what the seed was built from, that is the seed's own source, and compiling it
must give the seed back byte for byte. When `compiler/` has changed, the compiler it
describes is built instead, and must compile itself to the same bytes again and flatten
`compiler/` to the same text. That is the fixpoint: the compiler as written is the compiler
that runs, and anyone can check it with a WebAssembly runtime and nothing of ours.

An edit that changes a definition changes its hash, and every import of it, and of what
imports it, has to name the new one:

```bash
./pin.sh            # re-pin compiler/ against the last commit's modules
./build.sh          # build the compiler it describes, to its own fixpoint
./build.sh seed     # and make that the seed
```

`pin.sh` runs [tools/pin.wtn](tools/pin.wtn), which reads the modules as they were committed, to
know what each old hash was, and rewrites only the hashes.

[seed/SHA256](seed/SHA256) records the seed's hashes.

## Conformance, and the backends made from RISC-V

```bash
./conform.sh        # every conformance case, checked by compiler/check.wtn
./gen.sh            # remake native_riscv32, _thumb, _xtensa, _xtensa_s3, _esp32p4, _esp32s31
```

`conform.sh` runs [tools/conform.wtn](tools/conform.wtn): each case of
[conformance/manifest.json](conformance/manifest.json) is checked under its profile and must
come out with the manifest's verdict and the very rules among its errors and its warnings; a
case the checker does not read is listed as `unread`, never counted as agreeing. `gen.sh` runs
[tools/gen.wtn](tools/gen.wtn), which makes six backends from the RISC-V one: edit
`compiler/native_riscv.wtn`, `riscv.wtn`, `thumb.wtn`, `xtensa.wtn` or the generator, never
the files it writes.

## Check

```bash
./check.sh program.wtn          # or: ./check.sh program.wtn mcu
```

The checker is [compiler/check.wtn](compiler/check.wtn), compiled into the seed with the rest
of the compiler: every pass of the front end over the module, in the reference's order (the
contracts are proved only once the rest passes), a line per finding, `error NAME RULE`, and a
verdict, `accept`, `warn`, `reject` or `unread`, which is also the exit status (0, 0, 1, 3).
On every conformance case it says what the manifest says, verdict and the exact rules among
the errors and the warnings, and on every example what the reference says (witness-bootstrap's
`tests/test_check_wtn.py`, and `tests/test_selfhost.py` for the compiled one). Where it is
weaker than the reference, the source says so: a function's first fault is the only one
reported, `needless-declassify` for a value is only given when its type can be told from the
parameters, and the warning for a redaction no log field reaches is not given.

A program that imports is resolved first against the modules of `compiler/`, as the
compiler's own imports are, and what it imports is checked with it; a hash none of them holds
is `unresolved-import`.

## What still needs witness-bootstrap

Stated plainly, so nothing here claims more than it does:

- **The tests the reference keeps.** The evidence that each backend's code does what the
  interpreter does -- emulator runs on every target -- and the kernel compared with the
  prototype, run there. What runs here: the fixpoint (`./build.sh`), the conformance suite
  under the Witness checker (`./conform.sh`), and the backends made from the RISC-V one
  (`./gen.sh`, which writes them; `git diff` says whether anything changed).

That is the last step on the [roadmap](docs/ROADMAP.md) toward this repository standing on
its own. The documents are carried as they are, so where they name a test file or a Python
module, it is witness-bootstrap's.

## License

See [LICENSE](LICENSE) and [NOTICE](NOTICE).
