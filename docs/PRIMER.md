# Witness Primer — for AI authors

```yaml
document: witness-primer
audience: AI code generators (humans welcome)
language: Witness
also-called: W                # informal short name; same language
stage: 0                     # the Python prototype in this repository
file-extension: .wtn
normative: true              # this file describes what the Stage 0 checker accepts today
verified-by: tests/test_primer.py   # every ```wtn block below is checked by the test suite
companions: [SPEC.md (what it is), DESIGN.md (why), ROADMAP.md (what is planned)]
```

## 0. Contract for the reader

- **Emit only constructs defined in §2–§9.** DESIGN.md describes features that do not
  exist yet (collectives, autodiff, quantised tensors, …). They are listed in §13.
  Emitting them produces `syntax` or `unknown-name` errors.
- **Every program is one complete `(module ...)` per file.** There are no imports.
- **Unknown is an error, never a guess.** If a builtin is not in §7, it does not exist.
- **Success means zero errors *and* zero warnings** from `witness check`.
- **Fix the cause, not the symptom.** §10 gives the correct repair for every rule,
  and §10.2 lists repairs that are forbidden even though they silence the checker.
- **Write in the canonical form.** `witness fmt --check` must pass: a tree has exactly
  one spelling (§12), and layout is not something to have an opinion about.
- Rules are cited as `[rule-id]`; the same ids appear in checker output.

## 1. Mental model

1. A program is a tree of definitions: `enum`, `newtype`, `record`, `fn`. Order does not
   matter. The prelude adds `Option` and `Result` to every module.
2. Types are nominal. Nothing converts implicitly. There is no null.
3. A type may carry **labels** (`Secret`, `Unsanitised`, `tenant:acme`). Labels spread to
   everything computed from the value and block it from **sinks**.
4. A function declares its **effects** (`uses Net Console`). Pure is the default.
5. Every `match` names every variant. There is no wildcard.
6. A function may carry a **contract** (`requires` / `ensures`). It is proved at check
   time and erased before anything runs: a contract never fails, it only fails to check.
7. **Recursion must provably make something smaller**, or the proofs above would be
   worth nothing — a function that never returns satisfies any `ensures`.
8. The checker gate cannot be skipped: rejected code cannot run, hash or be stored.

## 2. Lexical rules

| Item | Rule |
|---|---|
| Comment | `;` to end of line |
| Integer | `-?[0-9]+`; the literal's type is `Int`, the unbounded integer. Fixed widths are separate types reached by conversion: `(u8.of 200)` |
| Decimal | `-?[0-9]+\.[0-9]+`; its type is `Real`, which has **no format** and no arithmetic. Name one: `(f32.of 1.5)` |
| String | `"..."` on one line; escapes `\n` `\t` `\"` `\\` only |
| Boolean | `true` `false` |
| Unit value | `unit` |
| Delimiters | whitespace `(` `)` `;` `"` — any other run of characters is one symbol, so `net.send`, `<=` and `tenant:acme` are single symbols |
| Keywords | `module enum newtype record patch foreign redact channel accepts model tensor infer test property snapshot fn let if match seq unwrap make get with update declassify label uses declassifies requires ensures result schema bounds par scope deadline on-fail on send recv unit true false _` — never usable as names |
| Reserved prefix | No name may start with `?`; the checker uses it for label parameters |

## 3. Grammar

```ebnf
file         = module ;                                   (* exactly one per file *)
module       = "(" "module" name decl* ")" ;
decl         = enum | newtype | record | patch | foreign | redact | channel | model
             | test | property | snapshot | fn ;
enum         = "(" "enum" enumname variant* ")" ;         (* zero variants -> [empty-enum] *)
enumname     = Upper | "(" Upper Upper+ ")" ;            (* generic: (Option T) *)
variant      = "(" Upper field* ")" ;                     (* no fields: (Name) *)
field        = "(" lower type ")" ;
newtype      = "(" "newtype" Upper type [refine] ")" ;
refine       = "(" "requires" lower expr ")" ;              (* names the wrapped value *)
record       = "(" "record" Upper [schema] field* ")" ;
schema       = "(" "schema" Upper INT ")" ;                 (* wire name and version *)
patch        = "(" "patch" Upper Upper ")" ;                (* name, record it updates *)
foreign      = "(" "foreign" lower "(" param* ")" type [uses] ")" ;
redact       = "(" "redact" Label policy ")" ;
channel      = "(" "channel" Upper Upper [accepts] ")" ;  (* name, payload record *)
accepts      = "(" "accepts" Label* ")" ;
model        = "(" "model" Upper "(" "input" type ")" "(" "output" type ")"
                   "(" "trained-on" Label* ")" "(" "device" dev ")"
                   "(" "weights" STRING ")" ")" ;
dev          = "cpu" | "gpu" | "npu" ;
test         = "(" "test" STRING expr ")" ;               (* a Bool that must hold *)
property     = "(" "property" STRING "(" param* ")" [requires] expr ")" ;
snapshot     = "(" "snapshot" STRING expr STRING ")" ;    (* a Str and what it said *)
policy       = "hidden" | "digest" | "length" | "keep" ;
fn           = "(" "fn" fnname "(" param* ")" type clause* expr ")" ;
fnname       = lower | "(" lower Upper* [labelparam] ")" ;
labelparam   = "(" "label" Label ")" ;                    (* at most one, written last *)
param        = "(" lower type ")" ;
clause       = uses | declassifies | requires | ensures | bounds ;
                                                          (* in this order, once each *)
uses         = "(" "uses" Effect* ")" ;
declassifies = "(" "declassifies" Label* ")" ;
requires     = "(" "requires" expr ")" ;                  (* a pure Bool over the params *)
ensures      = "(" "ensures" expr ")" ;                   (* ... and over "result" *)
bounds       = "(" "bounds" bound+ ")" ;
bound        = "(" ("depth" | "alloc" | "repeats") INT ")" ;
type         = Upper | "(" Upper type+ ")" | "(" "label" Label+ type ")"
             | "(" "tensor" Format axis+ ")" ;
axis         = "(" lower INT ")" ;                        (* a named axis and its size *)
expr         = INT | STRING | "true" | "false" | "unit" | lower | "result"
             | "(" "let" lower expr expr ")"
             | "(" "if" expr expr expr ")"
             | "(" "match" expr arm* ")"
             | "(" "seq" expr+ ")"
             | "(" "unwrap" expr ")"
             | "(" "declassify" Label expr ")"
             | "(" "make" Upper init* ")"                (* every field, declaration order *)
             | "(" "get" expr lower ")"
             | "(" "with" expr init+ ")"                 (* changed fields, declaration order *)
             | "(" "update" expr expr ")"                 (* record, patch of that record *)
             | "(" "log.fields" init+ ")"                  (* a structured log line *)
             | "(" "par" "(" branch+ ")" expr ")"          (* fork-join *)
             | "(" "scope" "(" task+ ")" expr ")"          (* supervised child tasks *)
             | "(" "send" Upper expr ")"
             | "(" "recv" Upper ")"
             | "(" "infer" Upper expr ")"
             | "(" callee expr* ")" ;
init         = "(" lower expr ")" ;
branch       = "(" lower expr [place] ")" ;               (* a name and its work *)
task         = "(" lower expr deadline onfail [place] ")" ;
place        = "(" "on" ("inline"|"thread"|"core"|"process"|"node") ")" ;   (* default core *)
deadline     = "(" "deadline" expr ")" ;                  (* a Duration *)
onfail       = "(" "on-fail" ("fail" | "escalate" | "restart" INT) ")" ;
arm          = "(" "(" Upper lower* ")" expr ")" ;        (* pattern is always a list *)
callee       = lower | builtin | Upper ;                  (* fn, builtin, variant or newtype constructor *)
Upper        = symbol starting upper-case ;               (* types, variants *)
lower        = symbol starting lower-case ;               (* fns, params, fields, bindings *)
Label        = any non-keyword symbol ;                   (* convention: Secret, tenant:acme *)
Effect       = "Alloc" | "Clock" | "Console" | "Env" | "Foreign" | "Gpu" | "Ipc" | "Log"
             | "Net" | "Nondet" | "Npu" | "Store" ;
```

Shape constraints the grammar cannot show:

- A `fn` has exactly one body expression. Use `seq` or `let` to sequence.
- `let` binds exactly one name and has exactly one body: `(let name value body)`.
- A function with no parameters is written `()`.
- A function's name contains no `.` (dots are reserved for builtins).
- Each clause appears at most once: write two conditions as one `(and a b)`, not two
  `requires` clauses.
- `result` is only in scope inside `(ensures ...)` `[result-outside-ensures]`.

## 4. Names `[naming]` `[duplicate-definition]` `[duplicate-binding]` `[shadowing]`

| Kind | Case | Namespace |
|---|---|---|
| Type (`enum`, `newtype`, `record`), variant, type parameter of a type or a function | Upper | types; variants and newtypes share the constructor namespace |
| Function, parameter, field, binding | lower | functions may not reuse a builtin's name |

- A binding (`let`, match binder) may not reuse any name already in scope, including a
  parameter `[shadowing]`. Pick a new name.
- A binding or parameter may not be named after a group of builtins — `str`, `num`,
  `bytes`, `int`, `clock`, `wrap`, `sat`, `store`, `env`, `net`, `tensor`, `instant`,
  `wall`, `ticks`, `duration`, or a width or format — because `str.chars` would then read
  two ways `[naming]`.
- Built-in types: `Bool` `Bytes` `Int` `Str` `Unit`, the fixed widths `I8` `I16` `I32`
  `I64` `U8` `U16` `U32` `U64` (§7.4) and the floating formats `F16` `BF16` `F32`
  (§7.1.1). Prelude types: `Option` `Result` `Fault` and the length
  units `Chars` `Octets`; the names
  `None` `Some` `Ok` `Err` `fault` `context` cannot be redefined `[duplicate-definition]`.

## 5. Types and values

