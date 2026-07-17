# gen-edge — API Reference

Complete public surface of `gen-edge.lib`. Section numbers reference the component spec
`den-architecture/specs/2026-07-05-gen-edge-component-spec.md`; law tags (E1–E13) reference its §3.
Every entry point passes and receives values (edge records, Π records, graph accessors, nameSpecs
carrying identity); strings appear only as internal sort keys and rendered trace/display output.

## Identity: nameSpec

A position identity is a **nameSpec**, one of:

- `{ kind; idHash; }` — an entity position; renders `"<kind>:<idHash>"` (parent-blind, stable across
  re-keying, same-name siblings collapse by design — §4.4).
- `{ opaque = string; }` — a non-entity position or the pipeline root; renders the string verbatim.

Constructors coerce their position arguments: a bare string → `{ opaque = string; }`; a registry entry
carrying `kind` + `idHash`/`id_hash` → the entity form. A "kind:name" string is never valid input.

## Constructors

### `edge { source, target, path ? [ ], mode ? "merge", adapt ? null, annotations ? { }, kind ? null }` → `<edge>`

Builds the canonical edge record `{ source; target; path; mode; adapt; annotations; kind; }` (§4.1).
Validation is definition-time and loud (§2.1):

- `mode` ∉ `modes` → error naming the edge and the enum.
- `path ≠ [ ]` with `mode = "merge"` → error (merge is union at the root; use nest for placement — the
  `nest ∘ merge` decomposition).
- `adapt ≠ null` with `mode = "merge"` → error (adapters transform placed content; merge contributions
  are transformed at their producing side).

`adapt` (schema v2, additive) is a per-edge content transform `content: Π: content`, applied to nest-mode
placements only. `annotations` are provenance/diagnostics ONLY — never read by `materialize` (Law E10
excludes them from reads/writes).

`kind` is the optional edge-kind label of the typed-edge vocabulary (additive). `kind = null` (the
default) is an **un-labeled** edge: its sort key (`edgeSortKey`), trace entry (`traceEntryOf`) and
rendering (`renderEntry`/`renderTrace`) are all byte-identical to a record built without the field —
un-labeled edges render the historical four-component `T | P | S | M` key exactly. A labeled edge
appends its kind as a fifth component (`T | P | S | M | K`) in the sort key and rendering, and carries a
`kind` field in the trace entry; `null` never adds a name to the entry attrset. Records built outside the
constructor stay total (`edge.kind or null`), so every existing caller is unaffected.

### `sources` — the S variants

| Constructor | Result | Notes |
|---|---|---|
| `sources.collected { scope, class, members ? null }` | `{ collected = { scope; class; members; }; }` | `members` is the RESOLVED, isolation-bounded membership (rendered position names — internal keys, §2.2). `null` is a transient pre-resolution state that `toposort`/`materialize` reject loudly. |
| `sources.synthesize { spec, module, reads ? [ ] }` | `{ synthesize = { spec; module; reads; }; }` | `spec` is identity-bearing (`{ forwardId; fromClass; intoClass; }` v1, or `{ key; }` v2); `module` is opaque; `reads` are declared cell-refs (§4.3), default a pure producer. |
| `sources.value v` | `{ value = { value = v; key = null; }; }` | Direct value — the general case. |
| `sources.keyedValue { key, value }` | `{ value = { value; key; }; }` | `key` may be a string or an identity-bearing entry (rendered to its name — identity in, string key out). |
| `sources.rewalk { aspect, bindings, class }` | `{ rewalk = { aspect; bindings; class; }; }` | LEGACY (den-compat only). `aspect` is the v1 aspect **name** string, `bindings` a list of strings, `class` a string. |

### `targets` — the T variants

- `targets.root { root, class }` → `{ root = <nameSpec>; class; }` — an instantiation root (position, channel).
- `targets.output { output }` → `{ output = <attrpath list>; }` — a terminal named sink (flake-output arm).

### `modes` → `[ "merge" "nest" "nest-verbatim" ]`

The closed mode enum (Law E6). `nest-verbatim` is reinstantiate (corollary 3).

### `defaultFold { subtree, class, members ? null }` → `<edge>`

Corollary-1 sugar: `collected(subtree, class) → root(subtree, class), P = [], M = merge`, with the
`collectedScopes` annotation set to the sorted `members` when resolved. `edgesFor` emits these by
construction (Law E7); this exists so callers can *state* the corollary. A sugar edge with `members = null`
is pre-resolution only — `toposort`/`materialize` reject it.

