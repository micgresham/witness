# The kernel, reviewed

```yaml
document: witness-kernel-review
phase: 1
reviewed_by: Michael Gresham <micgresham@gmail.com>
reviewed_on: 2026-10-31
commit: 5d95586
lines: 2449
findings: one -- `names_union` (core.wtn) declares Alloc and never performs it (the unused-effect warning, tests/test_env.py); not a soundness matter, left for the next change to the kernel
```

Phase 1's exit criteria have two halves. The first is mechanical and the build checks it:
every Phase 0 check is re-expressed as evidence that a kernel written in Witness
re-checks ([EVIDENCE.md](../docs/EVIDENCE.md)). The second cannot be checked by anything
— **a kernel is only trustworthy if a person has read all of it** — so it is recorded
here instead, with what was read and the exact text that was read.

## What was read

| Module | Lines | SHA-256 of the file, first 32 |
|---|---|---|
| [`arith.wtn`](arith.wtn) | 452 | `f3b8e214b8a5ae8aeb8ac67f64103073` |
| [`core.wtn`](core.wtn) | 1,279 | `0b38704d4786dd874ad5b9043514c6b9` |
| [`costs.wtn`](costs.wtn) | 332 | `1decbddea01eaa8e878120c0e3629779` |
| [`decls.wtn`](decls.wtn) | 386 | `20b6c8f1b1fc82697b74150d75ed33ac` |

Those hashes are not decoration. [`tests/test_review.py`](../tests/test_review.py)
recomputes them, and the build fails if any kernel module has changed since the review.
A review of text that has since been edited is not a review of anything, so changing a
kernel module means this record has to be renewed — by a person, reading the change.

## What the review covers

The four modules above, line by line, as the text that the Phase 0 interpreter runs. That
is the whole trusted base of Phase 1 *in Witness*.

## What it does not cover

Stated plainly, because a review record that overstates its reach is worse than none:

- **The Python kernel.** `witness/kernel.py` and `witness/certificate.py` are the models
  the Witness modules were transcribed from, and the toolchain still runs them by
  default. They are checked against the Witness modules on the whole corpus, in both
  directions, and under damage ([EVIDENCE.md §5.5](../docs/EVIDENCE.md)) — but they have
  not themselves been read line by line, and they are not the artefact Phase 2 carries
  forward.
- **The interpreter underneath.** The Witness kernel is only as sound as the Phase 0
  interpreter that runs it, which is Python and is not part of this review. Phase 2
  replaces it; until then the kernel's answers rest on it.
- **The harnesses.** `witness/witnessed.py`, `judged.py`, `declared.py` and `bounded.py`
  write a program's evidence into a copy of a kernel module. A bug in one of them makes a
  kernel refuse, not accept, so they are outside the trusted base by construction — but
  they are also outside this review.
- **The size target.** [EVIDENCE.md §1](../docs/EVIDENCE.md) hoped for "a few hundred
  lines". The four modules are 2,449, of which about 260 are the primitive table of
  SPEC §6.3 written out as data and a good deal more is the same list and set handling
  repeated in each module, because a Witness module imports nothing. The review happening
  is the stronger evidence that the kernel is readable; the number is recorded here
  rather than quietly dropped.
