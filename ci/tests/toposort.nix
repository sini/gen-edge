# edge-toposort suite — Laws E9 (toposort soundness & loud cycles) and E10 (accumulator locality).
# The accumulator dependency relation (edge B depends on A iff B reads a cell A writes) is the complete
# scheduling requirement; readsOf/writesOf are its declared, public read/write sets. A cycle aborts loudly
# naming the (target, channel) chain; unresolved collected membership is a loud definition-time error.
{ lib, genEdge, ... }:
let
  inherit (genEdge)
    edge
    sources
    targets
    edgesFor
    toposort
    materialize
    project
    readsOf
    writesOf
    ;
  fx = import ./_fixtures/graphs.nix { inherit lib; };

  didThrow = e: !(builtins.tryEval (builtins.deepSeq e null)).success;

  indexOf =
    pred: xs:
    lib.foldl' (acc: i: if acc == null && pred (lib.elemAt xs i) then i else acc) null (
      lib.range 0 (lib.length xs - 1)
    );

  # ── nest write → collected read: nest must precede the default fold that reads its cell ──
  arcGraph = fx.mkGraph {
    buckets = {
      R = {
        nixos = [ (fx.c "seed" "s") ];
      };
    };
    declared = {
      R = [
        (edge {
          source = sources.value "nested";
          target = targets.root {
            root = "R";
            class = "nixos";
          };
          mode = "nest";
        })
      ];
    };
  };
  arcSorted = toposort (edgesFor {
    graph = arcGraph;
    root = "R";
  });
  nestIdx = indexOf (e: e.mode == "nest") arcSorted;
  mergeIdx = indexOf (e: e.mode == "merge") arcSorted;

  # ── aggregate read expands to every same-channel writer ──
  aggEdges = [
    (edge {
      source = sources.value "n1";
      target = targets.root {
        root = "R";
        class = "c";
      };
      mode = "nest";
    })
    (edge {
      source = sources.value "n2";
      target = targets.root {
        root = "R";
        class = "c";
      };
      mode = "nest";
    })
    (edge {
      source = sources.synthesize {
        spec = {
          key = "agg";
        };
        module = null;
        reads = [ { aggregate = "c"; } ];
      };
      target = targets.output {
        output = [ "sink" ];
      };
      mode = "merge";
    })
  ];
  aggSorted = toposort aggEdges;
  synthIdx = indexOf (e: e.source ? synthesize) aggSorted;
  n1Idx = indexOf (e: e.source ? value && e.source.value.value == "n1") aggSorted;
  n2Idx = indexOf (e: e.source ? value && e.source.value.value == "n2") aggSorted;

  # ── cycle: two synthesize/nest edges each reading the other's write ──
  cycleEdges = [
    (edge {
      source = sources.synthesize {
        spec = {
          key = "a";
        };
        module = null;
        reads = [
          {
            position = "R";
            channel = "c2";
          }
        ];
      };
      target = targets.root {
        root = "R";
        class = "c1";
      };
      mode = "nest";
    })
    (edge {
      source = sources.synthesize {
        spec = {
          key = "b";
        };
        module = null;
        reads = [
          {
            position = "R";
            channel = "c1";
          }
        ];
      };
      target = targets.root {
        root = "R";
        class = "c2";
      };
      mode = "nest";
    })
  ];

  # ── unresolved collected membership ──
  unresolvedEdge = edge {
    source = sources.collected {
      scope = "R";
      class = "nixos";
    }; # members = null
    target = targets.root {
      root = "R";
      class = "nixos";
    };
    mode = "merge";
  };
  # a valid Π to fold the unresolved edge against — the loud error fires before the enumeration runs.
  unresolvedPi = project {
    graph = fx.mkGraph {
      buckets = {
        R = {
          nixos = [ (fx.c "seed" "s") ];
        };
      };
    };
    root = "R";
  };
in
{
  flake.tests.edge-toposort = {
    # E10: readsOf/writesOf are the declared sets.
    test-readsOf-collected = {
      expr = readsOf (edge {
        source = sources.collected {
          scope = "R";
          class = "nixos";
          members = [
            "R"
            "C"
          ];
        };
        target = targets.root {
          root = "R";
          class = "nixos";
        };
        mode = "merge";
      });
      expected = [
        {
          position = "R";
          channel = "nixos";
        }
        {
          position = "C";
          channel = "nixos";
        }
      ];
    };
    test-writesOf-merge = {
      expr = writesOf (edge {
        source = sources.value 1;
        target = targets.root {
          root = "R";
          class = "nixos";
        };
        mode = "merge";
      });
      expected = [
        {
          output = "R";
          channel = "nixos";
        }
      ];
    };
    test-writesOf-nest = {
      expr = writesOf (edge {
        source = sources.value 1;
        target = targets.root {
          root = "R";
          class = "nixos";
        };
        mode = "nest";
      });
      expected = [
        {
          position = "R";
          channel = "nixos";
        }
      ];
    };
    test-value-reads-nothing = {
      expr = readsOf (edge {
        source = sources.value 1;
        target = targets.root {
          root = "R";
          class = "nixos";
        };
        mode = "merge";
      });
      expected = [ ];
    };

    # E9: reader after writer — the nest precedes the default-fold merge that reads its cell.
    test-nest-before-merge = {
      expr = nestIdx < mergeIdx;
      expected = true;
    };

    # E9: an aggregate read sits after every same-channel writer.
    test-aggregate-after-all-writers = {
      expr = synthIdx > n1Idx && synthIdx > n2Idx;
      expected = true;
    };

    # E9: a dependency cycle aborts loudly.
    test-cycle-throws = {
      expr = didThrow (toposort cycleEdges);
      expected = true;
    };

    # §2.2: an unresolved collected membership is a loud error at toposort.
    test-unresolved-members-throws = {
      expr = didThrow (toposort [ unresolvedEdge ]);
      expected = true;
    };

    # §2.2: materialize rejects it too — a caller bypassing toposort and folding a hand-built collected
    # edge directly gets the same named error, not a cryptic listToAttrs type error from the enumeration.
    test-unresolved-members-materialize-throws = {
      expr = didThrow (materialize {
        edges = [ unresolvedEdge ];
        projection = unresolvedPi;
      });
      expected = true;
    };
  };
}
