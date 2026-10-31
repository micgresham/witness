# Witness — Language Specification (Stage 0)

```yaml
document: witness-specification
stage: 0
status: draft, tracking the Phase 0 prototype
conformance: ../conformance/manifest.json
companions: [PRIMER.md (how to write it), DESIGN.md (why), ROADMAP.md (what is planned)]
```

This document says what the language *is*, in enough detail to implement it again from
nothing. [PRIMER.md](PRIMER.md) teaches the same language to an author; where the two
disagree, this document is wrong and should be fixed, because the primer is checked
against a running implementation.

**Conformance.** An implementation conforms when, for every program in
[`conformance/`](../conformance), it reports the same outcome and the same rules as
[`conformance/manifest.json`](../conformance/manifest.json) says. The suite is data: it
names each program, whether it is accepted, accepted with warnings, or rejected, and
exactly which rules it must report, in order. Accepting a program the suite rejects and
rejecting one it accepts are equally wrong. Rule identifiers are part of the language,
not of any implementation's diagnostics.

---

## 1. Shape of a program

A **compilation unit** is one file holding exactly one `module` form. There are no
imports: everything a module refers to is either declared in it or in the **prelude**
(§4.8), which every module contains.

A module's declarations may appear in any order, and every declaration is visible
throughout the module. Order never affects meaning.

---

## 2. Lexical structure

Source is UTF-8 text. A token is one of:

| Token | Form |
|---|---|
| `(` `)` | list delimiters |
| comment | `;` to the end of the line; not a token, and carries no meaning |
| integer | `-?[0-9]+`, unbounded |
| decimal | `-?[0-9]+\.[0-9]+` |
| string | `"` … `"` on one line; escapes `\n` `\t` `\"` `\\` only; any other escape is an error |
| boolean | `true` `false` |
| symbol | any run of characters other than whitespace, `(`, `)`, `;`, `"` |

Whitespace separates tokens and is otherwise insignificant. A symbol may not begin with
`?`, a prefix reserved for label parameters (§5.4).

**Keywords** are symbols that may never be used as a name:

```
module enum newtype record patch foreign redact channel accepts model tensor infer
test property snapshot fn let if match seq unwrap make get with update declassify label
uses declassifies requires ensures result schema bounds par scope deadline on-fail on
send recv unit true false _
```

Case carries meaning: a symbol beginning with an upper-case letter names a type, a
variant, a schema, a channel, a model or a type parameter; one beginning with a
lower-case letter names a function, parameter, field or binding. A label is any
non-keyword symbol (§5.3).

---

## 3. Grammar

```ebnf
file         = module ;
module       = "(" "module" lower decl* ")" ;
decl         = enum | newtype | record | patch | foreign | redact | channel | model
             | test | property | snapshot | fn ;

enum         = "(" "enum" enumname variant+ ")" ;
enumname     = Upper | "(" Upper Upper+ ")" ;
variant      = "(" Upper field* ")" ;
field        = "(" lower type ")" ;
newtype      = "(" "newtype" Upper type [refine] ")" ;
refine       = "(" "requires" lower expr ")" ;
record       = "(" "record" Upper [schema] field* ")" ;
schema       = "(" "schema" Upper INT ")" ;
patch        = "(" "patch" Upper Upper ")" ;
foreign      = "(" "foreign" lower "(" param* ")" type [uses] ")" ;
redact       = "(" "redact" Label policy ")" ;
policy       = "hidden" | "digest" | "length" | "keep" ;
channel      = "(" "channel" Upper Upper [accepts] ")" ;
accepts      = "(" "accepts" Label* ")" ;
model        = "(" "model" Upper "(" "input" type ")" "(" "output" type ")"
                   "(" "trained-on" Label* ")" "(" "device" device ")"
                   "(" "weights" STRING ")" ")" ;
device       = "cpu" | "gpu" | "npu" ;
test         = "(" "test" STRING expr ")" ;
property     = "(" "property" STRING "(" param* ")" [requires] expr ")" ;
snapshot     = "(" "snapshot" STRING expr STRING ")" ;

fn           = "(" "fn" fnname "(" param* ")" type clause* expr ")" ;
fnname       = lower | "(" lower Upper* [labelparam] ")" ;
labelparam   = "(" "label" Label ")" ;
param        = "(" lower type ")" ;
clause       = uses | declassifies | requires | ensures | bounds ;   (* this order, once each *)
uses         = "(" "uses" Effect* ")" ;
declassifies = "(" "declassifies" Label* ")" ;
requires     = "(" "requires" expr ")" ;
ensures      = "(" "ensures" expr ")" ;
bounds       = "(" "bounds" bound+ ")" ;
bound        = "(" ("depth" | "alloc" | "repeats") INT ")" ;

type         = Upper | "(" Upper type+ ")" | "(" "label" Label+ type ")"
             | "(" "tensor" Format axis+ ")" ;
axis         = "(" lower INT ")" ;

expr         = INT | DECIMAL | STRING | "true" | "false" | "unit" | lower | "result"
             | "(" "let" lower expr expr ")"
             | "(" "if" expr expr expr ")"
             | "(" "match" expr arm+ ")"
             | "(" "seq" expr+ ")"
             | "(" "unwrap" expr ")"
             | "(" "declassify" Label expr ")"
             | "(" "make" Upper init* ")"
             | "(" "get" expr lower ")"
             | "(" "with" expr init+ ")"
             | "(" "update" expr expr ")"
             | "(" "log.fields" init+ ")"
             | "(" "par" "(" branch+ ")" expr ")"
             | "(" "scope" "(" task+ ")" expr ")"
             | "(" "send" Upper expr ")" | "(" "recv" Upper ")"
             | "(" "infer" Upper expr ")"
             | "(" callee expr* ")" ;
init         = "(" lower expr ")" ;
arm          = "(" "(" Upper lower* ")" expr ")" ;
branch       = "(" lower expr [place] ")" ;
task         = "(" lower expr "(" "deadline" expr ")" onfail [place] ")" ;
onfail       = "(" "on-fail" ("fail" | "escalate" | "restart" INT) ")" ;
place        = "(" "on" ("inline" | "thread" | "core" | "process" | "node") ")" ;
callee       = lower | Upper ;
Effect       = "Alloc" | "Clock" | "Console" | "Env" | "Foreign" | "Gpu" | "Ipc" | "Log"
             | "Net" | "Nondet" | "Npu" | "Store" ;
Format       = "I8" | "I16" | "I32" | "I64" | "U8" | "U16" | "U32" | "U64"
             | "F16" | "BF16" | "F32" ;
```