## Derivation & ordering

### `edgesFor { graph, root }` → `[ <edge> ]`

The complete edge set of `root` — a pure function of the structural stratum (Law E13; forces no bucket
content). Returns:

1. **default-fold edges by construction** (Law E7): exactly one `collected(subtree(R), C) → (R, C)` merge
   edge for every channel `C` present (via `channelsOf`) in R's resolved isolation-bounded subtree, with
   `members` resolved and the `collectedScopes` annotation mirroring it. No per-descendant edge (a
   descendant root folds to its own root via its own `edgesFor`).
1. **declared edges targeting this root**, gathered from `edgesAt` over the whole graph, selected by
   `edge.target` (including cross-root declarations — the first-class form of v1 `appendToParent`).

`graph` is an accessor-graph exposing (§2.3): `nodes`, `childrenOf`, `parentOf`, `isolatedAt`,
`channelsOf`, `edgesAt`, `nameOf`, and (for `materialize` via Π) `contentsOf`.

### `toposort edges` → `[ <edge> ]`

Kahn's algorithm over the accumulator dependency relation (edge B depends on A iff `writesOf A` feeds a
read in `readsOf B`; the derived `{ aggregate = C; }` read expands to every input-cell writer of channel
`C`). Incomparable edges emit in frozen-sort-key order (tie-broken by the JSON of the reads/writes sets),
making `toposort` a pure function of the edge SET — permutation-invariant (Law E2). An unresolved
collected membership is a loud error; a dependency cycle aborts loudly naming the `(target, channel)`
chain (Law E9). Write–write conflicts are **not** arcs (Bernstein output independence relaxed).

### `readsOf edge` → `[ <cell-ref> ]`, `writesOf edge` → `[ <cell-ref> ]`

The declared accumulator dependency sets (§4.3), public — den-compat's differential tests and `toposort`
both consume them. Pure functions of the edge record alone.

- `readsOf`: collected → `{ position = s; channel = class; }` for `s ∈ members`; synthesize → its declared
  `reads`; value/keyedValue/rewalk → `[ ]`.
- `writesOf`: merge → `{ output = rootName; channel; }` (or `{ outputArm = key; }` for output targets);
  nest/nest-verbatim → `{ position = rootName; channel; }`.

A **cell-ref** is `{ position; channel; }` | `{ output = rootName; channel; }` | `{ outputArm = key; }` |
`{ aggregate = channel; }` (read-only derived view).

## Projection & materialization

### `project { graph, root, dials ? { }, contexts ? null, contextsAreAugmented ? false }` → `<Π>`

The only constructor of the static per-root projection Π (§4.2). Derives every structural field; forces
only structural accessors (Law E5/E13 — `contentsOf` and `contexts` carried lazily). Π fields:
`rootScopeId`, `membership` (resolved isolation-bounded subtree), `universe` (resolved membership
universe), `contents` (seed buckets, lazy), `scopeContexts`, `contextsAreAugmented`, `isolationMode`,
`dedupMode`, `classInject`. Raw isolation marks and the parent accessor deliberately do **not** appear.

**Dials** (frozen v1 semantics):

| Dial | Default | Meaning |
|---|---|---|
| `isolationMode` | `"aware"` | `"aware"`: the membership walk honors `isolatedAt`. `"blind"`: the isolation set is `{}` (spawn final-extraction invariant). |
| `dedupMode` | `"dedup"` | `"dedup"`: first-occurrence-wins key dedup + universe-order enumeration. `"raw"`: dedup-free concat + lexicographic bucket-bearing enumeration. |
| `allScopeIds` | `null` | Explicit membership-universe override (its order is load-bearing under dedup); `null` derives it from the graph's bucket-bearing positions, lexicographically. |
| `classInject` | `null` | Optional channel key injected into interpreter context (defensive; no observable witness). |

### `materialize { edges, projection, combine ? { }, interpret ? { } }` → `config`

THE fold (§2.6). One left fold over the ordered edge list, threading the accumulator. Seeded from Π's
buckets before any edge runs (a plain leaf graph folds to its seeded buckets, never to empty config).

