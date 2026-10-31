# Witness — Evidence and the kernel's logic (Phase 1)

```yaml
document: witness-evidence
phase: 1
status: done — every Phase 0 check is re-expressed as evidence that a kernel written in Witness re-checks, and the kernel has been read line by line (kernel/REVIEW.md)
companions: [SPEC.md (what the language is), ROADMAP.md (what is planned)]
```

Phase 0 ends with a checker that decides whether a program is acceptable. Phase 1 makes
that checker **untrusted**: it must emit *evidence*, and a small kernel must re-check it.
If the kernel accepts, the program satisfies the specification whatever bugs the checker
has. This is the de Bruijn criterion, and it is only worth anything if the kernel is
small enough that a person can read all of it.

---

## 1. The logic the kernel needs — and the one it does not

The roadmap assumed dependent type theory, with inductive types, universes and an
equality. Having written the language down ([SPEC.md](SPEC.md)), that is more than it
needs, and "more than it needs" is the wrong direction for a kernel whose whole value is
being reviewable.

Look at what the 53 rules actually ask. They split cleanly in two:

**Syntactic judgements** — types, labels, effects, exhaustiveness, shapes, schemas,
placements, policies, naming, arity. Each is a *decidable* relation on the core term
(SPEC §9.1), and each rule of the specification is one inference rule. Evidence for these
is a **derivation**: a tree that names, at every node, the rule applied. The kernel
re-checks a node by matching the rule and verifying its side conditions — no search, no
unification beyond the equality of §4.3, and one case per rule. No type theory is
involved, because no judgement here depends on a *value*.

**Arithmetic obligations** — contracts, refinements, overflow, termination measures,
resource bounds. Every one of them reduces to a single question: *is this set of linear
integer constraints unsatisfiable?* The contract language is quantifier-free: there is no
∀, no ∃, no induction over data, nothing that needs a universe. Unsatisfiability of
linear integer constraints has a classical, tiny certificate — a positive combination
that reaches a contradiction, with rounding where the integers allow it. The kernel
checks that with integer arithmetic and nothing else.

**So the kernel's logic is:** a derivation checker for the rules of the specification,
plus a certificate checker for linear integer arithmetic. Not a proof assistant. The
whole trusted base is intended to be a few hundred lines, not a few thousand.

**What would change this.** Dependent types come back the moment contracts can quantify
(`for all i, a[i] >= 0` — which needs sequences, which Phase 0 does not have), or when
Phase 3 asks the kernel to check that *a compiler pass preserves meaning*, which is a
statement about all inputs. Both are real futures. The decision here is that Phase 1
should not pay for them before it has them: a kernel that checks Phase 0's judgements can
be reviewed now, and growing its logic later is honest work, where starting with a
dependent type theory and never finishing the review is not.

---

## 2. The arithmetic certificate — built, and checked

This half exists: [`witness/logic.py`](../witness/logic.py) emits it and
[`witness/certificate.py`](../witness/certificate.py) checks it, sharing none of the
search.

### 2.1 What an obligation is

An obligation is a **list of hypotheses**, a **goal**, and what elaboration says about
any atom standing for a product. A hypothesis is either

- **from elaboration** — a type's range, a refinement's condition, the length of a
  literal, which branch is running, which variant an arm is for. These are what the term
  itself says, and they are the syntactic derivation's business (§3), not the
  arithmetic's; or
- **proved** — from the hypotheses *before* it, with its reason attached.

The order is the order each fact was learned, so nothing is ever used before it is
established. A kernel replays the list and then checks the goal.

Hypotheses and the goal are formulas over:

- linear terms: an integer constant plus integer multiples of named atoms;
- `t <= 0` and `t = 0` over those terms;
- boolean atoms, which stand for anything the prover cannot see into;
- `and`, `or`, `not`.

The goal holds when `assumptions ∧ ¬goal` is unsatisfiable over the integers.

### 2.2 Cases