Shape constraints the grammar does not show: a `fn` has exactly one body; `let` binds one
name; a function's name contains no `.`; a model's clauses appear in the order written
above; a `restart` limit is at least 1; an axis size is at least 1; a schema version is
at least 1.

Anything that does not parse is `syntax`.

---

### 3.9 Imports

```
(use "H" as name)
(use module.definition as name)
```

The second form is how a dependency is *asked for* by someone who has no hash to hand. It
is never checked: a module holding one is rejected `[unpinned-import]`, whose message
says which hash the name stands for today. `witness pin file` rewrites each such line to
the first form, in place and touching nothing else, and refuses to change the file unless
every name resolves. A name is how the hash is looked up; what is depended on is the
hash, so the same source never checks differently because the codebase moved.

`H` is a content hash. The declaration brings the definition `H` names into this module
under `name`, together with every definition it is built out of, each under the name the
codebase has for it.

What is depended on is **the hash**, never a name: a name is this module's convenience,
which is why it is written on the left of `as` and the hash is written out in full. A
definition imported under another name is the same definition — its hash does not change,
because a name is not part of what a definition is (§8). So an importing module's own
hash already records what it depends on, and there is nothing further to write down.

The **audit view** (§10) of a module shows it as written, import lines and all, and not
what they resolved to: a hash is a complete reference, so showing one hides nothing,
where splicing would lose the line between what a module wrote and what it took. To read
a dependency, view the dependency.

An import is resolved by *splicing*: the definition and its dependencies become
declarations of the importing module before anything else looks at it. A dependency is
therefore checked exactly as the code around it is, every time, rather than trusted
because of where it came from. Two consequences, both deliberate:

- definitions are imported **one at a time**. There is no way to ask for everything a
  module has, because a module does not export anything — the codebase holds definitions
  and a module is a way of writing some of them down;
- two imports may not claim one local name unless they are the same definition
  `[unresolved-import]`.

## 4. Types

### 4.1 Primitive types

`Bool`, `Unit`, `Str`, `Bytes`, `Tensor`, `Array`, the integers `Int` `I8` `I16` `I32`
`I64` `U8` `U16` `U32` `U64`, and the floating formats `F16` `BF16` `F32`.

`Tensor` and `Array` each take one type argument and are written `(tensor F ...)` (§4.5)
and `(Array T)`. Every other primitive is nullary.

`Int` is the unbounded integer. Each `IN`/`UN` denotes exactly the integers in
[-2^(N-1), 2^(N-1)-1] / [0, 2^N-1]. Each floating format denotes IEEE 754 binary values
of its layout; `BF16` is `F32` truncated to 16 bits.

`Real` is the type of a decimal literal. It is not a type any declaration may name: a
literal has no format until one is named for it (§6.4).

`(Array T)` is a sequence of `T` read by position. It is a **value**: pushing answers a
new array rather than changing the one given, so an array never has two owners and
nothing observes a change made elsewhere. Reading is total — an index that is not there
answers nothing — so no obligation stands between a program and an element, and an index
is a `Count`, which is a unit and not a bare `Int`.

An array is only as transferable as what it holds: one may cross into memory of its own
(§7.2) exactly when its element type may.

`Str` is **opaque**: it can be built, compared, measured and encoded, and nothing can
look inside it. That is what makes "a `Str` is valid UTF-8" true rather than hoped for —
the one place a sequence of bytes becomes text is `bytes.decode`, which may refuse. A
program that reads text reads `Bytes`, where `bytes.at`, `bytes.slice` and `bytes.of`
(§6.3) give byte-at-a-time access, and decodes once at the end.

### 4.2 Declared types

- `(enum N (V field*)+)` — a sum. Variants are nominal and live in one module-wide
  constructor namespace with newtypes. A generic enum `(enum (N P+) …)` takes exactly its
  declared number of type arguments wherever it is written.
