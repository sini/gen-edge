{
  description = "gen-edge — the content-movement contract: the (S,T,P,M) edge algebra, toposorted materialization fold, and the frozen edge-trace parity oracle";

  # Class layering: gen-prelude + gen-graph → gen-edge (Class B, deps injected as flake inputs per the
  # gen convention). The library (./lib) is nixpkgs-lib-free (ci/tests/purity.nix enforces it): it moves
  # content between graph positions using builtins + gen-prelude primitives + gen-graph's accessor/Kahn
  # toposort, and never evaluates a module system. gen-graph supplies the toposort DAG substrate; every
  # public entry point passes and receives values (edge records, Π records, nameSpecs carrying identity),
  # never "kind:name" strings — strings are internal sort keys and rendered trace output only.
  inputs = {
    gen-prelude.url = "github:sini/gen-prelude";
    gen-graph.url = "github:sini/gen-graph";
  };

  outputs =
    {
      gen-prelude,
      gen-graph,
      ...
    }:
    {
      lib = import ./lib {
        prelude = gen-prelude.lib;
        graph = gen-graph.lib;
      };
    };
}
