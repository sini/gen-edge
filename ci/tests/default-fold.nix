# edge-default-fold suite — Law E7 (default fold by construction, one edge per (root, channel)).
# edgesFor emits EXACTLY one corollary-1 merge edge per channel present in the root's resolved
# isolation-bounded subtree, and NO default-fold edge for any descendant subtree (per-descendant edges
# would multiply-count content since subtree(S) ⊆ subtree(R)). Descendant roots fold only to themselves.
{ lib, genEdge, ... }:
let
  inherit (genEdge) edgesFor;
  fx = import ./_fixtures/graphs.nix { inherit lib; };

  # R ── C1 (nixos, hm) ── C2 (nixos) ── I [isolated] (nixos)
  graph = fx.mkGraph {
    tree = {
      R = [
        "C1"
        "C2"
        "I"
      ];
      C1 = [ ];
    };
    isolated = [ "I" ];
    buckets = {
      C1 = {
        nixos = [ (fx.c "c1-nixos" "c1") ];
        hm = [ (fx.c "c1-hm" "c1h") ];
      };
      C2 = {
        nixos = [ (fx.c "c2-nixos" "c2") ];
      };
      I = {
        nixos = [ (fx.c "i-nixos" "i") ];
      };
    };
  };

  edgesR = edgesFor {
    inherit graph;
    root = "R";
  };
  defaultsR = lib.filter (e: e.source ? collected && e.mode == "merge") edgesR;
  channelsR = lib.sort lib.lessThan (map (e: e.target.class) defaultsR);

  edgesI = edgesFor {
    inherit graph;
    root = "I";
  };
in
{
  flake.tests.edge-default-fold = {
    # exactly one default-fold edge per channel present in R's isolation-bounded subtree {R,C1,C2}:
    # channels {hm, nixos} — the isolated I's channel does not leak in.
    test-one-edge-per-channel = {
      expr = channelsR;
      expected = [
        "hm"
        "nixos"
      ];
    };
    test-default-count = {
      expr = lib.length defaultsR;
      expected = 2;
    };

    # every default fold targets R and reads R's resolved membership (I excluded).
    test-all-target-root = {
      expr = lib.all (e: e.target.root == { opaque = "R"; }) defaultsR;
      expected = true;
    };
    test-members-resolved = {
      expr = (lib.head defaultsR).source.collected.members;
      expected = [
        "C1"
        "C2"
        "R"
      ];
    };
    # the collectedScopes annotation is the rendered mirror of source.members — and the isolated child's
    # name NEVER appears in it (the teeth of the E3 assertion).
    test-collectedScopes-mirrors-members = {
      expr = (lib.head defaultsR).annotations.collectedScopes;
      expected = [
        "C1"
        "C2"
        "R"
      ];
    };
    test-isolated-not-in-fold = {
      expr = lib.any (e: lib.elem "I" e.annotations.collectedScopes) defaultsR;
      expected = false;
    };

    # descendant roots fold ONLY to themselves: edgesFor I targets I, with membership {I}.
    test-descendant-folds-to-self = {
      expr = map (e: e.target.root) edgesI;
      expected = [ { opaque = "I"; } ];
    };
    test-descendant-membership = {
      expr = (lib.head edgesI).source.collected.members;
      expected = [ "I" ];
    };
    # no default-fold edge targets a non-root descendant (C1/C2 get no edge to R).
    test-no-descendant-target = {
      expr = lib.any (
        e: e.target.root == { opaque = "C1"; } || e.target.root == { opaque = "C2"; }
      ) edgesR;
      expected = false;
    };
  };
}