- `(newtype N T)` — a distinct type wrapping `T`. `T` may not carry labels
  (`labelled-newtype`). A newtype is **nominal**: it converts to and from `T` only by the
  constructor and `unwrap`.
- `(record N field*)` — a product with named fields. Field names are the wire form.
- `(patch N R)` — a record whose fields are those of `R`, each wrapped in one further
  `Option`. `R` must be a record and not itself a patch.
- `(tensor F axis+)` — an array of `F` with named axes. Two tensor types are the same type
  only when their format and their axes agree, by name, size **and order**.

### 4.3 Type equality

Types are compared **structurally over their parts and nominally over their names**: two
types are equal when their base names are equal, their type arguments are pairwise equal,
their axis lists are equal, and their label sets are equal. There is no subtyping other
than the label rule of §5.3, and no implicit conversion anywhere.

### 4.4 Schemas

A record may declare `(schema S V)`, making it version `V` of wire schema `S`. Within a
module, each `(S, V)` is declared once and `V ≥ 1` (`schema-version`). For each pair of
consecutive versions of one schema, ordered by `V`:

- a field in both must have the same type (`schema-incompatible`);
- a field only in the later version must be an `(Option T)`;
- a field only in the earlier version must have been an `(Option T)`.

### 4.5 Transferability

A type is **transferable** when a copy of a value can be agreed on by two machines:

- a primitive is transferable;
- a newtype is transferable when what it wraps is;
- an enum is transferable when its type arguments and all its variants' field types are;
- a record is transferable when it declares a schema and all its field types are.

Transferability is required of everything crossing to separate memory (§5.7, §5.8).

### 4.6 Channels

`(channel C R (accepts L*))` declares a channel carrying record `R`, which must declare a
schema (`channel-payload`), and accepting exactly the labels `L*`.

### 4.7 Models

`(model M (input T_i) (output T_o) (trained-on L*) (device d) (weights H))` declares a
model. `T_i` and `T_o` are each a tensor, `Str` or `Bytes`. `H` is a content hash and is
part of the model's identity. `L*` are the labels its training data carried.

### 4.8 The prelude

Every module contains, as if declared in it:

```lisp
(enum (Option T) (None) (Some (value T)))
(enum (Result T E) (Ok (value T)) (Err (error E)))
(record Fault (schema Fault 1) (op Str) (why Str) (cause (Option Fault)))
(newtype Chars Int)   (newtype Octets Int)
(newtype Instant I64) (newtype WallTime I64) (newtype Ticks I64) (newtype Duration I64)
(fn fault ((op Str) (why Str)) Fault (bounds (depth 1) (alloc 0)) …)
(fn (context T) ((r (Result T Fault)) (op Str) (why Str)) (Result T Fault) …)
```

Prelude names may not be redefined (`duplicate-definition`). Prelude declarations are
checked with the module but contribute no diagnostics of their own, and their proof
obligations are not counted as the module's.

---

## 5. Static semantics

A program is **accepted** when it produces no error. Warnings do not prevent acceptance
but an authoring tool should treat them as failures (PRIMER §0).

### 5.1 Judgements

The core judgement is

> Γ ; pc ⊢ e : τ @ ℓ ! ε

read as: under environment Γ, with program-counter labels pc, expression `e` has type τ,
carries label set ℓ, and performs at most effects ε. Γ maps names to typed slots; pc is
the set of labels of the data that decided which code is running (§5.3).

A function `(fn f (x:τ*) τ_r clauses body)` is well-typed when

> {x:τ*} ; ∅ ⊢ body : τ_r @ ℓ ! ε  with  ℓ ⊆ labels(τ_r)  and  ε ⊆ declared(f)

and its contracts, bounds and termination obligations (§5.9–§5.11) are discharged.

### 5.2 Names and scopes

A binding or parameter may not be named like a group of primitives (`str`, `num`,
`clock`, …), because `str.chars` would then read either as a primitive or as a field of
something called `str`, and the audit view would be ambiguous (`naming`).

Every reference must resolve (`unknown-name`, `unknown-type`, `unknown-variant`,
`unknown-field`, `unknown-effect`). A name is never guessed and never implicitly
imported. A binding may not reuse a name already in scope (`shadowing`), a parameter,
field or binder name may not repeat (`duplicate-binding`), and a name may not be declared
twice in its namespace (`duplicate-definition`). Case rules are enforced (`naming`).

Functions are not values: a function name in a value position is `not-a-value`. A call
must supply exactly the declared number of arguments (`arity`); a generic or
width-polymorphic type must be given exactly its type arguments (`type-arity`).

### 5.3 Labels, and the flow rule

A type may carry a finite set of labels. Labels are free symbols with no declared
meaning; by convention `Secret`, `Unsanitised`, `Personal`, `tenant:<id>`, and the two
the language itself applies: `Unverified` (§5.8) and `ModelOutput` (§5.12).

**Flow.** A value of type τ@ℓ may be used where τ@ℓ′ is required only when ℓ ⊆ ℓ′, and
the same holds inside type arguments, record fields and tensor elements. A violation is
`label-flow`.