A formula is put into disjunctive normal form: a list of **cases**, each a set of atoms
held true, a set held false, and a list of constraints `t <= 0`. Every assignment
satisfying the formula satisfies one of the cases, so ruling out every case rules out the
formula.

The order is fixed, because the evidence names cases by position: negations are pushed
down to the literals, parts are taken left to right, and a conjunction's cases are the
product of its parts' cases with the **leftmost part moving slowest**. The kernel builds
the cases itself from the formula — it does not take them from the prover.

### 2.3 Reasons

A hypothesis or goal is established either by a refutation of every case of its negation
(below), or by the product lemma (§2.4).

One reason per case, of two kinds.

**`Clash(atom)`** — the case holds that atom both true and false. Checking: the atom is
in both sets.

**`Refutation(steps, contradiction)`** — arithmetic. The case's constraints are numbered
from 0; each step appends one more, so a step can name the constraints it came from. Two
steps:

| Step | Means | Checked by |
|---|---|---|
| `Tighten(of, by)` | divide by `by` and round the bound inwards | recomputing it, and that `by` is more than one and divides every coefficient |
| `Combine(left, right, by_left, by_right)` | `left·by_left + right·by_right` | recomputing it, and that both multipliers are **positive** |

`contradiction` names a constraint that must be `k <= 0` with `k > 0`.

Three facts make this sound, and the kernel checks each use of them:

1. If `A <= 0` and `B <= 0` and `ka, kb > 0` then `ka·A + kb·B <= 0`.
2. If `Σ aᵢxᵢ + c <= 0` and `g > 1` divides every `aᵢ`, then `Σ (aᵢ/g)xᵢ` is an integer
   no greater than `-c/g`, hence `Σ (aᵢ/g)xᵢ + ⌈c/g⌉ <= 0`. The divisor is *carried* by
   the step rather than recomputed: finding the greatest one needs a gcd, checking a
   given one needs a division, and a divisor that is not the greatest only makes the
   step weaker. So the kernel never computes a gcd — which matters, because a gcd's
   recursion cannot be proved to terminate in the language the kernel is written in.
3. `k <= 0` with `k > 0` holds of nothing.

Note what the certificate does **not** carry: the value of any derived constraint. The
kernel recomputes every one. A certificate is a plan, so a forged one has nothing to
hide behind.

### 2.4 The one thing it knows about multiplication

Linear arithmetic cannot see a product: `(* w h)` on two unknowns becomes an opaque atom,
and no combination of linear constraints will bound it. One fact closes that gap:

> if `la <= a <= ha` and `lb <= b <= hb`, then `a·b` lies between the least and the
> greatest of the four products of those bounds.

`Product(atom, a, b, a_bounds, b_bounds, upper)` applies it. The kernel checks, at every
use:

1. the obligation itself states that `atom` is the product of `a` and `b` — the lemma
   cannot be aimed at any other atom, and that statement comes from elaboration, which
   is the derivation's business (§3);
2. each of the four bounds is a hypothesis **already established** at that point;
3. each is a bound of that factor by a *constant*, read off the constraint's shape;
4. the conclusion is exactly the interval the four corners give — no tighter.

So the bounds the lemma rests on are themselves proved, in order, before it is used, and
the lemma adds nothing beyond interval arithmetic. There is no longer anything in the
corpus that has to be taken on trust.

### 2.5 Where it already holds

Every obligation the toolchain discharges carries a reason, and every reason checks:
contracts (`unproven-precondition`, `unproven-postcondition`), refinements, `overflow`,
termination measures (`no-termination-proof`) and the measure bounds behind
`resource-bound`. Across the examples that is 104 obligations, and `witness evidence`
replays all of them. Nothing rests on an unchecked lemma.

---

## 3. The derivation — built, and checked

This half exists too: [`witness/derive.py`](../witness/derive.py) produces derivations
and [`witness/kernel.py`](../witness/kernel.py) checks them.

A derivation is the core term with its judgement written at every node:

```
node = { rule, type, effects, data, parts }
```

