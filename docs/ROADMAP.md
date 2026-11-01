# Witness — Roadmap

The path from a throwaway prototype to a self-hosted, verified toolchain with no
host language. See [DESIGN.md §5](DESIGN.md#5-independence-from-other-languages--the-bootstrap)
for the reasoning.

Each phase is a checklist; within a phase, items are in the order to do them. A phase
starts only when the previous phase's exit criteria are met, except where noted.
Phases 0–3 are the bootstrap stages of DESIGN.md §5 (Phase 0 = Stage 0, and so on).

| Phase | Goal | Status |
|---|---|---|
| 0 | Prototype in Python: settle the semantics | **done** — 0.1–0.7 |
| 1 | Trusted proof-checking kernel | **done** — kernel in Witness, [reviewed](../kernel/REVIEW.md) |
| 2 | Self-hosted compiler with its own backends | **in progress** |
| 3 | Verified backend: proof chain to machine code | not started |
| 4 | Platform: ML, scale range, concurrency runtime, fleet | not started |
| H | Optional hardening against trusting-trust | not started |

---

## Phase 0 — prototype (Python) — done

Purpose: settle semantics cheaply. Disposable by design. Every language change also
updates [PRIMER.md](PRIMER.md); its examples are checked by the test suite.

What the prototype settled, and how it is held in place: the language is written down in
[SPEC.md](SPEC.md), every rule it names is mapped to the core calculus the Phase 1 kernel
will check, and [`conformance/`](../conformance) states as data what any implementation
must do with 82 programs — with a test that fails if a rule has no case. Phase 1 starts
from the specification, not from this code.

### 0.1 Foundations — done

- [x] S-expression encoding of the tree; parser with positions
- [x] Nominal types; newtypes as units; no implicit conversion; no null
- [x] Information-flow labels; propagation through values, `if` and `match`; sinks;
      signature-declared `declassify`
- [x] Effects in signatures; undeclared is an error, unused a warning
- [x] Exhaustive `match` without wildcards
- [x] Rule-tagged diagnostics with fixes; `--json`
- [x] Content hashing (Merkle, name-independent, SCC groups) and a local object store
- [x] Tree-walking interpreter; effects granted by the host as capabilities
- [x] Human audit view
- [x] AI primer, test-verified

### 0.2 Core language — done

- [x] Effects under labelled branches rejected (program-counter labels)
- [x] Records: `make` (every field, declaration order), `get`, `with`
- [x] Generic enums with inferred type arguments; labels inside type arguments
- [x] `Option` and `Result` in a prelude

### 0.3 Core language — done, bar one item deferred on purpose

- [x] Prover decided: a built-in decision procedure for quantifier-free linear integer
      arithmetic, not z3 — no dependencies, and its steps are what the Phase 1 kernel
      will re-check ([DESIGN.md §6.1](DESIGN.md#61-why-the-prover-is-built-in-not-z3))
- [x] Contracts: `requires` / `ensures` on functions, discharged statically; pure and
      erased, part of a definition's hash
- [x] Termination checking: every recursive cycle needs a measure that falls —
      structural (a `match` binder of a parameter) or numeric (an `Int` above zero at
      the call); positions may differ around a mutual cycle
- [x] Generic functions: `(fn (unwrap_or T) ...)`, type arguments inferred at each call,
      rigid inside the body; type parameter names are not part of the hash
- [x] Label polymorphism: one label parameter per function, `(fn (shout (label L)) ...)`,
      solved from the arguments (joining when several positions share it) and rigid
      inside the body; its name is not part of the hash
- [ ] Effect polymorphism — **deferred, not skipped.** It varies a function's effects
      with those of a function it is given, and Stage 0 has no function values, so every
      call's effects are already known exactly. Revisit only if functions become values;
      until then an effect-polymorphic signature would have nothing to range over.
- [x] Error context: prelude `Fault` (op, why, cause) with `fault` to start a chain and
      `context` to add a layer — an ordinary generic prelude function, not new syntax.
      Needed a second thing: a record field now counts as structural descent, so walking
      a cause chain terminates without an annotation
- [x] Checked fixed-width integers (`I8`…`I64`, `U8`…`U64`): `+ - *` carry an
      `[overflow]` obligation discharged by the prover, with a value's type as a range
      fact; `wrap.*` and `sat.*` name the alternatives; conversions are explicit both
      ways (`int.of` widens freely, `u8.of` must be proved). Needed a side table of
      checked expression types — Stage 0's stand-in for monomorphisation, and how the
      interpreter knows the width to wrap at
- [x] `Str` distinct from `Bytes`: `str.encode` is total, `bytes.decode` answers
      `(Result Str Fault)`; lengths are unit-tagged by the prelude newtypes `Chars` and
      `Octets`, which stay opaque like any newtype (unwrap to compute). `str.len` is
      gone: it did not say which unit it counted
- [x] Time types: `Instant` (monotonic), `WallTime` (UTC), `Ticks` (device counter) and
      `Duration`, all prelude newtypes over `I64` nanoseconds; `clock.now` returns an
      `Instant`, `clock.wall` and `clock.ticks` read the other two, and a `Duration` is
      only a difference within one clock. `Ticks` → `Duration` awaits division
- [x] Interpreter: the ~150-call recursion limit is gone. `eval` is a work list with its
      control stack on the heap, so depth is bounded by memory (millions of calls) and a
      tail call reuses its own entry; a ceiling turns a runaway into a clear error

### 0.4 Data at the edges — done

- [x] Record schemas: `(schema Name Version)` on a record; consecutive versions must be
      able to read and be read by each other — optional fields may be added, already
      optional ones dropped, and a field's type never changes. Schema and version are
      part of the record's hash
- [x] Partial update vs full replace as distinct types: `(patch P R)` declares a record
      of `R`'s fields each one `Option` deeper, and `(update r p)` is the only way to
      apply one. A patch cannot be passed where the whole record is wanted
- [x] Refinement types validated once at ingress: `(newtype Port U16 (requires n ...))`,
      proved where a value is built and then free as a fact everywhere the type appears
- [x] `foreign` declarations: no body, the `Foreign` effect on every call, an
      `Unverified` label on the result, and an implementation only if the host hands one
      over. A foreign name is part of its identity, unlike a Witness function's
- [x] Per-label redaction policies for structured log fields: `(redact Secret hidden)`
      and `(log.fields (name value)...)`. A labelled value reaches a log line only
      through a declared policy, the strictest of a value's labels wins, the redacted
      form is built at the sink so the raw value never arrives — and the policy is part
      of the function's hash, since the same body under a different policy logs something
      else

### 0.5 Platform semantics (checker and interpreter only; no real backends) — done

- [x] `Alloc` effect: performed by building a value whose size its type does not fix
      (`concat`, `num.to_str`, `str.encode`, …). A record or variant is fixed-size, so
      its placement stays the compiler's business and costs no effect
- [x] Target profiles as effect sets: `check --profile host|embedded|mcu`, where a
      definition fits a profile exactly when its declared effects do. Not dialects —
      the code is identical. The interpreter always has a heap, so `Alloc` is enforced
      at check time, which is where a profile lives
- [x] Resource bounds in contracts: `(bounds (depth N) (alloc N) (repeats N))`, proved
      by a static cost pass — allocations add along a path and take the worst of
      branches, depth and allocation flow through the call graph, and a recursion is
      counted by having the prover bound its measure. Mandatory on `mcu`. A structural
      measure carries no number, so recursion over data terminates without being bounded
- [x] Structured tasks with parents and deadlines: `(scope ((name work (deadline d)
      (on-fail p))...) body)`. A parent waits for its children, a task's work must be a
      `(Result T Fault)` so a policy has something to act on, and the body must be able
      to carry an escalation. Cancelling a *running* task from outside needs a scheduler
      and is not in Phase 0; a deadline is the limit that is checkable here
- [x] Placement: one task model, four distances — `(on inline|thread|core|process|node)`
      on a branch or a task, defaulting to `core`, so `par` is **multi-core by default**
      (shared address space, immutable values, nothing copied). `process` and `node` have
      memory of their own, so everything crossing must have a wire form — the same rule
      channels use. A profile says how far work may go (`mcu` only `inline`), and work
      placed elsewhere costs this target's resource bounds nothing
- [x] Deterministic `par` / fork-join and a `Nondet` effect: `(par ((name work)...) body)`
      is deterministic because values are immutable — a data race cannot be written — so
      the only order-sensitive thing left is an effect in a branch, and that needs
      `(uses Nondet)`. `Alloc` is exempt: an allocator is not an observer. Reductions
      wait on a sequence type
- [x] Data-race freedom by type: every value is immutable, so sharing across a task
      boundary is safe by construction and ownership transfer has nothing to protect.
      Shared *mutable* state does not exist in Phase 0, so the explicit synchronised
      type DESIGN calls for has nothing to guard yet — revisit with mutation
- [x] Typed, schema-checked, labelled channels: `(channel Readings Update (accepts
      tenant:acme))`, with `(send C v)` / `(recv C)` under an `Ipc` effect. The payload
      must declare a wire schema, sending data labelled beyond `accepts` is a
      `label-flow` error **at the sender**, and what arrives carries exactly the labels
      the channel admits
- [x] Supervision policies: `fail`, `escalate` and `restart N` on every task, with no
      default — a task with no policy does not parse. Restarts are counted in the
      resource bound. Liveness as a *cadence* contract needs a scheduler, so a deadline
      and its failure are what Phase 0 checks
- [x] Fixed-format numerics: `F16`, `BF16` and `F32` as separate types with the layout
      their names say, strict IEEE rounding (to nearest even, once per operation, no
      reassociation or wider intermediates, so results reproduce on every target), and a
      `Real` literal type that has no format until one is named for it. `num.div` answers
      an `Option`, so no NaN and no remainder. Floats are opaque to the prover, since
      rounding is not linear. Fixed-point (`Q15`) is not in: it is an integer with a
      stated scale and needs no new machinery
- [x] `Tensor` with static named shapes: element format and named axes are part of the
      type, `tensor.add` needs one shape and `tensor.matmul` contracts the last axis of
      the left with the first of the right **by name as well as size**, so a transposed
      weight matrix is a `shape` error. Quantised tensors, autodiff and reshaping are
      not in; a tensor arrives from `foreign` code or a model
- [x] `ModelOutput` label and models as hashed values: `(model Name (input T) (output T)
      (trained-on Label...) (device d) (weights "wtn:..."))`. An inference's answer
      carries `ModelOutput`, the labels of its input, and the labels its training data
      carried, so prompt injection is an information-flow error and releasing a model's
      answer is a signature-visible declassify. The weights hash is part of the model's
      identity. Differential privacy as budgeted declassification is not in
- [x] Accelerator effects: `Gpu` and `Npu`, taken from the model's `device`, so code
      that needs an accelerator says so and a profile may refuse it. The host supplies
      the weights, and an inference is journalled like any other effect
- [x] Effect journaling: `run --record` writes every effect and what it answered;
      `run --replay` answers each from the journal **without performing it again**, so a
      recorded run reproduces exactly (clock and environment included) and a workflow
      resumes rather than redoes. A mismatched or exhausted journal is refused. `Store`
      is durable key-value state whose put is one assignment
- [x] Trace IDs that follow the task tree: every structured log line starts with the
      position of the task that wrote it (`trace=1.2.1`), appended by each `par` branch
      and `scope` task. No signature mentions it and nothing passes it along

### 0.6 Codebase and tooling — done

- [x] Hash-addressed store as the primary codebase; text becomes import/export.
      `witness store` imports a module; `witness export` hands a whole module back;
      `witness codebase` lists what it holds and prints the manifest. Three layers, and
      only the first is identity: `objects/<hash>.json` is the definition, so two files
      that say the same thing land on the same object and a rename touches nothing but
      `names/<module>.json`; `text/<module>/<name>.wtn` is the readable layer. Every
      example round-trips **byte for byte**, and what comes out is canonical even when
      what went in was not
- [x] Lossless round-trip between the store and the audit view. Store ↔ *text* is
      byte-for-byte; view ↔ source comes back with **every definition's hash unchanged**,
      for every example and for every construct in the language (`witness read`). Writing
      the parser found a real defect it was meant to find: the view rendered
      `(seq (let x v b) c)` and `(let x v (seq b c))` — two definitions with *different
      hashes* — identically, so an auditor could not tell which one they were approving.
      A binding's body is now indented, which puts its scope on the page. It also forced
      one language restriction: a binding may not be named after a group of builtins, or
      `str.chars` reads two ways. Comments are not part of a definition and the view
      never showed them; they live in the store's text layer
- [x] Formatter: `witness fmt` gives a tree exactly one spelling, so a diff shows
      meaning rather than layout. It formats the reader's tree, so it works on anything
      that parses; a module is always one group per declaration and a signature's
      clauses always stand on their own lines. Comments on their own line are kept with
      what follows; one sharing a line with code has no canonical place, so it is
      reported and nothing is rewritten. Every example is canonical, and formatting
      leaves every content hash unchanged
- [x] `witness test` with property and snapshot tests: `(test ...)` holds once,
      `(property ...)` holds for inputs made up from a seed taken from its own name (so
      a failure reproduces and names the input), `(snapshot ...)` must still say what it
      said. All three are pure. A `requires` that nothing satisfies is a failure, not a
      pass. `--update` writes down what a snapshot says now
- [x] Package format: a manifest beside the names, listing every definition by hash and
      what a host must provide before any of it runs — effects, placements, released
      labels, foreign implementations, model weights by hash, and channels

### 0.7 Specification freeze — exit criteria

- [x] Written language specification: [SPEC.md](SPEC.md) — lexical structure, the whole
      grammar, static semantics (types, labels and the flow rule, effects, polymorphism,
      contracts, termination, bounds, profiles, redaction), dynamic semantics, the
      canonical form and what is *not* part of identity. Precise about **what** is
      checked and about every rule identifier; the judgement *forms* are given but not
      yet every rule as a formal derivation — that arrives with the Phase 1 kernel's
      logic. §10 lists what it deliberately leaves unfixed
- [x] Core calculus fixed: [SPEC.md §9.1](SPEC.md) — terms, types, the five judgement
      forms, and how each surface construct elaborates. `fork`, `supervise`, `chan` and
      `run` are core forms, because their meaning is primitive and cannot be desugared
- [x] Every checker rule mapped to a rule of the core calculus:
      [SPEC.md §9.2](SPEC.md) maps all 53, and a test fails if a rule is unmapped or the
      map invents one
- [x] Conformance suite, independent of the Python code:
      [`conformance/`](../conformance) holds 80 programs and a manifest saying, for each,
      whether it is accepted, accepted with warnings, or rejected, and exactly which
      rules it must report. Every one of the 53 rules is exercised, and a test fails if
      any is not. `witness conform` runs it; any implementation can, from the data alone

---

## Phase 1 — trusted kernel — done

A small proof-checking kernel (the de Bruijn criterion: a few hundred lines that check
everything else), written in a Witness subset and compiled by Phase 0. The format and
the logic are decided and written down in [EVIDENCE.md](EVIDENCE.md).

- [x] Define the evidence format: an obligation is assumptions and a goal; a proof is one
      reason per case of the goal's negation — either a boolean atom held both ways, or a
      sequence of positive combinations and integer roundings reaching `k <= 0` with
      k > 0. A certificate carries only the *plan*: the kernel recomputes every derived
      constraint, so a forged one has nowhere to hide. Derivations for the syntactic
      judgements have a format too ([EVIDENCE.md §3](EVIDENCE.md)) but no checker yet
- [x] Chose the kernel's logic, and it is **not** dependent type theory. Writing the
      language down showed the 53 rules split in two: syntactic judgements, each a
      decidable relation needing only a derivation checker, and arithmetic obligations,
      every one of which is quantifier-free linear integer unsatisfiability. That has a
      classical tiny certificate. Dependent types buy nothing here and cost the review
      the kernel exists for; they come back when contracts can quantify (which needs
      sequences) or when Phase 3 asks for "this pass preserves meaning"
      ([EVIDENCE.md §1](EVIDENCE.md) records the reasoning and what would change it)
- [x] Contract proofs are kernel-checked terms for the arithmetic half: the prover emits
      its reasons and [certificate.py](../witness/certificate.py) re-checks them sharing
      none of its search. `witness evidence` runs it, and every obligation across the
      corpus checks. An obligation is a *list* of hypotheses in the order they were
      learned — each either read off the term or proved from the ones before it — so a
      kernel replays it and nothing is used before it is established
- [x] Phase 0 emits derivations for the syntactic judgements, one per function, and a
      kernel checks them: nineteen rules, no inference, no search, Γ and the
      program-counter labels carried by the kernel itself
      ([EVIDENCE.md §3](EVIDENCE.md)). Every function in the examples and the
      conformance suite, the prelude's included — 217 of them — has a derivation the
      kernel accepts, and every
      rule is exercised. It found a checker bug four hundred tests had not: where two
      arguments share a type parameter, the wrong variable was being rebound, so a type
      stayed undecided. The program was right; the *reasoning* was not
- [x] The kernel judges a module whole, not just its function bodies: schema
      compatibility version by version, a channel's payload having a wire form, model
      input and output shapes and weights named by hash, redaction policies, a target's
      effects and the places it can put work, what may cross to memory of its own, and
      the inputs a property can be generated for. Resource bounds are **recomputed** from
      the core term — a frame per call, an allocation per operation that builds something
      whose size is not known in advance, a task on another machine spending another
      machine's stack. The one number the kernel cannot count is how often a recursion
      repeats, because that rests on the termination measure: it is taken as claimed, and
      the certificate checker replays the obligation behind it. Every module in the
      corpus, under every profile it checks for, is accepted whole
- [x] The arithmetic kernel is written in the Witness subset and runs under the Phase 0
      interpreter ([kernel/arith.wtn](../kernel/arith.wtn)). It has no entry point and
      performs nothing but `Alloc`, so nothing can tell it what to conclude; it shares no
      code with `certificate.py`; and on all 95 obligations the corpus discharges the two
      agree exactly, with every tampered plan refused. Writing it needed no new language
      feature — a cons list is a generic recursive enum, and walking one terminates
      structurally — but it did change the format: the `Tighten` step now carries its
      divisor, because a gcd's recursion cannot be proved to terminate in Witness, and
      checking a given divisor is a division where finding the greatest one is a gcd.
      It found two defects in the toolchain, both in how it reached a right answer: the
      prover was guarding facts that hold in every branch, which doubled the cases in the
      normal form for each literal and lost provable goals; and the audit view rendered a
      multi-line `if` that `witness read` could not read back
      ([EVIDENCE.md §5](EVIDENCE.md))
- [x] The derivation half in Witness ([kernel/core.wtn](../kernel/core.wtn)): the core
      term, the module's declarations and the scope as Witness data, and the rules as
      functions over them. It agrees with the Python kernel on every derivation in the
      corpus and refuses every tampered one. Its shape was
      forced by the termination checker and is better for it: because a derivation states
      its type and effects at every node, each rule's conditions can be checked from the
      node and the *claims* of its premises, so `local` is twelve rules that recurse into
      nothing and `descend` is the only recursion there is. It found a third toolchain
      defect: the audit view could not read back a call written over several lines when an
      argument of it also ran over several lines ([EVIDENCE.md §5](EVIDENCE.md))
- [x] Both kernels agree on what to **refuse**, not only on what to accept: random damage
      to real derivations and real proofs, answered by both, must give the same answer.
      That found a missing check in the Witness derivation kernel, which had `check` but
      no `judge` and so never compared the body with the signature; and it found that nine
      rules of the Python kernel *crashed* rather than rejecting when a derivation's detail
      did not match its rule. A kernel may accept or reject; a crash is a third answer it
      must not have. Every rule now reads its detail through one check that names the
      shape it needs, and a test wrecks every derivation in the corpus eight ways to hold
      that nothing else ever comes back ([EVIDENCE.md §5.3](EVIDENCE.md))
- [x] `prim`, with the 56 primitive signatures of SPEC 6.3 as Witness data — they are
      part of the language, not of a program, so the kernel carries them itself. Two
      copies of §6.3 drift, so a test has the Witness table render every signature
      through the interpreter and compares that with the table `test_spec.py` holds to
      the specification. 189 of the 208 derivations are now judged by both kernels
- [x] The last eight rules, all of them reaching outside a value: `fork`, `supervise`,
      `send`, `recv`, `run`, `tensor`, `outside`, `logfields`. **All twenty-one rules are
      now judged by a kernel written in Witness**, and all 208 derivations in the corpus
      are accepted by it, agreeing with the Python kernel every time. Two things had to
      give: whether a value can cross into memory of its own is decided by following
      declarations rather than structure, so nothing gets smaller and that walk is given
      a budget counted from the module's declarations, where running out answers "no";
      and the termination checker was skipping its search entirely above a cap, so a
      seven-function mutual cycle got no measure *attempted*. It now tries the integer
      positions first, where a numeric measure can live
      ([EVIDENCE.md §5](EVIDENCE.md))
- [x] The declaration judgements in Witness ([kernel/decls.wtn](../kernel/decls.wtn)):
      type references, enums with variants, newtypes not wrapping something labelled,
      wire versions counted from one, patches of records that are not patches, channels
      carrying something with a wire schema, model shapes and weights named by hash,
      redaction policies, a property's inputs, every effect being one the target provides,
      and each version of a schema reading the one before it. All 48 modules in the corpus
      pass, and each condition's refusal is tested one at a time. It is deliberately
      stricter than Phase 0 in two places, both in the direction that only loses a
      program: field types are compared as written rather than resolved, and a target it
      has never heard of provides nothing. A separate module from core.wtn because a
      Witness module imports nothing ([EVIDENCE.md §5.2](EVIDENCE.md))
- [x] The arithmetic kernel in Witness replays a **whole** obligation, not only its goal:
      the hypothesis list in the order it was learned, each proved hypothesis established
      from the ones before it, and the product lemma checked at every use. It had only
      `follows` before, which took the hypotheses as given -- so "all of §2" was an
      overclaim until now. All 95 obligations agree with `certificate.discharges`, and a
      product lemma aimed at an atom the obligation does not call a product is refused
- [x] The resource bounds in Witness ([kernel/costs.wtn](../kernel/costs.wtn)): the cost
      walk redone from the core terms. Working the strongly connected components out
      inside a kernel would need a closure, a condensation and a topological sort, none of
      which has anything smaller to recurse on -- so the evidence carries a **rank** per
      function instead, and the kernel checks at every call site that the callee ranks no
      higher, then costs the ranks in turn from the bottom. A rank holding more than one
      cycle asks for more than is needed, which only loses a program, and the ranking
      Phase 0 emits is the condensation's own order. It found that a restarting task
      repeats what it *builds* and not how deep it goes -- the attempts are one after
      another on the same stack -- which `sweep` in survey.wtn was the only function in
      the corpus able to tell ([EVIDENCE.md §5.3](EVIDENCE.md))
- [x] The termination checker's measure search rebuilt: it was walking the *product* of
      the parameter positions over a cycle's members and giving up above a cap, so a
      seven-function mutual recursion got no measure attempted rather than one rejected.
      It now places a member at a time and checks each call as soon as both ends are
      placed, numbers first
- [x] A kernel step for the product lemma: linear arithmetic cannot see a product, so
      `Product` carries interval bounds across one, and the kernel checks at every use
      that the obligation itself calls that atom a product, that the four factor bounds
      are already established, that each bounds its factor by a constant, and that the
      conclusion is exactly what the corners give. The bounds it rests on are proved
      first. Nothing in the corpus is taken on trust any more
- [x] Conformance suite passes with the kernel as the final judge. Every accepted case is
      judged whole by the kernel. Of the 50 rejected cases, 45 never reach a program at
      all, one the kernel refuses itself, and four are arithmetic obligations that were
      never discharged — there is no proof for a kernel to check, which is the refusal.
      A test enforces exactly those three outcomes and nothing else
- [x] `./build.sh` re-runs every claim the repository makes, in order, and stops at the
      first that does not hold: `phase0` checks, formats, reads the audit view back,
      runs each module's tests, the conformance suite and the toolchain's own tests;
      `phase1` has the kernel judge every module and re-check every proof
- [x] Human line-by-line review of the kernel, recorded in
      [kernel/REVIEW.md](../kernel/REVIEW.md): who read it, when, and the SHA-256 of each
      module as it was read, with what the review covers and what it does not. The
      hashes are checked by the build, so a kernel module edited after the review fails
      until the record is renewed by a person reading the change — a review of text that
      has since been edited is not a review of anything

**Exit criteria:** every Phase 0 check is re-expressed as kernel-checked evidence — done;
the kernel is small enough for line-by-line human review — read, at 2,359 lines across
four modules, which is more than the few hundred EVIDENCE 1 hoped for. The review
happening is the stronger evidence; the number is recorded rather than quietly dropped,
and most of what is over is list and set handling repeated in each module because a
Witness module imports nothing. A module system is Phase 2's work.

---

## Phase 2 — self-hosting — in progress

The Witness compiler written in Witness, with its own backends (no LLVM). Phase 0 is
retired at the end.

**Where it stands.** The exit criteria below are met: the compiler compiles itself to
byte-identical output, and the build is deterministic and content-hashed. What is open is
the rest of the list, and each open item is waiting on something other than effort:

- *Xtensa backend.* **RV32 and Cortex-M are done**
  ([compiler/native_riscv32.wtn](../compiler/native_riscv32.wtn),
  [compiler/native_thumb.wtn](../compiler/native_thumb.wtn), made from the RV64 backend by
  [tools/gen_riscv32.py](../tools/gen_riscv32.py) and [tools/gen_thumb.py](../tools/gen_thumb.py)):
  a 64-bit value is a slot of two registers, so the compiler, runtime and reference counts run
  unchanged, and emulator tests compare them with the interpreter, edge cases of carries,
  shifts, signs and division included. The Cortex-M image is bare metal: fixed RAM places and
  host functions called through fixed addresses a board's support code supplies (the
  Cortex-M3 model in Unicorn answers them). **Xtensa is done too**, for two chips: the
  ESP32 (LX6, [compiler/native_xtensa.wtn](../compiler/native_xtensa.wtn)) and the ESP32-S3
  (LX7, [compiler/native_xtensa_s3.wtn](../compiler/native_xtensa_s3.wtn)), one walk and one
  encoder ([compiler/xtensa.wtn](../compiler/xtensa.wtn)) for two memory maps, made by
  [tools/gen_xtensa.py](../tools/gen_xtensa.py) from a table of where each chip's RAM is. On
  the S3, SRAM1 is instruction RAM and data RAM at once, so the code takes its first 128 KiB
  and the data the rest, with SRAM2. Each image is run on Espressif's QEMU, on its own chip's
  core model, with
  a small board loaded beside it that answers the host functions through the simulator's
  calls. Xtensa has no flags, so a carry is an unsigned comparison, and a 64-bit shift is the
  funnel shift `src`. Calls are `call0`, the convention without register windows: a0 is saved
  in the frame like Thumb's lr, so there is no window to overflow and the frame is Thumb's 16
  bytes; every function is padded to start on a word, as `call0` needs, and the data image is
  copied a word at a time, since instruction RAM cannot be read in bytes. The chips' RAM is
  what the layouts fit (320 KiB of data on the ESP32, 352 KiB on the S3), so the deepest test
  recursion is 1000, not Cortex-M's 3000.
  QEMU does not trap a word access off a word boundary, which the ESP32 does; the same
  programs, as Cortex-M images, make none (counted in Unicorn), but that is evidence for those
  programs, not a proof for every one. Writing it found two bugs in shared code: a `U64` from
  2^63 up compared as negative, in every target (lower_ir.wtn); and the resolver renamed a
  spliced text by every name any module had for its dependencies, so one module's `mem` could
  turn another's `r2` into a different definition (witness/resolve.py). Reviewing it found a
  third, in both bare-metal images: the runtime counts on memory it has not written reading as
  zero, as a wasm module's does (the free lists' table is allocated and never cleared), and
  RAM after reset holds anything. The emulators map zeroed RAM, which hid it; the start code
  now clears the wasm memory and the operand stack first, and every Cortex-M and ESP32 test
  runs on RAM filled with 0xA5. An ESP32 image larger than the 128 KiB of instruction RAM,
  which is also the reach of its jumps, is refused.
- *Proven stack and heap bounds in bytes* are done for the Cortex-M image (below): the frame
  sizes are read off the compiled module, and a recursion is bounded by the depth the
  checker proved of it.
- *The `esp32` profile* has its effects decided (`Alloc Clock Log Net`, placement up to
  `inline thread core`, bounds required: SPEC 5.13, in the checker, the kernel and
  compiler/effects.wtn) and its stacks bounded on both Xtensa layouts; what it still lacks
  is a bound for a heap that grows (below).
- *The IR* now reads generic functions (a call names `id@Int`, the types it was called with,
  and each copy is read with them in place of the parameters, so what it owns is known) and
  arrays (a counted block: the length, then the elements; one that holds counted values has
  the top bit of its mask set, and the runtime releases every word after the length). It reads
  every function of the compiler (fixed widths, Bytes, `with`, `bytes.decode` as rtlib's check,
  the prelude's `fault`), and **the compiler compiled through it compiles itself to stage 1's
  bytes** while freeing what it no longer holds: about 30 MB of heap for the self-compile,
  where the tree backend's never-freed run takes 59 MB ([tools/irc.js](../tools/irc.js) prints
  it). **It is now the road the driver takes**: `drive` and every native entry read the IR's
  module, which imports only the host functions the program uses (`log`, the clocks and the
  time arithmetic are read too; `store.get`, `net.send` and `env.secret` are not yet), and
  `witness bootstrap` is a fixpoint through it, natively too. A self-call in tail position
  is a jump, and the deeper non-tail recursion of the reader wants node's stack at 200000.
  `lower.wtn` stays: the IR reuses its tables and helpers, and its own tests still run.
- *The front end in Witness* lacks several contract forms (`effect-under-label` for `match`,
  the wire-form half of `placement`, termination and resource bounds are done); **Retire Phase 0**
  cannot happen before it does, and deleting the prototype is not something to do unasked.

Starting it found that **none of it was possible**, and not for want of effort. Nothing
could look inside a `Str` or a `Bytes`: the complete set of primitives that touched text
was build, compare, measure and convert. There was no way to get the nth byte, no way to
make a byte from a number. So no reader, no hashing, no audit-view reader, and no backend
that has to emit bytes — every item below was blocked behind three missing primitives.

- [x] Reading bytes: `bytes.at` for the nth one, `bytes.slice` for a run of them,
      `bytes.of` to build one from a number. All three total, so none carries an
      obligation. **Nothing was added to `Str`**, deliberately: `Str` stays opaque, which
      is what makes "a `Str` is valid UTF-8" true rather than hoped for, so a reader works
      in `Bytes` and decodes once at the end (SPEC 4.1, 6.3)
- [x] A tokeniser for the surface syntax, written in Witness and run by Phase 0
      ([compiler/reader.wtn](../compiler/reader.wtn)): parens, words, numbers, quoted
      strings with escapes, comments to end of line. It needed one thing the language had
      not asked for before — a walk over a sequence has no structure to recurse on, so
      every scan carries a **budget** that falls at each step. That is now in the primer
- [x] `(Array T)`, a sequence read by position: `array.len`, `array.at`, `array.empty`,
      `array.push`. A **value** — pushing answers a new array rather than changing the one
      given, so an array never has two owners. Reading is total, so no obligation stands
      between a program and an element, and an index is a `Count`, a unit rather than a
      bare `Int`. The monomorphic builtin table cannot express it, since what each
      operation answers depends on what the array holds, so it is typed by a rule of its
      own in the checker and judged by a rule of its own in both kernels — and an array
      is the one primitive whose crossing into other memory is not settled by its own
      name, because it is only as transferable as what it holds
- [x] Bitwise operations: `bit.and`, `bit.or`, `bit.xor`, `bit.not`, `bit.shl`,
      `bit.shr`. There were none at all before, so content hashing — which the project's
      identity rests on, since hashes are identity — could not be written in Witness.
      **Fixed widths only**: `Int` is unbounded, so it has no complement and no top bit
      for a shift to fall off, and giving those a meaning would mean a width nobody wrote
      down. All total, so none carries an obligation; a shift count is a plain `Int`
      because it counts positions rather than being a value of the width, and a count at
      or past the width shifts everything out rather than raising a proof obligation.
      `bit.shr` is a *logical* shift, because these are operations on a bit pattern — on
      a signed width the sign bit moves along like any other
- [x] **SHA-256 in Witness** ([compiler/sha256.wtn](../compiler/sha256.wtn)): the proof
      that hashing is now expressible. 51 definitions, 114 obligations proved, the FIPS
      180-4 vectors as propositions the module states about itself, and every function
      proved to terminate — a hash is a fixed number of rounds over a budget and the
      checker knows it. Nothing a digest depends on touches a clock, a store or the
      network, so the same bytes give the same digest wherever it runs
- [x] A parser over the tokens ([compiler/parse.wtn](../compiler/parse.wtn)): one token
      list to one tree, refusing an unclosed form, a stray close, an empty source and a
      second form, with a `(fn name (params) ret body)` reading above it. `parse` itself
      declares **no effects at all** — records and variants are fixed-size, so only
      cutting bytes out and building text allocate, which means the parser is something
      the `mcu` profile would accept
- [ ] Two findings from writing the parser, both worth acting on. A `match` on a
      five-variant enum asserts all ten pairwise exclusions as disjunctions, and nested
      inside another such match that is past the prover's disjunct cap — so a budget
      proof that shares no atom with any of them is reported as *unproven arithmetic*,
      and the repair is somewhere else entirely. Cheap relevance filtering of assumptions
      would discharge it instantly. ~~And `unused-effect` is blind to a declaration that
      only its own recursive call justifies~~ (done: a function on a cycle of calls is
      asked what the cycle performs other than by calling itself -- every member reaches
      every other, so that is one set for the group -- in the Python checker and in
      [compiler/effects.wtn](../compiler/effects.wtn) alike, with a conformance case; it
      found `largest` in examples/sequence.wtn declaring an `Alloc` nothing performs, and
      `names_union` in kernel/core.wtn doing the same, which waits for the kernel's next review).
      Neither can make an undeclared effect slip through, so both are diagnostic quality
      rather than soundness — but the first one costs an afternoon when it bites. The
      relevance filter is not a change to the search alone: the evidence states which
      assumptions an obligation rests on, and a derived fact's own reason is a case split
      over every fact before it, so dropping facts means restating those reasons too
- [x] Content-addressed imports: `(use "wtn:..." as name)`, resolved through the codebase
      store (SPEC 3.9). What is depended on is the **hash**; the name is local, which is
      why it sits on the left of `as` and the hash is written out in full in the audit
      view. Resolution is *splicing*: the definition and the closure of what it is built
      out of become declarations of the importing module before anything else looks at it,
      so a dependency is checked exactly as the code around it is, every time, rather than
      trusted for where it came from — and the checker, the prover, the interpreter, the
      view and all four kernel modules needed no notion of a module boundary at all.
      The property that makes it coherent: a definition imported under another name hashes
      to the object it already was, because a name is not identity, so the importing
      module's hash records its dependency with nothing extra written down and there is no
      lock file that can disagree with the code. Definitions come in one at a time, since
      a module does not export — the codebase holds definitions and a module writes some
      of them down
- [x] Named imports, pinned to hashes: `(use text.reverse as rev)` is accepted by the
      parser and refused by the checker as `[unpinned-import]`, whose message names the
      hash it would pin to; `witness pin f.wtn` rewrites those lines to the hash form in
      place, all or nothing. Chosen over whole-module exports and over file-path imports
      because it adds no notion of a module boundary anywhere downstream — the checker,
      prover, interpreter, kernels and WASM compiler still only ever see spliced
      definitions — and no lock file, since the pinned source *is* the lock. What it does
      not do: there are still no exports, no namespaces and no import of a whole module;
      each definition is asked for by name, one at a time.
- [x] Imports used in anger, which is the only way to find out whether they work. The
      parser had copied the tokeniser wholesale — 19 definitions, all hash-identical, the
      duplication imports exist to remove — and now names three of them by hash and lets
      the closure bring the rest. It shook out two things the single-definition test could
      not: a closure reaches **prelude** definitions, which need nothing done about them
      because every module already has them and the store rightly keeps no text for one;
      and it reaches **group** objects, the single identity a mutually recursive cycle
      hashes to, which have no name and no text of their own — so the resolver looks the
      other way down that edge and brings every member of a cycle, because a cycle
      arrives whole or not at all. `build.sh` now stores what is depended on as its first
      step, which is what building means for a content-addressed codebase: put the
      definitions in, then check what is written against them
- [x] The Phase 2 checker will share the Phase 1 kernel's notion of a type rather than
      keep a second copy: `kernel/core.wtn` is in the codebase and its `ty_fits` imports
      cleanly, bringing `Ty`, `Tys`, `Dims`, `Names` and its mutually recursive partner
      with it — nine objects. That is the arrangement the front end gets built in, and it
      is what imports were for: one notion of a type, by hash, rather than two that drift.
      Importing it found a resolver bug nothing smaller could: a rename has to be applied
      over the **whole spliced set**, not inside the renamed declaration, because another
      imported definition may call it — and a mutually recursive group certainly does
- [x] The checker's first piece ([compiler/typecheck.wtn](../compiler/typecheck.wtn)):
      reading a type out of source. It starts here because everything else in a checker
      needs it, and it **declares no type of its own** — `Ty` and `ty_fits` come in from
      `kernel/core.wtn` by hash and the tree from `compiler/parse.wtn`, so the Phase 2
      checker and the Phase 1 kernel share one notion of a type, verified by a test to be
      the same objects. Storing it found that the **store** did not know about imports: it
      paired each definition's text with the *resolved* module's declarations, so a module
      with three imports put every definition's text under another definition's name, and
      claimed in its own name listing to have written its dependencies. What is stored is
      now what the source declares
- [x] A canonical byte form for a parsed tree and its digest
      ([compiler/digest.wtn](../compiler/digest.wtn)), on top of the Witness SHA-256: a
      marker, then recursively a tag and an eight-byte count before each payload, so the
      encoding is self-delimiting and therefore injective — one tree has one spelling and
      no two share one. Tested against a Python model byte for byte, with the ambiguous
      pairs that matter (`("ab" "")` against `("a" "b")`, `"a"` against `("a")`, `""`
      against `()`), and the digest checked against `hashlib` over the *same* bytes the
      Witness serialiser produced, which is a check of the pipeline rather than of itself.
      It is a hash of the **written** form and **not** `witness/hashing.py`'s
      name-independent hash — rename a parameter and it changes — and a test asserts that
      difference rather than only the module's comments describing it. It is the bottom
      half of the real thing: the same two steps over a different tree, once the checker
      exists to produce one
- [x] **A clash of names is not a clash of dependencies.** Found by trying to import from
      two libraries at once: `compiler/reader.wtn` reverses a token list and
      `compiler/sha256.wtn` reverses a word list, so both closures bring a `reversed`, and
      splicing refused. That was wrong twice over — the name is not what was depended on,
      and `(use ... as ...)` could not fix it, since it names the definition asked for and
      the clash is between definitions *under* it, which nobody chose. One of them now
      takes a name derived from its hash, and a test holds that both land and that
      renaming changed neither. Two imports *explicitly* asking for one alias is still
      refused, because an author wrote both names and only an author can settle it
- [x] The audit view, written in Witness ([compiler/view.wtn](../compiler/view.wtn)):
      calls, operators, field chains, records, updates, log lines, inference, channels,
      and the five forms that need lines — `let`, `seq`, `match`, `if` and broken-open
      calls — with the same indentation rules as `witness/view.py`, including that
      **length is never what breaks a line**: a form breaks only when something inside it
      needs lines of its own. Types too, labels and tensor axes included. The evidence is
      a sweep: every function body and every type in the repository, rendered by both
      writers and compared, with the corpus size asserted first so that a sweep over
      nothing cannot pass. Types agree everywhere; expressions disagree only on
      `par`/`scope`, which `view.py` gives a layout of its own that is declaration-shaped
      and belongs with the signature reader
- [x] Put the **kind of a token** back in the parser's tree. A `Leaf` keeps a token's
      bytes and not whether it was a word, a number or a quoted string, so the view
      writer renders `(f "8080")` as `f(8080)` — it cannot know. Quoting a leaf that
      merely looks like a word would be a guess, so the repair is in `compiler/parse.wtn`,
      not in the writer. Second sighting: it is also why `fn_shape` accepts
      `(fn "f" () Int 1)`. Done: `Leaf` carries `quoted`; the view writer quotes a string
      and `fn_shape` refuses one where a name belongs. The digest ignores the flag, so it
      still agrees with the Python side
- [x] **Third sighting of "every call in a cycle must decrease", and it is now shaping
      code rather than annoying it.** A structural measure is accepted only for an
      argument a `match` took out of a parameter, so a member of a recursive cycle may
      never hand another member a parameter unchanged — which refuses the natural
      decomposition "peel the form, pass the pieces to a handler". `compiler/view.wtn` is
      written as it is because of this: every form handler takes the argument list and
      peels it itself, and the dispatch is one long nested `if` rather than a dispatcher
      and a chooser. The rule is sound and the workaround is honest, but a cycle that
      descends overall should not require every edge to. Done: a call that hands the
      caller's measure on unchanged is accepted if those calls cannot form a cycle among
      themselves, so any endless path must still shrink infinitely often. `view.wtn` has
      not been rewritten to the shape it wanted; that is the follow-up
- [x] The declaration environment ([compiler/env.wtn](../compiler/env.wtn)): what a
      module declares and what each signature is, as three association lists, since there
      is no map. It reads generic and label-parameter names too — `(fn (unwrap_or T) ...)`
      — because without `type_params` nothing downstream could tell a rigid parameter from
      an undeclared type, `type_of` recording a written `T` exactly as it records `Int`.
      A duplicate name is refused, naming it; forms it does not read are left alone rather
      than turned away, since a pass that refused them could not run on a real module. The
      evidence is agreement with the **Python checker** — every function in order, every
      enum, every newtype, for 19 examples plus `compiler/reader.wtn` — which is a
      different reader, a different declaration pass and a different representation
      reaching the same answer
- [x] **`type_of` does not read `(label L T)` or `(tensor F (axis N) ...)`**, which is
      what the environment found and the one thing blocking the next piece. The kernel's
      `Ty` has `labels` and `dims`; `compiler/typecheck.wtn` records what was *written*,
      so both forms arrive as applied types with base `label` or `tensor`. An environment
      collected today therefore **cannot support an information-flow or shape check** —
      the repair is to extend `type_of`, not to work around it. Two tests pin the current
      behaviour on both sides so the gap stays visible
      Done: both forms are read into the kernel's `labels` and `dims`, shown as `Str @L`
      and `(Tensor F32 (sample 4))`; the two tests that pinned the gap now pin the repair.
      A repeated label collapses, a repeated or non-positive axis is refused, as in Python.
      An information-flow or shape check over an environment is now possible
- [x] **`compiler/parse.wtn`'s `fn_shape` cannot read a real `fn`**: it insists on exactly
      one tree after the result type, so any function carrying `(uses ...)` is refused.
      It is usable only on clause-free definitions, which is nearly none of them
      Done: the last form is the body and everything before it must be a list; the clauses
      are kept in `FnShape` and not yet read, since naming them would cost `fn_body` an
      `Alloc` nothing else there needs
- [x] **The Stage 0 interpreter is too slow to self-host on, measured rather than
      guessed**: collecting an environment takes 1.1s for a 1.5KB module, 5s for 6KB, 19s
      for `kernel/arith.wtn` at 23KB and **77s** for `kernel/core.wtn` at 86KB. The parse
      budget is `2 + 2*tokens` and each step re-matches. This is the concrete reason the
      Wasm backend is the gate on everything after it, and it already shaped the
      environment's design — one reading that answers many questions, rather than one per
      question
      Done: [witness/fast.py](../witness/fast.py) translates each function into a Python
      function -- a `let` is an assignment, a `match` an `if` on the variant, a call in tail
      position a `while` -- and runs it on a thread with a large stack. The values and every
      primitive are the machine's own, so the two cannot disagree about what a program
      means, and [tests/test_fast.py](../tests/test_fast.py) runs both over the corpus to
      check. Reading `kernel/core.wtn` takes 1.7s rather than 77s; the whole suite went from
      13 minutes to 7. What it does not translate -- tasks, `par`, models, channels,
      structured logging -- stays on the machine, a function at a time
- [x] **A function-level type checker** ([compiler/expr.wtn](../compiler/expr.wtn)): the
      type of every body in a module, against its declared result, with the prelude
      (`Option`, `Result`, `Fault`, the newtypes) as the starting environment. It reads
      literals, names, `if`, `let`, `seq`, `unwrap`, `match` on declared and generic enums
      (no wildcard, every variant once, a binder per field, arms that agree), records
      (`make` in declaration order, `get`, `with`), newtype and variant constructors, calls
      to declared and **generic** functions, and every primitive in the kernel's own table,
      typed from the same `Wants` entries the kernel uses rather than a copy of them. Type
      arguments are found from the arguments by binding, and one nothing settles stays an
      unknown `?` that the place it is used fills in -- the poor man's version of the
      unification variables Python's checker has. Declared types are resolved: unknown names
      and wrong arities are refused. Binders follow Python's rules (lower-case, no builtin
      group, no shadowing). Anything it does not read is turned away *by name* and counted
      as such, never guessed at.

      The evidence is **measured on whole programs, in both directions**
      ([tests/test_expr_corpus.py](../tests/test_expr_corpus.py)). Of the 143 functions in
      `examples/` and the conformance accept and warn cases, **140 are read and accepted,
      3 are refused as not yet read, and none is wrongly rejected** -- that last number
      was 28 on the first run, and the 28 were the work: operators fixed to `Int`, a prelude
      nobody had put in scope, `unwrap` on the primitives' newtypes, generic enums. The
      count read outright is pinned from below. In the other direction every conformance
      program Python rejects for a *type-level* rule (22 rules) has at least one function
      the typer rejects. Beside that, 153 chosen expressions are compared one at a time with
      the Python checker
      ([tests/test_expr.py](../tests/test_expr.py)). What is still unread is **label parameters**
      (`(fn (f T (label L)) ...)`, 3 functions), which need the label flow worked out
      before a call can be typed. Channels (`send`, `recv`), models (`infer`, whose answers
      carry `ModelOutput` and their training labels), and tasks (`scope`, `par`) are read;
      what a placement may carry across a process boundary is a different pass's rule.
      **Effects** are read off the same walk: a call performs what the function it names
      declares, a primitive what the kernel's table says, and a few forms (`log.fields`,
      `send`/`recv`, `scope`, `infer` by device, `par` with a branch that does more than
      build values) perform something of their own. A body that performs an effect its
      `(uses ...)` does not declare, a `uses` naming no effect, and an undeclared `Nondet`
      are refused, compared with Python's on thirteen written-out cases as well as the
      corpus. `FnSignature` now keeps the `(uses ...)` it was declared with
