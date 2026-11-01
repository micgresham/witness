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
| [compiler/](compiler/) | The compiler: reader, parser, type reader, verifier, intermediate representation, runtime, and backends for WebAssembly, x86-64, AArch64, RISC-V (RV64, RV32), Cortex-M, ESP32, ESP32-S3 and ESP32-P4; `driver.wtn` is the whole of it as one function |
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

The seed compiles the compiler's own source, and the module that comes out must be the
seed, byte for byte; compiled once more, it must be the same bytes again. That is the
fixpoint: the compiler as written is the compiler that runs, and anyone can check it with
a WebAssembly runtime and nothing of ours. [seed/SHA256](seed/SHA256) records the seed's
hashes, and witness-bootstrap's `witness bootstrap` makes the same files from the same
commit of `compiler/`.

## What still needs witness-bootstrap

Stated plainly, so nothing here claims more than it does:

- **Checking a program.** The Witness compiler reads and types what it compiles, and its
  verifier proves contracts, termination and resource bounds for 186 of the corpus's 197
  functions, but it is not yet the whole checker. Programs are checked by the reference.
- **Building from `compiler/`.** Its modules name each other by content hash, and the
  codebase that resolves those hashes, and puts the modules into the one text in
  `seed/compiler.wtn`, is still the reference's (`witness store`, `witness bootstrap`). A
  change to `compiler/` is built there and brought here with a new seed.
- **The backends' instruction tables.** `native_riscv32.wtn`, `native_thumb.wtn`,
  `native_xtensa.wtn`, `native_xtensa_s3.wtn` and `native_esp32p4.wtn` are made from the
  RISC-V backend by generators in witness-bootstrap's `tools/`; edit those, not the files here.
- **The tests.** The evidence for every claim the roadmap makes -- emulator runs of each
  backend against the interpreter, the conformance suite, the kernel compared with the
  prototype -- runs there.

Each of these is a step on the [roadmap](docs/ROADMAP.md) toward this repository standing on
its own. The documents are carried as they are, so where they name a test file or a Python
module, it is witness-bootstrap's.

## License

See [LICENSE](LICENSE) and [NOTICE](NOTICE).