`rule` is one of nineteen (§3.1), `type` is what the node concludes with its labels,
`effects` is what it performs, `data` is the rule's own detail — a variable's index, a
primitive's name, which variant, which field — and `parts` are its premises.

The kernel checks a node by applying the rule to its parts and verifying that the
conclusion claimed is exactly the one the rule gives. It also carries two things down the
tree: Γ, the types in scope, which it extends at every binder itself; and `pc`, the
labels of the data that chose the branch, which it extends at every `case` arm. **Nothing
is inferred.** Where the surface language solved for a type argument or a label set, the
derivation states the answer and the kernel substitutes and checks the fit — a wrong
answer cannot make a value fit where it does not.

### 3.1 The rules

| Rule | What it is | Among the conditions it checks |
|---|---|---|
| `var` | a variable, by index | in scope; the type claimed is the one bound |
| `const` | a literal | the type matches the kind of literal |
| `let` | a binding | the body is judged with Γ extended |
| `case` | a case over an enum, or over `Bool` | one arm per variant, each exactly once; each arm binds exactly that variant's fields; every arm fits the conclusion; the scrutinee's labels are carried, and its labels enter `pc` |
| `call` | a function, by name | arity; the type and label arguments substituted into every parameter and the result; every argument fits |
| `prim` | a primitive of SPEC §6.3 | its signature; one number type at the polymorphic positions; a sink takes nothing labelled |
| `con` | a variant | the field types with the enum's type arguments in place |
| `rec` / `proj` / `upd` | a record built, read, replaced | every field, in order; the field exists; the record's labels ride along |
| `wrap` / `unwrap` | the newtype identity | what it wraps, as declared |
| `release` | a declassify | the signature declares that release |
| `fork` | `par` | a branch performing anything but `Alloc` needs `Nondet` declared |
| `supervise` | `scope` | each task's work and the body can carry a failure; a deadline is a `Duration` |
| `send` / `recv` | a channel | the payload's type; the labels the channel accepts |
| `run` | a model | the input's type; the output carries `ModelOutput`, the input's labels and the training labels |
| `tensor` | `tensor.add`, `tensor.matmul` | one element format; shapes equal, or the contracted axis agreeing by name and size |
| `outside` | a foreign call | the declared parameters; the result carries `Unverified` |
| `logfields` | a structured log line | every label on a field has a redaction policy |

Then one check for the whole definition: under its parameters, the body has the declared
type, carries no label the signature does not admit, and performs no effect it does not
declare. Every function is judged, the prelude's included: code the module calls but did
not write still has to stand up.

### 3.2 What elaborates away

The core is smaller than the surface. `seq` becomes nested `let` over a name nothing
uses; `if` becomes a `case` over `Bool`, whose variants are `False` then `True`; `with`
and `update` become `upd` — and a patch needs nothing new, because each field becomes a
`case` over the patch's `Option`, answering the patch's value where there is one and the
record's where there is not. Nineteen rules cover everything the language has.

### 3.3 What this found

Writing the kernel found a bug in the checker that four hundred tests had not. Where two
arguments share a type parameter and the first has already made it stand for another
undecided type, the checker was rebinding the wrong one, so `(None)` in
`(unwrap_or (None) 0)` kept a type that was never settled. The program still checked and
still ran correctly; what was wrong was the *record* of why. The kernel refused the
derivation because a node cannot claim a type the checker never decided, and the
elaborator now refuses to write one down at all.

That is the whole argument for this phase, in one example: the checker's answer was
right and its reasoning was not, and only something that re-derives the reasoning could
tell.

---

## 4. The declarations

A function body is a term, so it has a derivation. A declaration is not: what has to hold
of it is a set of conditions, each decidable. `judge_module` checks them itself rather
than being told the answer, so the whole module is judged, not only the code in it.

