# gen-edge public API — the content-movement contract: the (S,T,P,M) edge algebra, edge-set derivation
# for a root, toposorted materialization over the static per-root projection Π, and the frozen edge-trace
# parity oracle E. Class B: consumes gen-prelude (pure primitives) and gen-graph (accessor/Kahn substrate).
{
  prelude,
  graph,
}:
let
  core = import ./core.nix { inherit prelude; };
  edge = import ./edge.nix { inherit prelude core; };
  trace = import ./trace.nix { inherit prelude core; };
  derive = import ./derive.nix { inherit prelude core edge; };
  project = import ./project.nix { inherit prelude core; };
  toposort = import ./toposort.nix { inherit prelude core graph; };
  materialize = import ./materialize.nix { inherit prelude core; };
in
edge
// trace
// derive
// project
// toposort
// materialize
# the core sort-key / trace-entry primitives + the attrpath-placement primitive reach consumers
# (tests + den-hoag's fold/nest engines) through the public surface; `core` itself stays unexported.
# `setAttrByPath` is the nest mode's `[]⇒verbatim` placement (path list → nested attrset), exposed so
# consumers call it instead of mirroring a local twin.
// {
  inherit (core) edgeSortKey traceEntryOf setAttrByPath;
}
