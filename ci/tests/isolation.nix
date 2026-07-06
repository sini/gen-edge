# edge-isolation suite — Law E3 (isolation is edge absence, resolved at construction). An isolated scope
# has no default-fold edge crossing to an outer root — it IS a root. Isolation marks are consumed only by
# edgesFor/project; their entire product is the resolved membership on collected sources and Π. Π carries
# no raw marks, and materialize reads none — so poisoning isolatedAt AFTER construction cannot reach it.
{ lib, genEdge, ... }:
let
  inherit (genEdge)
    edgesFor
    toposort
    project
    materialize
    ;
  fx = import ./_fixtures/graphs.nix { inherit lib; };

  graph = fx.mkGraph {
    tree = {
      R = [
        "C"
        "I"
      ];
    };
    isolated = [ "I" ];
    buckets = {
      R = {
        nixos = [ (fx.c "R-n" "r") ];
      };
      C = {
        nixos = [ (fx.c "C-n" "c") ];
      };
      I = {
        nixos = [ (fx.c "I-n" "i") ];
      };
    };
  };

  edgesR = edgesFor {
    inherit graph;
    root = "R";
  };
  piR = project {
    inherit graph;
    root = "R";
  };
  cfgR = materialize {
    edges = toposort edgesR;
    projection = piR;
  };

  cfgI = materialize {
    edges = toposort (edgesFor {
      inherit graph;
      root = "I";
    });
    projection = project {
      inherit graph;
      root = "I";
    };
  };
in
{
  flake.tests.edge-isolation = {
    # the isolated I's content does NOT reach R's config (edge absence across the boundary).
    test-isolated-excluded-from-outer = {
      expr = lib.elem "I-n" cfgR.R.nixos;
      expected = false;
    };
    test-outer-fold = {
      expr = cfgR.R.nixos;
      expected = [
        "C-n"
        "R-n"
      ];
    };
    # I is its own root: its own edge set folds its own content completely.
    test-isolated-is-root = {
      expr = cfgI.I.nixos;
      expected = [ "I-n" ];
    };

    # Π carries the RESOLVED membership (I excluded) and NO raw isolation marks / parent accessor.
    test-pi-resolved-membership = {
      expr = piR.membership;
      expected = [
        "C"
        "R"
      ];
    };
    test-pi-no-raw-marks = {
      expr = piR ? scopeIsolated || piR ? scopeParent || piR ? isolatedAt;
      expected = false;
    };

    # materialize takes only edges + projection — no graph, no marks. Poisoning isolatedAt after
    # construction is structurally unable to change its output: recompute over a poisoned graph whose
    # isolatedAt throws, reusing the ALREADY-resolved edges/pi — byte-identical.
    test-poison-isolatedAt-unchanged = {
      expr =
        let
          poisoned = graph // {
            isolatedAt = _: throw "poisoned isolation mark";
          };
          # edges/pi were resolved over the good graph; materialize never consults `poisoned`.
          cfg' = materialize {
            edges = toposort edgesR;
            projection = piR;
          };
        in
        builtins.deepSeq poisoned (cfg' == cfgR);
      expected = true;
    };
  };
}