| Declaration | What the kernel checks |
|---|---|
| `enum` | at least one variant; every field's type is one the module declares |
| `newtype` | what it wraps is declared, and is not itself labelled — a label belongs where a value is used, not in the type it was cut from |
| `record` | every field's type is declared; a wire schema's version is a positive whole number |
| `patch` | its target is a record, and not a patch |
| `channel` | its payload is a record with a wire schema — nothing without an agreed form may be sent |
| `model` | the input and output are a tensor, `Str` or `Bytes`; the weights are named by hash |
| `redact` | the policy named exists |
| `foreign` | the parameters and result are declared types |
| `test` / `property` | every input is of a type an implementation can make up values for, following newtypes to what they are built on |
| `fn` / `foreign` | every effect named is an effect, and one the target provides |

And two conditions that are about more than one declaration at a time:

**Schemas.** Each version of a wire schema must read, and be read by, the one before it:
no field changes type, an added field is optional, and a dropped field was optional. The
kernel compares the versions pairwise, in order.

**Placements.** Work may only be put where the target can put it, and `inline` and
`thread` share memory where a core, a process or a node may not — so everything crossing
to memory of its own needs a wire form, which the kernel decides by walking the type:
primitives and newtypes over them, enums whose every field transfers, records with a wire
schema, and nothing else.

### 4.1 Resource bounds, recomputed

`(bounds (depth N) (alloc N) (repeats N))` is the one declaration whose condition is a
*computation*, and the kernel redoes it from the core term rather than trusting the
checker's number:

- a frame for the function itself, and the deepest call it makes — branches of a `case`
  are alternatives, so the worst of them, while a `let` and its body are in sequence;
- one allocation per operation that builds something whose size is not known in advance;
- a branch of a `par` or a task of a `scope` placed in memory of its own spends another
  machine's stack and heap, not this one's; a task that may restart spends what it builds
  once per attempt;
- callees first, so a caller reads a cost already computed, with a group of mutually
  recursive functions costed as one.

What the kernel cannot count is **how often a recursion repeats**: that rests on the
termination measure, which is arithmetic, not syntax. So the repeat count is taken as
claimed, and the obligation behind it is one of the arithmetic obligations §2 replays. A
recursion with no counted repeat is unbounded, and then nothing may be declared about it.
This is the one place in the kernel where a number comes from elsewhere, and it is bounded
above by a proof the kernel has already checked.

### 4.2 Where it holds

Every module in the examples and the conformance suite — 48 of them, 217 functions, 170
declarations, 95 obligations — is accepted whole by the kernel, under every profile it
checks for. `witness evidence FILE` prints the three counts.

The conformance suite now has the kernel as its final judge. For the 50 rejected cases
exactly three outcomes are allowed, and a test enforces that nothing else happens: 45
never reach a program at all, one the kernel refuses itself, and four are arithmetic
obligations that were never discharged — for those there is no proof for a kernel to
check, which is itself the refusal.

---

## 5. The kernel, in Witness

Two modules, both run under the Phase 0 interpreter, each a transcription of its Python
model sharing no code with it. That is the point: a slip in either shows up as a
disagreement on the corpus rather than as two quiet acceptances.

| Module | Model | Covers |
|---|---|---|
| [`kernel/arith.wtn`](../kernel/arith.wtn) | `certificate.py` | all of §2, the product lemma and the hypothesis list included |
| [`kernel/core.wtn`](../kernel/core.wtn) | `kernel.py` | all twenty-one rules of §3.1 |
| [`kernel/decls.wtn`](../kernel/decls.wtn) | `judge_module` in `kernel.py` | the declaration conditions of §4 |
| [`kernel/costs.wtn`](../kernel/costs.wtn) | `_bounds` in `kernel.py` | the resource bounds of §4.1 |

Four modules and not one, because a Witness module imports nothing: they are run
separately, and each stays a thing a person can read in one sitting.

### 5.0 The arithmetic

It has **no entry point** and performs nothing but `Alloc` — no `Console`, no `Store`, no
`foreign` — so there is no way for it to be told what to conclude, and a test enforces
that. A module has no imports, so to ask it about a real obligation
[`witness/witnessed.py`](../witness/witnessed.py) writes the obligation into a copy of it
as ordinary constructor expressions and runs the result.

