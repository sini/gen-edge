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

  didThrow = e: !(builtins.tryEval (builtins.deepSeq e null)).success;

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

  # A graph whose isolatedAt is a live throw-sentinel. Consulting the mark anywhere aborts; the resolved
  # membership walk in edgesFor/project touches every child's mark, so building either over this graph
  # forces the sentinel. materialize, taking no graph, cannot reach it — that asymmetry IS Law E3.
  poisonedGraph = graph // {
    isolatedAt = _: throw "poisoned isolation mark consulted";
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

    # ── E3 enforcement sentinel: isolation is consumed at construction, materialize is blind to it ──
    # The claim has two halves that must BOTH be witnessed, or "materialize unchanged" is vacuous
    # (materialize takes no graph, so it cannot consult isolatedAt by construction regardless):
    #   (a) edgesFor/project DO consume isolatedAt at construction — poisoning it there throws;
    #   (b) materialize does NOT — even a Π carrying a live isolation mark folds unchanged.

    # The sentinel is a real throw (not a value that silently forces to something).
    test-poison-sentinel-live = {
      expr = didThrow (poisonedGraph.isolatedAt "C");
      expected = true;
    };

    # (a) edgesFor consumes isolatedAt at construction: the resolved membership walk touches every
    # child's mark, so building the edge set over the poisoned graph forces the sentinel.
    test-poison-consumed-by-edgesFor = {
      expr = didThrow (edgesFor {
        graph = poisonedGraph;
        root = "R";
      });
      expected = true;
    };

    # (a) project likewise: forcing the derived membership over the poisoned graph forces the sentinel.
    test-poison-consumed-by-project = {
      expr =
        didThrow
          (project {
            graph = poisonedGraph;
            root = "R";
          }).membership;
      expected = true;
    };

    # (b) materialize is blind to isolation marks. Smuggle a live isolatedAt throw-sentinel INTO Π — the
    # only surface materialize sees — over the ALREADY-resolved edges/Π: the fold consults resolved
    # membership on edges + Π and never a mark, so output is byte-identical to the good run. A regression
    # that re-added mark consultation to the fold would force the sentinel and throw here.
    test-poison-isolatedAt-unchanged = {
      expr =
        let
          piPoisoned = piR // {
            isolatedAt = _: throw "materialize consulted an isolation mark";
          };
        in
        materialize {
          edges = toposort edgesR;
          projection = piPoisoned;
        } == cfgR;
      expected = true;
    };
  };
}
