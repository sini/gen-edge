# edge-trace-golden suite (G1–G4) — Laws E4, §4.4, §4.5. The FROZEN v1 byte contract: the (T,P,S,M) sort
# key and per-arm renderings are pinned exactly as §4.4 fixes them, covering every source arm (collected
# incl. collectedScopes annotations, rewalk aspect/bindings/class, synthesize forwardId/fromClass/intoClass,
# root/output targets). Schema v2 (`value` arm + keyed synthesize spec + adapt) is strictly additive — a
# topology with no value/keyed-synth/adapter renders a byte-identical v1 trace.
{ lib, genEdge, ... }:
let
  inherit (genEdge)
    edge
    sources
    targets
    trace
    renderTrace
    ;

  # entity scope naming: "<kind>:<idHash>" (parent-blind id_hash identity).
  hostH1 = {
    kind = "host";
    idHash = "h1";
  };

  # ── one edge per v1 source arm ──
  collectedEdge = edge {
    source = sources.collected {
      scope = hostH1;
      class = "nixos";
      members = [
        "host:h1"
        "user:u1"
      ];
    };
    target = targets.root {
      root = hostH1;
      class = "nixos";
    };
    mode = "merge";
    annotations = {
      collectedScopes = [
        "host:h1"
        "user:u1"
      ];
    };
  };
  rewalkEdge = edge {
    source = sources.rewalk {
      aspect = "theme";
      bindings = [
        "a"
        "b"
      ];
      class = "nixos";
    };
    target = targets.root {
      root = "R";
      class = "nixos";
    };
    mode = "nest";
  };
  synthesizeEdge = edge {
    source = sources.synthesize {
      spec = {
        forwardId = "fwd";
        fromClass = "hm";
        intoClass = "nixos";
      };
      module = "opaque-content";
    };
    target = targets.root {
      root = "R";
      class = "nixos";
    };
    mode = "nest";
  };
  outputEdge = edge {
    source = sources.synthesize {
      spec = {
        forwardId = "g";
        fromClass = "hm";
        intoClass = "nixos";
      };
      module = "x";
    };
    target = targets.output {
      output = [
        "nixosConfigurations"
        "axon"
      ];
    };
    mode = "merge";
  };

  # a v1-only topology (no value/keyed-synth/adapter arms)
  v1Edges = [
    collectedEdge
    rewalkEdge
    synthesizeEdge
    outputEdge
  ];

  # v2 = v1 + an additive value edge
  valueEdge = edge {
    source = sources.keyedValue {
      key = "policy:p1";
      value = "injected";
    };
    target = targets.root {
      root = "R";
      class = "nixos";
    };
    mode = "merge";
  };
  v2Edges = v1Edges ++ [ valueEdge ];
in
{
  flake.tests.edge-trace-golden = {
    # G2: per-arm frozen renderings (§4.4).
    test-collected-render = {
      expr = renderTrace (trace [ collectedEdge ]);
      expected = "root:host:h1/nixos |  | collected:host:h1/nixos | merge";
    };
    test-rewalk-render = {
      expr = renderTrace (trace [ rewalkEdge ]);
      expected = "root:R/nixos |  | rewalk:theme/a+b/nixos | nest";
    };
    test-synthesize-render = {
      expr = renderTrace (trace [ synthesizeEdge ]);
      expected = "root:R/nixos |  | synthesize:fwd/hm>nixos | nest";
    };
    test-output-arm-render = {
      expr = renderTrace (trace [ outputEdge ]);
      expected = "out:nixosConfigurations.axon |  | synthesize:g/hm>nixos | merge";
    };

    # G1: the committed golden for the whole v1 topology family (sorted by the frozen key).
    test-v1-family-golden = {
      expr = renderTrace (trace v1Edges);
      expected = lib.concatStringsSep "\n" [
        "out:nixosConfigurations.axon |  | synthesize:g/hm>nixos | merge"
        "root:R/nixos |  | rewalk:theme/a+b/nixos | nest"
        "root:R/nixos |  | synthesize:fwd/hm>nixos | nest"
        "root:host:h1/nixos |  | collected:host:h1/nixos | merge"
      ];
    };

    # G3: annotations carried verbatim into the trace entry.
    test-annotations-verbatim = {
      expr = (lib.head (trace [ collectedEdge ])).annotations;
      expected = {
        collectedScopes = [
          "host:h1"
          "user:u1"
        ];
      };
    };

    # G4: additivity — the v1-arm renderings in the mixed v2 trace are byte-identical to the v1 trace;
    # dropping the (additive) value arm recovers exactly the v1 trace.
    test-additivity = {
      expr = lib.filter (e: e.source.arm != "value") (trace v2Edges) == trace v1Edges;
      expected = true;
    };
    # the value arm is the only difference introduced by v2.
    test-value-arm-additive = {
      expr = lib.length (trace v2Edges) - lib.length (trace v1Edges);
      expected = 1;
    };
  };
}
