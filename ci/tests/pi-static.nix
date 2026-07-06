# edge-pi-static suite — Law E5 (Π staticity). `project` is a pure function of (graph, root, dials,
# contexts) and forces ONLY the structural accessors: contentsOf and contexts are carried lazily, so
# poisoning them with throw-sentinels leaves project succeeding. The four dials (aware/blind ×
# dedup/raw × derived/explicit universe) resolve membership/universe deterministically.
{ lib, genEdge, ... }:
let
  inherit (genEdge) project;
  fx = import ./_fixtures/graphs.nix { inherit lib; };

  base = fx.mkGraph {
    tree = {
      R = [
        "C"
        "I"
      ];
    };
    isolated = [ "I" ];
    buckets = {
      C = {
        nixos = [ (fx.c "c" "c") ];
      };
      I = {
        nixos = [ (fx.c "i" "i") ];
      };
      R = {
        nixos = [ (fx.c "r" "r") ];
      };
    };
  };

  # poison the content stratum: contentsOf + contexts throw on force.
  poisoned = base // {
    contentsOf = _: _: throw "bucket content forced during project!";
  };
  piPoisoned = project {
    graph = poisoned;
    root = "R";
    dials = { };
    contexts = throw "contexts forced during project!";
  };
in
{
  flake.tests.edge-pi-static = {
    # project forces only structural fields even with content + contexts poisoned.
    test-project-content-inert = {
      expr =
        (builtins.tryEval (
          builtins.deepSeq [
            piPoisoned.membership
            piPoisoned.universe
            piPoisoned.rootScopeId
            piPoisoned.dedupMode
            piPoisoned.isolationMode
          ] true
        )).success;
      expected = true;
    };
    # Π carries no accumulator/fold field — its keys are the static §4.2 set.
    test-pi-keys-static = {
      expr = lib.sort lib.lessThan (builtins.attrNames piPoisoned);
      expected = lib.sort lib.lessThan [
        "rootScopeId"
        "membership"
        "universe"
        "contents"
        "scopeContexts"
        "contextsAreAugmented"
        "isolationMode"
        "dedupMode"
        "classInject"
      ];
    };

    # ── dials matrix ──
    # aware (default): isolated I excluded from membership.
    test-aware-membership = {
      expr =
        (project {
          graph = base;
          root = "R";
        }).membership;
      expected = [
        "C"
        "R"
      ];
    };
    # blind: the isolation set is {} — I re-enters membership (spawn final-extraction invariant).
    test-blind-membership = {
      expr =
        (project {
          graph = base;
          root = "R";
          dials = {
            isolationMode = "blind";
          };
        }).membership;
      expected = [
        "C"
        "I"
        "R"
      ];
    };
    # derived universe = bucket-bearing positions, lexicographic.
    test-derived-universe = {
      expr =
        (project {
          graph = base;
          root = "R";
        }).universe;
      expected = [
        "C"
        "I"
        "R"
      ];
    };
    # explicit universe dial is carried verbatim (order preserved).
    test-explicit-universe = {
      expr =
        (project {
          graph = base;
          root = "R";
          dials = {
            allScopeIds = [
              "R"
              "C"
            ];
          };
        }).universe;
      expected = [
        "R"
        "C"
      ];
    };
    # dedupMode dial recorded on Π.
    test-dedup-mode-recorded = {
      expr =
        (project {
          graph = base;
          root = "R";
          dials = {
            dedupMode = "raw";
          };
        }).dedupMode;
      expected = "raw";
    };
  };
}