**Propagation.** The label set of a result is the union of the label sets of everything
it was computed from: the operands of a pure primitive, the scrutinee of a `match`, the
condition of an `if`, the record of a `get`, the value a newtype wraps, the patch in an
`update`, the input and the model of an `infer`.

**Implicit flow.** Entering an `if` branch or a `match` arm adds the labels of the
condition or scrutinee to pc. If ε ≠ ∅ and pc ≠ ∅ the program is rejected
(`effect-under-label`): whether an effect happened would reveal the data that chose the
branch.

**Release.** The only way to remove a label is `(declassify L e)`, inside a function
declaring `(declassifies L)` (`undeclared-declassify`). It removes `L` everywhere in the
value's type. Releasing a label the value does not carry is `needless-declassify`
(warning); declaring a release that never happens is `unused-declassify` (warning).

**Sinks.** The primitives marked *sink* in §6.3 accept only unlabelled arguments.

### 5.4 Polymorphism

A function may declare type parameters and at most one label parameter.

- Inside the body a type parameter is **rigid**: it is a type equal only to itself, so no
  primitive applies to it (`type-mismatch`).
- At a call, each type parameter is solved from the arguments. Argument positions sharing
  one parameter must agree, and their label sets join, so argument order never decides a
  result's labels.
- A label parameter stands for a label *set*. Inside the body it behaves as one
  unremovable label, held internally as `?L`; at a call it is solved as the union of the
  labels the arguments carry at every position mentioning it, and the result carries that
  union. The body cannot release it (`needless-declassify`).

Neither kind of parameter is part of a definition's identity (§8).

### 5.5 Effects

Each function declares the effects it performs. Performing an undeclared effect is
`undeclared-effect`; declaring an unperformed one is `unused-effect` (warning). The effect
set is closed (§6.3 lists which primitive performs what). A call performs what its callee
declares, except where `unused-effect` asks of a function on a cycle of calls: there what
the cycle's functions perform is what any of them performs other than by calling one
another, since a call around the cycle is taken at the very declaration in question.

`Alloc` is performed by building a value whose size its type does not fix. `Nondet` is
performed by a `par` whose branches observe order (§5.7). Neither is a capability a host
grants; both exist so a profile can refuse them (§5.13).

### 5.6 Matching

A `match` requires an enum (`match-non-enum`), must name every variant of it exactly once
(`non-exhaustive`, `duplicate-arm`), must bind exactly as many names as the variant has
fields (`pattern-arity`), and may not use a wildcard arm (`no-wildcard`). All arms must
have one type, and the result carries the scrutinee's labels.

Records are read with `get` and copied with `with`, both only on records
(`not-a-record`); `make` requires every field, in declaration order, with no defaults
(`missing-field`, `field-order`); `unwrap` applies only to a newtype
(`unwrap-non-newtype`); `update` applies a patch of exactly the record's own type
(`not-a-patch`). A non-`Unit` value in a non-final `seq` position is `discarded-value`.

### 5.7 Doing several things at once

`(par ((x e)+ ) body)`: each `e` is typed in the environment outside the `par`; the body
is typed with each `x` bound to its branch's type. Branches cannot see one another.

A branch performing any effect other than `Alloc` makes the result depend on the order
branches run in. That is allowed only if the enclosing function declares `Nondet`, and
then the `par` itself performs `Nondet`; otherwise `nondeterministic-par`.

`(scope ((x e (deadline d) (on-fail p) [(on w)])+) body)`: each `e` must have type
`(Result T Fault)` (`task-shape`) and `d` must be a `Duration`; inside the body `x` has
type `T`. The body must also have type `(Result U Fault)` (`task-shape`), and that is the
scope's type: a task whose policy does not recover becomes the scope's `Err`. A scope
performs `Clock`.

A placement is `inline`, `thread`, `core` (the default), `process` or `node`. For
`process` and `node` everything crossing must be transferable (§4.5) — the branch's or
task's type — otherwise `placement`.

### 5.8 Code from outside

`(foreign f (x:τ*) τ_r [uses ε])` declares a function with no body. A call performs
`Foreign` together with ε, and its result carries `Unverified` in addition to the labels
of its arguments. Nothing else about it is known.

### 5.9 Contracts

`(requires c)` and `(ensures c)` are expressions of type `Bool` over the parameters, and
over `result` in an `ensures` (`result-outside-ensures`). A contract must be pure: it may
perform no effect other than `Alloc` and may not declassify (`contract-impure`). A
contract is erased before execution; it may therefore read labelled data freely.

Obligations:

- at every call of `f`, the caller must establish `requires(f)` with the arguments
  substituted (`unproven-precondition`);
- in `f`'s body, `ensures(f)` must follow from `requires(f)` and the body
  (`unproven-postcondition`);
- building a value of a refined newtype must establish its condition
  (`unproven-precondition`);
- a fixed-width arithmetic result or narrowing conversion must lie in the type's range
  (`overflow`).

Every value of a refined newtype satisfies its condition wherever it appears, including
inside generic containers. An implementation must discharge at least the obligations the
conformance suite requires; a *sound* implementation may discharge more, since failing to
prove something true costs only expressiveness, while proving something false is wrong.

### 5.10 Termination

