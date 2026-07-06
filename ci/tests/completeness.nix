# edge-completeness suite — Law E1. `materialize (toposort (edgesFor root))` over `project` IS
# config(root): the full pipeline produces the folded per-root/per-channel content, and every seed
# contribution reaches config through exactly the default-fold path — there is no other content path
# (materialize is the sole exported function that returns config).
{ lib, genEdge, ... }:
let
  inherit (genEdge)
    edgesFor
    toposort
    project
    materialize
    ;
  fx = import ./_fixtures/graphs.nix { inherit lib; };

  # two-channel, three-level graph
  graph = fx.mkGraph {
    tree = {
      R = [
        "C1"
        "C2"
      ];
      C1 = [ "G" ];
    };
    buckets = {
      R = {
        nixos = [ (fx.c "R-n" "R") ];
      };
      C1 = {
        nixos = [ (fx.c "C1-n" "C1") ];
        hm = [ (fx.c "C1-h" "C1h") ];
      };
      C2 = {
        nixos = [ (fx.c "C2-n" "C2") ];
      };
      G = {
        nixos = [ (fx.c "G-n" "G") ];
      };
    };
  };

  run =
    root:
    materialize {
      edges = toposort (edgesFor {
        inherit graph root;
      });
      projection = project {
        inherit graph root;
      };
    };
  config = run "R";

  runLeaf =
    g:
    materialize {
      edges = toposort (edgesFor {
        graph = g;
        root = "L";
      });
      projection = project {
        graph = g;
        root = "L";
      };
    };
in
{
  flake.tests.edge-completeness = {
    # config(R) has both channels present in the subtree; nixos folds every non-isolated position's
    # bucket in universe order (C1, C2, G, R lexicographic).
    test-config-channels = {
      expr = lib.sort lib.lessThan (builtins.attrNames config.R);
      expected = [
        "hm"
        "nixos"
      ];
    };
    test-nixos-fold = {
      expr = config.R.nixos;
      expected = [
        "C1-n"
        "C2-n"
        "G-n"
        "R-n"
      ];
    };
    test-hm-fold = {
      expr = config.R.hm;
      expected = [ "C1-h" ];
    };

    # completeness: every seed content value appears in exactly one channel of config(R).
    test-every-contribution-present = {
      expr = lib.all (v: lib.elem v (config.R.nixos ++ config.R.hm)) [
        "R-n"
        "C1-n"
        "C2-n"
        "G-n"
        "C1-h"
      ];
      expected = true;
    };
    # the fold is total: number of nixos contributions equals the number of nixos-bearing positions.
    test-nixos-count = {
      expr = lib.length config.R.nixos;
      expected = 4;
    };

    # a plain leaf graph (no declared edges) folds to its seeded bucket — never empty config.
    test-leaf-not-empty = {
      expr =
        let
          leaf = fx.mkGraph {
            buckets = {
              L = {
                nixos = [ (fx.c "only" "k") ];
              };
            };
          };
        in
        (runLeaf leaf).L.nixos;
      expected = [ "only" ];
    };
  };
}