It replays a **whole** obligation, not only its goal: the hypothesis list in the order it
was learned, each proved hypothesis established from the ones before it, each hypothesis
read off the term taken as given because that is the derivation's business (§3), and the
product lemma of §2.4 checked at every use. Across all 95 obligations the corpus
discharges, the Witness kernel and the Python one agree exactly, and the Witness kernel
refuses every tampered plan it is given: a negative multiplier, a contradiction that is
not one, a missing reason, a divisor that divides nothing, and a product lemma aimed at an
atom the obligation does not call a product.

### 5.1 The derivation

[`kernel/core.wtn`](../kernel/core.wtn) carries the core term, the module's declarations
and the scope as Witness data, and judges `var`, `const`, `let`, `release`, `wrap`,
`unwrap`, `call`, `con`, `case`, `rec`, `proj`, `upd`, `prim`, `fork`, `supervise`,
`send`, `recv`, `run`, `tensor`, `outside` and `logfields` — **all twenty-one rules**. All
208 derivations in the corpus are accepted, the same answer as the Python kernel every
time, while refusing a claimed type that is not the rule's, a field read at the wrong
index, a variable out of scope, a dropped label, a case whose arms do not cover, an arm
binding the wrong number of fields, work placed where the target cannot put it, and a
rule it does not know.

**The primitives.** `prim` needed the signatures of SPEC §6.3, and those are part of the
*language*, not of a program, so the kernel carries them itself rather than being told
them: 56 entries, in seven groups, each saying what it takes, what it answers, what it
performs, whether it is a sink, and whether it needs a fixed width. Two copies of §6.3 is
a thing that drifts, so a test runs the Witness table through the interpreter, has it
render every signature, and compares that with the rendering of the table
`tests/test_spec.py` already holds to the specification. Writing it found a mistranslation
immediately: a decimal literal's type is `Real`, not the `F32` it becomes once a format is
named for it, and the two `floats.wtn` derivations were the only ones in the corpus that
could tell.

**What its shape had to be.** The termination checker requires every call in a recursive
cycle to make something smaller, and `check(node) → rule(node)` makes nothing smaller. So
the judgement had to be split in two, and the split is an improvement: because a
derivation states its type and effects at *every* node, each rule's own conditions can be
checked from the node and the **claims** of its premises, without looking inside them.
`local` is therefore twelve independent rules that recurse into nothing, `scopes` says
what scope each premise is judged under — only `let` and `case` change it — and `descend`
is the only recursion there is. A kernel in that shape is far easier to read than one
where the walk and the rules are interleaved, which is what `kernel.py` does.

### 5.2 The declarations

[`kernel/decls.wtn`](../kernel/decls.wtn) checks the conditions of §4 — every type
reference naming a type that exists, an enum having variants, a newtype not wrapping
something labelled, a version on the wire counted from one, a patch patching a record
that is not a patch, a channel carrying a record with a wire schema, a model's shapes and
its weights named by hash, a redaction naming a policy the language has, a property's
inputs being of types values can be made up for, every effect being an effect and one the
target provides, and each version of a wire schema reading the one before it. All 48
modules in the corpus pass, and the tests check each condition's refusal one at a time.

Two places where it is deliberately *stricter* than the Phase 0 checker, both in the
direction that only ever loses a program:

- it compares two versions' field types as **written**, where the checker compares them
  resolved — so a field whose type is spelled differently but resolves the same would be
  refused;
- a target it has never heard of provides **nothing**, so every effect is refused, rather
  than falling back to the host's.

And one thing it got wrong until the corpus said so: a patch carries its target's schema
and version so that it can be sent, but it is a partial update and not a version of
anything, so it takes no part in the schema history. Comparing `ListenerPatch` against
version 1 of `Listener` said a required `Str` had become an optional one. The Phase 0
checker never had the bug because it registers versions in a table a patch never enters;
the transcription had to learn it.

