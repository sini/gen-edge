# gen-edge ordering — `toposort`, ordering as a property of the edge SET.
#
# THEORY: Kahn's algorithm (A. B. Kahn 1962, "Topological sorting of large networks", CACM 5(11)) over
# the accumulator dependency relation — edge B depends on edge A iff B reads a cell A writes (§4.3). The
# loud-cycle behavior is Kahn's residual-queue emptiness check. This is A. B. Kahn 1962, NOT Gilles
# Kahn 1974 (KPN) — the KPN citation is inapplicable to collection semantics.
#
# Determinism (Law E2): incomparable edges are emitted in frozen-sort-key order (a canonical tie-break),
# making toposort a pure function of the edge SET — invariant under input permutation. Write–write
# conflicts are NOT arcs (Bernstein output independence is relaxed); the fold's observable output is
# schedule-independent because cells are canonically ordered (materialize.nix), not because same-cell
# writes commute as list appends.
{
  prelude,
  core,
  graph,
}:
let
  inherit (core)
    readsOf
    writesOf
    writeSatisfiesRead
    edgeSortKey
    renderName
    ;
  inherit (prelude)
    genList
    elemAt
    filter
    length
    map
    sort
    foldl'
    head
    any
    concatStringsSep
    ;

  # Canonical per-edge key: the frozen sort key, tie-broken by the JSON of the (reads, writes) sets so
  # edges sharing a sort key but differing in dependency footprint still order deterministically.
  canonKeyOf =
    edge:
    edgeSortKey edge
    + ""
    + builtins.toJSON {
      reads = readsOf edge;
      writes = writesOf edge;
    };

  toposort =
    edges:
    let
      n = length edges;
      # Force readsOf on every edge up front: an unresolved collected membership is a loud error HERE
      # (spec §2.2), not a silent mis-ordering.
      nodes = genList (
        i:
        let
          e = elemAt edges i;
        in
        {
          inherit i e;
          reads = readsOf e;
          writes = writesOf e;
          key = canonKeyOf e;
        }
      ) n;

      nodeAt = i: elemAt nodes i;

      # Force readsOf/writesOf on EVERY edge up front — an unresolved collected membership must be a loud
      # error regardless of the arc topology (a lone unresolved edge generates no arcs to force it).
      forcedDeps = builtins.deepSeq (map (nd: [
        nd.reads
        nd.writes
      ]) nodes) true;

      # predecessors of B: every A whose write feeds a read of B (A ≠ B). O(n²) — fine at edge-set scale.
      predsOf = genList (
        bi:
        let
          b = nodeAt bi;
        in
        filter (ai: ai != bi && any (r: any (w: writeSatisfiesRead w r) (nodeAt ai).writes) b.reads) (
          genList (x: x) n
        )
      ) n;

      indeg0 = genList (i: length (elemAt predsOf i)) n;

      # Kahn: repeatedly emit the ready (indegree-0) node with the smallest canonical key.
      step =
        state:
        let
          ready = sort (a: b: (nodeAt a).key < (nodeAt b).key) (
            filter (i: (elemAt state.indeg i) == 0 && !(state.done ? ${toString i})) state.remaining
          );
        in
        if ready == [ ] then
          state
        else
          let
            pick = head ready;
            remaining' = filter (i: i != pick) state.remaining;
            # decrement indegree of every successor of pick
            indeg' = genList (
              j:
              let
                base = elemAt state.indeg j;
              in
              if builtins.elem pick (elemAt predsOf j) then base - 1 else base
            ) n;
          in
          step {
            remaining = remaining';
            indeg = indeg';
            emitted = state.emitted ++ [ pick ];
            done = state.done // {
              ${toString pick} = true;
            };
          };

      final = step {
        remaining = genList (x: x) n;
        indeg = indeg0;
        emitted = [ ];
        done = { };
      };

      # A residual non-empty queue ⇒ a cycle. Name the participating (target, channel) chain via
      # gen-graph.cycles over the arc accessor (gen-graph underneath).
      cyclicIdx = graph.cycles {
        nodes = genList (x: x) n;
        edges = ai: filter (bi: bi != ai && builtins.elem ai (elemAt predsOf bi)) (genList (x: x) n);
      };
      chain = map (
        i:
        let
          e = (nodeAt i).e;
          t = e.target;
        in
        if t ? output then "out:${concatStringsSep "." t.output}" else "${renderName t.root}/${t.class}"
      ) cyclicIdx;
    in
    builtins.seq forcedDeps (
      if length final.emitted < n then
        throw "gen-edge.toposort: delivery-edge cycle among (target, channel): ${builtins.toJSON chain}"
      else
        map (i: (nodeAt i).e) final.emitted
    );
in
{
  inherit toposort;
}