| Need | Write |
|---|---|
| Sum type | `(enum Name (VariantA) (VariantB (field Type)...))` |
| Generic sum type | `(enum (Pair A B) (MkPair (first A) (second B)))`; used as `(Pair Int Str)` |
| Product type with named fields | `(record Site (code Str) (minutes Int))` |
| Distinct unit / id type | `(newtype Seconds Int)`; construct `(Seconds 30)`; read `(unwrap s)` |
| Absent value | `(Option T)`: `(None)` or `(Some v)` |
| Error | `(Result T E)`: `(Ok v)` or `(Err e)` — errors are values |
| Error with a cause chain | `Fault` (prelude): build with `(fault op why)`, add a layer with `(context r op why)` — see §5.1 |
| Labelled type | `(label Secret Str)`, `(label Secret tenant:acme Str)`, `(Option (label Secret Str))` |
| Validated-once type | `(newtype Port U16 (requires n (<= (u16.of 1) n)))` — §5.2 |
| Versioned wire record | `(record SiteV2 (schema Site 2) (code Str) (tenant (Option Str)))` — §5.3 |
| Partial update | `(patch SitePatch SiteV2)`; apply with `(update site p)` — §5.3 |
| Code from outside | `(foreign read_config ((key Str)) Str)` — §5.4 |

The prelude, present in every module and checked with it:

```lisp
(enum (Option T) (None) (Some (value T)))
(enum (Result T E) (Ok (value T)) (Err (error E)))

(record Fault (op Str) (why Str) (cause (Option Fault)))

(fn fault ((op Str) (why Str)) Fault
  (make Fault (op op) (why why) (cause (None))))

(fn (context T) ((r (Result T Fault)) (op Str) (why Str)) (Result T Fault)
  (match r
    ((Ok v) (Ok v))
    ((Err cause) (Err (make Fault (op op) (why why) (cause (Some cause)))))))
```

- Newtypes are nominal: `Minutes` ≠ `Seconds` ≠ `Int` `[type-mismatch]`.
- A newtype wraps an unlabelled type; put labels where it is used `[labelled-newtype]`.
- A generic type is always written with all its arguments: `(Option Int)`, never `Option` `[type-arity]`.
- Type arguments are inferred at construction: `(Some 1)` is `(Option Int)`; `(None)` takes
  its argument from where it is used.
- **Functions may be generic too**: `(fn (unwrap_or T) ((o (Option T)) (fallback T)) T ...)`.
  The type parameters are named with the function, and each call infers them from its
  arguments — they are never written at the call.
- Inside the body a type parameter is **rigid**: nothing is known about `T`, so no
  concrete operation applies to it `[type-mismatch]`. A body that needs `+` or `str.chars`
  needs a concrete type instead.
- Arguments that share a type parameter must agree, and their labels join: a label
  travels through a type parameter, so `(id s)` on `Str@Secret` is `Str@Secret`.
- Functions are not values: no lambdas, no passing `f` as an argument `[not-a-value]`.

### 5.1 Refinement types `[unproven-precondition]`

A `newtype` may carry a condition that every value of it satisfies. The condition names
the value being wrapped, and it is **proved where the value is built** — so nothing
downstream needs to check again:

```wtn
(module ports
  (newtype Port U16 (requires n (<= (u16.of 1) n)))

  ; One check, at the edge, and the Result says what happens when it fails.
  (fn parse ((n U16)) (Result Port Fault)
    (if (<= (u16.of 1) n)
      (Ok (Port n))
      (Err (fault "parse" "0 is not a port"))))

  ; The condition is a fact about the type here, not something to re-test.
  (fn is_privileged ((p Port)) Bool
    (ensures (or result (<= (int.of (u16.of 1024)) (int.of (unwrap p)))))
    (<= (unwrap p) (u16.of 1023))))
```

- The condition must be a pure `Bool` `[contract-impure]`, like any contract.
- `(Port n)` carries the obligation; an unproved one is `[unproven-precondition]`.
- Every value of the type — parameter, field, result — gives the prover the condition for
  free. That is what "validated once at ingress" means in practice.
- The condition is part of the type's identity: changing it changes its hash.

### 5.2 Errors and context

A failure is an `(Err e)`, never an exception. `Fault` is the prelude's error type when a
failure should say where it happened and what it came from, and `context` is the one
operator that adds a layer:

```wtn
(module settings
  (fn parse ((raw Str)) (Result Int Fault)
    (uses Alloc)
    (if (str.eq raw "1")
      (Ok 1)
      (Err (fault "parse" (concat "not a number: " raw)))))

  (fn load ((raw Str)) (Result Int Fault)
    (uses Alloc)
    (context (parse raw) "load" "reading the retry count"))

  (fn trace ((f Fault)) Str
    (uses Alloc)
    (match (get f cause)
      ((None) (get f why))
      ((Some inner) (concat (get f op) (concat " <- " (trace inner)))))))
```

- `(context r op why)` leaves an `(Ok v)` untouched and turns an `(Err cause)` into a new
  `Fault` whose `cause` is the one it wrapped. It is generic in the success type, so it
  works wherever the error is a `Fault`.
- Walking the chain terminates without an annotation: `cause` is a record field, and a
  field is a part of its record (§9.3).
- A `Fault` carries **unlabelled** text. Putting labelled data in an error message is a
  release like any other `[label-flow]`: `declassify` it in a function that admits to it,
  or declare your own error record with the label on the field. Error messages are a
  known leak path, so this is deliberate.
- Any other `E` is still fine: `(Result Int Str)` needs no `Fault`. Use `Fault` when the
  chain is worth keeping.

### 5.3 Wire schemas and partial updates

A record may declare which **wire schema** it is a version of. Data outlives the code
that wrote it, so each version must be able to read, and be read by, the one before it
`[schema-incompatible]`:

```wtn
(module wire
  (record SiteV1 (schema Site 1) (code Str) (note (Option Str)))
  ; A new version may add optional fields and drop fields that were already optional.
  (record SiteV2 (schema Site 2) (code Str) (tenant (Option Str)))

  (patch SitePatch SiteV2)

  (fn retenant ((s SiteV2) (tenant Str)) SiteV2
    (update s (make SitePatch (code (None)) (tenant (Some (Some tenant)))))))
```

Rules between consecutive versions:

| Change | Allowed? |
|---|---|
| add an `(Option T)` field | yes |
| add a required field | no — the older writer does not write it |
| drop a field that was `(Option T)` | yes |
| drop a required field | no — make it optional in a version first |
| change a field's type | never; a wire field keeps its type for ever |

Versions start at 1 and each is declared once `[schema-version]`. The schema name and
version are part of the record's identity.

`(patch P R)` declares a record whose fields are those of `R`, each wrapped in one more
`Option`. A **partial update is its own type**: it cannot be passed where `R` is wanted
`[type-mismatch]`, so no field is ever dropped by not being mentioned.

- `(update r p)` replaces every field the patch gives and keeps the rest.
- A field of `(Option T)` becomes `(Option (Option T))` in the patch: `(None)` keeps the
  old value, `(Some (None))` sets it to absent, `(Some (Some v))` sets it to `v`.
- Only the patch of `R` updates an `R` `[not-a-patch]`.

### 5.4 Foreign code

`(foreign name (params) Ret [(uses ...)])` declares something implemented outside
Witness. There is no body, so nothing about it is checked. Two things follow:

- Calling it performs the **`Foreign` effect**, which the caller must declare, and which
  the host must grant before anything runs.
- Its result is labelled **`Unverified`**, so it cannot reach a sink or a plain return
  type until something in Witness has checked it.

```wtn
(module outside
  (foreign read_config ((key Str)) Str)

  ; One reviewed release point: take the label off into a local, then decide.
  (fn validate ((raw (label Unverified Str))) (Result Str Fault)
    (declassifies Unverified)
    (let text (declassify Unverified raw)
      (if (< 0 (unwrap (str.chars text)))
        (Ok text)
        (Err (fault "validate" "the config value was empty")))))

  (fn host_name () Str
    (uses Foreign)
    (match (validate (read_config "host"))
      ((Ok text) text)
      ((Err f) (get f why)))))
```

A decision taken from unverified data is itself unverified, which is why the pattern
above releases the label **before** branching on the value, in a function whose signature
admits to it. A foreign declaration's name is the symbol being called outside, so unlike
a Witness function's name it is part of its identity.

## 6. Expressions and their typing rules

`T@L` means base type `T` with label set `L`. A position typed `T@A` accepts `T@B` only
when `B ⊆ A`, and the same holds inside type arguments: `(Option Str@B)` fits
`(Option Str@A)` only when `B ⊆ A`. `Unit` never carries labels.

| Form | Rule |
|---|---|
| `(let x v body)` | `x` fresh `[shadowing]`; result = type of `body` |
| `(if c a b)` | `c : Bool@Lc`; `a`, `b` same type; result `T@(La ∪ Lb ∪ Lc)`; any effect inside `a` or `b` when `Lc` is non-empty `[effect-under-label]` |
| `(match s arm...)` | `s : E@Ls` with `E` an enum `[match-non-enum]`; one arm per variant `[non-exhaustive]` `[duplicate-arm]` `[no-wildcard]`; binders positional, count = field count `[pattern-arity]`; each binder gets its field's type (with `s`'s type arguments substituted) plus `Ls`; result = join of arms plus `Ls`; any effect inside an arm when `Ls` is non-empty `[effect-under-label]` |
| `(seq e1 ... en)` | `e1..e(n-1) : Unit` `[discarded-value]`; result = type of `en` |
| `(f a...)` user fn | arity `[arity]`; each arg checked against its param; result = **declared** return type (labels are not inferred through calls) |
| `(b a...)` pure builtin | args checked by base type; result labels = ∪ arg labels |
| `(b a...)` sink builtin | every arg must be unlabelled `[label-flow]` |
| `(Variant a...)` | args checked against field types; type arguments inferred from the args (fields sharing a parameter join their labels); result `(E args...)` |
| `(Newtype v)` | `v` has the inner type; result keeps `v`'s labels |
| `(unwrap v)` | `v : N@L` with `N` a newtype `[unwrap-non-newtype]`; result `Inner@L` |
| `(make R (f v)...)` | `R` a record `[not-a-record]`; every field `[missing-field]`, once `[duplicate-binding]`, in declaration order `[field-order]`, known `[unknown-field]`; each value checked against its field type; result `R` |
| `(get r f)` | `r : R@L` with `R` a record `[not-a-record]`; result = field type plus `L` |
| `(with r (f v)...)` | like `make` for the listed fields only; other fields are kept; result = type of `r` |
| `(update r p)` | `p` is the patch of `r`'s record `[not-a-patch]`; result = type of `r`, plus the patch's labels |
| `(log.fields (n v)...)` | `Unit`; performs `Log`; every label on a field needs a policy `[undeclared-redaction]` (§8.2) |
| `(declassify L v)` | enclosing fn declares `(declassifies L)` `[undeclared-declassify]`; removes `L` everywhere in the type, including type arguments |
| function body | same base as the return type; body labels ⊆ declared labels `[label-flow]` |

