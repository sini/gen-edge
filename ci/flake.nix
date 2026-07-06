{
  inputs = {
    gen.url = "github:sini/gen";
    gen-prelude.url = "github:sini/gen-prelude";
    gen-graph.url = "github:sini/gen-graph";
    # nixpkgs is the CI runner's dependency (nix-unit harness, treefmt) and supplies the `lib` the test
    # modules use for their own assembly. It enters ONLY here (a VALUE in ci/), never a `lib/` dep — the
    # library (../lib) is nixpkgs-lib-free (ci/tests/purity.nix enforces this).
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{
      gen,
      gen-prelude,
      gen-graph,
      ...
    }:
    let
      genEdge = import ../lib {
        prelude = gen-prelude.lib;
        graph = gen-graph.lib;
      };
    in
    gen.lib.mkCi {
      inherit inputs;
      name = "gen-edge";
      testModules = ./tests;
      specialArgs = {
        inherit genEdge;
      };
    };
}
