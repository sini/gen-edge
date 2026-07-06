# edge-modes suite — Laws E6 (closed modes, single switch) and E8 (reinstantiate is nest-verbatim).
# nest∘merge decomposition: a nest edge places content at a path into the target root's input cell,
# which then participates in the root's default-fold merge (v1 provides behavior). nest-verbatim places
# keyed wrappers by reference, keys intact, dedup-exempt (corollary 3).
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
    graph:
    materialize {
      edges = toposort (edgesFor {
        inherit graph;
        root = "R";
      });
      projection = project {
        inherit graph;
        root = "R";
      };
    };

  # ── nest: a placed module joins the target's default fold (nest∘merge) ──
  nestGraph = fx.mkGraph {
    buckets = {
      R = {
        nixos = [ (fx.c "base" "base") ];
      };
    };
    declared = {
      R = [
        (edge {
          source = sources.value { svc = true; };
          target = targets.root {
            root = "R";
            class = "nixos";
          };
          path = [ "services" ];
          mode = "nest";
        })
      ];
    };
  };
  nestCfg = run nestGraph;

  # ── nest + adapt: adapter transforms placed content ──
  adaptGraph = fx.mkGraph {
    buckets = {
      R = {
        nixos = [ ];
      };
    };
    declared = {
      R = [
        (edge {
          source = sources.value 10;
          target = targets.root {
            root = "R";
            class = "nixos";
          };
          mode = "nest";
          adapt = c: _pi: c * 2;
        })
      ];
    };
  };

  # ── nest-verbatim: same-key wrappers survive dedup; keys/content intact ──
  verbatimGraph = fx.mkGraph {
    buckets = {
      R = {
        nixos = [ ];
      };
    };
    declared = {
      R = [
        (edge {
          source = sources.keyedValue {
            key = "dup";
            value = "A";
          };
          target = targets.root {
            root = "R";
            class = "nixos";
          };
          mode = "nest-verbatim";
        })
        (edge {
          source = sources.keyedValue {
            key = "dup";
            value = "B";
          };
          target = targets.root {
            root = "R";
            class = "nixos";
          };
          mode = "nest-verbatim";
        })
      ];
    };
  };

  # contrast: two same-key NEST edges dedup to one (first-occurrence-wins).
  dedupGraph = fx.mkGraph {
    buckets = {
      R = {
        nixos = [ ];
      };
    };
    declared = {
      R = [
        (edge {
          source = sources.keyedValue {
            key = "dup";
            value = "first";
          };
          target = targets.root {
            root = "R";
            class = "nixos";
          };
          mode = "nest";
        })
        (edge {
          source = sources.keyedValue {
            key = "dup";
            value = "second";
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
in
{
  flake.tests.edge-modes = {
    # nest∘merge: the placed { services.svc } module appears in R's folded nixos alongside the seed.
    test-nest-joins-fold = {
      expr = nestCfg.R.nixos;
      expected = [
        "base"
        {
          services = {
            svc = true;
          };
        }
      ];
    };

    # adapt transforms the placed content (10 → 20) before it joins the fold.
    test-nest-adapt = {
      expr = (run adaptGraph).R.nixos;
      expected = [ 20 ];
    };

    # verbatim: BOTH same-key wrappers survive (no dedup), keys/content intact.
    test-verbatim-no-dedup = {
      expr = (run verbatimGraph).R.nixos;
      expected = [
        "A"
        "B"
      ];
    };
    # nest (non-verbatim) dedups the same key to the first occurrence.
    test-nest-dedups = {
      expr = (run dedupGraph).R.nixos;
      expected = [ "first" ];
    };
  };
}
