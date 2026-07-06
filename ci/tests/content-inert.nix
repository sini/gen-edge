# edge-content-inert suite — Law E13 (content inertness, the B2 boundary). edgesFor/toposort/trace/project
# force NO bucket content: they consult only the structural accessors plus channel PRESENCE. With every
# bucket (contentsOf) and context poisoned by throw-sentinels, all four constructions run to completion;
# only materialize (collected reads / interpreter args) forces resolution-stratum values.
{ lib, genEdge, ... }:
let
  inherit (genEdge)
    edgesFor
    toposort
    trace
    project
    ;
  fx = import ./_fixtures/graphs.nix { inherit lib; };

  # a structurally-complete graph whose content stratum is entirely poisoned.
  graph =
    (fx.mkGraph {
      tree = {
        R = [ "C" ];
      };
      buckets = {
        R = {
          nixos = [ ];
        };
        C = {
          nixos = [ ];
          hm = [ ];
        };
      };
    })
    // {
      contentsOf = _: _: throw "bucket content forced during a structural construction!";
    };

  edges = edgesFor {
    inherit graph;
    root = "R";
  };
  forces = e: (builtins.tryEval (builtins.deepSeq e true)).success;
in
{
  flake.tests.edge-content-inert = {
    # edgesFor produces the full edge structure (targets, modes, resolved members) without forcing content.
    test-edgesFor-inert = {
      expr = forces (
        map (e: {
          inherit (e) mode;
          t = e.target;
          m = e.source.collected.members or null;
        }) edges
      );
      expected = true;
    };
    # channel PRESENCE is readable without forcing bucket content — two channels present in the subtree.
    test-channel-presence-only = {
      expr = lib.length edges;
      expected = 2; # one default fold per present channel {hm, nixos}
    };
    # toposort orders the poisoned-content edge set fine (uses reads/writes only).
    test-toposort-inert = {
      expr = forces (map (e: e.mode) (toposort edges));
      expected = true;
    };
    # trace renders the poisoned-content edge set fine (identity only).
    test-trace-inert = {
      expr = forces (trace edges);
      expected = true;
    };
    # project resolves membership/universe fine with content poisoned.
    test-project-inert = {
      expr = forces (
        let
          pi = project {
            inherit graph;
            root = "R";
          };
        in
        [
          pi.membership
          pi.universe
        ]
      );
      expected = true;
    };
  };
}
