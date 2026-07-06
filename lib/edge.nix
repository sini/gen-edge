# gen-edge constructors — the edge record, its source/target variants, the closed mode enum, and the
# corollary-1 default-fold sugar. Validation is definition-time and loud (§2.1).
#
# THEORY (internal provenance): the (S,T,P,M) rule and corollaries 1–3 are fixed by
# `delivery-edge-unification` §2 — every content move is one edge; isolation is edge absence;
# reinstantiate is a mode, not route plumbing.
{ prelude, core }:
let
  inherit (core) toNameSpec renderName;

  modes = [
    "merge"
    "nest"
    "nest-verbatim"
  ];

  # The canonical edge record (§4.1). `adapt` (v2, additive) is a per-edge content transform for nest
  # modes; `annotations` are provenance/diagnostics ONLY — never read by materialize.
  edge =
    {
      source,
      target,
      path ? [ ],
      mode ? "merge",
      adapt ? null,
      annotations ? { },
    }:
    let
      described = "${core.targetKey target} | ${core.pathKey path} | ${mode}";
    in
    # mode must be in the closed enum (Law E6) — apparent hybrids decompose into edge composition.
    if !(builtins.elem mode modes) then
      throw "gen-edge.edge: mode '${mode}' for edge (${described}) is not in the closed enum ${builtins.toJSON modes}"
    # merge is bucket union at the root: a placement path is what nest is for. A 'merge at path' is the
    # nest∘merge decomposition — two edges, not one.
    else if path != [ ] && mode == "merge" then
      throw "gen-edge.edge: merge edge (${described}) has a non-empty path — merge is union at the root; use nest for placement (the nest∘merge decomposition)"
    # adapters transform placed content; a merge contribution is transformed at its producing side.
    else if adapt != null && mode == "merge" then
      throw "gen-edge.edge: merge edge (${described}) carries an adapt — adapters apply to nest modes only; transform merge contributions at their producing side"
    else
      {
        inherit
          source
          target
          path
          mode
          adapt
          annotations
          ;
      };

  # ── sources (S) ─────────────────────────────────────────────────────────────
  sources = {
    # The channel bucket of a scope subtree. `members` is the RESOLVED, isolation-bounded membership
    # (rendered position names — internal keys, §2.2); null is a transient pre-resolution state that
    # toposort/materialize reject loudly.
    collected =
      {
        scope,
        class,
        members ? null,
      }:
      {
        collected = {
          scope = toNameSpec scope;
          inherit class members;
        };
      };

    # Content constructed by a caller-supplied adapter at materialization. `spec` is identity-bearing
    # (v1 `{ forwardId; fromClass; intoClass; }` or the additive `{ key; }`); `module` is an opaque
    # content seed; `reads` are declared accumulator cell-refs (default none — a pure producer).
    synthesize =
      {
        spec,
        module,
        reads ? [ ],
      }:
      {
        synthesize = {
          inherit spec module reads;
        };
      };

    # Direct value source — the general case that collected/synthesize specialize.
    value = v: {
      value = {
        value = v;
        key = null;
      };
    };

    # A value plus a stable trace identity. `key` may be a string or an identity-bearing entry (rendered
    # to its name here — identity in, string key out).
    keyedValue =
      {
        key,
        value,
      }:
      {
        value = {
          inherit value;
          key = if builtins.isString key then key else renderName key;
        };
      };

    # LEGACY (den-compat only): content re-resolved from an aspect under bindings. Native den-hoag code
    # never constructs this; its interpreter is supplied by den-compat through materialize (§2.6).
    rewalk =
      {
        aspect,
        bindings,
        class,
      }:
      {
        rewalk = {
          inherit aspect bindings class;
        };
      };
  };

  # ── targets (T) ──────────────────────────────────────────────────────────────
  targets = {
    # An instantiation root: (position, channel). `root` is a position identity (nameSpec / entry).
    root =
      {
        root,
        class,
      }:
      {
        root = toNameSpec root;
        inherit class;
      };

    # A terminal named sink (the flake-output arm). `output` is an attrpath list.
    output =
      {
        output,
      }:
      {
        inherit output;
      };
  };

  # Corollary-1 sugar: a subtree's merge edge to its own root. `edgesFor` emits these by construction
  # (Law E7); this exists so callers can *state* the corollary. A sugar edge with members = null is
  # pre-resolution only — toposort/materialize reject it.
  defaultFold =
    {
      subtree,
      class,
      members ? null,
    }:
    edge {
      source = sources.collected {
        scope = subtree;
        inherit class members;
      };
      target = targets.root {
        root = subtree;
        inherit class;
      };
      path = [ ];
      mode = "merge";
      annotations = prelude.optionalAttrs (members != null) {
        collectedScopes = prelude.sort builtins.lessThan members;
      };
    };
in
{
  inherit
    edge
    sources
    targets
    modes
    defaultFold
    ;
}
