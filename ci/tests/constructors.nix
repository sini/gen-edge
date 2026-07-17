# Constructor + validation suite: the edge record shape, the closed mode enum, the §2.1 definition-time
# errors, and the defaultFold sugar. Laws E6 (closed modes / single switch — validation half) and the
# §2.2 unresolved-membership rejection. Throws use the tryEval/deepSeq idiom; nix-unit compares expr==expected.
{ genEdge, ... }:
let
  inherit (genEdge)
    edge
    sources
    targets
    modes
    defaultFold
    edgeSortKey
    traceEntryOf
    renderEntry
    ;

  didThrow = e: !(builtins.tryEval (builtins.deepSeq e null)).success;

  goodMerge = edge {
    source = sources.value 1;
    target = targets.root {
      root = "R";
      class = "c";
    };
  };

  # local fixtures for the kind tests — the simplest valid source/target pair
  src = sources.value 1;
  tgt = targets.root {
    root = "R";
    class = "c";
  };
in
{
  flake.tests.constructors = {
    # ── the closed mode enum ──
    test-modes-enum = {
      expr = modes;
      expected = [
        "merge"
        "nest"
        "nest-verbatim"
      ];
    };

    # ── edge record shape (defaults: path [], mode merge, adapt null, annotations {}) ──
    test-edge-defaults = {
      expr = {
        inherit (goodMerge)
          path
          mode
          adapt
          annotations
          ;
      };
      expected = {
        path = [ ];
        mode = "merge";
        adapt = null;
        annotations = { };
      };
    };
    test-edge-carries-source-target = {
      expr = goodMerge.source ? value && goodMerge.target ? root;
      expected = true;
    };

    # ── targets ──
    test-target-root-nameSpec = {
      expr =
        (targets.root {
          root = "host-a";
          class = "nixos";
        }).root;
      expected = {
        opaque = "host-a";
      };
    };
    test-target-root-entity-identity = {
      # an identity-bearing entry coerces to the entity nameSpec (id_hash), never a kind:name string
      expr =
        (targets.root {
          root = {
            kind = "host";
            idHash = "abc123";
          };
          class = "nixos";
        }).root;
      expected = {
        kind = "host";
        idHash = "abc123";
      };
    };
    test-target-output = {
      expr =
        (targets.output {
          output = [
            "nixosConfigurations"
            "axon"
          ];
        }).output;
      expected = [
        "nixosConfigurations"
        "axon"
      ];
    };

    # ── sources ──
    test-source-value-unkeyed = {
      expr = (sources.value 42).value;
      expected = {
        value = 42;
        key = null;
      };
    };
    test-source-keyedValue-string = {
      expr =
        (sources.keyedValue {
          key = "k1";
          value = 7;
        }).value;
      expected = {
        value = 7;
        key = "k1";
      };
    };
    test-source-keyedValue-entity-key-renders = {
      # an identity-bearing key renders to its name (identity in, string key out)
      expr =
        (sources.keyedValue {
          key = {
            kind = "policy";
            idHash = "deadbeef";
          };
          value = 7;
        }).value.key;
      expected = "policy:deadbeef";
    };
    test-source-collected-unresolved-default = {
      expr =
        (sources.collected {
          scope = "R";
          class = "c";
        }).collected.members;
      expected = null;
    };
    test-source-synthesize-default-reads-empty = {
      expr =
        (sources.synthesize {
          spec = {
            forwardId = "f";
            fromClass = "hm";
            intoClass = "nixos";
          };
          module = "opaque";
        }).synthesize.reads;
      expected = [ ];
    };

    # ── §2.1 loud validation ──
    test-throws-bad-mode = {
      expr = didThrow (edge {
        source = sources.value 1;
        target = targets.root {
          root = "R";
          class = "c";
        };
        mode = "teleport";
      });
      expected = true;
    };
    test-throws-merge-with-path = {
      expr = didThrow (edge {
        source = sources.value 1;
        target = targets.root {
          root = "R";
          class = "c";
        };
        path = [ "a" ];
        mode = "merge";
      });
      expected = true;
    };
    test-throws-adapt-with-merge = {
      expr = didThrow (edge {
        source = sources.value 1;
        target = targets.root {
          root = "R";
          class = "c";
        };
        adapt = c: _pi: c;
        mode = "merge";
      });
      expected = true;
    };
    test-nest-with-path-ok = {
      expr =
        (edge {
          source = sources.value 1;
          target = targets.root {
            root = "R";
            class = "c";
          };
          path = [
            "a"
            "b"
          ];
          mode = "nest";
        }).mode;
      expected = "nest";
    };

    # ── defaultFold sugar ──
    test-defaultFold-record = {
      expr =
        let
          e = defaultFold {
            subtree = "R";
            class = "nixos";
            members = [
              "R"
              "C"
            ];
          };
        in
        {
          m = e.mode;
          p = e.path;
          scope = e.source.collected.scope;
          rootT = e.target.root;
          members = e.source.collected.members;
          ann = e.annotations.collectedScopes;
        };
      expected = {
        m = "merge";
        p = [ ];
        scope = {
          opaque = "R";
        };
        rootT = {
          opaque = "R";
        };
        members = [
          "R"
          "C"
        ];
        ann = [
          "C"
          "R"
        ];
      };
    };
    # a sugar edge with members = null carries no collectedScopes annotation (pre-resolution state)
    test-defaultFold-unresolved-no-annotation = {
      expr =
        (defaultFold {
          subtree = "R";
          class = "nixos";
        }).annotations;
      expected = { };
    };

    # ── the optional kind label ──
    test-edge-kind-default-null = {
      expr =
        (edge {
          source = src;
          target = tgt;
        }).kind;
      expected = null;
    };
    test-edge-kind-carried = {
      expr =
        (edge {
          source = src;
          target = tgt;
          kind = "demand";
        }).kind;
      expected = "demand";
    };
    test-sortkey-stamped-appends-kind = {
      # THE load-bearing assertion: un-stamped renders the historical key byte-identically;
      # stamped appends exactly one " | <kind>" component
      expr =
        let
          e0 = edge {
            source = src;
            target = tgt;
          };
          e1 = edge {
            source = src;
            target = tgt;
            kind = "demand";
          };
        in
        edgeSortKey e1 == edgeSortKey e0 + " | demand";
      expected = true;
    };
    test-trace-entry-unstamped-no-kind-name = {
      expr = builtins.attrNames (
        traceEntryOf (edge {
          source = src;
          target = tgt;
        })
      );
      expected = [
        "annotations"
        "mode"
        "path"
        "source"
        "target"
      ];
    };
    test-trace-entry-stamped-kind = {
      expr =
        (traceEntryOf (edge {
          source = src;
          target = tgt;
          kind = "demand";
        })).kind;
      expected = "demand";
    };
    test-render-entry-stamped-kind = {
      # the trace RENDERER (lib/trace.nix renderEntry) — the second key surface — carries K
      # exactly like the sort key: the stamped rendering IS the un-stamped rendering plus one
      # " | <kind>" component (exact equality pins BOTH halves — byte-identity of the un-stamped
      # form AND the appended component — with zero helper dependencies)
      expr =
        let
          e0 = edge {
            source = src;
            target = tgt;
          };
          e1 = edge {
            source = src;
            target = tgt;
            kind = "demand";
          };
        in
        renderEntry (traceEntryOf e1) == renderEntry (traceEntryOf e0) + " | demand";
      expected = true;
    };
  };
}
