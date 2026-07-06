# edge-permutation suite — Law E2 (order invariance: input permutation + schedule independence).
# toposort/materialize/trace are pure functions of the edge SET: permuting the input list (and thus the
# valid execution order) yields byte-identical materialize output AND byte-identical trace. Covers the
# previously order-sensitive same-cell-writer case (two nest edges into one (root, class); a cross-root
# merge alongside the target's own default fold into one output cell).
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
    trace
    ;
  fx = import ./_fixtures/graphs.nix { inherit lib; };

  # R with a child C; two same-cell nest writers into (R,nixos); a cross-root merge declared at C
  # targeting R's output (joins R's own default fold at one output cell).
  graph = fx.mkGraph {
    tree = {
      R = [ "C" ];
    };
    buckets = {
      R = {
        nixos = [ (fx.c "R-seed" "rs") ];
      };
      C = {
        nixos = [ (fx.c "C-seed" "cs") ];
      };
    };
    declared = {
      R = [
        (edge {
          source = sources.keyedValue {
            key = "n-alpha";
            value = "alpha";
          };
          target = targets.root {
            root = "R";
            class = "nixos";
          };
          mode = "nest";
        })
        (edge {
          source = sources.keyedValue {
            key = "n-beta";
            value = "beta";
          };
          target = targets.root {
            root = "R";
            class = "nixos";
          };
          mode = "nest";
        })
      ];
      C = [
        (edge {
          source = sources.keyedValue {
            key = "cross";
            value = "cross-merge";
          };
          target = targets.root {
            root = "R";
            class = "nixos";
          };
          mode = "merge";
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
  rev = lib.reverseList edges;
  rot = if lib.length edges > 1 then (lib.tail edges) ++ [ (lib.head edges) ] else edges;

  mat =
    es:
    materialize {
      edges = toposort es;
      projection = pi;
    };

  cfg0 = mat edges;
  cfgR = mat rev;
  cfgRot = mat rot;
in
{
  flake.tests.edge-permutation = {
    # materialize output is byte-identical across permutations of the input edge list.
    test-materialize-permutation-invariant = {
      expr = cfg0 == cfgR && cfg0 == cfgRot;
      expected = true;
    };
    # trace is byte-identical across permutations.
    test-trace-permutation-invariant = {
      expr = trace edges == trace rev && trace edges == trace rot;
      expected = true;
    };
    # the same-cell writers land in canonical (frozen-sort-key) order, not arrival order — stable content.
    test-canonical-content = {
      expr = cfg0.R.nixos;
      # seeds first (R-seed, C-seed in universe order C,R → C-seed, R-seed), then nest writers by sort key
      # (n-alpha, n-beta), then the cross-root merge contribution folds at the output cell.
      expected = [
        "C-seed"
        "R-seed"
        "alpha"
        "beta"
        "cross-merge"
      ];
    };
  };
}
