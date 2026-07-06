# gen-edge core — the shared, pure primitives every other module rests on: identity/name rendering,
# the FROZEN trace sort key (§4.4), the structured trace entry, cell-ref canonical keys, the
# `readsOf`/`writesOf` accumulator dependency sets (§4.3), and the isolation-bounded subtree walk.
#
# THEORY: the read/write dependency sets realize the read/write half of Bernstein's conditions
# (Bernstein 1966, "Analysis of Programs for Parallel Processing", IEEE Trans. EC-15) — the arcs an
# edge's execution imposes on the schedule. Output independence (W₁ ∩ W₂ = ∅) is deliberately relaxed
# here and discharged by canonical cell ordering downstream (see materialize.nix).
{ prelude }:
let
  inherit (prelude)
    concatStringsSep
    concatMap
    filter
    map
    sort
    elem
    unique
    ;

  # ── identity & rendering ───────────────────────────────────────────────────
  # A position identity is a nameSpec: `{ kind; idHash; }` (entity — parent-blind id_hash identity) or
  # `{ opaque = string; }` (non-entity position / pipeline root). Strings coerce to opaque; a registry
  # entry carrying kind + id_hash coerces to the entity form. Rendered names are INTERNAL keys only.
  toNameSpec =
    x:
    if builtins.isString x then
      { opaque = x; }
    else if !(builtins.isAttrs x) then
      throw "gen-edge: cannot derive a position nameSpec from ${builtins.typeOf x}"
    else if x ? opaque then
      x
    else if x ? kind && x ? idHash then
      { inherit (x) kind idHash; }
    else if x ? kind && x ? id_hash then
      {
        inherit (x) kind;
        idHash = x.id_hash;
      }
    else
      throw "gen-edge: value is neither a nameSpec nor an identity-bearing entry: ${builtins.toJSON x}";

  # Frozen scope naming (§4.4): entity → "<kind>:<idHash>" (parent-blind, stable across re-keying);
  # non-entity / pipeline root → its opaque string.
  renderName =
    ns:
    let
      s = toNameSpec ns;
    in
    if s ? kind then "${s.kind}:${s.idHash}" else s.opaque;

  # A graph position id may itself be a registry entry carrying `.id`; graph accessors key by the id.
  resolveId = x: if builtins.isAttrs x && x ? id then x.id else x;

  # ── attrpath placement (nest) ──────────────────────────────────────────────
  setAttrByPath =
    path: value:
    if path == [ ] then
      value
    else
      { ${builtins.head path} = setAttrByPath (builtins.tail path) value; };

  # ── the FROZEN trace sort key (§4.4 — v1 byte contract) ─────────────────────
  targetKey =
    target:
    if target ? output then
      "out:" + concatStringsSep "." target.output
    else
      "root:" + renderName target.root + "/" + target.class;

  pathKey = path: concatStringsSep "/" path;

  sourceKey =
    source:
    if source ? collected then
      "collected:" + renderName source.collected.scope + "/" + source.collected.class
    else if source ? rewalk then
      "rewalk:"
      + source.rewalk.aspect
      + "/"
      + concatStringsSep "+" source.rewalk.bindings
      + "/"
      + source.rewalk.class
    else if source ? synthesize then
      (
        let
          spec = source.synthesize.spec;
        in
        if spec ? key then
          "synthesize:" + spec.key
        else
          "synthesize:" + spec.forwardId + "/" + spec.fromClass + ">" + spec.intoClass
      )
    else if source ? value then
      "value:" + (if source.value.key == null then "_" else source.value.key)
    else
      throw "gen-edge: unknown source arm in ${builtins.toJSON (builtins.attrNames source)}";

  edgeSortKey =
    edge:
    targetKey edge.target
    + " | "
    + pathKey edge.path
    + " | "
    + sourceKey edge.source
    + " | "
    + edge.mode;

  # ── structured trace entry (§4.5) — identity ONLY, never resolved content ────
  # The source projection carries identity fields (names, cell-refs, keys) and EXCLUDES every content
  # thunk (`synthesize.module`, `value.value`, collected bucket content) so `trace` never forces content.
  sourceIdentity =
    source:
    if source ? collected then
      {
        arm = "collected";
        scope = renderName source.collected.scope;
        inherit (source.collected) class members;
      }
    else if source ? synthesize then
      {
        arm = "synthesize";
        spec = source.synthesize.spec; # forwardId/fromClass/intoClass | key — all identity strings
        inherit (source.synthesize) reads;
      }
    else if source ? value then
      {
        arm = "value";
        inherit (source.value) key;
      }
    else if source ? rewalk then
      {
        arm = "rewalk";
        inherit (source.rewalk) aspect bindings class;
      }
    else
      throw "gen-edge: unknown source arm";

  targetIdentity =
    target:
    if target ? output then
      {
        arm = "output";
        inherit (target) output;
      }
    else
      {
        arm = "root";
        root = renderName target.root;
        inherit (target) class;
      };

  traceEntryOf = edge: {
    target = targetIdentity edge.target;
    inherit (edge) path mode annotations;
    source = sourceIdentity edge.source;
  };

  # ── accumulator cells & dependency sets (§4.3) ──────────────────────────────
  # Three cell-ref arms: an input `{ position; channel; }` cell (seeds + nest placements, read by
  # collected sources), an `{ output = rootName; channel; }` cell (folded merge result — the config
  # face), and an `{ outputArm = key; }` terminal (flake-output sink). The derived `{ aggregate = C; }`
  # read is a flat view over input cells, never a stored cell.
  cellKey =
    ref:
    if ref ? aggregate then
      "agg:" + ref.aggregate
    else if ref ? outputArm then
      "outarm:" + ref.outputArm
    else if ref ? output then
      "out:" + ref.output + "/" + ref.channel
    else
      "pos:" + ref.position + "/" + ref.channel;

  # readsOf: the cells an edge consumes. A collected source reads (s, class) for every resolved member;
  # an unresolved membership (null) is a loud definition-time error (§2.2). A synthesize source reads
  # exactly its declared cell-refs. value/keyedValue/rewalk read nothing.
  readsOf =
    edge:
    let
      s = edge.source;
    in
    if s ? collected then
      (
        if s.collected.members == null then
          throw "gen-edge: collected source for '${edgeSortKey edge}' has unresolved members (null) — build it via edgesFor, or supply an explicit resolved membership (spec §2.2)"
        else
          map (m: {
            position = m;
            channel = s.collected.class;
          }) s.collected.members
      )
    else if s ? synthesize then
      s.synthesize.reads
    else
      [ ];

  # writesOf: the cells an edge produces. merge → the target's output cell (or output-arm terminal);
  # nest/nest-verbatim → the target root's input cell (their placed content joins that bucket — the
  # nest∘merge decomposition; a root target only).
  writesOf =
    edge:
    let
      t = edge.target;
    in
    if edge.mode == "merge" then
      (
        if t ? output then
          [ { outputArm = concatStringsSep "." t.output; } ]
        else
          [
            {
              output = renderName t.root;
              channel = t.class;
            }
          ]
      )
    else
      (
        if t ? output then
          throw "gen-edge: nest/${edge.mode} requires a root target, got an output target for '${edgeSortKey edge}'"
        else
          [
            {
              position = renderName t.root;
              channel = t.class;
            }
          ]
      );

  # Does a producing write satisfy (feed) a consuming read? The `{ aggregate = C; }` read is satisfied
  # by EVERY input-cell write of channel C (the v1 flat read-back expansion, §2.4).
  writeSatisfiesRead =
    write: read:
    if read ? aggregate then
      (write ? position && write.channel == read.aggregate)
    else if read ? position then
      (write ? position && write.position == read.position && write.channel == read.channel)
    else if read ? output then
      (write ? output && write.output == read.output && write.channel == read.channel)
    else if read ? outputArm then
      (write ? outputArm && write.outputArm == read.outputArm)
    else
      false;

  # ── isolation-bounded subtree (Law E3, consumed only at construction) ────────
  # aware: the walk stops at (and excludes) isolated descendants — each is its own root. blind: the
  # isolation set is {} (the v1 spawn final-extraction invariant). The root itself is always included.
  subtreeIds =
    graph: isolationMode: rootId:
    let
      isolated = id: if isolationMode == "blind" then false else graph.isolatedAt id;
      go =
        visited: id:
        let
          k = renderName (graph.nameOf id);
        in
        if visited ? ${k} then
          [ ]
        else
          let
            v = visited // {
              ${k} = true;
            };
          in
          [ id ] ++ concatMap (c: if isolated c then [ ] else go v c) (graph.childrenOf id);
    in
    go { } rootId;

  # Seed normalization (§4.3): the caller's `contentsOf` bucket is a list of contributions. A bare
  # value is wrapped keyless; a `{ content; key ? null; }` record is taken as-is. Never forces content.
  normalizeSeed =
    c:
    if builtins.isAttrs c && c ? content then
      {
        inherit (c) content;
        key = c.key or null;
        noDedup = c.noDedup or false;
        provenance =
          c.provenance or {
            edge = null;
            source = "seed";
          };
      }
    else
      {
        content = c;
        key = null;
        noDedup = false;
        provenance = {
          edge = null;
          source = "seed";
        };
      };

  # First-occurrence-wins key dedup (§2.6): null keys and noDedup contributions are never deduped.
  dedupFirst =
    contribs:
    (prelude.foldl'
      (
        acc: c:
        if c.key == null || c.noDedup or false then
          acc // { items = acc.items ++ [ c ]; }
        else if elem c.key acc.seen then
          acc
        else
          acc
          // {
            seen = acc.seen ++ [ c.key ];
            items = acc.items ++ [ c ];
          }
      )
      {
        seen = [ ];
        items = [ ];
      }
      contribs
    ).items;
in
{
  inherit
    toNameSpec
    renderName
    resolveId
    setAttrByPath
    targetKey
    pathKey
    sourceKey
    edgeSortKey
    traceEntryOf
    sourceIdentity
    targetIdentity
    cellKey
    readsOf
    writesOf
    writeSatisfiesRead
    subtreeIds
    normalizeSeed
    dedupFirst
    ;
}
