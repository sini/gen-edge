# gen-edge trace — the frozen, versioned, cross-repo parity oracle E(topology).
#
# `trace` is a pure, identity-level function of the edge SET: it renders edge identities (§4.4/§4.5)
# and never forces resolved content. Sorting is total and permutation-invariant — the frozen sort key
# (§4.4) primary, a canonical-JSON tie-break on the structured entry secondary — so equal topologies
# (equal edge sets up to permutation) yield byte-equal traces (Laws E2/E4).
{ prelude, core }:
let
  inherit (core) edgeSortKey traceEntryOf;
  inherit (prelude) map sort concatStringsSep;

  # Total order: primary = the frozen (T,P,S,M) key; secondary = canonical JSON of the identity-level
  # entry. The secondary makes `trace` a pure function of the SET even when two edges share a sort key
  # but differ in identity (e.g. distinct resolved memberships) — only genuinely identical entries
  # (unkeyed value duplicates, §2.2) collapse to an order-irrelevant tie.
  entryOrd =
    a: b:
    let
      ka = edgeSortKey a.edge;
      kb = edgeSortKey b.edge;
    in
    if ka != kb then ka < kb else builtins.toJSON a.entry < builtins.toJSON b.entry;

  trace =
    edges:
    let
      tagged = map (e: {
        edge = e;
        entry = traceEntryOf e;
      }) edges;
    in
    map (t: t.entry) (sort entryOrd tagged);

  # Display rendering — strings derived HERE only; nothing consumes them programmatically.
  renderEntry =
    entry:
    let
      t =
        if entry.target.arm == "output" then
          "out:" + concatStringsSep "." entry.target.output
        else
          "root:" + entry.target.root + "/" + entry.target.class;
      s =
        if entry.source.arm == "collected" then
          "collected:" + entry.source.scope + "/" + entry.source.class
        else if entry.source.arm == "rewalk" then
          "rewalk:"
          + entry.source.aspect
          + "/"
          + concatStringsSep "+" entry.source.bindings
          + "/"
          + entry.source.class
        else if entry.source.arm == "synthesize" then
          (
            if entry.source.spec ? key then
              "synthesize:" + entry.source.spec.key
            else
              "synthesize:"
              + entry.source.spec.forwardId
              + "/"
              + entry.source.spec.fromClass
              + ">"
              + entry.source.spec.intoClass
          )
        else
          "value:" + (if entry.source.key == null then "_" else entry.source.key);
      p = concatStringsSep "/" entry.path;
    in
    t
    + " | "
    + p
    + " | "
    + s
    + " | "
    + entry.mode
    # a labeled entry appends its kind — the rendered trace carries K exactly when the sort key
    # does; un-labeled entries render the historical four-component string (REFERENCE.md)
    + (if (entry.kind or null) == null then "" else " | " + entry.kind);

  renderTrace = E: concatStringsSep "\n" (map renderEntry E);

  # Canonical, stable hash of a trace — the content-independent structural fingerprint of a topology.
  hashTrace = edges: builtins.hashString "sha256" (builtins.toJSON (trace edges));
in
{
  inherit
    trace
    renderTrace
    renderEntry
    hashTrace
    ;
}
