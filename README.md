# gen-edge — the content-movement contract (the `(S,T,P,M)` edge algebra)

[![CI](https://github.com/sini/gen-edge/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen-edge/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

Pure-Nix, `nixpkgs.lib`-free **content-movement contract**: a general algebra for moving values between
positions of a graph. Everything that moves content between graph positions is an edge `(S, T, P, M)` —
**source**, **target**, attr**p**ath, **m**ode. Nothing else moves content. gen-edge owns the edge record
and its constructors, edge-set derivation for a root, toposorted materialization over a static per-root
projection Π, and the **frozen, hashable edge trace `E`** — the cross-repo parity oracle.

It is graph-generic by construction: positions are arbitrary node identities, channels (the "class"
coordinate) are arbitrary keys, and content is arbitrary values combined by caller-supplied associative
combiners. den's NixOS class buckets, key-deduped module lists and instantiation roots are **one
instantiation**, assembled at the den-hoag layer.

Design spec (authoritative on all semantics): `den-architecture/specs/2026-07-05-gen-edge-component-spec.md`.

## The pipeline

```nix
config(root) = materialize {
  edges      = toposort (edgesFor { graph; root; });
  projection = project  { graph; root; dials; };
}
```

- **`edgesFor { graph, root }`** — the complete edge set of a root: exactly one default-fold merge edge
  per channel present in the root's resolved isolation-bounded subtree (corollary 1, by construction),
  plus every declared edge targeting the root (including cross-root declarations).
- **`toposort edges`** — Kahn's algorithm over the accumulator dependency relation (edge B depends on A
  iff B reads a cell A writes). Incomparable edges emit in frozen-sort-key order, so `toposort` is a pure
  function of the edge **set** (permutation-invariant). Cycles abort loudly, naming the `(target, channel)`
  chain.
- **`project { graph, root, dials }`** — the static per-root projection Π: the resolved membership, the
  resolved universe, and the lazily-carried seed buckets. Π never depends on fold results.
- **`materialize { edges, projection, combine, interpret }`** — THE fold: one left fold over the ordered
  edge list, seeded from Π's buckets, dispatching on the single closed mode switch (`merge` | `nest` |
  `nest-verbatim`). Produces the per-root/per-channel content map.
- **`trace edges`** — the normalized, stably-sorted, hashable edge trace `E(topology)`. Identity-level:
  it renders edge identities and **never forces resolved content**. `E_v1(topology) ≡ E_hoag(topology)`
  is den v2's structural ship gate.

## Layering

```
gen-prelude ┐
gen-graph  ─┴─→ gen-edge   (Class B: prelude + graph, both Class A/dep-free; nixpkgs-lib-free)
```