Every cycle in the call graph must have a **measure**: one parameter position per
function in the cycle such that every call around the cycle lowers it, where the measure
is that parameter clamped at zero. Two kinds of decrease are recognised:

- **structural** — the argument is a part of the caller's measure: a `match` binder of it,
  or a field read from it;
- **numeric** — both positions are integer-typed and the argument is provably less than
  the caller's parameter while that parameter is provably above zero.

A cycle with no such measure is `no-termination-proof`. Without this, an `ensures` would
hold vacuously.

### 5.11 Resource bounds

`(bounds (depth N) (alloc N) (repeats N))` states upper bounds, each checked against a
static cost:

- allocations **add** along a path and take the **worst** of alternative branches;
- `depth` is one plus the deepest call made, with parallel branches taking the worst;
- a cycle is as deep as its body once per repeat, where the repeat count is derived by
  bounding its measure (§5.10); a structural measure carries no number, so such a cycle is
  unbounded;
- what a cycle builds is its bodies' allocations once for every time a body can run: when
  one pass through a body calls back into the cycle at most *k* times (calls add along a
  path and take the worst of alternative branches, as allocations do), a cycle entered *n*
  deep runs its bodies at most 1 + *k* + … + *k*<sup>*n*−1</sup> times — *n* when *k* is
  one, and 2<sup>*n*</sup> − 1 for a body that calls itself twice;
- work placed in separate memory costs this target nothing.

A declared bound below the computed cost, or one that cannot be computed, is
`resource-bound`. On a profile that requires bounds, a function without them is also
`resource-bound`.

### 5.12 Tensors and models

`tensor.add` requires both operands to have the same format and the same axes.
`tensor.matmul` contracts the last axis of its left operand with the first axis of its
right, which must agree by name **and** size; the result has the left's remaining leading
axes followed by the right's remaining trailing axes. Any mismatch is `shape`.

`(infer M e)` requires `e` to have `M`'s input type; it performs `Gpu`, `Npu` or `Alloc`
according to `M`'s device, and its result has `M`'s output type carrying `ModelOutput`,
the labels of `e`, and `M`'s training labels.

### 5.13 Profiles

A profile is a set of effects together with a set of placements. A definition builds for
a profile exactly when its declared effects and the placements it names are inside them
(`profile-effect`, `placement`). Profiles are not dialects: no program text depends on
which profile it is built for.

The `mcu` and `esp32` profiles are for machines with 32-bit words. A value there is one
word, so a definition whose declared types mention `Int`, `I64` or `U64` does not fit
(`profile-type`), exactly as one whose effects are not provided does not. `I8` … `I32`,
`U8` … `U32`, `Bool`, `Str`, records, enums and the prelude's newtypes remain.

| Profile | Effects | Placements | Bounds |
|---|---|---|---|
| `host` | all | all | optional |
| `embedded` | `Alloc Clock Ipc Log Store` | `inline thread core` | optional |
| `esp32` | `Alloc Clock Log Net` | `inline thread core` | required |
| `mcu` | `Clock Log` | `inline` | required |

On `mcu` an image is built only when what it can use of each stack is bounded in bytes
before it runs and fits the room the image has: a call's frame from the compiled body, a
chain of calls as the sum of its frames, a recursion as its proved `depth` (§5.11) times
the largest frame it reaches. A recursion without a declared `depth`, or a program that
allocates, has no such bound and is not built.

### 5.14 Logging and redaction

`(redact L p)` declares how data labelled `L` may appear in a log field. One policy per
label; an unknown policy, a second policy for one label, or a policy nothing uses is
`redaction` (the last is a warning).

`(log.fields (n e)+)` performs `Log` and has type `Unit`. Every label carried by any
field must have a policy (`undeclared-redaction`). A field's rendering is decided by the
**strictest** policy among its labels, ordered `hidden` > `digest` > `length` > `keep`;
an unlabelled field renders as `keep`. The policy that applies is part of the enclosing
definition's identity (§8).

### 5.15 Tests

`(test …)`, `(property …)` and `(snapshot …)` state propositions. A test's body is `Bool`
(`Str` for a snapshot), it may perform no effect other than `Alloc`, and a property's
inputs must be of a type an implementation can enumerate values of (`test-shape`). They
do not affect the meaning of any other declaration.

---

## 6. Dynamic semantics

### 6.1 Evaluation

Evaluation is call-by-value, left to right, with no short-circuiting: `and` and `or`
evaluate both operands. There is no mutation, so every value is immutable and sharing is
never observable. Labels, contracts, bounds and types are **erased**: they decide whether
a program runs, never what it computes.

`(if c a b)` evaluates `c` then exactly one branch. `(match e …)` evaluates `e` then the
arm whose variant matches. `(seq e+)` evaluates each in order and answers the last.
`(let x e b)` binds the value of `e` and answers `b`.

`(par ((x e)+) body)` answers what the sequential reading of the same branches answers;
an implementation may evaluate branches concurrently, and §5.7 is what makes that the
same answer.

`(scope ((x e (deadline d) (on-fail p))+) body)` evaluates each task in turn. A task
answering `(Err …)`, or exceeding its deadline, fails; `restart N` retries it at most `N`
times, and a failure that is not recovered is the scope's answer. Otherwise `x` is bound
to the `Ok` payload and the body is evaluated.

