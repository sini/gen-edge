# edge-trace-stability suite — Law E4 (trace stability). `trace` is a pure, stably-sorted function of the
# edge SET: equal topologies (equal sets up to permutation) yield byte-equal traces across eval orders.
# The trace is identity-level — rewalk/synthesize/value arms carry identity, never resolved content — so
# it never forces content (sentinel content that throws on force must not break the trace).
{ lib, genEdge, ... }:
let
  inherit (genEdge)
    edge
    sources
    targets
    trace
    ;

  mk =
    key:
    edge {
      source = sources.keyedValue {
        inherit key;
        value = "v-${key}";
      };
      target = targets.root {
        root = "R";
        class = "nixos";
      };
      mode = "merge";
    };
  edges = [
    (mk "a")
    (mk "b")
    (mk "c")
  ];

  # sentinel: content that THROWS on force. The trace records identity only and must not force it.
  boomValue = edge {
    source = sources.value (throw "value content forced!");
    target = targets.root {
      root = "R";
      class = "nixos";
    };
    mode = "merge";
  };
  boomSynth = edge {
    source = sources.synthesize {
      spec = {
        forwardId = "f";
        fromClass = "hm";
        intoClass = "nixos";
      };
      module = throw "synthesize module forced!";
    };
    target = targets.root {
      root = "R";
      class = "nixos";
    };
    mode = "nest";
  };
in
{
  flake.tests.edge-trace-stability = {
    # equal edge sets built in different orders → byte-equal traces.
    test-permutation-equal = {
      expr = trace edges == trace (lib.reverseList edges);
      expected = true;
    };
    # the trace is a total order (identity-level), deterministic regardless of input order.
    test-trace-deterministic = {
      expr =
        trace edges == trace [
          (mk "c")
          (mk "a")
          (mk "b")
        ];
      expected = true;
    };

    # trace forces NO content: sentinel throwing values/modules render fine.
    test-trace-no-force-value = {
      expr = (builtins.tryEval (builtins.deepSeq (trace [ boomValue ]) true)).success;
      expected = true;
    };
    test-trace-no-force-synthesize = {
      expr = (builtins.tryEval (builtins.deepSeq (trace [ boomSynth ]) true)).success;
      expected = true;
    };
    # the identity survives even though content would throw: the value arm is present with its key.
    test-trace-value-identity = {
      expr = (lib.head (trace [ boomValue ])).source;
      expected = {
        arm = "value";
        key = null;
      };
    };
  };
}