Evaluation (Stage 0 interpreter): call-by-value, arguments left to right, **no
short-circuit** (`and`/`or` evaluate both sides), labels erased at runtime. No loops:
iterate with recursion. The interpreter keeps its own stack on the heap, so depth is
limited by memory rather than by the host: millions of calls are fine, and a call in tail
position costs nothing. A runaway computation stops with a clear error instead of
exhausting memory.

## 7. Builtins and effects

| Builtin | Type | Effect | Kind |
|---|---|---|---|
| `+` `-` `*` | # # → # | — | pure; on a fixed-width integer the result is proved in range `[overflow]`, on a floating format it is rounded |
| `<` `<=` `=` | # # → Bool | — | pure; exact, including on floats |
| `num.div` | # # → `(Option #)` | — | pure; nothing when the divisor is zero, so no NaN and no remainder to guess at |
| `f16.of` `bf16.of` `f32.of` | any number or `Real` → that format | — | pure; rounds to nearest even |
| `wrap.add` `wrap.sub` `wrap.mul` | N N → N | — | pure; modular at the width; no proof needed |
| `sat.add` `sat.sub` `sat.mul` | N N → N | — | pure; clamped to the range; no proof needed |
| `bit.and` `bit.or` `bit.xor` | N N → N | — | pure; on the width's bit pattern; fixed widths only; no proof needed |
| `bit.not` | N → N | — | pure; every bit of the width turned over; fixed widths only |
| `bit.shl` `bit.shr` | N `Int` → N | — | pure; the count is a number of positions; both fill with zero, and a count outside `0 … width-1` gives zero |
| `bit.sar` | N `Int` → N | — | pure; the arithmetic shift: fills from the top bit of the width, and a count outside `0 … width-1` leaves only that bit |
| `int.of` | N → Int | — | pure; widening to the unbounded integer, always safe |
| `i8.of` `i16.of` `i32.of` `i64.of` | N → I8 … I64 | — | pure; the value must be proved to fit `[overflow]` |
| `u8.of` `u16.of` `u32.of` `u64.of` | N → U8 … U64 | — | pure; the value must be proved to fit `[overflow]` |
| `and` `or` | Bool Bool → Bool | — | pure (both sides evaluated) |
| `not` | Bool → Bool | — | pure |
| `concat` | Str Str → Str | — | pure |
| `str.eq` | Str Str → Bool | — | pure |
| `tensor.add` | two tensors of one shape → that shape | `Alloc` | pure; elementwise |
| `tensor.matmul` | (…,k) (k,…) → (…,…) | `Alloc` | pure; the contracted axis must match by name and size |
| `str.chars` | Str → `Chars` | — | pure; code points |
| `str.octets` | Str → `Octets` | — | pure; bytes the text would encode to |
| `str.encode` | Str → Bytes | — | pure; UTF-8, always safe |
| `bytes.decode` | Bytes → `(Result Str Fault)` | — | pure; UTF-8, fails on invalid input |
| `bytes.len` | Bytes → `Octets` | — | pure |
| `bytes.eq` | Bytes Bytes → Bool | — | pure |
| `bytes.concat` | Bytes Bytes → Bytes | — | pure |
| `bytes.at` | Bytes `Octets` → `(Option U8)` | — | pure; nothing where there is no such byte |
| `bytes.slice` | Bytes `Octets` `Octets` → Bytes | — | pure; from, up to; clamped to what is there |
| `bytes.of` | U8 → Bytes | — | pure; one byte |
| `array.len` | `(Array T)` → `Count` | — | pure |
| `array.at` | `(Array T)` `Count` → `(Option T)` | — | pure; nothing where there is no such element |
| `array.empty` | → `(Array T)` | `Alloc` | the element type comes from how it is used |
| `array.push` | `(Array T)` T → `(Array T)` | `Alloc` | a new array, one longer |
| `num.to_str` | # → Str | — | pure |
| `print` | Str → Unit | `Console` | sink (stdout) |
| `log` | Str → Unit | `Log` | sink (stderr) |
| `net.send` | Str Str → Str | `Net` | sink; destination, payload; **simulated** — returns `"ok"` |
| `store.put` | Str Str → Unit | `Store` | durable; one assignment, so a key never holds half a value |
| `store.get` | Str → `(Option Str)` | `Store` | durable |
| `clock.now` | → `Instant` | `Clock` | monotonic reading; only differences mean anything |
| `clock.wall` | → `WallTime` | `Clock` | UTC reading |
| `clock.ticks` | → `Ticks` | `Clock` | device counter |
| `instant.since` `wall.since` | two readings of one clock → `Duration` | — | pure |
| `ticks.since` | `Ticks` `Ticks` → `Ticks` | — | pure; elapsed ticks, not a duration |
| `instant.plus` `wall.plus` | reading, `Duration` → reading | — | pure |
| `duration.of_ms` `duration.ms` | `I64` → `Duration`, `Duration` → `I64` | — | pure |
| `env.secret` | Str → `(label Secret Str)` | `Env` | sink for its argument; `""` if unset |

`N` means **one** integer type, the same at every `N` position: `Int`, or one of the
eight fixed widths. `#` widens that to any number — the integers plus the floating
formats. Either way there is no implicit widening, so mixing two of them is a
`[type-mismatch]`, not a promotion.

### 7.1 Text, bytes and lengths

`Str` is always valid text; `Bytes` is raw. They are different types, with no implicit
conversion either way:

- `(str.encode s)` is always safe — text has a valid encoding by construction.
- `(bytes.decode b)` can fail, so it answers `(Result Str Fault)`. That is the only way
  from `Bytes` to `Str`: invalid input is caught there rather than assumed away.
- A length states its unit. `Chars` counts code points and `Octets` counts bytes; both
  are prelude newtypes, so neither passes as the other or as a plain `Int`
  `[type-mismatch]`. Unwrap to compute with one: `(unwrap (str.chars s))`.
- **Nothing looks inside a `Str`.** That is what makes "a `Str` is valid text" true
  rather than hoped for. To read text, work in `Bytes` — `bytes.at` for the nth byte,
  `bytes.slice` for a run of them, `bytes.of` to build one from a number — and decode
  once at the end. All three are total: an index out of range answers `(None)` and a
  slice is clamped, so none of them carries an obligation.
- A walk over a sequence needs a **budget**, because an index does not get smaller on its
  own: carry a count that falls at every step, and guard on it. A measure is clamped at
  zero, so for a function that walks by calling *itself* the guard is all you need —
  `(if (or (<= left 0) (<= (unwrap (bytes.len b)) at)) ... )` tells the prover `left > 0`
  in the branch that recurses. A budget passed *between* functions needs
  `(requires (< 0 left))` on each of them as well, because a branch's facts do not travel
  into a call. [compiler/reader.wtn](../compiler/reader.wtn) is a tokeniser written this
  way and [examples/sequence.wtn](../examples/sequence.wtn) walks an array.

### 7.2 Depending on something

A module imports by content hash, under whatever local name reads well:

```
(use "wtn:5758bd5e..." as sum_of)
```

- The **hash** is what you depend on. A name is local, so the same definition imported
  under two names in two modules is still one definition, with one hash.
- Everything it is built out of comes with it, under the names the codebase has for them.
  You do not list those.
- You do not need the hash to start. Write `(use text.reverse as rev)` — a stored module,
  a dot, a definition — and `witness pin f.wtn --dir <codebase>` rewrites the line to its
  hash. Until then `check` answers `[unpinned-import]` and names the hash it would pin to.
  Only the hash form is ever checked, so a name can never change what a module means.
- Definitions come in one at a time. There is no "import everything from X", because a
  module does not export — the codebase holds definitions and a module writes some down.
- `witness check --dir <codebase>` says which codebase to resolve through; it is
  `.witness` by default. A hash it does not hold is `[unresolved-import]`.

### 7.3 Arrays

`(Array T)` is a sequence read by position. It is a **value**: `array.push` answers a new
array rather than changing the one you gave it, so nothing you hold is ever altered from
somewhere else.

```wtn
(module arrays
  (fn (second T) ((a (Array T)) (fallback T)) T
    (match (array.at a (Count 1)) ((None) fallback) ((Some v) v)))

  (fn sum_two ((a (Array Int))) Int
    (+ (second a 0) (unwrap (array.len a)))))
```

- Reading is total. `array.at` answers `(Option T)`, so an index that is not there is a
  `(None)` you must handle and not a proof you must write.
- An index is a `Count`, a prelude newtype, not a bare `Int` `[type-mismatch]`. Write
  `(Count i)` to make one and `(unwrap (array.len a))` to compute with a length.
- `(array.empty)` says nothing about its element type; whatever reads it decides, exactly
  like `(None)`. If nothing does, that is an `[unresolved-type]`.
- Walking an array needs a budget, as above, and `(unwrap (array.len a))` is where it
  starts. Nothing says a length is non-negative, so do not write a contract that needs
  that: guard on the budget instead, which is what makes the walk finite anyway.

```wtn
(module text
  (fn is_empty ((s Str)) Bool
    (= 0 (unwrap (str.chars s))))

  (fn round_trip ((s Str)) Str
    (uses Alloc)
    (match (bytes.decode (str.encode s))
      ((Ok back) back)
      ((Err f) (get f why))))

  ; A byte count and a character count are different things and do not mix.
  (fn fits_in_frame ((s Str)) Bool
    (<= (unwrap (str.octets s)) 1500)))
```

### 7.1.1 Floating formats

Three formats, each with the layout its name says: `F16`, `BF16`, `F32`. They are
separate types, and nothing converts between them by itself.

```wtn
(module numeric
  ; A decimal literal has no format of its own, so one is named here.
  (fn tenth () F32 (f32.of 0.1))

  ; (a + b) + c and a + (b + c) may differ, and the language does not pretend otherwise.
  (fn sum3 ((a F32) (b F32) (c F32)) F32 (+ (+ a b) c))

  ; Division answers nothing rather than inventing a NaN.
  (fn ratio ((a F32) (b F32)) F32
    (match (num.div a b)
      ((None) (f32.of 0.0))
      ((Some q) q))))
```