Recursion depth is bounded only by available memory; an implementation must report
exhaustion rather than behave unpredictably.

### 6.2 Capabilities

An entry point runs only if the host grants every effect it declares, except `Alloc` and
`Nondet`, which are not capabilities. A primitive re-checks its effect when it runs. A
`foreign` call runs only if the host supplies an implementation; an `infer` only if the
host supplies the model's weights.

### 6.3 Primitives

`#` is one number type, the same at every `#` position; `N` is one integer type.

| Primitive | Type | Effect | Notes |
|---|---|---|---|
| `+` `-` `*` | # # → # | — | fixed-width integers carry an `overflow` obligation; floats round per §6.4 |
| `<` `<=` `=` | # # → Bool | — | exact |
| `num.div` | # # → `(Option #)` | — | `None` on a zero divisor |
| `wrap.add` `wrap.sub` `wrap.mul` | N N → N | — | modular at the width; fixed widths only |
| `sat.add` `sat.sub` `sat.mul` | N N → N | — | clamped to the range; fixed widths only |
| `bit.and` `bit.or` `bit.xor` | N N → N | — | on the width's bit pattern; fixed widths only; total |
| `bit.not` | N → N | — | every bit of the width turned over; fixed widths only; total |
| `bit.shl` `bit.shr` | N Int → N | — | the count is a number of positions; both fill with zero, and a count outside 0 … width-1 gives zero; fixed widths only; total |
| `bit.sar` | N Int → N | — | the arithmetic shift: fills from the top bit of the width, and a count outside 0 … width-1 leaves only that bit (all ones or all zeros); fixed widths only; total |
| `int.of` | # → Int | — | widening, always defined |
| `i8.of` `i16.of` `i32.of` `i64.of` | # → that width | — | `overflow` obligation |
| `u8.of` `u16.of` `u32.of` `u64.of` | # → that width | — | `overflow` obligation |
| `f16.of` `bf16.of` `f32.of` | # or `Real` → that format | — | rounds per §6.4 |
| `and` `or` | Bool Bool → Bool | — | both operands evaluated |
| `not` | Bool → Bool | — | |
| `concat` | Str Str → Str | `Alloc` | |
| `str.eq` | Str Str → Bool | — | exact code points |
| `str.chars` | Str → `Chars` | — | code points |
| `str.octets` | Str → `Octets` | — | bytes of the UTF-8 encoding |
| `str.encode` | Str → Bytes | `Alloc` | UTF-8, total |
| `bytes.decode` | Bytes → `(Result Str Fault)` | `Alloc` | UTF-8 |
| `bytes.len` | Bytes → `Octets` | — | |
| `bytes.eq` | Bytes Bytes → Bool | — | |
| `bytes.concat` | Bytes Bytes → Bytes | `Alloc` | |
| `bytes.at` | Bytes `Octets` → `(Option U8)` | — | nothing where there is no such byte |
| `bytes.slice` | Bytes `Octets` `Octets` → Bytes | `Alloc` | from, up to; clamped to what is there |
| `bytes.of` | U8 → Bytes | `Alloc` | one byte |
| `(bytes "hex")` | → Bytes | — | a literal, not a call: pairs of hexadecimal digits, either case, so any byte value; the empty string is empty `Bytes`; anything else is a parse error. Hashed by its bytes |
| `array.len` | `(Array T)` → `Count` | — | |
| `array.at` | `(Array T)` `Count` → `(Option T)` | — | nothing where there is no such element |
| `array.empty` | → `(Array T)` | `Alloc` | the element type comes from the use |
| `array.push` | `(Array T)` T → `(Array T)` | `Alloc` | a new array, one longer |
| `num.to_str` | # → Str | `Alloc` | |
| `tensor.add` `tensor.matmul` | §5.12 | `Alloc` | |
| `print` | Str → Unit | `Console` | sink |
| `log` | Str → Unit | `Log` | sink |
| `net.send` | Str Str → Str | `Net` | sink |
| `store.put` | Str Str → Unit | `Store` | sink; one assignment |
| `store.get` | Str → `(Option Str)` | `Store` | sink |
| `clock.now` | → `Instant` | `Clock` | monotonic |
| `clock.wall` | → `WallTime` | `Clock` | UTC |
| `clock.ticks` | → `Ticks` | `Clock` | device counter |
| `instant.since` `wall.since` | two readings of one clock → `Duration` | — | |
| `ticks.since` | `Ticks` `Ticks` → `Ticks` | — | |
| `instant.plus` `wall.plus` | reading `Duration` → reading | — | |
| `duration.of_ms` `duration.ms` | `I64` ↔ `Duration` | — | |
| `env.secret` | Str → `(label Secret Str)` | `Env` | sink for its argument |

### 6.4 Numbers

Integer arithmetic on `Int` is exact and unbounded. On a fixed width it is exact because
§5.9 proves the result is in range. `wrap.*` is arithmetic modulo the width; `sat.*`
clamps to the range.