gen-edge is a Class-B lib (deps injected as flake inputs per the gen convention): `prelude`
([gen-prelude](https://github.com/sini/gen-prelude), the pure utility base) and `graph`
([gen-graph](https://github.com/sini/gen-graph), the accessor/Kahn toposort substrate). No dependency on
gen-schema — identity values (id_hash-bearing entries) are consumed **structurally** (through `nameOf`
and source identity fields), never constructed here. Nothing above (den-hoag, den-compat) is a dependency.

## Gen Ecosystem

| Library | Role |
|---------|------|
| [gen-prelude](https://github.com/sini/gen-prelude) | Pure nixpkgs-lib-free utility base (builtins re-exports + vendored lib utils) |
| [gen-graph](https://github.com/sini/gen-graph) | Accessor-based graph query combinators (traversal, condensation, cycles, phaseOrder) |
| [gen-edge](https://github.com/sini/gen-edge) | **This lib** — the `(S,T,P,M)` content-movement contract, toposorted materialization, frozen trace oracle |

## Identity law

Every public entry point passes and receives **values** — edge records, Π records, graph accessors, and
**nameSpecs** carrying identity (`{ kind; idHash; }` for entities, `{ opaque = string; }` for non-entity
positions). `"kind:name"` strings appear only as internal sort keys and rendered trace/display output,
never as input. Registry entries carrying `kind` + `idHash`/`id_hash` coerce to the entity nameSpec.

## The frozen edge algebra

An edge is `{ source; target; path; mode; adapt; annotations; kind; }`. `kind` (default `null`) is the
optional typed-edge label — an un-labeled edge (`kind = null`) keys, traces and renders byte-identically to
one built without the field; a labeled edge appends its kind as the `K` component (see `REFERENCE.md`).

**Sources (S)** — where content comes from:

| Source | Shape | Semantics |
|---|---|---|
| `collected { scope, class, members }` | channel bucket of a subtree | the pinned-order bucket union over the resolved, isolation-bounded `members` |
| `synthesize { spec, module, reads }` | adapter-constructed content | produced by a caller-supplied `interpret.synthesize`, handed exactly its declared `reads` |
| `value v` | direct value | the general case (collected/synthesize specialize it) |
| `keyedValue { key, value }` | value + trace identity | as `value`, with a stable trace key |
| `rewalk { aspect, bindings, class }` | LEGACY | re-resolved by den-compat's `interpret.rewalk`; native den-hoag never constructs it |

**Targets (T)** — where content goes: `root { root, class }` (an instantiation root) or
`output { output }` (a terminal flake-output sink).

**Path (P)** — the attrpath inside the target; `[ ]` = at root.

**Mode (M)** — the closed enum `merge` | `nest` | `nest-verbatim`. Apparent hybrids **decompose** into
edge composition (a "merge at path" is the `nest ∘ merge` decomposition — two edges). Exactly one mode
switch exists in the library, and it contains no mechanism vocabulary (no route/provides/spawn/instantiate/aspect).

## Corollaries preserved

- **default-fold-by-construction** — `edgesFor` emits exactly one merge edge per `(root, channel)`; no
  per-descendant edge (which would multiply-count, since `subtree(S) ⊆ subtree(R)`).
- **isolation-as-edge-absence** — an isolated scope has no default-fold edge to an outer root; it *is* a
  root. Isolation marks are consumed only at construction; Π carries only the resolved membership.
- **reinstantiate-as-nest-verbatim** — verbatim is a mode (keyed wrappers placed by reference, keys
  intact, dedup-exempt), not out-of-band route plumbing.
- **ordering emergent via toposort** — no phase numbering exists anywhere in the API.

## The B2 boundary (content inertness)

`edgesFor`, `toposort`, `trace` and `project` force **no** bucket content: they consult only the six
structural accessors plus channel *presence*. Resolution-stratum values (`contentsOf` buckets, `contexts`)
enter the computation exclusively through `materialize`, as inert seeds gen-edge never inspects at
construction. Every construction succeeds with every bucket and context poisoned by throw-sentinels.

## Usage

```nix
# flake input
inputs.gen-edge.url = "github:sini/gen-edge";

# in a consumer
let
  genEdge = inputs.gen-edge.lib;   # already wired to gen-prelude + gen-graph

  graph = {
    nodes      = [ "host" "user" ];
    childrenOf = id: if id == "host" then [ "user" ] else [ ];
    parentOf   = id: if id == "user" then "host" else null;
    isolatedAt = _: false;
    channelsOf = _: [ "nixos" ];
    edgesAt    = _: [ ];
    nameOf     = id: { opaque = id; };
    contentsOf = id: ch: [ { content = "${id}/${ch}"; key = id; } ];
  };

  config = genEdge.materialize {
    edges      = genEdge.toposort (genEdge.edgesFor { inherit graph; root = "host"; });
    projection = genEdge.project  { inherit graph; root = "host"; };
  };
in
  config.host.nixos   # ⇒ [ "user/nixos" "host/nixos" ]
```

## Tests

`nix build ./ci#checks.<system>.default` (or `nix flake check ./ci`) runs the pure-eval nix-unit suites —
self-contained synthetic accessor-graphs, no fleet fixtures. Every spec law is a named group:

| Group | Law |
|---|---|
| `constructors` | §2.1 validation, E6 (closed modes) |
| `edge-completeness` | E1 |
| `edge-permutation` | E2 |
| `edge-isolation` | E3 |
| `edge-trace-stability` | E4 |
| `edge-pi-static` | E5 |
| `edge-modes` | E6, E8 |
| `edge-default-fold` | E7 |
| `edge-toposort` | E9, E10 |
| `edge-emergent-order` | E11 |
| `edge-content-order` | E12 |
| `edge-content-inert` | E13 |
| `edge-value-source` | §2.2 |
| `edge-trace-golden` | E4, §4.4/§4.5 (G1–G4) |
| `purity` | Class B nixpkgs-lib-freedom |

## Theory

- **Kahn (1962)**, "Topological sorting of large networks", CACM 5(11) — `toposort` is Kahn's algorithm
  over the accumulator dependency DAG; loud cycles are the residual-queue emptiness check. (A. B. Kahn
  1962, **not** Gilles Kahn 1974 / KPN — inapplicable to collection semantics.)
- **Bernstein (1966)**, "Analysis of Programs for Parallel Processing", IEEE Trans. EC-15 — Laws
  E2/E9/E10 realize the read/write half of Bernstein's conditions through `readsOf`/`writesOf`. Output
  independence (`W₁ ∩ W₂ = ∅`) is deliberately **relaxed**: same-cell writes are permitted and the
  conflict is discharged by canonical cell ordering (contributions ordered by producing-edge sort key),
  so conflicting writers commute *as observed*.

Deliberately **not** cited: KPN/Kahn-1974, semilattice/CRDT framing (merge is associative-only, not
commutative/idempotent), optimal-reduction/graph-rewriting (the fold is first-order).
