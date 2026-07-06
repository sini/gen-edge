# gen-edge projection — `project`, the ONLY constructor of the static per-root projection Π (§2.5/§4.2).
#
# Π is a pure function of (graph, root, dials, contexts) — NEVER of fold results (Law E5). It derives
# every structural field: the resolved isolation-bounded membership (governed by isolationMode), the
# resolved membership universe (allScopeIds dial, or the graph's bucket-bearing positions), and the
# lazily-carried seed-content accessor. Raw isolation marks and the parent accessor deliberately do NOT
# appear — Π carries only their product, so nothing downstream can consult a mark (Law E3). Seed content
# is carried lazily and forced only by collected reads at fold time (Law E13).
{ prelude, core }:
let
  inherit (core)
    renderName
    resolveId
    subtreeIds
    normalizeSeed
    ;
  inherit (prelude)
    map
    filter
    sort
    listToAttrs
    genAttrs
    ;

  project =
    {
      graph,
      root,
      dials ? { },
      contexts ? null,
      contextsAreAugmented ? false,
    }:
    let
      d = {
        isolationMode = "aware";
        dedupMode = "dedup";
        allScopeIds = null;
        classInject = null;
      }
      // dials;

      rootId = resolveId root;
      rootName = renderName (graph.nameOf rootId);

      # The resolved isolation-bounded membership — the only isolation product that survives construction.
      membershipIds = subtreeIds graph d.isolationMode rootId;
      membership = sort builtins.lessThan (map (id: renderName (graph.nameOf id)) membershipIds);

      # The resolved membership universe: the explicit dial order when supplied, else the graph's
      # bucket-bearing positions in lexicographic name order (v1 perScope attrnames). Channel PRESENCE
      # (channelsOf) is consulted — bucket content is never forced.
      universe =
        if d.allScopeIds != null then
          d.allScopeIds
        else
          sort builtins.lessThan (
            map (id: renderName (graph.nameOf id)) (filter (id: graph.channelsOf id != [ ]) graph.nodes)
          );

      # Seed buckets: position → channel → [ contribution ], carried LAZILY. The genAttrs values are
      # thunks — project forces only nameOf (keys) and channelsOf (presence), never contentsOf (Law E13).
      contents = listToAttrs (
        map (id: {
          name = renderName (graph.nameOf id);
          value = genAttrs (graph.channelsOf id) (ch: map normalizeSeed (graph.contentsOf id ch));
        }) graph.nodes
      );
    in
    {
      rootScopeId = rootName;
      inherit membership universe contents;
      scopeContexts = if contexts == null then { } else contexts;
      inherit contextsAreAugmented;
      inherit (d) isolationMode dedupMode classInject;
    };
in
{
  inherit project;
}
