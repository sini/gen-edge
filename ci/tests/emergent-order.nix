# edge-emergent-order suite — Law E11 (ordering is emergent). No phase identifiers exist anywhere; any
# externally imposed phase order must be ONE valid topological order of the edge DAG. A hand-phased fold
# order (writers-first, the shape v1's phase1→4 imposes) materializes byte-identically to toposort order.
{ lib, genEdge, ... }:
let
  inherit (genEdge)
    edge
    sources
    targets
    edgesFor
    toposort
    project
    materialize
    ;
  fx = import ./_fixtures/graphs.nix { inherit lib; };

  graph = fx.mkGraph {
    tree = {
      R = [ "C" ];
    };
    buckets = {
      R = {
        nixos = [ (fx.c "R-seed" "r") ];
      };
      C = {
        nixos = [ (fx.c "C-seed" "c") ];
      };
    };
    declared = {
      R = [
        (edge {
          source = sources.keyedValue {
            key = "p1";
            value = "prov-1";
          };
          target = targets.root {
            root = "R";
            class = "nixos";
          };
          mode = "nest";
        })
        (edge {
          source = sources.keyedValue {
            key = "p2";
            value = "prov-2";
          };
          target = targets.root {
            root = "R";
            class = "nixos";
          };
          mode = "nest";
        })
      ];
    };
  };

  edges = edgesFor {
    inherit graph;
    root = "R";
  };
  pi = project {
    inherit graph;
    root = "R";
  };

  # a hand-imposed "phase" order: all writers (nest placements) first, then the collecting merge — a
  # valid topological order (nest → merge). This mimics den v1's phase ordering.
  handPhased = (lib.filter (e: e.mode == "nest") edges) ++ (lib.filter (e: e.mode == "merge") edges);

  mat =
    es:
    materialize {
      edges = es;
      projection = pi;
    };
in
{
  flake.tests.edge-emergent-order = {
    # the hand-phased order and the toposort order materialize byte-identically.
    test-phase-equals-toposort = {
      expr = mat handPhased == mat (toposort edges);
      expected = true;
    };
    # no phase identifiers surface anywhere in the edge records.
    test-no-phase-fields = {
      expr = lib.any (e: e ? phase || e ? phaseIndex || e.annotations ? phase) edges;
      expected = false;
    };
  };
}
