# edge-value-source suite — §2.2 (the additive `value`/`keyedValue` source). Direct value materialization;
# the unkeyed trace `value:_` determinism (stable-sort duplicate entries); the keyed arm rendering.
{ lib, genEdge, ... }:
let
  inherit (genEdge)
    edge
    sources
    targets
    toposort
    project
    materialize
    trace
    renderTrace
    ;
  fx = import ./_fixtures/graphs.nix { inherit lib; };

  # value merged into a root
  valGraph = fx.mkGraph {
    buckets = {
      R = {
        nixos = [ ];
      };
    };
    declared = {
      R = [
        (edge {
          source = sources.value "direct";
          target = targets.root {
            root = "R";
            class = "nixos";
          };
          mode = "merge";
        })
      ];
    };
  };
  valCfg = materialize {
    edges = toposort (
      genEdge.edgesFor {
        graph = valGraph;
        root = "R";
      }
    );
    projection = project {
      graph = valGraph;
      root = "R";
    };
  };

  # value into an output-arm terminal sink
  outEdge = edge {
    source = sources.keyedValue {
      key = "k";
      value = "sunk";
    };
    target = targets.output {
      output = [
        "nixosConfigurations"
        "axon"
      ];
    };
    mode = "merge";
  };
  outCfg = materialize {
    edges = [ outEdge ];
    projection = project {
      graph = fx.mkGraph { buckets.R.nixos = [ ]; };
      root = "R";
    };
  };

  # two unkeyed value edges, (T,P,M)-equal → trace-indistinguishable duplicate `value:_` entries.
  unkeyed = [
    (edge {
      source = sources.value "x";
      target = targets.root {
        root = "R";
        class = "nixos";
      };
      mode = "merge";
    })
    (edge {
      source = sources.value "y";
      target = targets.root {
        root = "R";
        class = "nixos";
      };
      mode = "merge";
    })
  ];

  keyed = edge {
    source = sources.keyedValue {
      key = "mykey";
      value = "kv";
    };
    target = targets.root {
      root = "R";
      class = "nixos";
    };
    mode = "merge";
  };
in
{
  flake.tests.edge-value-source = {
    # a direct value materializes into the target root's channel.
    test-value-materializes = {
      expr = valCfg.R.nixos;
      expected = [ "direct" ];
    };
    # a value into an output arm lands under config.outputs keyed by the dotted attrpath.
    test-value-output-arm = {
      expr = outCfg.outputs."nixosConfigurations.axon";
      expected = [ "sunk" ];
    };

    # unkeyed value renders `value:_` and is deterministic (two duplicate entries, stable order).
    test-unkeyed-renders-underscore = {
      expr = renderTrace (trace unkeyed);
      expected = "root:R/nixos |  | value:_ | merge\nroot:R/nixos |  | value:_ | merge";
    };
    test-unkeyed-count-preserved = {
      expr = lib.length (trace unkeyed);
      expected = 2;
    };

    # the keyed arm renders `value:<key>`.
    test-keyed-renders-key = {
      expr = renderTrace (trace [ keyed ]);
      expected = "root:R/nixos |  | value:mykey | merge";
    };
  };
}