`bit.*` works on the bit pattern a fixed width holds, and on nothing else: each operand
is read as that pattern, the operation is applied to it, and the answer is read back as a
value of the width — two's complement where the width is signed, so `(bit.not (u8.of 0))`
is 255 and `(bit.not (i8.of 0))` is -1. `Int` is rejected because an unbounded integer
has no width, so it has no complement and no position for a shifted bit to leave from.
Both shifts fill with zero, which makes `bit.shr` a movement of bits and not a division:
on a signed width the sign bit moves along like any other. `bit.sar` is the shift that does
fill with the top bit of the width, so on a signed width it is division by a power of two
rounded toward minus infinity; a count outside `0 … width-1` leaves only that bit. None of
the seven can leave the
width it works in, so none carries the obligation of §5.9, and a shift count outside
`0 … width-1` answers zero (or, for `bit.sar`, the filled bit) rather than making the
operation partial.

Floating arithmetic is IEEE 754 with round-to-nearest-even, applied **once per
operation** in the format of the operands. No reassociation, no wider intermediate, no
contraction of several operations into one. A decimal literal is converted by the
conversion that names its format, with the same rounding. Consequently `(a+b)+c` and
`a+(b+c)` may differ, and both are defined.

### 6.5 Observability

A log line written by `log.fields` carries the position of the task that wrote it in the
task tree: the root is `1`, and each `par` branch and `scope` task appends its position.
Each field is rendered through the policy of §5.14; the unredacted value never reaches
the sink.

### 6.6 Journalling

An implementation may record every effect performed, with what it answered, and replay
that record. A replay answers each effect from the record **without performing it**, in
the order recorded; a record that does not match the program, or that runs out, must be
reported rather than guessed at. A recorded run therefore reproduces exactly.

---

## 7. Diagnostics

A diagnostic names the **rule** it enforces, a severity (`error` or `warning`), a
position, the enclosing definition, and zero or more candidate repairs. Rule identifiers
are part of the language: §9 maps every one of them to the judgement it enforces.

---

## 8. Identity and the canonical form

A definition's **identity** is the hash of its canonical form. The canonical form is a
tree of JSON-encodable values, serialised with sorted keys and no insignificant
whitespace, hashed with SHA-256 and written `wtn:<hex>`.

What is *not* part of identity: the definition's own name, its parameters' names, its
binders' names, its type parameters' names, its label parameter's name, the order of
`match` arms, the order of effects or released labels, and all layout and comments.

What *is*: the structure of the body with variables as de Bruijn indices; the types of
parameters and result, with labels sorted and type parameters by position; declared
effects and released labels as sorted sets; contracts and bounds; a record's field names
and order, and its schema and version; a newtype's refinement; a channel's payload,
schema and accepted labels; a model's shapes, training labels, device and weights hash;
a foreign declaration's **name**, because that is the symbol being called outside; the
redaction policy that applies at each log field; the placement of each branch and task.

References to other definitions are by hash, so a rename cannot break a caller. A
mutually recursive group is hashed as one object, its members ordered by name, with
members referring to one another by position.

Two definitions with the same canonical form are the same definition.

---

## 9. The core calculus, and where every rule lives

The surface language elaborates into a small core, which is what the Phase 1 kernel will
check. Elaboration resolves names to indices and hashes, and drops everything §8 says is
not identity.

### 9.1 Core terms

```
τ ::= P | N⟨τ*⟩ | τ@ℓ | tensor(F, (a:n)*)        types: primitive, named, labelled, tensor
e ::= i                                          variable, de Bruijn index
    | k                                          constant
    | call(h, e*)                                a definition, by hash
    | prim(p, e*)                                a primitive
    | con(h, j, e*)                              variant j of enum h
    | case(e, (j, e)*)                           exhaustive, one arm per variant
    | let(e, e)
    | rec(h, e*) | proj(e, i) | upd(e, (i, e)*)   records
    | release(L, e)                              declassify
    | fork((e, w)*, e)                           par, with a placement per branch
    | supervise((e, e, p, w)*, e)                scope: work, deadline, policy, placement
    | chan(send|recv, h, e*)                     a channel, by declaration hash
    | run(h, e)                                  a model, by declaration hash
```

Judgements:

```
Γ ⊢ τ ok                                   a type is well formed
Γ ; pc ⊢ e : τ @ ℓ ! ε                     the term judgement of §5.1
Γ ; φ ⊨ c                                  c follows from the assumptions φ
Γ ⊢ cycle(f*) measured by (f ↦ i)*         a cycle has a falling measure
Γ ⊢ e ≤ (depth d, alloc a)                 a term's static cost
```

Elaboration: `seq` becomes nested `let`; `if` becomes `case` over `Bool`; `with` and
`update` become `upd`; `unwrap` and a newtype constructor are identities on the
representation and change only the type; `make`/`get` become `rec`/`proj`;
`log.fields` becomes `prim` with the policy of each field resolved; a contract becomes an
obligation of the form `Γ ; φ ⊨ c`. `fork`, `supervise`, `chan` and `run` are core forms:
their meaning is primitive and cannot be desugared.

### 9.2 Rule map

Every rule identifier, and the judgement or side condition it enforces.

