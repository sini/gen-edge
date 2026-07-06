# Standalone (non-flake) entry. Flake consumers should use the `.lib` output.
#
# gen-edge is a function of `prelude` (gen-prelude, the pure utility base) and `graph` (gen-graph, the
# accessor/toposort substrate). The default fetches the flake-locked revs (content-addressed via
# narHash, so the plain-import path stays pure and in lockstep with the flake output; per the gen
# root-file convention). Pass either explicitly to override (e.g. local checkouts).
{
  lock ? builtins.fromJSON (builtins.readFile ./flake.lock),
  fetch ?
    name:
    builtins.fetchTree (
      let
        node = lock.nodes.${lock.nodes.root.inputs.${name}}.locked;
      in
      node
    ),
  prelude ? import "${fetch "gen-prelude"}/lib",
  graph ? import "${fetch "gen-graph"}/lib" { inherit prelude; },
}:
import ./lib { inherit prelude graph; }