- Arithmetic is **strict IEEE**: every operation rounds once, to nearest even, in the
  format of its operands. No reassociation, no wider intermediate, no fast-math — so the
  same program gives the same numbers on every target, which is what makes a model's
  results reproduce.
- `num.div` answers `(Option #)`, so a zero divisor is a `None` rather than a NaN. For
  integers it is division without a remainder.
- A float is **opaque to the prover**: rounding is not linear arithmetic, so contracts
  about floats can say only that a value equals itself. Keep contracts on the integers.
- There is no float literal of a bare type, no implicit promotion, and no conversion from
  a float back to an integer yet.

### 7.2 Target profiles `[profile-effect]`

A **profile** is the set of effects a host provides. `witness check --profile mcu`
accepts a definition exactly when its declared effects fit inside the profile. Profiles
are not dialects: the code is identical, only what fits changes.

| Profile | Provides | Means |
|---|---|---|
| `host` (default) | every effect | an ordinary machine with an OS |
| `embedded` | `Alloc` `Clock` `Log` | an allocator and a clock, no OS services |
| `mcu` | `Clock` `Log` | freestanding: no heap at all, so no allocator is linked |

```wtn
(module device
  (newtype Celsius I16)

  ; No effects at all, so this fits every profile, down to a bare microcontroller.
  (fn too_hot ((reading Celsius) (limit Celsius)) Bool
    (< (unwrap limit) (unwrap reading)))

  ; Building a Str needs a heap, so this one does not fit `mcu`.
  (fn describe ((reading Celsius)) Str
    (uses Alloc)
    (concat "temp " (num.to_str (unwrap reading)))))
```

The Stage 0 interpreter always has a heap, so `run` never asks for `Alloc` to be granted.
`Alloc` is a check-time matter: it is what lets a profile, and a resource bound, talk
about allocation at all.

### 7.3 Time

Three clocks, three types, and they never mix `[type-mismatch]`:

| Type | What it is |
|---|---|
| `Instant` | a monotonic reading; the origin is unspecified, so only differences mean anything |
| `WallTime` | a UTC reading, which can jump backwards when the host clock is corrected |
| `Ticks` | a device counter, whose rate is device knowledge |
| `Duration` | the difference between two readings **of the same clock** |

```wtn
(module timing
  (fn took_too_long ((start Instant) (finish Instant)) Bool
    (< (i64.of 500) (duration.ms (instant.since finish start))))

  (fn due_at ((start Instant)) Instant
    (instant.plus start (duration.of_ms (i64.of 500))))

  (fn main () Unit
    (uses Clock Console)
    (let start (clock.now)
      (let finish (clock.now)
        (print (if (took_too_long start finish) "slow" "fine"))))))
```

- All four are prelude newtypes over `I64` nanoseconds (`Ticks` counts ticks). Unwrap to
  reach the number, and the unit discipline is yours again from that point.
- Reading any clock needs the `Clock` effect. There is no conversion between clocks:
  take a reading from the one you mean.
- Turning elapsed `Ticks` into a `Duration` needs the device rate and division, neither
  of which Stage 0 has.
- Time zones and formatting do not exist; they belong at the presentation edge.

### 7.4 Fixed-width integers

| Type | Range | | Type | Range |
|---|---|---|---|---|
| `I8` | -128 … 127 | | `U8` | 0 … 255 |
| `I16` | -32768 … 32767 | | `U16` | 0 … 65535 |
| `I32` | -2^31 … 2^31-1 | | `U32` | 0 … 2^32-1 |
| `I64` | -2^63 … 2^63-1 | | `U64` | 0 … 2^64-1 |

`Int` is the unbounded integer: arithmetic on it cannot overflow, and it is what literals
give you. (Compiled for bare metal -- Cortex-M and the ESP32 family -- an `Int` that leaves
the machine word stops the program with a trap rather than growing, since memory there is
bounded before the run.) The fixed widths are machine integers, and on them **every
operation must be proved to stay in range** — that is the `[overflow]` rule, discharged
by the same prover as contracts (§9.1).

```wtn
(module counters
  ; The contract supplies the bound; state it over the unbounded values with int.of.
  (fn add ((a U8) (b U8)) U8
    (requires (<= (+ (int.of a) (int.of b)) 255))
    (+ a b))

  ; Or decide what should happen instead of proving it cannot happen.
  (fn add_wrapping ((a U8) (b U8)) U8 (wrap.add a b))
  (fn add_saturating ((a U8) (b U8)) U8 (sat.add a b))

  ; Or widen, compute without a bound, and narrow once the value is known to fit.
  (fn add_checked ((a U8) (b U8)) (Result U8 Fault)
    (let total (+ (int.of a) (int.of b))
      (if (<= total 255)
        (Ok (u8.of total))
        (Err (fault "add_checked" "over 255")))))

  ; A branch can supply the bound too.
  (fn bump ((a U8)) U8
    (if (<= (int.of a) 254) (+ a (u8.of 1)) a)))
```

- Write contracts about fixed-width values with `int.of`, so the arithmetic in the
  contract is unbounded and cannot itself overflow.
- A value's type is a fact the prover uses: a `U8` is known to be between 0 and 255
  everywhere, with no `requires` needed.
- Once an operation is proved in range, later arithmetic may rely on that.
- A product of two unknowns is bounded by bounding its factors; `(* w h)` needs each of
  `w` and `h` bounded by a constant, or `sat.mul` / `wrap.mul` / `Int`.
- Widening is written out (`(u32.of x)`) but needs no proof; narrowing needs one.

Missing on purpose — write the equivalent:

| Wanted | Write |
|---|---|
| `(> a b)` / `(>= a b)` | `(< b a)` / `(<= b a)` |
| negation | `(- 0 x)` or a literal `-5` |
| a fixed-width literal | `(u8.of 200)`; a bare literal is always `Int` |
| a byte literal | `(bytes "0061736d")`, pairs of hex digits |
| string indexing, slicing, search, case folding | not yet |
| Bool or Str equality | `if` / `and` / `or` / `not`; `str.eq` |
| division | `num.div`, which answers an `Option`; there is no modulo |

### 7.4.1 Bit patterns

`bit.and` `bit.or` `bit.xor` `bit.not` `bit.shl` `bit.shr` `bit.sar` work on the bits a fixed width
holds. They are **fixed widths only**: a bitwise operation is a statement about a
particular set of bits, and `Int` is unbounded, so it has no complement to take and no
top bit for a shift to push a value off. Asking for one on an `Int` is a
`[type-mismatch]` with the same shape as `wrap.add` on an `Int`. They are also **total**:
an operation on the bits of a width cannot leave that width, so there is no `[overflow]`
obligation on any of them, and a shift count nobody meant answers zero instead of making
the caller prove the count is sane.

```wtn
(module bits
  ; One rule for all six: read each operand as the pattern its width holds, work on the
  ; pattern, read the answer back as a value of the width. Masking is total, but the
  ; narrowing after it is not, so the `if` is what supplies the bound `u8.of` needs.
  (fn low_byte ((w U32)) U8
    (let masked (bit.and w (u32.of 255))
      (if (<= (int.of masked) 255) (u8.of masked) (u8.of 0))))

  ; Two's complement is why a signed width answers differently: on a U8 the complement
  ; of zero is 255, and on an I8 it is -1.
  (fn invert ((b U8)) U8 (bit.not b))

  ; Rotating left is a shift each way joined together, which is what a hash is made of.
  (fn rotate_left ((w U32) (by Int)) U32
    (bit.or (bit.shl w by) (bit.shr w (- 32 by))))

  (test "the low byte of a word" (= (u8.of 120) (low_byte (u32.of 66680))))
  (test "complement at eight bits" (= (u8.of 254) (invert (u8.of 1))))
  (test "a rotation keeps every bit" (= (u32.of 16) (rotate_left (u32.of 1) 4))))
```

- The second argument of a shift is a plain `Int`, because it counts positions rather
  than being a value of the same kind: a `U8` could not hold the counts a `U64` takes.
- Both shifts fill with zero. `bit.shr` therefore moves bits and is not division by a
  power of two: on a signed width the sign bit travels along like any other bit. Use
  `bit.sar` when the sign should fill in: it is division by a power of two, rounded down.
- The prover knows only that a bitwise result is somewhere inside its width: it does not
  know that `(bit.and w (u32.of 255))` is at most 255. Bit patterns are not linear
  arithmetic, so keep contracts off them, as with floats (§7.1.1) — and where a masked
  value has to be narrowed, let an `if` supply the bound, as `low_byte` does above.

Effect rules:

- Effects used = effects of builtins called + **declared** effects of user functions called.
- Used but not declared → `[undeclared-effect]` (error). Declared but unused → `[unused-effect]` (warning).
- Unknown effect name → `[unknown-effect]`. The set is closed:
  `Alloc Clock Console Env Foreign Gpu Ipc Log Net Nondet Npu Store`.
- `Alloc` and `Nondet` are never *granted*: a heap is simply there, and `Nondet` is a
  statement about the program rather than a capability. Both are still effects, because
  that is what lets a profile refuse them (§7.2).
- **`Alloc` is performed by building a value whose size its type does not fix**:
  `concat`, `num.to_str`, `str.encode`, `bytes.concat`, `bytes.decode`. Records, variants
  and newtypes are fixed-size, so where they live is the compiler's business and costs no
  effect. A function without `(uses Alloc)` needs no heap — that is what makes the `mcu`
  profile below mean something (§7.3).
- `Foreign` is implied by every `(foreign ...)` declaration; the caller still declares it.

## 8. Labels

- A label is any non-keyword symbol. Conventional ones: `Secret`, `Unsanitised`,
  `Personal`, `tenant:<id>`.
- Labels enter through types (`(label Unsanitised Str)` params) and builtins (`env.secret`).
- Labels spread through pure builtins, `if` conditions, `match` scrutinees, newtype
  wrapping, `get`, and into type arguments (`(Some s)` with `s : Str@Secret` is
  `(Option Str@Secret)`).