| Rule | Where it lives |
|---|---|
| `syntax` | §3: the term does not parse |
| `naming` | §2, §5.2: case and namespace conditions on names |
| `duplicate-definition` | §5.2: one declaration per name per namespace |
| `duplicate-binding` | §5.2: distinct names in one binder list |
| `shadowing` | §5.2: Γ does not already bind the name |
| `unknown-name` | §5.2: the name is not in Γ or the definition environment |
| `unpinned-import` | §3.9: a `(use module.name ...)` has not been pinned to its hash |
| `unresolved-import` | §3.9: the codebase does not hold that hash, or two imports claim one name |
| `unknown-type` | §5.2 with `Γ ⊢ τ ok` |
| `type-arity` | `Γ ⊢ τ ok`: a named type gets exactly its arguments |
| `unknown-effect` | §5.5: ε is drawn from the closed effect set |
| `unknown-variant` | `case`: each arm names a variant of the scrutinee's enum |
| `not-a-value` | §5.2: a definition name is not a term |
| `arity` | `call`/`con`/`prim`: exactly the declared arguments |
| `type-mismatch` | the type part of `Γ ; pc ⊢ e : τ @ ℓ ! ε`, with §4.3 equality |
| `label-flow` | the label part: ℓ ⊆ ℓ′ (§5.3), sinks included |
| `undeclared-declassify` | `release(L, e)` requires L ∈ declassifies(f) |
| `needless-declassify` | `release(L, e)` where L ∉ ℓ(e) — warning |
| `unused-declassify` | L ∈ declassifies(f) unused in the body — warning |
| `undeclared-effect` | the effect part: ε ⊆ declared(f) |
| `unused-effect` | declared(f) ⊄ ε — warning |
| `effect-under-label` | ε ≠ ∅ requires pc = ∅ (§5.3) |
| `no-wildcard` | `case` has no default arm |
| `non-exhaustive` | `case` has one arm per variant |
| `duplicate-arm` | `case` has at most one arm per variant |
| `pattern-arity` | an arm binds exactly the variant's fields |
| `match-non-enum` | `case` applies only to a named enum |
| `not-a-record` | `rec`/`proj`/`upd` apply only to a record |
| `unknown-field` | `proj`/`upd` name a field the record has |
| `missing-field` | `rec` supplies every field |
| `field-order` | `rec` supplies them in declaration order |
| `discarded-value` | a non-final `let` body of non-`Unit` type |
| `unwrap-non-newtype` | the newtype identity applies only to a newtype |
| `labelled-newtype` | `Γ ⊢ τ ok` for a newtype's inner type: ℓ = ∅ |
| `empty-enum` | an enum has at least one variant |
| `main-params` | an entry point takes no arguments |
| `contract-impure` | a contract's ε ⊆ {Alloc} and contains no `release` (§5.9) |
| `result-outside-ensures` | `result` is in Γ only while checking an `ensures` |
| `unproven-precondition` | `Γ ; φ ⊨ requires(f)[args]`, and refinements (§5.9) |
| `unproven-postcondition` | `Γ ; φ ⊨ ensures(f)[result ↦ body]` |
| `no-termination-proof` | `Γ ⊢ cycle(f*) measured by …` (§5.10) |
| `overflow` | `Γ ; φ ⊨ lo ≤ e ≤ hi` for a fixed width (§5.9) |
| `schema-version` | §4.4: versions are distinct and at least 1 |
| `schema-incompatible` | §4.4: the three conditions between consecutive versions |
| `not-a-patch` | `upd` by a patch of exactly that record |
| `redaction` | §5.14: one known policy per label; unused is a warning |
| `undeclared-redaction` | §5.14: every label on a log field has a policy |
| `profile-effect` | §5.13: declared(f) ⊆ effects(profile) |
| `profile-type` | §5.13: a 32-bit profile mentions no `Int`, `I64` or `U64` |
| `resource-bound` | `Γ ⊢ e ≤ (depth d, alloc a)` against what is declared (§5.11) |
| `nondeterministic-par` | §5.7: a branch's ε ⊆ {Alloc}, or Nondet is declared |
| `task-shape` | §5.7: a task's work and a scope's body are `(Result T Fault)` |
| `channel-payload` | §4.6: the payload is a record with a schema |
| `placement` | §5.7 with §4.5: separate memory carries only transferable types |
| `shape` | §5.12: axes agree by name, size and order |
| `test-shape` | §5.15: a test is a pure proposition of the right type |

---

## 10. What this specification does not yet fix

Stage 0 is a prototype, and these are known to be unsettled rather than decided:

- **The evidence format.** §5.9 says obligations must be discharged but not what a proof
  *is*. Phase 1 defines that, and until then an implementation's prover is trusted.
- **The prover's strength.** Any sound procedure conforms, so two conforming
  implementations may disagree about which true programs they accept. The conformance
  suite pins the cases that must work; beyond those, strength is a quality, not a
  requirement.
- **The audit view**'s syntax is not specified here, only its two properties: it hides
  nothing a signature says, and every definition read back out of it is the definition
  that went in. An implementation may project differently as long as both hold.
- **Collectives, autodiff, quantised tensors, cancellation of a running task, periodic
  liveness contracts, modulo, float-to-integer conversion, and reading the trace id in
  code** do not exist yet (ROADMAP).