### 5.3 The resource bounds

[`kernel/costs.wtn`](../kernel/costs.wtn) redoes the cost walk of §4.1 from the core
terms. Two numbers it cannot count come from the evidence, and they are different in
kind:

**How often a recursion repeats** rests on the termination measure, which is arithmetic.
It is taken as claimed, and §2 replays the obligation behind it.

**Which calls are recursive** would otherwise need the strongly connected components of
the call graph worked out inside the kernel — a closure, a condensation and a topological
sort, none of which has anything smaller to recurse on. So the evidence carries a
**rank** per function instead: a call out of a cycle goes to a lower rank, a call within
one goes to the same rank, and a call to a higher rank is refused because its cost would
depend on itself. That is a local condition at every call site, which the kernel checks
rather than computes, and then it costs the ranks in turn from the bottom. A rank holding
more than one cycle is costed as though it were one, which can only ask for more than is
needed — and the ranking Phase 0 emits is the condensation's own order, where each rank
holds exactly one cycle, so nothing is lost in practice.

All 50 module-and-target pairs in the corpus pass, and the tests check each refusal: a
declared depth that does not cover the term, a declared allocation that does not cover
what it builds, a recursion with no counted repeat, a target that demands bounds from a
function with none, and a call ranked above its caller.

It found one thing. A task that may **restart** repeats what it *builds* — each attempt
allocates again — but the attempts happen one after another on the same stack, so the
depth does not repeat. Multiplying both gave `sweep` in `survey.wtn` a depth of 4 against
its declared 3, and that function is the only one in the corpus that could tell.

### 5.4 What writing it in Witness changed

Three things, each a consequence of the language being smaller than Python:

**No gcd.** Euclid's recursion needs `a mod b < b`, which is not linear, so the
termination checker cannot see it. Rather than weaken the kernel, the divisor moved into
the `Tighten` step (§2.3): the prover finds it, the kernel checks it. The trusted base got
smaller for it.

**No ordering on `Str`.** The language has `str.eq` but nothing that puts two strings in
order, so the Witness `Lin` keeps its terms in no particular order and compares two of
them by looking each term up. Equality is by content rather than by shape.

**One module, no imports.** A Witness module imports nothing, so the kernel is one file
by construction, and will stay one file until the language has a module system. That is
the single strongest argument for giving it one, and it is Phase 2's problem.

**A walk with no structure needs a budget.** Whether a value can cross into memory of its
own is decided by following *declarations*, not the structure of a value, so nothing gets
smaller and the termination checker cannot see an end to it. The Witness version is given
a budget counted from how many types the module declares, and running out answers **no** —
which is the safe answer, because a kernel that refuses too much loses a program where
one that accepts too much loses the point.

**Every function total.** `num.div` answers an `Option`, every `match` is exhaustive, and
every recursion needed a measure that falls. Nothing in the kernel can fail to answer.

### 5.5 Agreeing on what to refuse

Two kernels that agree on what to accept may still disagree on what to refuse, and a
missing check shows up only in the second half. So both pairs are also asked about
**damaged** evidence: random changes to a real derivation's rule, type, labels, effects,
detail or premises, and to a real proof's reasons, steps, multipliers and divisors. Each
pair must give the same answer.

That found two things.

**The Witness derivation kernel had no `judge`, only `check`.** `check` verifies every
node against its rule, which is most of the judgement — but not the part that compares
the *body* with the *signature*. A body carrying a label the signature does not admit was
therefore accepted. The Witness kernel now has `judge`, which resolves the declared
return type itself (type parameters rigid, the label parameter standing for itself) and
checks the body against it, exactly as `kernel.py` does.