- [x] Declaration-level rules in Witness ([compiler/decl_rules.wtn](../compiler/decl_rules.wtn)):
      `empty-enum`, `channel-payload`, `schema-version` and `schema-incompatible`, read from
      the tree alone. It imports no environment: the schema is the clause `env.wtn` steps
      over, so keeping it here left the environment, and every module that pins it by hash,
      untouched. `duplicate-definition` was already the environment's refusal of a name
      declared twice. Types in a schema history are compared as written, which agrees with
      Python's resolved comparison because the language has no alias. Evidence
      ([tests/test_decls.py](../tests/test_decls.py)): nothing is reported for any example,
      kernel, compiler or accepted conformance module (the sweep's size asserted first),
      every reject case for one of the four rules is reported for it, and no reject case of
      another rule is
- [x] Label parameters in the expression typer. A call to `(shout (label L))` reads `L` off
      its arguments -- every position that mentions it contributes what the argument carries
      beyond the labels written beside it, and they join, so order decides nothing -- then
      replaces it in the parameters and result and reads the call as any other, type
      parameters included. In the body `L` is an ordinary label, which is what rigid means:
      a value carrying it cannot come back without it. Seven cases agree with Python in both
      directions ([tests/test_expr_corpus.py](../tests/test_expr_corpus.py)), and the
      corpus no longer turns any function away as unread for this
- [x] **The prover's search, in Witness** ([compiler/prove.wtn](../compiler/prove.wtn)):
      Fourier-Motzkin elimination with integer tightening, one case at a time, producing
      the same `Reasons` that [kernel/arith.wtn](../kernel/arith.wtn) replays. The cases
      come from the kernel's own `all_cases`, and `verdict` says "proved" only after the
      kernel's `follows` accepts the reasons -- so a slip in the search can lose a proof and
      cannot make the kernel take a false one, the arrangement Python's prover and
      `certificate.py` already have. A gcd, an elimination order by fewest new constraints,
      and the same 2048-constraint cap. It checked its own termination proofs on the way:
      every loop carries a budget, and the budget is a function with an `ensures`, since the
      prover cannot see through an `if` into a bound it needs. Evidence
      ([tests/test_prove.py](../tests/test_prove.py)): it agrees with Python on whether there
      is a proof for 240 generated formulas (half built to be provable) and for every
      obligation the corpus discharges, and an ``invalid`` verdict, a reason the kernel
      refused, appears nowhere. What remains of contracts is the **translation** -- from a
      body to these formulas -- which is `verify.py`'s 1,100 lines
- [x] **Contracts, first slice** ([compiler/verify.wtn](../compiler/verify.wtn)): the
      translation from a body to the prover's formulas, for functions over `Int` and `Bool`
      -- literals, `+ - *` (one side constant), `< <= =`, `and or not`, `let`, `if`, and
      calls to such functions. A function's `requires` is assumed on entry, a call must
      establish the callee's, a call's `ensures` is a fact after it, and the function's own
      `ensures` must follow from the result. Facts an `if` branch learns are kept guarded by
      its condition; a pure call is named by its arguments, so the same call twice is one
      value, and one with effects is a fresh unknown. Everything else is refused by name as
      "not read yet", and a goal is proved only when the kernel's replay accepts
      ([compiler/prove.wtn](../compiler/prove.wtn)). Evidence
      ([tests/test_verify_wtn.py](../tests/test_verify_wtn.py)): of 184 functions in the
      examples and conformance corpus it reads 129 and agrees with Python's set of unproven
      contract rules on every one; and on 150 generated functions (calls, branches,
      contracts that hold and contracts that do not) it agrees on all, with both proofs and
      refusals in volume.

      **Fixed widths and `overflow`** are in the same module: a parameter, a call's result
      and a conversion are known to sit in their type's range; `+ - *` (one side constant)
      must be proved to fit, and once proved the value may be relied on; `u8.of` and its kin
      must fit, `int.of` widens; `wrap.*` leaves only the range and `sat.add`/`sat.sub` are
      the exact value clamped. A literal has no width of its own, so an operation takes the
      type of whichever operand has one. 120 generated functions over five widths agree with
      Python, a dozen or more of them refused for `overflow`. **Not yet:** the product of
      two unknowns in a fixed width (the product lemma, which the kernel's `ByProduct` step
      is for), records and `match`, termination and resource bounds

      **Refined newtypes** follow the chain to the base type: a parameter or a call's result
      of a refined type is known to satisfy the condition, and a constructor `(Port x)` must
      be proved of `x` (`unproven-precondition`) and answers `x`. That, with `unwrap` and `seq`, moves the corpus to 40
      of 184 functions read, all agreeing, and 200 generated functions over refined and
      chained newtypes agree with Python.

      **Values the prover only sees as names** -- strings, labelled values, the floating
      formats, anything with no structure -- are read too: a value is an atom that equals
      only itself; a primitive on them (from the kernel's own table) is an unknown named by
      its arguments, so the same call twice is one value, with the length facts and the mask
      range the Python verifier has; a string literal is known by its lengths; floating
      arithmetic only gives the same answer for the same operands. A contract that performs
      an effect is refused by name. The corpus is now 83 of 188 functions read, all
      agreeing, and 120 generated string functions agree with Python.

      **Records, enums and `match`** are read from the module's declarations and the
      prelude's. A record built in the function is exact and a known variant takes its arm;
      anything that comes from outside is a name whose fields, tags and binders are named
      after it and carry what their declared types say (a range, a refinement), with the
      value's own type arguments put in for the declaration's parameters. The corpus is now
      129 of 188 functions read, all agreeing, and 160 generated functions over records,
      enums, `Option` and `match` agree with Python. The prover's disjunct cap is what a
      deeply nested `match` runs into -- each opaque `match` multiplies the cases -- so the
      reading is split into small functions. **Not yet:** generic functions, arrays, tasks
      (`scope`/`par`), `update`, effects like `send` and `infer`, termination and resource
      bounds
- [ ] The rest of the front end in Witness: the contract forms listed above as not read
      yet; the verifier now reads tasks (`scope`, `par`), `infer`, `send`, `recv`,
      `log.fields`, `update`, arrays, foreign calls, the prelude's newtypes and generic
      functions, conversions to a float format or to bytes (which keep the value, as Python
      has it), fields of a value whose type it does not read, `unit`, and **the product of
      two unknowns in a fixed width**: each factor is pinned between the tightest constants
      the facts support and the product lies between the four corners, the lemma the
      kernel's `ByProduct` step checks. That is 186 of the corpus's 197 functions, all
      agreeing with Python, and 123 generated products (bounded or not, signed or not, some
      at a width's edge exactly) agree too. The eleven it refuses are programs the checker
      rejects (an unknown name or variant, an arity mismatch, an import that does not
      resolve) and one contract that performs an effect. Comparing them found a soundness
      bug in witness/verify.py: a factor's lower bound was read with its sign flipped, so a
      factor in -16..0 times one in 0..8 was taken to be at least 0. The kernel's replay
      reads the bound correctly and would have refused the evidence, but `witness check`
      alone accepted the false `ensures`; it is fixed, with a test in
      [tests/test_certificate.py](../tests/test_certificate.py). **Resource bounds** are done in the same module: `(bounds (depth N) (alloc N)
      (repeats N))` against a pass through each body (a frame, its deepest call, each
      allocating builtin; a task up to its restarts, work placed with memory of its own
      free) times the repeats the termination measure allows from what is known on entry,
      compared with Python over the corpus and 60 generated recursions. Starting a heap bound
      for the `esp32` profile found the rule unsound in all four places that state it (the
      checker, the Python kernel, kernel/costs.wtn and this module): a cycle's allocations
      were counted once per repeat, which is once per level of nesting, so a body that calls
      itself twice -- 2^n - 1 runs for n -- was accepted with `(alloc n)`. A cycle now builds
      its bodies' allocations once for every time a body can run, 1 + k + ... + k^(n-1) for
      at most k calls back into it on one pass (SPEC 5.11); 40 generated recursions that call
      themselves one to three times agree with Python, and a conformance case of each kind. **Termination** is done in
      [compiler/verify.wtn](../compiler/verify.wtn), as witness/verify.py decides it: the calls
      a body makes are kept with what was known at each, the recursive groups are found from
      the call graph, and one parameter per member is searched for that every call in the
      group lowers (a number still above 0 handed something provably smaller, or a part a
      `match` or field read took apart) or passes on unchanged, the pass-through calls unable
      to go round by themselves. A group with a member it does not read is not read. Compared
      with Python over the corpus and 60 generated groups of one to three functions. The wire-form half of `placement` is done:
      the expression typer asks of what a task or branch placed on another `process` or
      `node` answers that every part of it be a primitive or a record with a schema (an
      array or enum as far as what it holds, a newtype as far as what it wraps), as Python
      does. `effect-under-label` is done for `if` and
      `match` alike: the expression typer reads a match on labelled data (its binders and what
      it answers carry the labels) and refuses an effect in any arm, as Python does.
      Done in [compiler/effects.wtn](../compiler/effects.wtn): `profile-effect` (a definition
      declaring an effect the profile does not provide, `Foreign` implied for a foreign one),
      the `unused-effect` warning (against what the expression typer's own walk says a body
      performs) and the profile half of `placement` (work placed further than the profile
      reaches, `core` unless written otherwise). All three profiles are run over every example
      and conformance case against the Python checker
      ([tests/test_effects_wtn.py](../tests/test_effects_wtn.py)): 309 comparisons, 147 findings,
      identical
      the hashing *of a module* on top of SHA-256
- [x] Decided what the audit view of a module with imports is for: **the module as
      written**, `(use ...)` lines and all. A hash is already a complete reference —
      nothing else can be that hash — so showing one hides nothing, while splicing would
      lose the one line a reviewer needs, between what this module wrote and what it
      took, and would make the view of a module with fifty imports its whole transitive
      closure. "See everything that runs" already has its own mechanism, which is the
      codebase; to read a dependency, view the dependency. `view | read` is the identity
      again, and `--hashes` leaves an import untagged because the hash *is* what it is
      written as
- [ ] Intermediate representation with effects and ownership explicit. **Started**, and
      the next thing the backend wants: [compiler/lower.wtn](../compiler/lower.wtn) goes from
      the tree straight to WebAssembly instructions, so a function's effects and who owns
      what it allocates are not written anywhere a pass could read them. The effects are
      known from the type checker and the ownership is nothing -- memory is never freed
      **Started:** [compiler/ir.wtn](../compiler/ir.wtn) is the form in between, for `Int`,
      `Bool` and `Str` with `let`, `if`, `seq`, arithmetic, `concat`, `num.to_str`, `str.eq`,
      `print` and calls: A-normal form, each primitive and call carrying the effects it
      performs (from the kernel's own table and the callee's `uses`), and ownership written
      out -- a literal, `concat` or a call *allocates*, a call *borrows*, a parameter is
      borrowed from the caller, `let` and `done` *move* unless the value is used again (then
      `retain`), and a `drop` follows the last use on every path. It prints the module as
      s-expressions; [tests/test_ir.py](../tests/test_ir.py) runs those against the interpreter
      on generated modules and counts references: same answers, same output, no use after the
      last drop, nothing left behind but the answer, the lent string untouched. **Records and
      enums** are read too: `make` and constructors allocate and hold a reference to each heap
      field, `get` and the binders of a `match` arm take a reference of their own (so nothing
      dangles when the record is dropped), each arm is its own block, and the runner frees a
      value's fields when its last reference goes. **Generics** are read too, for
      enums: `Option`, `Result` and any `(enum (N T...) ...)` of the module, with a type written
      as text (`(Option Str)`), a constructor's type taken from its arguments (a `?` where
      nothing fixes it, settled by the other branch), and a match binder typed from the
      scrutinee's arguments. **Generic functions** are written out once per set of types they are called with (`id@Int`; the copies a copy calls follow, within a limit), in both `ir.wtn` and `lower_ir.wtn`. **Arrays** too: `array.empty`, `array.push` (a new array, each element held once more), `array.len` and `array.at` (an `Option` holding a reference of its own), with `Count` and its `unwrap` read as the number they are at run time. (Wildcard patterns are not a gap: the language refuses them.) **Not yet:** `lower.wtn` does
      not consume it -- the backend still goes from the tree. **The runtime now counts:**
      `rt_make(n, mask)` answers a block with two header words (a count, and its size and a mask
      of which words hold counted blocks), `rt_retain` adds a reference, `rt_release` takes one
      away and at zero releases what the mask names and puts the block on a list for its size,
      where the next `make` finds it; anything below the heap (static cells and strings) is
      never counted. **And they are called:**
      [compiler/lower_ir.wtn](../compiler/lower_ir.wtn) lowers the IR to WebAssembly -- a record or
      variant is a counted block with its tag and fields and a mask of the counted ones, `retain`
      and `drop` are `rt_retain` and `rt_release`, a literal is a string in static memory, and
      strings made by the runtime are counted too. [tests/test_lower_ir.py](../tests/test_lower_ir.py)
      runs generated modules in node against the interpreter (answers and output) and then
      repeats each call: the heap must not grow, which it does the moment one block is left
      counted (leaving out one `retain` makes it fail). `lower.wtn` itself still goes from the
      tree and allocates without a header
- [x] **WebAssembly backend**, written in Witness and run by Phase 0 and then by itself.
      Three modules: [compiler/emit.wtn](../compiler/emit.wtn) writes the binary format
      (every value an i64, one memory, a heap pointer in a global, imports, static data,
      signed and unsigned LEB128 to 64 bits); [compiler/runtime.wtn](../compiler/runtime.wtn)
      is what WebAssembly does not have, as instructions (allocate, make, concatenate,
      compare, index and slice a string, checked `Int` arithmetic, floor division, decimal
      printing); and [compiler/lower.wtn](../compiler/lower.wtn) walks the program.

      **Representation.** One i64 for everything: a number, a `Bool`, the address of a
      block. That is what lets a generic function and an `Option` of anything share their
      code with no copy per type, and lets a newtype vanish -- `(Seconds 5)` and `(unwrap s)`
      compile to nothing. A variant with fields is `[id][field]...`; one without is the
      address of a shared one-word cell holding its id; a record is its fields in
      declaration order; `Str` and `Bytes` are `[length][bytes]`. `match` reads the id, a
      self call in tail position is a jump, and a width is decided from the type of the
      operand: `wrap.*` is the instruction and then a pull back into the width, a
      comparison is unsigned for `U64` only, and the narrower types are kept sign- or
      zero-extended so that nothing else has to know.

      **`Int` is a 64-bit word that traps on overflow.** This was decided against the
      grain of the plan, and it is worth saying why. The plan was to refuse `Int`
      arithmetic by name and write the compiler against fixed widths. That turned out to
      be impossible without editing the reviewed kernel: the compiler imports six
      list-counting functions from `kernel/core.wtn` whose result is an `Int`, and a
      change there invalidates [kernel/REVIEW.md](../kernel/REVIEW.md), which only a person
      can renew. So `+ - *` on `Int` are the runtime's checked operations: either the
      interpreter's exact answer or a trap, never a wrong number, and nothing needs a
      bignum. A wrapping operation on an `Int` is still refused, as it has no width to
      wrap at. This is one function to change if the other choice is made later.

      **The evidence is that it runs, and runs the same**
      ([tests/test_lower.py](../tests/test_lower.py), [tests/test_runtime_wasm.py](../tests/test_runtime_wasm.py),
      [tests/test_emit.py](../tests/test_emit.py)): programs are accepted by the Python
      checker, compiled, loaded by node, and called over a spread of inputs, and every
      answer is compared with the interpreter's -- arithmetic at every width, enums,
      records, `with`, `match`, strings, `bytes.decode` against Python's decoder on its
      edge cases, floor division, printing, a tail call a hundred thousand times deep.
      What it cannot compile is refused by name with no output: floats, tensors, arrays,
      tasks, channels, models, `log.fields`, `update`.
- [x] **Effects mapped to host-granted Wasm capabilities.** A builtin that performs an
      effect (`print`, `log`, `net.send`, `clock.*`, `env.secret`, `store.put`, `store.get`)
      is an import from a module named for the effect -- `Console.print`, `Net.net.send` --
      and a module imports only the builtins it calls, so a host that does not grant `Net`
      cannot even instantiate a module that sends. Timestamps and durations are a word each.
      Tested against a scripted host in node ([tests/test_lower.py](../tests/test_lower.py));
      a module that uses nothing imports nothing. Not mapped: `Foreign`, `Ipc`, `Gpu`, `Npu`
      -- channels, models and foreign calls are still refused by name
- [x] **Building bytes is quadratic**, which the Wasm encoder found and which matters
      before any backend grows. Appending a byte answers a new `Bytes`, so emitting a
      module of n bytes copies O(n²). Fine at 63 bytes and fatal at 63,000. Wanted: a
      byte builder, or `(Array U8)` with a one-shot freeze into `Bytes`
      Done in the new encoder without a new primitive: a function body of n instructions is
      n small pieces joined by merging neighbours, round after round, so each byte is copied
      about log n times rather than n. The old encoder in `wasm.wtn` is unchanged
- [x] **`bit.shr` is logical only**, so every signed varint has to hand-build an
      arithmetic shift out of a sign test and a width-specific constant — the Wasm
      encoder does, and every future backend would re-derive it. Either `bit.shr` is
      arithmetic on signed widths or there is a `bit.sar`.
      Done as `bit.sar`: it fills from the top bit of the width and a count outside the width
      leaves only that bit; it is in the kernel's builtin table, the checker, the interpreter
      and the lowering, and the compiled code is compared with the interpreter over every
      width and a spread of counts (`tests/test_lower.py`)
- [x] **A refinement does not survive a record field.** `(newtype Index Int (requires n
      ...))` gives the prover the bound for free at a parameter, but reading one out of a
      record field loses it, so every reader needs a boilerplate accessor whose `ensures`
      restates the condition. A refined field is strictly weaker than a refined parameter,
      which is not what anyone would expect.
      Done: reading a field of a record the prover cannot look into now takes the field's
      declared type as the checker recorded it, so the value is known to satisfy its
      refinement and sit in its range exactly as a parameter does
      ([witness/verify.py](../witness/verify.py); `tests/test_contracts.py`). The Witness
      translation does not read records yet, so it refuses them by name as before
- [ ] Smaller things the encoder wanted, each cheap and each paying for itself across
      every backend: ~~a **`Bytes` literal**~~ (done: `(bytes "0061736d")`, a new syntax node, pairs of hex digits;
      the Wasm backend pools it like a string. It is **not** derivable yet -- the kernel's `const` knows five
      kinds and a sixth is a reviewed-kernel edit -- so `witness evidence` reports it unelaborated. Nothing
      uses it yet: the preamble and `no_bytes` still wait to be rewritten);
      ~~a **range fact for `bit.and`**, so that a masked value narrows to `U8` without a
      guard~~ (done: a mask by a non-negative constant leaves 0..k on any width, and
      `arm64.wtn` lost its guard; `sha256.wtn` still has its own); and ~~**`witness run --entry f --arg ...`**~~
      (done: integers, `Bool` and `Str`; the entry's `requires` are taken on trust)
- [ ] Minimal runtime: reference counting and regions; no tracing GC
- [x] Compile the compiler with Phase 0, then with itself
- [x] **Byte-identical fixpoint; deterministic, content-hashed build artifacts.**
      `witness bootstrap` flattens the driver ([compiler/driver.wtn](../compiler/driver.wtn))
      and everything it imports into one module, puts the runtime library beside it, and
      runs three stages on that one text: Phase 0 runs the compiler on it (22s), node runs
      the module that produced (0.5s), and node runs *that* (0.5s). All three are the same
      152,231 bytes, `sha256:6406f873484a4dd6d1ba3b6d37bc68b93e7076330bb9ce4eb4587c3ba1def35d`
      today, and the hashes are left in `build/compiler.sha256`. The compiled compiler is
      also checked to be the same compiler: on eleven modules of this repository it writes
      the bytes the interpreter's run writes, or refuses with the same words
      ([tests/test_selfhost.py](../tests/test_selfhost.py)). `./build.sh phase2` runs it.

      What this does **not** yet mean: the input is still flattened and checked by Phase 0
      (the compiler is a code generator with a partial type reader, not yet the checker),
      memory is never freed (the self-compile uses 59MB), node runs it with a large stack
      because compiled recursion is real recursion, and the host that loads it is a page of
      JavaScript ([tools/wasmc.js](../tools/wasmc.js))
- [x] **Native backend for servers: x86-64 and AArch64.**
      [compiler/native.wtn](../compiler/native.wtn) and [compiler/x86.wtn](../compiler/x86.wtn)
      translate the *same instructions* the WebAssembly backend writes into machine code and
      wrap them in a static ELF file, so the two backends cannot disagree about what a
      program is: layout, widths, tags and tail calls were decided once, in `lower.wtn`. The
      operand stack is the machine stack, locals live in the frame, memory is one region
      mapped at startup with its base in a register, and a branch first sets the stack back
      to the height its target expects, which is why every instruction is tracked for how
      many values it leaves. `print`, `log` and the clocks are inline system calls; the
      environment, the network and the store have no meaning for a bare process and are not
      mapped. Out-of-bounds access is a segfault rather than a trap with a message.

      **Evidence.** Every encoding is read back by capstone
      ([tests/test_x86.py](../tests/test_x86.py), 57 cases); programs are compiled to ELF,
      *run*, and what they print is compared with the interpreter's
      ([tests/test_native.py](../tests/test_native.py)). And the compiler is a fixpoint
      natively too: the node compiler writes `native1.elf`, which run on the compiler's
      source writes `native2.elf`, which writes `native3.elf` -- 447,277 bytes each, the same
      `sha256:9d09087c...`, in under two seconds a generation, with no node and no Python after the
      first. A native compiler asked for WebAssembly writes exactly stage 1's module.
      `witness bootstrap` checks all six stages.

      **AArch64** is the same walk with another machine behind it
      ([compiler/arm64.wtn](../compiler/arm64.wtn), [compiler/native_arm.wtn](../compiler/native_arm.wtn)):
      every instruction is a 32-bit word, the operand stack is a second stack in x28 so that
      sp stays aligned, and division by zero and the most negative number over -1, which
      AArch64 answers rather than faults on, are checked in the code. There is no AArch64
      machine here, so the evidence is an **emulator**: 58 encodings are read back by
      capstone ([tests/test_arm64.py](../tests/test_arm64.py)); programs are compiled, loaded
      into Unicorn with a few system calls answered
      ([tests/emulate.py](../tests/emulate.py)), and what they print is compared with the
      interpreter's; and, with `WITNESS_EMULATE_COMPILER=1`, the **whole compiler as an
      AArch64 program**, in the emulator, compiles a module to exactly the bytes the
      interpreted compiler writes. Real hardware has not been tried.

      **RISC-V (RV64IM)** is the same walk a third time
      ([compiler/riscv.wtn](../compiler/riscv.wtn), [compiler/native_riscv.wtn](../compiler/native_riscv.wtn)):
      no flags, so a comparison leaves 0 or 1 and a conditional jump is the opposite branch
      over a `jal`; no register-plus-register addressing, so an access adds first; a call is
      `auipc` and `jalr`. Evidence as for AArch64: the encodings are read back by capstone
      ([tests/test_riscv.py](../tests/test_riscv.py)), constants are run, and programs are
      compared with the interpreter in the emulator
      ([tests/test_native_riscv.py](../tests/test_native_riscv.py)).

      **The same translation** is what Cortex-M, RV32 and Xtensa need: another register file
      and another encoder behind the same walk. They are 32-bit machines, though, and every
      value here is 64 bits wide, so they want a word-size parameter first. Those are the next items
- [ ] **32-bit targets: narrow types only (decided).** `mcu` and `esp32` have 32-bit words,
      and every value in the backends is one machine word, so a type that needs two is not
      available there. **Done:** the `profile-type` rule -- a definition that writes `Int`,
      `I64` or `U64` among its declared types does not fit `mcu` or `esp32`, as one whose
      effects are not provided does not -- in the Python checker, in
      [compiler/effects.wtn](../compiler/effects.wtn) (compared with it on every example and
      conformance case under every profile), in SPEC 5.13, the primer and a conformance case.
      **Not yet:** the backends that make use of it. Because a narrow value is the same bits in
      a 32-bit register as in the low half of a 64-bit one, and a shift by 48 is a shift by 16
      once the count is taken modulo 32, the instruction-level translation of the 64-bit
      backends carries over; what does not is the runtime (its checked `Int` arithmetic is
      64-bit) and the container formats
- [ ] Native freestanding backend for microcontrollers: **Cortex-M** (ARMv6-M/v7-M/v8-M),
      **RISC-V** (RV32I and RV32E, with and without M), and **Xtensa LX6/LX7** for the
      ESP32 family. Xtensa is there for one reason: the ESP32, ESP32-S2 and ESP32-S3 are
      Xtensa cores, and nothing else in the plan reaches them. The ESP32-C and -H parts
      (C3, C6, H2, P4) are RISC-V and are covered by that backend instead — so ESP32
      support is two targets, not one, and which one a board needs depends on its part
      number. Xtensa is a windowed-register architecture, but the backend uses its
      windowless `call0` convention, so a window overflow cannot happen and the frame is
      Thumb's. **All three are written and run in emulators**; what is not done is the
      `esp32` profile (below), and with it a bound for the ESP32 image like the one `mcu`
      has for Cortex-M: compiler/stack.wtn knows Thumb's layout, not the ESP32's
- [ ] An `esp32` target profile: Internal Memory: 512 KB SRAM, 384 KB ROM, and 16 KB RTC SRAM, External Memory: Support for high-speed Octal SPI flash and PSRAM, AI Acceleration (ESP32-S3, ESP32-S31 and ESP32-P4 only): Vector instructions extension for neural network and signal processing  and a radio, so it sits between `mcu` and `embedded` rather than at either end — heap allowed,`Net` allowed, and the proven bounds of the `mcu` profile still enforced, because a
      device that reboots on a stack overflow in the field is the case the bounds exist
      for. **The effects are decided** (SPEC 5.13: `Alloc Clock Log Net`, placement up to
      `inline thread core`, bounds required). The memory above is the ESP32-S3's, which the
      Xtensa backend has a layout for beside the original ESP32's; the ESP32-S31 and -P4 are
      RISC-V parts, for the RV32 backend with layouts of their own. **The ESP32-P4 has one**
      ([compiler/native_esp32p4.wtn](../compiler/native_esp32p4.wtn), made from the RV32
      backend by [tools/gen_esp32p4.py](../tools/gen_esp32p4.py)): only the parts that spoke
      to Linux are replaced -- memory from mmap becomes fixed places in the P4's 768 KiB of
      L2 memory, cleared at start, and the system calls become calls to the board -- so the
      walk and the 64-bit operations are RV32's, run in Unicorn's RV32 against the
      interpreter, on RAM filled with 0xA5. The stack and heap bounds hold for it too (its
      room is 512 KiB for data and 96 KiB of machine stack). The S31's map is still to come. **The stack bounds are
      done** for both Xtensa layouts: compiler/stack.wtn's bound is one walk's, so the
      ESP32 and ESP32-S3 images have the Cortex-M image's bound and only the room differs
      (`checked_bound_in`, with a room per layout, checked against the generator's table);
      `drive_xtensa_bounded` and `drive_xtensa_s3_bounded` write an image only if it fits.
      On QEMU the board measures the machine stack at exit (RAM is filled first and that
      stack is left as it was), and no run exceeds its bound; the chain of calls meets it
      exactly, 80 bytes, as on Cortex-M ([tests/test_stack_xtensa.py](../tests/test_stack_xtensa.py)).
      **The heap is bounded too**, for every block whose size is a constant where it is
      made -- records, variants, `num.to_str` -- in compiler/stack.wtn: a body makes what its
      blocks add up to, a function that goes round again (a self tail call is a jump) makes
      it up to its declared depth of times, and a recursion `1 + k + ... + k^(d-1)` times;
      nothing freed is counted as given back. Every counted block is at least 24 bytes, so
      the heap's bound over 24 also bounds how deep releasing can recurse, which is what lets
      a program that allocates have a stack bound at all; the wasm memory grows a page at a
      time and the operand stack has what the pages leave. The bounded builds for Cortex-M,
      the ESP32 and the ESP32-S3 take such programs now, and on all three the heap pointer
      at exit is read back and never past its bound ([tests/test_heap.py](../tests/test_heap.py)).
      **Not yet:** a block whose size the program computes -- what `concat` or `bytes.slice`
      makes -- which needs bounds on lengths, and is refused by name
- [x] **Proven stack and heap bounds enforced for the `mcu` profile**
      ([compiler/stack.wtn](../compiler/stack.wtn)). Before a Cortex-M image is written, what
      it can use of each of its two stacks is bounded in bytes from the compiled module:
      sixteen bytes of the machine stack a call, and eight bytes of the operand stack for each
      local and each slot the body's operands reach at their deepest (WebAssembly's own stack
      effects, which the backend keeps slot for slot). A chain of calls with no cycle costs
      the sum of its frames; a function that reaches itself costs its proved `(bounds (depth
      N))` times the largest frame it reaches, with the runtime's deepest chain on top, and
      every program function under it must be one the checker counted. The runtime's one
      cycle -- releasing what a freed block holds -- is never entered where nothing but a
      release can reach `rt_alloc`, since only `rt_alloc` makes a block that can be freed.
      `mcu` provides no `Alloc`, so its heap is the image's static data and nothing more; a
      program that allocates is refused, as is a recursion with no declared depth, and an
      image whose bound exceeds the room it has (`drive_thumb_bounded` in
      [compiler/driver.wtn](../compiler/driver.wtn)) is not written. Evidence
      ([tests/test_stack.py](../tests/test_stack.py)): programs the checker accepts under
      `mcu` -- a recursion, a mutual one, a chain of calls through a generic function -- run
      in the emulator, which measures the most of each stack written to; no run exceeds its
      bound, the mutual recursion comes within 32 bytes of it, and the chain's machine stack
      meets it exactly. Counting only the locals, without the operand height, fails four of
      those tests. What a board's host functions use of the machine stack is the board's
      own, outside the bound. **Not yet:** a bound on a heap that grows, which `esp32` will
      need, since a block's size is data-dependent
- [ ] Retire Phase 0

**Exit criteria:** the compiler compiles itself to byte-identical output (fixpoint),
and deterministic content-hashed builds make that verifiable by anyone.

---

## Phase 3 — verified backend

- [ ] Formal semantics of the IR and of each target (Wasm first)
- [ ] Proof that each compiler pass preserves meaning (CakeML-style)
- [ ] Proof chain from source to Wasm, then to native targets
- [ ] Proofs checked by the Phase 1 kernel

**Exit criteria:** a kernel-checked proof that compiled code behaves as the source says.

---

## Phase 4 — platform

Can start once the Phase 2 Wasm backend works; items do not wait for Phase 3.

- [ ] Concurrency runtime: tasks, threads, processes and nodes under one model
- [ ] Deterministic parallel reductions on real hardware
- [ ] IPC transport with schema-versioned wire forms; cancellation across nodes
- [ ] HPC collectives (broadcast, reduce, all-reduce, scatter, gather)
- [ ] GPU kernel generation for tensor code
- [ ] Autodiff as a compiler transform
- [ ] Quantised tensor types with scale and zero-point checked
- [ ] Model import (ONNX and similar) with shape checks
- [ ] Differential privacy and federated aggregation as budgeted declassification
- [ ] Energy and timing cost models per target profile
- [ ] Signed, hash-addressed fleet updates; staged rollout; automatic rollback
- [ ] Simulation profile for device code (recorded or synthetic hardware traces)
- [ ] **Interactive playground**: the real toolchain compiled to WebAssembly and run in
      the tab, not a web service in front of a copy of it. Nothing is uploaded, so a
      language about where data is allowed to go does not begin by sending a program to
      somebody's server, and anyone can serve it from a static file. It is the Phase 2
      backend's first external user, which is also why it waits for it: a playground
      built sooner would be a server running the Python prototype, and Phase 0 is retired
      at the end of Phase 2 — a throwaway with a known shelf life. Worth revisiting if
      teaching the language turns out to need one before then
- [ ] What the playground shows, which is the part that makes it a Witness playground
      rather than a text box with a Run button. Five panes, each an existing verb:
      **check** with rule-tagged diagnostics and their suggested fixes, already available
      as `--json`; **run** against host-granted capabilities; **test**, so the
      propositions a module states about itself are what you watch pass; the **audit
      view**, beside the source and editable in both directions, since a language
      audited by people should show a newcomer the thing a reviewer reads; and the
      **evidence** — the derivations, declarations and obligations that were re-checked.
      A playground that shows *why* a program was accepted is teaching the language;
      one that only runs it is teaching the syntax
- [ ] The playground is a **host**, so its capability set is the design question and not
      an afterthought. `Console` is the tab, `Clock` is real, `Alloc` is the Wasm heap;
      `Store` and `Net` need stand-ins that are visibly stand-ins rather than quietly
      broken; `Foreign` must be refused outright, because there is nothing on the other
      side of it and pretending otherwise would teach the wrong lesson about what the
      effect means. Whether that is a `browser` target profile or `host` with a reduced
      grant set is a decision to take against the running thing
- [ ] The playground **hosts the documentation** — PRIMER, SPEC, DESIGN, ROADMAP, the
      conformance suite and the kernel review — and hosts it *live*, which is a thing
      this project can do and most cannot. Every `wtn` block in the primer is already
      checked by the test suite, and the spec's rule table is already mapped to the
      conformance cases that exercise each rule. So every example can be a button that
      opens it in the editor, every rule can link to the programs that must be rejected
      for it, and the build is what keeps the prose and the runnable thing from drifting:
      a snippet that stopped checking would fail CI before it reached the page. Served
      from the same static bundle as the toolchain, so the language, its reference and a
      place to try it are one download and work offline. That matters twice over here —
      the primer is the **normative** reference for AI authors, so "where do I point a
      model at this language" and "where does a person read it" get the same answer
- [ ] Sharing a program by **hash** rather than by a URL with the source packed into it:
      the codebase already addresses definitions that way, so a link names exactly one
      program and cannot name a different one later. A playground is where that stops
      being an abstract property and becomes the reason a link still works

**Exit criteria:** one program runs on a microcontroller and on a cluster, with only
the target profile changing; and the language, its reference and a place to run it are
one static bundle that works offline.

---

## Optional hardening

- [ ] **Diverse double-compiling:** two independently written Phase 0s must produce
      the same Phase 2 binary — defence against trusting-trust attacks
- [ ] **Full-source bootstrap:** a hand-auditable hex seed that rebuilds the chain from
      almost nothing
