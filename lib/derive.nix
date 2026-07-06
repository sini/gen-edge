# gen-edge derivation — `edgesFor`, the complete edge set of a root, a pure function of the STRUCTURAL
# stratum only (Law E13). It never interprets sources, never reads the accumulator, never forces bucket
# content: it consults `childrenOf`/`parentOf`/`isolatedAt`/`channelsOf`/`edgesAt`/`nameOf`/`nodes`.
#
# THEORY (internal provenance): corollary 1 (default-fold-by-construction) and its non-double-count
# refinement — exactly one merge edge per (root, channel), no per-descendant edge — are fixed by
# `delivery-edge-unification` §2 (Law E7). Because subtree(S) ⊆ subtree(R), a per-descendant edge to R
# would multiply-count content.
{
  prelude,
  core,
  edge,
}:
let
  inherit (core) renderName resolveId subtreeIds;
  inherit (prelude)
    map
    filter
    sort
    unique
    concatMap
    ;
  inherit (edge) sources targets;
  mkEdge = edge.edge;

  edgesFor =
    {
      graph,
      root,
    }:
    let
      rootId = resolveId root;
      rootSpec = graph.nameOf rootId;
      rootName = renderName rootSpec;

      # R's resolved isolation-bounded subtree (aware isolation — edgesFor is dial-free; the blind-mode
      # spawn projection is a project-level Π concern, den-compat territory).
      membershipIds = subtreeIds graph "aware" rootId;
      membershipNames = sort builtins.lessThan (map (id: renderName (graph.nameOf id)) membershipIds);

      # Channels present anywhere in the subtree (presence via channelsOf — never forces bucket content).
      channels = sort builtins.lessThan (unique (concatMap (id: graph.channelsOf id) membershipIds));

      # Default-fold edges by construction (Law E7): exactly one per present channel. members is the
      # resolved membership; the collectedScopes annotation is its rendered mirror (§4.1).
      defaultEdges = map (
        ch:
        mkEdge {
          source = sources.collected {
            scope = rootSpec;
            class = ch;
            members = membershipNames;
          };
          target = targets.root {
            root = rootSpec;
            class = ch;
          };
          path = [ ];
          mode = "merge";
          annotations = {
            collectedScopes = membershipNames;
          };
        }
      ) channels;

      # Declared edges targeting this root, gathered from edgesAt over the WHOLE graph (a child scope may
      # declare an edge targeting the parent root — the first-class form of v1 appendToParent).
      allDeclared = concatMap (id: graph.edgesAt id) graph.nodes;
      targetingRoot = filter (e: (e.target ? root) && renderName e.target.root == rootName) allDeclared;
    in
    defaultEdges ++ targetingRoot;
in
{
  inherit edgesFor;
}