**The Python kernel crashed rather than rejecting.** Nine rules unpacked their own detail
— `(index,) = node.data` — which raises on a derivation whose detail does not match its
rule. A kernel may accept or it may reject; a crash is a third answer it must not have,
and "the elaborator never produces that" is not an argument about a kernel whose whole
point is not trusting the elaborator. Every rule now reads its detail through one
`_detail` check that names the shape it needs and refuses anything else. A test wrecks
every derivation in the corpus eight ways and holds that nothing but the two answers ever
comes back; by hand that number has been taken to 12,480 damaged derivations and 810
damaged modules with no third answer. `certificate.py` already had this property.

### 5.6 What writing it found

Five defects in the toolchain, all found by a kernel refusing to be written:

**The prover was guarding facts that hold everywhere.** A string literal's length is the
same whatever branch is running, but it was learned *inside* a branch and so came out
guarded by the branch's condition — one extra disjunction, and so a doubling of the cases
in the normal form, for every literal in every branch. Three nested branches with two
literals each was enough to blow the disjunct cap and lose a proof the prover could
otherwise do easily. Facts that hold everywhere are now kept plain, and learned once.

**The audit view could not read back a multi-line `if`.** The view is a two-way
projection, and `witness read` is driven by indentation; `then` and `else` were rendered
at the same indentation as `if`, which made them siblings of it rather than parts of it,
so a long `if` rendered to a view that would not parse. No example in the repository had
one. They are now indented under the `if`, like a match arm.

**The audit view could not read back a call written over several lines.** When an
argument of such a call itself ran over several lines, the line closing it was taken for
another argument rather than for part of that one. `kernel/core.wtn` is the first module
in the repository with a call long enough to be rendered that way. The reader now groups
a multi-line call's arguments the way it groups statements.

**The termination checker was searching the wrong way.** A measure is one parameter
position per function in a recursive cycle, and the search was the *product* of the
positions over the members, abandoned entirely above a cap — so a seven-function mutual
cycle with four parameters each, which is tens of thousands of assignments, got no measure
*attempted* rather than one rejected. It now places a member at a time and checks every
call as soon as both of its ends are placed, so a wrong placement is abandoned at the
first call it cannot justify instead of after the rest of the cycle has been filled in;
numbers are tried first at each member, since a measure is numeric or it is structural and
a number has no structure to descend. It can still give up, and giving up still only
loses a proof — but it no longer gives up before starting on exactly the shape a kernel's
traversal takes.

All five are the same shape of finding as §3.3: the toolchain's answers were right and
something about how it got there was not.

---

## 6. Where Phase 1 ends

Every Phase 0 check is re-expressed as evidence that a kernel written in Witness
re-checks: the twenty-one rules, the declaration conditions, the resource bounds and the
arithmetic. The build re-runs all of it.

And the kernel has been **read**. [kernel/REVIEW.md](../kernel/REVIEW.md) records who did
it, when, and the SHA-256 of each module as it was read, together with what the review
covers and what it does not — the Python models, the interpreter underneath and the
harnesses are all outside it, and the record says so. The hashes are checked by the
build: a kernel module edited after the review fails until the record is renewed by a
person reading the change, because a review of text that has since been edited is not a
review of anything.

The four modules are 2,359 lines, more than the "few hundred" §1 hoped for. About 260 of
those are the primitive table of SPEC §6.3 written out as data, and a good deal more is
the same list and set handling repeated in each module, because a Witness module imports
nothing. That repetition is not waste to be tidied away: it is what the absence of a
module system costs, and a module system is Phase 2's work. The review happening is the
stronger evidence that the kernel is readable; the number is recorded here rather than
quietly dropped.

**What Phase 1 does not give.** The toolchain still *runs* the Python kernel by default:
`witness evidence` calls `kernel.py` and `certificate.py`, and the Witness modules are
run by the tests. Making the Witness kernel the thing in the path needs an implementation
that is not a tree-walking interpreter, which is Phase 2.

The exit criterion is unchanged: every Phase 0 check re-expressed as kernel-checked
evidence, and a kernel small enough to review. §2 is the proof that the hard half is
tractable — the arithmetic, which is where a "trust me" would otherwise hide.
