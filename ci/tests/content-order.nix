# edge-content-order suite — Law E12 (pinned collection order). Every observable collection order is
# pinned and frozen: dedup mode enumerates positions in universe order, raw mode in lexicographic
# bucket-bearing order; within a cell, seeds precede edge contributions (seeds verbatim), edge
# contributions are producing-edge sort-key ordered; the only dedup is the declared key dedup, and
# null-keyed contributions are never deduped. These are trace-invisible — hence content-level goldens.
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

  run =
    graph: dials:
    materialize {
      edges = toposort (edgesFor {
        inherit graph;
        root = "R";
      });
      projection = project {
        inherit graph;
        root = "R";
        inherit dials;
      };
    };

  # R over A,B — enumeration order diverges between dedup (universe order) and raw (lexicographic).
  divGraph = fx.mkGraph {
    tree = {
      R = [
        "A"
        "B"
      ];
    };
    buckets = {
      A = {
        nixos = [ (fx.c "a" "ka") ];
      };
      B = {
        nixos = [ (fx.c "b" "kb") ];
      };
    };
  };

  # seed-before-edge + canonical producing-edge order within one cell.
  seedGraph = fx.mkGraph {
    buckets = {
      R = {
        nixos = [
          (fx.c "seed1" "s1")
          (fx.c "seed2" "s2")
        ];
      };
    };
    declared = {
      R = [
        (edge {
          source = sources.keyedValue {
            key = "zeta";
            value = "z";
          };
          target = targets.root {
            root = "R";
            class = "nixos";
          };
          mode = "nest";
        })
        (edge {
          source = sources.keyedValue {
            key = "alpha";
            value = "a";
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

  # null-keyed contributions are never deduped (two identical keyless seeds both survive).
  nullKeyGraph = fx.mkGraph {
    buckets = {
      R = {
        nixos = [
          (fx.c "dupe" null)
          (fx.c "dupe" null)
        ];
      };
    };
  };

  # first-occurrence-wins dedup: same key across two positions, survivor is universe-order-first.
  dedupGraph = fx.mkGraph {
    tree = {
      R = [
        "A"
        "B"
      ];
    };
    buckets = {
      A = {
        nixos = [ (fx.c "from-A" "shared") ];
      };
      B = {
        nixos = [ (fx.c "from-B" "shared") ];
      };
    };
  };
in
{
  flake.tests.edge-content-order = {
    # dedup mode: universe order (explicit dial [B,A]) → b before a.
    test-dedup-universe-order = {
      expr =
        (run divGraph {
          dedupMode = "dedup";
          allScopeIds = [
            "B"
            "A"
          ];
        }).R.nixos;
      expected = [
        "b"
        "a"
      ];
    };
    # raw mode: lexicographic bucket-bearing order → a before b (independent of the universe dial).
    test-raw-lexicographic-order = {
      expr =
        (run divGraph {
          dedupMode = "raw";
          allScopeIds = [
            "B"
            "A"
          ];
        }).R.nixos;
      expected = [
        "a"
        "b"
      ];
    };

    # seeds precede edge contributions (seeds verbatim in caller order), edges by producing sort key
    # (alpha < zeta despite declaration order zeta-then-alpha).
    test-seed-before-edge-canonical = {
      expr = (run seedGraph { }).R.nixos;
      expected = [
        "seed1"
        "seed2"
        "a"
        "z"
      ];
    };

    # null-keyed contributions are never deduped.
    test-null-keyed-never-deduped = {
      expr = (run nullKeyGraph { }).R.nixos;
      expected = [
        "dupe"
        "dupe"
      ];
    };

    # first-occurrence-wins: shared key across A,B keeps the universe-order-first survivor (A).
    test-first-occurrence-wins = {
      expr = (run dedupGraph { dedupMode = "dedup"; }).R.nixos;
      expected = [ "from-A" ];
    };
    # raw mode keeps BOTH (no key dedup).
    test-raw-keeps-duplicates = {
      expr = (run dedupGraph { dedupMode = "raw"; }).R.nixos;
      expected = [
        "from-A"
        "from-B"
      ];
    };
  };
}