- `projection` — a Π, or a per-root function `rootName → Π` for cross-root edge sets (each edge
  materializes under its own target root's Π; all Πs must derive from the same graph).
- `combine` — per-mode combiner overrides; `combine.merge` (MUST be associative) receives the ordered
  content list of an output cell.
- `interpret` — caller-supplied source interpreters: `interpret.synthesize edge Π readValues` (where
  `readValues` are the resolved values of the edge's declared `reads`, and nothing else) and
  `interpret.rewalk edge Π`. gen-edge defines neither; a present source kind with no matching interpreter
  is a loud error.

Per edge: interpret the source into content → apply `adapt` (nest modes) → dispatch on the single mode
switch (`merge` writes the target output cell; `nest` places content at `path` into the target's input
cell — the `nest ∘ merge` decomposition; `nest-verbatim` places keyed wrappers by reference, keys intact,
dedup-exempt) → write the declared cells. Every observable collection order is pinned (Law E12): seeds
precede edge contributions (seeds verbatim), edge contributions are producing-edge sort-key ordered, and
the only dedup is the declared `dedupMode` key dedup (null-keyed contributions never deduped).

`config` is `{ <rootName> = { <channel> = <content list>; }; }` for root targets, plus
`{ outputs = { <attrpath-key> = <content>; }; }` when output-arm targets are present.

## The parity oracle

### `trace edges` → `<E>`

The normalized, stably-sorted, hashable list of trace entries (§4.5) — a pure, identity-level function of
the edge SET (Laws E2/E4). Sorted by the frozen `(T,P,S,M[,K])` key (§4.4 — the optional `K` fifth
component present only on labeled edges) primary, canonical JSON of the structured entry secondary (total,
permutation-invariant). Records identity only; **never forces resolved
content** (synthesize `module`, value content, collected bucket content are all excluded). A trace entry
is `{ target; path; source; mode; annotations; }` with `source`/`target` carrying identity arms only — plus
a `kind` field iff the edge is labeled (`kind ≠ null`); an un-labeled edge's entry has exactly the
historical attribute set.

### `renderTrace E` → `string`

Display rendering of a trace, one line per entry:
`<targetKey> | <pathKey> | <sourceKey> | <mode>` (plus ` | <kind>` iff the entry is labeled). The frozen
§4.4 renderings:

```
targetKey  = "out:"  ++ dot-joined attrpath                          (output arm)
           | "root:" ++ scopeName ++ "/" ++ class                    (root arm)
pathKey    = "/"-joined attrpath
sourceKey  = "collected:"  ++ scopeName ++ "/" ++ class
           | "rewalk:"     ++ aspect ++ "/" ++ "+"-joined bindings ++ "/" ++ class
           | "synthesize:" ++ forwardId ++ "/" ++ fromClass ++ ">" ++ intoClass
           | "synthesize:" ++ key                                    (schema v2 spec-key arm)
           | "value:"      ++ (key | "_")                            (schema v2 value arm)
```

### `hashTrace edges` → `string`

`sha256` of the canonical JSON of `trace edges` — the content-independent structural fingerprint of a
topology (the structural half of den v2's ship gate).

### `edgeSortKey edge` → `string`, `traceEntryOf edge` → `<entry>`, `renderEntry entry` → `string`

The per-edge primitives behind the oracle, exposed on the public surface for consumers that key or render
a single edge (the typed-edge substrate keys edges by these). `edgeSortKey` is the frozen `T | P | S | M`
key with the optional ` | K` fifth component; `traceEntryOf` is the structured identity entry (with the
optional `kind` field); `renderEntry` renders one entry to its `renderTrace` line.

## Schema versioning

- **Schema v1** — collected/rewalk/synthesize arms with the §4.4 frozen field shapes, root/output
  targets, the frozen key. Byte-frozen.
- **Schema v2** — v1 + the `value` arm + the synthesize `{ key }` spec arm + the `adapt` annotation.
  Strictly additive: any topology with no value edges, no keyed synthesize specs and no adapters renders a
  byte-identical v1 trace.
- **Schema v2.1** — v2 + the optional `kind` label. Strictly additive: any topology with no labeled edges
  (`kind = null` throughout) renders a byte-identical v2 trace — the sort key, trace entry and rendering
  carry K only when present.

## Theory

- **Kahn (1962)** — `toposort` is Kahn's algorithm over the accumulator dependency DAG; loud cycles are
  the residual-queue emptiness check.
- **Bernstein (1966)** — Laws E2/E9/E10 realize the read/write half of Bernstein's conditions; output
  independence is relaxed and discharged by canonical cell ordering, so incomparable same-cell writers
  commute *as observed*.
