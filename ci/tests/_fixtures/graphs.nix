# Synthetic accessor-graph builder for the gen-edge suites. A compact declarative spec compiles to the
# §2.3 accessor-graph (nodes + the six structural accessors + contentsOf). Positions are string ids;
# nameOf defaults to `{ opaque = id; }` unless a nameSpec is supplied in `names` (entity id_hash naming).
{ lib }:
let
  mkGraph =
    {
      tree ? { }, # id -> [ childId ]  (childrenOf; parentOf derived)
      roots ? [ ], # ids with no parent (informational; parentOf derived from tree)
      isolated ? [ ], # ids whose isolatedAt is true
      buckets ? { }, # id -> channel -> [ contribution ]  (contentsOf; channelsOf derived)
      declared ? { }, # id -> [ edge ]  (edgesAt)
      names ? { }, # id -> nameSpec  (nameOf; default { opaque = id; })
      extraNodes ? [ ], # ids present with no bucket/child (route-only scopes)
    }:
    let
      allIds = lib.unique (
        (builtins.attrNames tree)
        ++ (lib.concatLists (builtins.attrValues tree))
        ++ (builtins.attrNames buckets)
        ++ (builtins.attrNames declared)
        ++ (builtins.attrNames names)
        ++ isolated
        ++ roots
        ++ extraNodes
      );
      parentIndex = lib.listToAttrs (
        lib.concatLists (
          lib.mapAttrsToList (
            p: cs:
            map (c: {
              name = c;
              value = p;
            }) cs
          ) tree
        )
      );
    in
    {
      nodes = allIds;
      childrenOf = id: tree.${id} or [ ];
      parentOf = id: parentIndex.${id} or null;
      isolatedAt = id: builtins.elem id isolated;
      channelsOf = id: builtins.attrNames (buckets.${id} or { });
      edgesAt = id: declared.${id} or [ ];
      nameOf = id: names.${id} or { opaque = id; };
      contentsOf = id: channel: (buckets.${id} or { }).${channel} or [ ];
    };

  # A contribution seed: { content; key ? null; }.
  c = content: key: { inherit content key; };
in
{
  inherit mkGraph c;
}