- Sinks (`print`, `log`, `net.send`, `env.secret`'s argument) accept only unlabelled data.
- **Effects may not depend on labelled data** `[effect-under-label]`: no effect (including
  calls to functions that declare effects) inside an `if` branch or `match` arm decided by
  labelled data — whether the effect happens would reveal the data. Compute a value in
  the branch and perform the effect after it.
- The **only** way to remove a label is `(declassify L v)` inside a function whose
  signature says `(declassifies L)`. Such a function is a reviewed release point; keep it
  small and name it for what it does (`sanitise`, `redact`).

### 8.1 Label parameters

A function may take **one label parameter**, written last in its name, so that one
definition serves every label — including none. Where a type parameter lets the whole
type vary, a label parameter keeps the base type fixed, which is what a body needs when
it calls `concat` or `str.chars`.

```wtn
(module polylabel
  (fn (shout (label L)) ((s (label L Str))) (label L Str)
    (uses Alloc)
    (concat s "!"))

  (fn plain ((s Str)) Str (uses Alloc) (shout s))
  (fn secret ((s (label Secret Str))) (label Secret Str) (uses Alloc) (shout s)))
```

- The caller decides what `L` stands for: every position mentioning it contributes, and
  their labels **join**, so argument order never decides the result.
- `L` is solved inside type arguments too: `(Option (label L Str))` given
  `(Option Str@Secret)` makes `L` stand for `{Secret}`.
- Inside the body `L` is rigid: it may be any label, so the value cannot reach a sink and
  cannot be returned unlabelled `[label-flow]`, and the body cannot release it
  `[needless-declassify]` — only a caller, which knows the label, can.

### 8.2 Logging labelled data

`log` and `print` are sinks and take only unlabelled text. A **structured log line** is
different: `(log.fields (name value)...)` may carry labelled values, but only through a
**redaction policy** declared for each label, and the raw value never reaches the sink.

```wtn
(module tracing
  (redact Secret hidden)
  (redact Personal digest)
  (redact tenant:acme keep)

  (fn trace ((user (label tenant:acme Str)) (email (label Personal Str))
             (key (label Secret Str)) (count Int)) Unit
    (uses Log)
    (log.fields (user user) (email email) (api_key key) (count count))))
```

That line writes `user="acme" email=digest:8595b682a16b api_key=<redacted> count=7`.

| Policy | What appears |
|---|---|
| `hidden` | `<redacted>` — nothing about the value |
| `digest` | a short hash: equal values log equal, and nothing else shows |
| `length` | `<12 chars>` — the size of the rendered value only |
| `keep` | the value, which is a decision someone has to make on purpose |

- One policy per label `[redaction]`, and a policy that is never used is a warning.
- A value carrying several labels gets the **strictest** policy among them, so a lenient
  policy can never override a strict one.
- A field with no labels needs no policy. A declassified value has no labels left, so it
  needs none either — but then the release is visible in the signature, as always.
- The policy that applies is part of what the code does, so it is part of the function's
  content hash: the same body under a different policy is a different definition.

### 8.3 Doing several things at once

`(par ((name work)...) body)` says the branches **may** run at once; the body then sees
all their values. It is **deterministic by default**: every value in Witness is
immutable, so branches cannot race over data, and a data race cannot be written. What
order *could* change is what an effect sees or writes — so an effect in a branch makes
the answer depend on scheduling, and that is the `Nondet` effect, in the signature
`[nondeterministic-par]`.

```wtn
(module fanout
  (fn work ((n Int)) Int (* n n))

  ; Pure branches: the same answer however they are scheduled.
  (fn both ((a Int) (b Int)) Int
    (par ((left (work a)) (right (work b)))
      (+ left right)))

  ; Racing output is real nondeterminism, and the signature says so.
  (fn noisy ((a Int) (b Int)) Int
    (uses Alloc Console Nondet)
    (par ((left (print (num.to_str a))) (right (work b)))
      right)))
```

- A branch sees what came before the `par`, never another branch.
- `Alloc` is allowed in a branch: an allocator is not an observer.
- For bounds (§9.2), depth is the **worst** branch (each has its own stack) and
  allocation is **all** of them (they all run).

`(scope ((name work (deadline d) (on-fail p))...) body)` starts child tasks and waits for
them. Both clauses are required, because a task with neither can stall unnoticed:

| `on-fail` | What the parent does |
|---|---|
| `fail` | the failure becomes the scope's answer |
| `escalate` | the same, said explicitly: it is for somebody further up |
| `restart N` | try again up to `N` times, then escalate |

```wtn
(module survey
  (fn poll ((site Int)) (Result Int Fault)
    (if (< 0 site) (Ok (* site 10)) (Err (fault "poll" "no such site"))))

  (fn survey ((a Int) (b Int) (budget Duration)) (Result Int Fault)
    (uses Clock)
    (scope ((first (poll a) (deadline budget) (on-fail restart 2))
            (second (poll b) (deadline budget) (on-fail escalate)))
      (Ok (+ first second)))))
```

- A task's work must be able to fail — its type is `(Result T Fault)` — or the policy
  would have nothing to act on `[task-shape]`.
- The body's type must be able to carry an escalation, so it is a `(Result T Fault)` too,
  and that is the scope's type `[task-shape]`.
- Inside the body a task's name is the value it produced: the failure is already handled.
- A deadline is a `Duration`, and measuring it needs `(uses Clock)`. Stage 0 runs tasks
  one after another and checks each against its deadline afterwards; the rules above are
  what make running them at once give the same answer.

#### Where work runs

A branch or a task may say how far from here it runs. One task model, four distances —
the semantics never changes, only the cost and what may cross:

| `(on ...)` | Where | What may cross |
|---|---|---|
| `inline` | here, in order | anything |
| `thread` | another thread on this core | anything |
| `core` | **another core, same memory** (the default) | anything |
| `process` | another process on this host | only values with a wire form |
| `node` | another machine | only values with a wire form |

`core` is the default, so `par` means multi-core by default: the cores share one address
space, and because every value is immutable there is nothing to copy and nothing to
race over.

`process` and `node` have memory of their own, so a value crossing is **copied over a
wire**, and every part of it needs an agreed form `[placement]`: a primitive, a newtype
over one, an enum whose parts have one, or a record that declares a `schema` (§5.3).
That is the same rule channels use (§8.4), for the same reason.

```wtn
(module placed
  (record Reading (schema Reading 1) (site Str) (value Int))

  (fn read ((n Int)) (Result Reading Fault)
    (Ok (make Reading (site "ST1") (value n))))

  ; Two cores, shared memory: nothing is copied.
  (fn pair ((a Int) (b Int)) Int
    (par ((left (* a a)) (right (* b b)))
      (+ left right)))

  ; Another machine: Reading has a schema, so it can be shipped there and back.
  (fn remote ((a Int) (budget Duration)) (Result Reading Fault)
    (uses Clock)
    (scope ((probe (read a) (deadline budget) (on-fail restart 2) (on node)))
      (Ok probe))))
```

A profile says how far work may go: `host` all five, `embedded` `inline` `thread` `core`,
`mcu` only `inline` — one core and no scheduler `[placement]`. Work placed on another
process or node spends *that* machine's stack and heap, so it costs this target's
resource bounds (§9.2) nothing.

### 8.4 Channels

A channel is **typed, schema-first and labelled**. It carries one record, which must
declare a wire schema so both ends agree on its form `[channel-payload]`, and it states
which labels its receiver accepts:

```wtn
(module ipc
  (record Update (schema Update 1) (site Str) (reading Int))
  (channel Readings Update (accepts tenant:acme))

  (fn publish ((u (label tenant:acme Update))) Unit
    (uses Ipc)
    (send Readings u))

  (fn drain () Str
    (uses Ipc)
    (declassifies tenant:acme)
    (match (recv Readings)
      ((None) "nothing")
      ((Some u) (declassify tenant:acme (get u site))))))
```

- `(send C v)` and `(recv C)` perform the `Ipc` effect. `recv` answers `(Option Payload)`.
- Sending data labelled beyond `accepts` is a `[label-flow]` error **at the sender** —
  the check happens where the data still is, even though the receiver is elsewhere.
- What arrives carries exactly the labels the channel admits, so a receiver cannot
  quietly treat `tenant:acme` data as unlabelled.
- A channel declared with no `accepts` clause accepts nothing labelled at all.

### 8.5 Durable state, and replaying a run

`store.put` and `store.get` are durable key-value state under the `Store` effect. A put
is **one assignment**: a key never holds half a value.

Every effect a program performs can be **journalled**, and a journal can be **replayed**:

```text
$ witness run workflow.wtn --grant Store,Clock --record journal.json
$ witness run workflow.wtn --grant Store,Clock --replay journal.json
```

- Recording appends what each effect answered — the clock reading, the value from the
  store, what a channel delivered, what foreign code returned.
- Replaying answers each effect from the journal **without performing it again**: nothing
  is printed twice, no message is sent twice, the store is not touched. That is what lets
  a workflow resume rather than redo.
- A replay that does not match the program is refused rather than guessed at, and so is
  a journal that runs out.
- The order of effects is the order the journal holds, so a recorded run reproduces
  exactly — including `Clock` and `Env`, which are otherwise different every time.

### 8.6 Trace identifiers

Every structured log line (§8.2) begins with the position of the task that wrote it:

```text
[log] trace=1 where="root"
[log] trace=1.1 branch=1
[log] trace=1.2 branch=2
[log] trace=1.1.1 step=7
```

The root is `1`; a `par` branch or a `scope` task appends its position. Nothing in any
signature mentions it and nothing passes it along — it follows the task tree by itself,
across placements as well, so a line written on another node still says where in the
work it came from.

### 8.7 Tensors, models and accelerators

A tensor's **element format and named axes are part of its type**, so a shape mistake is
a compile error in the same way a unit mistake is `[shape]`:

```wtn
(module shapes
  ; The contracted axis must match by name as well as size, so a transposed weight
  ; matrix is caught here rather than in a wrong answer.
  (fn project ((batch (tensor F32 (sample 4) (feature 768)))
               (weights (tensor F32 (feature 768) (class 2))))
      (tensor F32 (sample 4) (class 2))
    (uses Alloc)
    (tensor.matmul batch weights)))
```

A **model is a value named by the hash of its weights**, and it says what it was trained
on and what it runs on:

```wtn
(module serving
  (model Assistant
    (input Str)
    (output Str)
    (trained-on)
    (device gpu)
    (weights "wtn:3c7f1ad2e9"))

  ; A generated answer is not a fact: ModelOutput cannot reach a sink that would execute
  ; or trust it, so validating it is a reviewed release point.
  (fn validated ((question Str)) (Result Str Fault)
    (uses Gpu)
    (declassifies ModelOutput)
    (let answer (declassify ModelOutput (infer Assistant question))
      (if (<= (unwrap (str.chars answer)) 280)
        (Ok answer)
        (Err (fault "validated" "the model said more than we will pass on"))))))
```

- `(infer M x)` performs `Gpu`, `Npu`, or `Alloc` for `cpu` — the accelerator is a
  capability, so code that needs one says so and a profile may refuse it.
- The output carries **`ModelOutput`**, the labels of the **input**, and the labels the
  model's **training data** carried. Prompt injection is then an information-flow error.
- Weights are named by hash, so a call says exactly which model ran, and a different
  hash is a different definition.
- Stage 0 has no weights to run: the host supplies the model, and an inference is
  journalled like any other effect (§8.5), so a run reproduces.
- Not in Stage 0: quantised tensors with scale and zero-point, autodiff, reshaping,
  tensor construction in the language (a tensor arrives from `foreign` code or a model).

## 9. Contracts and termination

A contract states what a function needs and what it guarantees. The checker **proves**
both; nothing is checked at runtime, because contracts are erased before anything runs.
A contract that cannot be proved is an error, not a warning.

```wtn
(module budget
  (fn deduct ((limit Int) (amount Int)) Int
    (requires (and (<= 0 amount) (<= amount limit)))
    (ensures (<= 0 result))
    (- limit amount))

  (fn spend ((limit Int)) Int
    (requires (<= 10 limit))
    (deduct limit 10)))
```

What the two clauses mean:

| Clause | Who proves it | Who may rely on it |
|---|---|---|
| `(requires c)` | every **caller**, at the call `[unproven-precondition]` | the body, as an assumption |
| `(ensures c)` | the **body**, once `[unproven-postcondition]` | every caller, after the call |

Rules for writing one:

- A contract is an ordinary expression of type `Bool` over the parameters; `ensures` may
  also name `result`.
- A contract must be **pure**: no effects, no `declassify` `[contract-impure]`. It may read
  labelled data directly — an erased contract cannot leak anything.
- A contract is part of the function's identity: changing it changes its content hash.

### 9.1 What the prover knows

The prover is exact on integers and boolean structure, and treats everything else as an
opaque value it only knows is equal to itself. So state conditions as integer
comparisons (`<` `<=` `=`, `+ - *` by a constant) and combine them with `and` `or` `not`.

It reasons through:

| Construct | What carries over |
|---|---|
| `let` | the binding's value, exactly |
| `if` / `match` | the branch condition, and which variant an arm is for |
| a call | the callee's `ensures`, instantiated at the arguments |
| `get` on a record | the field, exactly, for a record built with `make` |
| a length (`str.chars`, `str.octets`, `bytes.len`) | that it is at least 0 |

It cannot invent facts. If a proof needs something, say it: add it to the callee's
`ensures`, or to this function's `requires`, or test it with `if` so the branch condition
supplies it.

```wtn
(module clamp
  ; A branch supplies what the contract of the call needs.
  (fn at_least_one ((n Int)) Int
    (ensures (<= 1 result))
    (if (<= 1 n) n 1)))
```

### 9.2 Resource bounds `[resource-bound]`

A function may state what it may *use*, and the checker proves it:

| Bound | Means |
|---|---|
| `(depth N)` | at most `N` nested calls, this one included |
| `(alloc N)` | at most `N` allocating operations along any one path |
| `(repeats N)` | a recursive cycle is entered at most `N` times |

```wtn
(module costed
  (fn leaf ((n Int)) Int (bounds (depth 1) (alloc 0)) (+ n 1))

  (fn label_for ((n Int)) Str
    (uses Alloc)
    (bounds (depth 2) (alloc 2))
    (concat "n=" (num.to_str n)))

  ; A bounded measure bounds the recursion: n starts at 10 or less and falls each time.
  (fn countdown ((n Int)) Int
    (requires (and (<= 0 n) (<= n 10)))
    (bounds (depth 11) (repeats 11) (alloc 0))
    (if (= n 0) 0 (countdown (- n 1)))))
```

- Allocations **add up** along a path and **do not** add up across branches: only one
  branch runs, so the worst of them is the cost.
- Depth and allocation flow through the call graph: a caller's bound includes its
  callees'.
- A recursion is counted by bounding its measure (§9.3) with `requires`. Without an upper
  bound on the measure — and for a structural measure, which has no number attached —
  nothing bounds the repeats, and a declared bound is rejected rather than assumed.
- On the `mcu` profile a bound is **mandatory**: there is no heap and very little stack,
  so "it terminates" is not enough.

### 9.3 Termination

Every recursive call must make a **measure** smaller: one parameter position per
function, clamped at zero, that provably falls on every recursive call
`[no-termination-proof]`. Two measures are recognised:

- **structural** — the argument is a field that a `(match ...)` on that parameter took
  out of it, so it is a part of a part;
- **numeric** — the argument is an `Int` that provably falls while the parameter is still
  above 0 at the call. The bound comes from the branch condition or from `requires`.

```wtn
(module measures
  (enum Chain (End) (Link (head Int) (rest Chain)))

  ; Structural: `rest` is part of `c`.
  (fn total ((c Chain)) Int
    (ensures (<= 0 result))
    (match c
      ((End) 0)
      ((Link head rest) (if (< head 0) (total rest) (+ head (total rest))))))

  ; Numeric: `n` falls by one, and the branch says it is above 0.
  (fn drain ((n Int)) Int
    (ensures (= result 0))
    (if (<= n 0) 0 (drain (- n 1)))))
```

Mutually recursive functions are allowed; the measure may sit at a different parameter
position in each one, and every call around the cycle must lower it.

```wtn
(module parity
  (fn is_even ((n Int)) Bool
    (requires (<= 0 n))
    (if (= n 0) true (is_odd (- n 1))))

  (fn is_odd ((n Int)) Bool
    (requires (<= 0 n))
    (if (= n 0) false (is_even (- n 1)))))
```

Without `(requires (<= 0 n))` that module is rejected — correctly, since `is_even` with a
negative `n` would recurse for ever.

## 10. Diagnostics

`witness check --json file.wtn` prints:

```json
{"file": "f.wtn", "ok": false, "diagnostics": [
  {"rule": "type-mismatch", "severity": "error", "message": "...",
   "line": 10, "col": 18, "where": "schedule", "fixes": ["..."]}]}
```

`where` is the enclosing definition. `fixes` are candidate repairs; apply them only if
§10.2 allows it.

### 10.1 Every rule and its correct repair

| Rule | Sev | Cause | Repair |
|---|---|---|---|
| `syntax` | error | malformed tree | match §3 exactly; check parenthesis count and form shape |
| `naming` | error | wrong case, or `.` in a fn name | §4 |
| `duplicate-definition` | error | name defined twice, or reuses a builtin/constructor | rename |
| `duplicate-binding` | error | repeated param, field or binder | rename |
| `shadowing` | error | binding reuses a name in scope | choose a new name |
| `unknown-name` | error | reference resolves to nothing | use a name from §7 or one you defined; never invent APIs |
| `unpinned-import` | error | a `(use module.name ...)` has not been rewritten to its hash | run `witness pin f.wtn`, then check again |
| `unresolved-import` | error | a `(use ...)` names a hash the codebase does not hold, or two imports want one name | store the module the definition comes from, or rename one of them with `as` |
| `unknown-type` | error | type resolves to nothing | define it, or use `Bool Int Str Unit Option Result` |
| `type-arity` | error | generic type with the wrong number of type arguments | write every argument: `(Option Int)`, `(Result Int Str)` |
| `unknown-effect` | error | not in the closed set | use one of `Clock Console Env Log Net` |
| `unknown-variant` | error | arm names a variant the enum lacks | use the enum's variant names |
| `not-a-value` | error | a function used as a value | call it `(f ...)`; restructure without higher-order code |
| `arity` | error | wrong argument count | match the definition |
| `type-mismatch` | error | wrong base type | wrap `(Newtype v)`, `(unwrap v)`, or `num.to_str`; never change a declared unit to make it fit |
| `label-flow` | error | labelled data reaches a place that does not accept the label | propagate: add the label to the receiving type; release only via a declared sanitiser (§8) |
| `undeclared-declassify` | error | `declassify` without signature permission | add `(declassifies L)` **only** if this function is the intended release point |
| `needless-declassify` | warning | value does not carry that label | remove the `declassify` |
| `unused-declassify` | warning | declared release never happens | remove it from `(declassifies ...)` |
| `undeclared-effect` | error | effect performed but not declared | add it to `(uses ...)` |
| `unused-effect` | warning | effect declared but not performed | remove it |
| `effect-under-label` | error | effect inside a branch decided by labelled data | compute a value in the branch, perform the effect after it |
| `no-wildcard` | error | `_` arm | list the remaining variants explicitly |
| `non-exhaustive` | error | variants not handled | add an arm per missing variant, with real behaviour |
| `duplicate-arm` | error | variant handled twice | merge into one arm |
| `pattern-arity` | error | binder count ≠ field count | one binder per field, in order |
| `match-non-enum` | error | matching a non-enum | use `if` for `Bool`; `get` for records; wrap other data in an enum |
| `not-a-record` | error | `make`/`get`/`with` on a non-record | `match` for enums, `unwrap` for newtypes, `(Variant ...)` to construct |
| `unknown-field` | error | record has no such field | use a declared field name |
| `missing-field` | error | `make` without every field | add each missing field with a real value; there are no defaults |
| `field-order` | error | fields not in declaration order | reorder as the fix lists |
| `discarded-value` | error | non-Unit value in a non-final `seq` position | bind it with `let`, or remove it |
| `unwrap-non-newtype` | error | `unwrap` on a non-newtype | remove the `unwrap` |
| `labelled-newtype` | error | newtype wraps a labelled type | wrap the plain type; label at use sites |
| `empty-enum` | error | enum with no variants | add a variant |
| `main-params` | error | `main` has parameters | `main` takes `()` |
| `contract-impure` | error | a contract performs an effect or declassifies | state the condition over the parameters; a contract may read labelled data as it is |
| `result-outside-ensures` | error | `result` used outside `(ensures ...)` | name the value with `let`; only `ensures` has a result to talk about |
| `unproven-precondition` | error | a call does not establish the callee's `requires`, or a refined newtype is built from an unproved value | guard it with `if`, or add the condition to this function's `requires` (§5.1) |
| `unproven-postcondition` | error | the body does not establish the function's `ensures` | strengthen `requires`, weaken `ensures`, or add the missing fact to the `ensures` of what it calls |
| `no-termination-proof` | error | recursion with no measure that falls | recurse on a `match` binder, or on an `Int` that falls while provably above 0 (§9.3) |
| `schema-version` | error | version is not positive, or declared twice | versions start at 1, count up, and each is declared once |
| `schema-incompatible` | error | a version cannot read, or be read by, the one before | add only optional fields; drop only fields that were optional; never change a field's type (§5.3) |
| `not-a-patch` | error | `update` with something that is not the patch of that record | declare `(patch RPatch R)` and pass one of those |
| `redaction` | error/warning | a policy is unknown or declared twice; or declared and never used | one policy per label, from `hidden` `digest` `length` `keep`; remove unused ones (§8.2) |
| `undeclared-redaction` | error | a log field carries a label with no policy | declare a policy for that label, or declassify the value first |
| `profile-effect` | error | a definition uses an effect the target profile does not provide | drop the effect, or build for a profile that provides it (§7.2) |
| `profile-type` | error | a definition mentions `Int`, `I64` or `U64` on a 32-bit profile (`mcu`, `esp32`) | use `I32`, `U32` or a narrower type (§7.2) |
| `nondeterministic-par` | error | a `par` branch performs an effect other than `Alloc` | move the effect out of the branch, or declare `(uses Nondet)` (§8.3) |
| `channel-payload` | error | a channel carries something that is not a schema'd record | give the record a `(schema Name 1)`, or carry a different type (§8.4) |
| `test-shape` | error | a test performs an effect, is not a `Bool` (or `Str` for a snapshot), or takes an input that cannot be made up | test the pure function underneath; keep inputs to `Bool`, `Int`, `Str` or a fixed width (§11) |
| `shape` | error | axes do not line up by name and size | give both sides the same axes; for a matrix product the contracted axis must match (§8.7) |
| `placement` | error | work is placed further than the profile allows, or carries what has no wire form | drop the `(on ...)` clause, or give the payload a schema (§8.3) |
| `task-shape` | error | a task's work cannot fail, or a scope cannot escalate | give the work type `(Result T Fault)`, and the body too (§8.3) |
| `resource-bound` | error | a declared bound is less than what the code may use, or cannot be proved at all; or the profile requires one and none is declared | raise the bound, use less, or bound the recursion measure in `requires` (§9.2) |
| `overflow` | error | a fixed-width result is not proved in range | bound the operands in `requires`, or use `wrap.*` / `sat.*`, or widen with `int.of` and narrow once it fits (§7.4) |

### 10.2 Forbidden repairs

These silence the checker and defeat its purpose. Never do them unprompted:

- Adding `declassify` to make a `label-flow` error go away in a function whose job is not
  sanitising or redacting.
- Removing a label from a parameter or return type so labelled input "fits".
- Answering `non-exhaustive` with an arm that returns a default for variants it does not
  understand (the fallthrough this language exists to prevent).
- `unwrap`-ing a unit type to pass it where a different unit is expected.
- Declaring effects a function does not perform to pre-empt errors.
- Declassifying a branch condition only to perform an effect inside the branch.
- Answering `missing-field` with placeholder values (`0`, `""`) the program has no reason for.
- Deleting or weakening an `ensures` to silence `unproven-postcondition` when the stated
  guarantee is the one callers need; fix the body instead.
- Widening a `requires` into `true`, or dropping it, so that `unproven-precondition`
  disappears at a call site that really cannot establish it.

## 11. Tests

A module can state propositions about itself, and `witness test` runs them. All three
kinds are **pure**: a test is a proposition, not a program, so it performs no effect
other than building values `[test-shape]`.

```wtn
(module arith
  (fn double ((n Int)) Int (* n 2))

  ; Must hold, once.
  (test "two doubles to four" (= 4 (double 2)))

  ; Must hold for every input made up for it; (requires ...) narrows which ones count.
  (property "doubling grows" ((n Int))
    (requires (< 0 n))
    (< n (double n)))

  ; Must still say what it said when it was written down.
  (snapshot "shown" (num.to_str (double 21)) "42"))
```

- A property's inputs are made up from a seed taken from **its own name**, so a failure
  reproduces exactly and the report names the input that broke it.
- Inputs can be `Bool`, `Int`, `Str` and the fixed widths, or a newtype over one of
  those; the edges of a width come up often, because that is where mistakes are.
- A `requires` that **nothing** satisfies is a failure, not a pass: a property that tests
  nothing should not look like one that holds.
- `witness test --update` writes down what a snapshot says now; nothing else moves.
- A property holding for a hundred made-up inputs is evidence, not proof. Contracts
  (§9) are where proof lives; these catch what nobody thought to state.

## 12. Toolchain

| Command | Effect | Exit codes |
|---|---|---|
| `witness check f.wtn [--json] [--profile host\|embedded\|mcu]` | check and prove; the accepted line reports how many obligations were proved; `--profile` restricts which effects are available (§7.2) | 0 accepted · 1 rejected · 2 unreadable |
| `witness run f.wtn --grant E1,E2 [--entry name] [--arg V ...]` | check, then run `main` (or `--entry`); one `--arg` per parameter, in order — integers, `Bool`, `Str`; the entry's `requires` are taken on trust | 0 · 1 rejected · 2 bad grant/unreadable · 3 runtime or capability error |
| `witness hash f.wtn [--json]` | content hash per definition | 0 · 1 rejected · 2 |
| `witness view f.wtn [--hashes]` | human audit view; `--hashes` needs accepted code | 0 · 1 · 2 |
| `witness read f.view` | read an audit view back into source: every definition comes back with the hash it had | 0 · 1 not a view |
| `witness pin f.wtn [--dir .witness]` | rewrite `(use module.name ...)` to the hash it names, in place | 0 · 1 a name does not resolve |
| `witness store f.wtn [--dir .witness]` | import a module into the content-addressed codebase | 0 · 1 rejected · 2 |
| `witness export module [--dir]` | print a module reassembled from the codebase | 0 · 2 no such module |
| `witness codebase module [--dir] [--manifest]` | what the codebase holds; the package manifest | 0 · 2 |
| `witness test f.wtn [--cases N] [--update]` | run the file's tests, properties and snapshots | 0 all passed · 1 something failed · 2 unreadable |
| `witness fmt f.wtn [--check\|--write]` | the canonical text form; `--check` exits 1 if the file is not already in it | 0 · 1 not canonical or unparseable · 2 |
| `witness rules` | list every rule | 0 |

- The codebase keeps three layers, and only the first is identity: `objects/<hash>.json`
  is what a definition *is*, `names/<module>.json` says which name is bound to it, and
  `text/<module>/<name>.wtn` is the readable copy. A rename touches only the names.
- `--grant` must cover every effect `main` declares, or nothing runs.
- A non-`Unit` result of the entry point is printed as `=> value`.
- Run with the **smallest** grant set that works.

### Authoring loop

1. Write the whole module.
2. `witness check --json`. For each diagnostic, apply the §10.1 repair, respecting §10.2.
3. Repeat until `ok` is true and `diagnostics` is empty.
4. `witness fmt --check`, so the file is in the one canonical form.
5. `witness test`, if the module states anything about itself.
6. `witness run --grant <exactly main's uses>`.

## 13. Not in Stage 0 — do not emit

| Not available | Use instead |
|---|---|
| type classes, bounded type parameters | generic functions (§5) with no assumptions about `T` |
| maps, loops | recursion, over `Int` or over `(Array T)` (§7.3); enums for fixed sets |
| lambdas, closures, higher-order functions | a named function per case |
| modulo, remainder | not yet; `num.div` answers the quotient only |
| float to integer conversion | not yet |
| fixed-point formats (`Q15`) | not yet; use an integer with a stated scale |
| rotations | no primitive; combine `bit.shl` and `bit.shr` (§7.4.1) |
| string formatting, interpolation | nested `concat` with `num.to_str` |
| contracts over strings, records or variants | integer comparisons the prover can see into (§9.1) |
| worst-case execution time, energy bounds | not yet |
| serialisation, parsing of wire data | not yet; schemas declare the form, nothing encodes it |
| generic refinement types (`NonEmpty[T]`) | one refined newtype per inner type |
| effect polymorphism | nothing to vary over: there are no function values, so every call's effects are known |
| more than one label parameter per function | one; positions sharing it join their labels |
| time zones, date formatting, calendars | not yet; `WallTime` is a UTC reading |
| reading the trace id in code | not yet; it reaches log lines by itself (§8.6) |
| periodic tasks and cadence contracts | not yet: a scheduler is needed; deadlines cover the one-shot case |
| cancelling a running task from outside | not yet; a deadline is the only limit |
| collectives (broadcast, reduce, scatter) | not yet; they are library functions over `par` |
| quantised tensors, autodiff, reshaping | not yet |
| building a tensor in the language | not yet; one arrives from `foreign` code or a model |

## 14. Accepted patterns

Each block is a complete module that checks with zero diagnostics.

**Entry point with effects**

```wtn
(module hello
  (fn main () Unit
    (uses Console)
    (seq
      (print "hello")
      (print "from witness"))))
```

**Enum with fields; exhaustive match**

```wtn
(module shapes
  (enum Shape (Square (side Int)) (Rect (w Int) (h Int)))

  (fn area ((s Shape)) Int
    (match s
      ((Square side) (* side side))
      ((Rect w h) (* w h)))))
```

**Units as newtypes; explicit conversion**

```wtn
(module units
  (newtype Minutes Int)
  (newtype Seconds Int)

  (fn to_seconds ((m Minutes)) Seconds
    (Seconds (* (unwrap m) 60))))
```

**Absence and errors as values (prelude `Option`, `Result`)**

```wtn
(module ports
  (fn check_port ((n Int)) (Result Int Str)
    (uses Alloc)
    (if (and (<= 1 n) (<= n 65535))
      (Ok n)
      (Err (concat "port out of range: " (num.to_str n)))))

  (fn first_positive ((a Int) (b Int)) (Option Int)
    (if (< 0 a) (Some a) (if (< 0 b) (Some b) (None))))

  (fn describe ((r (Result Int Str))) Str
    (uses Alloc)
    (match r
      ((Ok port) (concat "port " (num.to_str port)))
      ((Err message) message))))
```

**Records: build, read, change**

```wtn
(module sites
  (newtype Minutes Int)
  (record Site (code Str) (interval Minutes))

  (fn new_site ((code Str)) Site
    (make Site (code code) (interval (Minutes 30))))

  (fn slower ((s Site)) Site
    (with s (interval (Minutes (* 2 (unwrap (get s interval))))))))
```

**Generic enum of your own**

```wtn
(module pairs
  (enum (Pair A B) (MkPair (first A) (second B)))

  (fn swap ((p (Pair Int Str))) (Pair Str Int)
    (match p ((MkPair a b) (MkPair b a)))))
```

**Labels inside type arguments; branch first, act after**

```wtn
(module lookup
  (fn keep ((key (label Secret Str))) (Option (label Secret Str))
    (Some key))

  (fn report ((found (label Secret Bool))) Unit
    (uses Console)
    (declassifies Secret)
    (let shown (if found "found" "missing")
      (print (declassify Secret shown)))))
```

**Iteration by recursion; mutual recursion** — each one carries a measure that falls (§9.3).

```wtn
(module parity
  (fn sum_to ((n Int)) Int
    (if (<= n 0) 0 (+ n (sum_to (- n 1)))))

  (fn is_even ((n Int)) Bool
    (requires (<= 0 n))
    (if (= n 0) true (is_odd (- n 1))))

  (fn is_odd ((n Int)) Bool
    (requires (<= 0 n))
    (if (= n 0) false (is_even (- n 1)))))
```

**One generic function instead of one per type**

```wtn
(module generic
  (fn (unwrap_or T) ((o (Option T)) (fallback T)) T
    (match o
      ((None) fallback)
      ((Some v) v)))

  (fn main () Unit
    (uses Alloc Console)
    (seq
      (print (unwrap_or (Some "found") "missing"))
      (print (num.to_str (unwrap_or (None) 0))))))
```

**A failure that says where it came from**

```wtn
(module faults
  (fn read ((raw Str)) (Result Int Fault)
    (if (str.eq raw "1") (Ok 1) (Err (fault "read" "not a number"))))

  (fn main () Unit
    (uses Alloc Console)
    (match (context (read "x") "main" "starting up")
      ((Ok v) (print (num.to_str v)))
      ((Err f) (print (concat (get f op) (concat ": " (get f why))))))))
```

**A structured log line that cannot leak**

```wtn
(module audit
  (redact Secret hidden)

  (fn record_attempt ((user Str) (key (label Secret Str))) Unit
    (uses Log)
    (log.fields (user user) (api_key key))))
```

**One label parameter instead of one function per label**

```wtn
(module tagging
  (fn (prefix (label L)) ((tag Str) (body (label L Str))) (label L Str)
    (uses Alloc)
    (concat tag body))

  (fn public ((note Str)) Str (uses Alloc) (prefix "note: " note))

  (fn private ((note (label Secret Str))) Unit
    (uses Alloc Log)
    (declassifies Secret)
    (log (declassify Secret (prefix "note: " note)))))
```

**A contract proved at check time**

```wtn
(module stock
  (record Shelf (capacity Int) (used Int))

  (fn free_space ((s Shelf)) Int
    (requires (<= (get s used) (get s capacity)))
    (ensures (<= 0 result))
    (- (get s capacity) (get s used)))

  (fn main () Unit
    (uses Alloc Console)
    (print (num.to_str (free_space (make Shelf (capacity 20) (used 8)))))))
```

**Labels propagate; the result type admits them**

```wtn
(module secrets
  (fn auth_header () (label Secret Str)
    (uses Alloc Env)
    (concat "Bearer " (env.secret "API_KEY")))

  (fn key_present ((key (label Secret Str))) (label Secret Bool)
    (< 0 (unwrap (str.chars key)))))
```

**A single, declared release point**

```wtn
(module dispatch
  (enum Provider (Azure) (Ollama))

  (fn sanitise ((text (label Unsanitised Str))) Str
    (uses Alloc)
    (declassifies Unsanitised)
    (concat "[sanitised] " (declassify Unsanitised text)))

  (fn endpoint ((p Provider)) Str
    (match p
      ((Azure) "azure-openai")
      ((Ollama) "ollama.local")))

  (fn ask ((p Provider) (prompt (label Unsanitised Str))) Str
    (uses Alloc Net)
    (net.send (endpoint p) (sanitise prompt)))

  (fn main () Unit
    (uses Alloc Net Console)
    (print (ask (Ollama) "which uplink serves ST1528?"))))
```

## 15. Rejected patterns

Each block is rejected with exactly the listed rules, in order. The comment shows the fix.

**Wildcard arm** — list every variant instead.

```wtn reject=no-wildcard,non-exhaustive
(module m
  (enum P (A) (B) (C))
  (fn f ((p P)) Int
    (match p ((A) 1) (_ 0))))
```

**Missing variant**

```wtn reject=non-exhaustive
(module m
  (enum P (A) (B))
  (fn f ((p P)) Int
    (match p ((A) 1))))
```

**Null does not exist** — use an enum variant.

```wtn reject=unknown-name
(module m
  (fn f () Int null))
```

**Shadowing a parameter** — choose a new name.

```wtn reject=shadowing
(module m
  (fn f ((x Int)) Int
    (let x 2 x)))
```

**Mixing units** — convert explicitly.

```wtn reject=type-mismatch
(module m
  (newtype Minutes Int)
  (newtype Seconds Int)
  (fn wait_for ((budget Seconds)) Int (unwrap budget))
  (fn schedule ((interval Minutes)) Int (wait_for interval)))
```

**Implicit conversion** — use `(num.to_str 5)`.

```wtn reject=type-mismatch
(module m
  (fn f () Str (uses Alloc) (concat "n=" 5)))
```

**Derived values keep labels** — the length of a secret is secret; declare `(label Secret Bool)`.

```wtn reject=label-flow
(module m
  (fn key_present ((key (label Secret Str))) Bool
    (< 0 (unwrap (str.chars key)))))
```

**A precondition that is not established** — guard the call, or require it here too.

```wtn reject=unproven-precondition
(module m
  (fn half_of ((n Int)) Int
    (requires (<= 2 n))
    (- n 1))

  (fn careless ((x Int)) Int
    (half_of x)))
```

**A promise the body does not keep** — the body returns `n`, which may be negative.

```wtn reject=unproven-postcondition
(module m
  (fn positive ((n Int)) Int
    (ensures (< 0 result))
    n))
```

**Recursion with no measure** — `n` grows, so nothing ever ends it.

```wtn reject=no-termination-proof
(module m
  (fn forever ((n Int)) Int
    (forever (+ n 1))))
```

**Assuming something about a type parameter** — `T` is rigid; declare `Str` to use `str.chars`.

```wtn reject=type-mismatch
(module m
  (fn (size T) ((x T)) Chars
    (str.chars x)))
```

**An effect in a contract** — a contract is erased, so it cannot perform anything.

```wtn reject=contract-impure
(module m
  (fn stamp ((name Str)) Str
    (ensures (str.eq result (env.secret "KEY")))
    name))
```

**Secret into a sink**

```wtn reject=label-flow
(module m
  (fn debug () Unit
    (uses Env Log)
    (log (env.secret "API_KEY"))))
```

**Undeclared release** — the signature must admit to it.

```wtn reject=undeclared-declassify
(module m
  (fn reveal ((key (label Secret Str))) Str
    (declassify Secret key)))
```

**Hidden effect**

```wtn reject=undeclared-effect
(module m
  (fn ping () Str
    (net.send "collector" "ping")))
```

**Guessed API**

```wtn reject=unknown-name
(module m
  (fn f ((a Int) (b Int)) Bool
    (> a b)))
```

**Function as a value**

```wtn reject=not-a-value
(module m
  (fn double ((x Int)) Int (* x 2))
  (fn f () Int
    (let g double 1)))
```

**Discarded value** — bind it or remove it.

```wtn reject=discarded-value
(module m
  (fn f () Unit
    (seq (+ 1 2) unit)))
```

**Matching a Bool** — use `if`.

```wtn reject=match-non-enum
(module m
  (fn f ((b Bool)) Int
    (match b)))
```

**Labelled newtype** — label at the use site.

```wtn reject=labelled-newtype
(module m
  (newtype ApiKey (label Secret Str)))
```

**Effect decided by a secret** — compute in the branch, act after it.

```wtn reject=effect-under-label
(module m
  (fn report ((found (label Secret Bool))) Unit
    (uses Console)
    (if found (print "found") unit)))
```

**Labels inside type arguments still count**

```wtn reject=label-flow
(module m
  (fn keep ((key (label Secret Str))) (Option Str)
    (Some key)))
```

**Generic type without its arguments**

```wtn reject=type-arity
(module m
  (fn f ((o Option)) Int 0))
```

**Redefining the prelude** — use `Option`/`Result`, or choose other names.

```wtn reject=duplicate-definition
(module m
  (enum Outcome (Ok) (Failed)))
```

**Records have no defaults** — give every field.

```wtn reject=missing-field
(module m
  (record Site (code Str) (minutes Int))
  (fn f () Site (make Site (code "ST1"))))
```

**One way to write a record** — declaration order.

```wtn reject=field-order
(module m
  (record Site (code Str) (minutes Int))
  (fn f () Site (make Site (minutes 5) (code "ST1"))))
```

**Records are not called like constructors**

```wtn reject=unknown-name
(module m
  (record Site (code Str) (minutes Int))
  (fn f () Site (Site "ST1" 5)))
```

**Warnings also block success.**

```wtn warn=unused-effect
(module m
  (fn f () Int
    (uses Clock)
    1))
```

```wtn warn=needless-declassify
(module m
  (fn f ((x Str)) Str
    (declassifies Secret)
    (declassify Secret x)))
```
