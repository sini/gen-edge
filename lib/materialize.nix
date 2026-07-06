# gen-edge materialization — THE fold. One left fold over the ordered edge list, threading the
# accumulator (§4.3/§2.6). The accumulator is SEEDED from Π.contents before any edge runs (the API path
# by which per-position channel content enters the fold — a plain leaf graph folds to its seeded buckets
# under the default-fold edges, never to empty config).
#
# THEORY: Bernstein (1966) read/write independence over readsOf/writesOf; the relaxed output-independence
# case (same-cell writers) is discharged HERE by canonical cell ordering — a cell's contributions observe
# seed-first-then-producing-edge-sort-key order, independent of execution schedule (Laws E2/E9/E12), so
# conflicting writers commute *as observed* even though they do not commute as list appends.
{ prelude, core }:
let
  inherit (core)
    cellKey
    readsOf
    writesOf
    renderName
    edgeSortKey
    setAttrByPath
    normalizeSeed
    dedupFirst
    ;
  inherit (prelude)
    map
    filter
    sort
    foldl'
    concatMap
    elem
    unique
    ;

  # ── cell reads: canonical order (§4.3) ──────────────────────────────────────
  # A cell is `{ seeds = [contrib]; edges = [{ sortKey; items = [contrib]; }]; }`. Its ordered contents
  # are seeds first (verbatim in caller order), then edge contributions ordered by producing-edge sort
  # key — never by arrival order. This is what makes E2/E9/E12 hold.
  orderedContribs =
    cell:
    (cell.seeds or [ ])
    ++ concatMap (ew: ew.items) (sort (a: b: a.sortKey < b.sortKey) (cell.edges or [ ]));

  cellOf =
    acc: ref:
    acc.${cellKey ref} or {
      seeds = [ ];
      edges = [ ];
    };

  # The derived flat aggregate view (§4.3, v1 classImports): the pinned-order concat of input cells
  # (s, channel) over the universe enumeration. Never threaded, never written — a read-only derivation.
  aggregateContribs =
    acc: pi: channel:
    concatMap (
      pos:
      orderedContribs (
        cellOf acc {
          position = pos;
          inherit channel;
        }
      )
    ) pi.universe;

  # Resolve a declared cell-ref to the ordered list of content VALUES an interpreter receives.
  readCellValues =
    acc: pi: ref:
    let
      contribs =
        if ref ? aggregate then
          aggregateContribs acc pi ref.aggregate
        else
          orderedContribs (cellOf acc ref);
    in
    map (c: c.content) contribs;

  # ── collected bucket union: the frozen §2.6 enumeration ─────────────────────
  # dedup mode: positions enumerate in universe order restricted to membership, then one first-occurrence
  # key dedup over the whole concatenation. raw mode: lexicographic bucket-bearing-position order
  # restricted to membership, dedup-free concat.
  enumerationOrder =
    pi: members: channel: acc:
    let
      memberSet = prelude.listToAttrs (map (m: prelude.nameValuePair m true) members);
    in
    if pi.dedupMode == "dedup" then
      filter (m: memberSet ? ${m}) pi.universe
    else
      sort builtins.lessThan (
        filter (
          m:
          orderedContribs (
            cellOf acc {
              position = m;
              inherit channel;
            }
          ) != [ ]
        ) members
      );

  collectedUnion =
    acc: pi: source:
    let
      class = source.collected.class;
      order = enumerationOrder pi source.collected.members class acc;
      concatted = concatMap (
        pos:
        orderedContribs (
          cellOf acc {
            position = pos;
            channel = class;
          }
        )
      ) order;
    in
    if pi.dedupMode == "dedup" then dedupFirst concatted else concatted;

  # ── source interpretation → a list of contributions ─────────────────────────
  interpretSource =
    acc: pi: interpret: edge:
    let
      s = edge.source;
    in
    if s ? collected then
      collectedUnion acc pi s
    else if s ? synthesize then
      (
        if !(interpret ? synthesize) then
          throw "gen-edge.materialize: source kind 'synthesize' present for edge '${edgeSortKey edge}' but no interpret.synthesize supplied (§2.6)"
        else
          [
            {
              content = interpret.synthesize edge pi (map (readCellValues acc pi) s.synthesize.reads);
              key = null;
            }
          ]
      )
    else if s ? rewalk then
      (
        if !(interpret ? rewalk) then
          throw "gen-edge.materialize: source kind 'rewalk' present for edge '${edgeSortKey edge}' but no interpret.rewalk supplied (§2.6)"
        else
          [
            {
              content = interpret.rewalk edge pi;
              key = null;
            }
          ]
      )
    else
      throw "gen-edge.materialize: unknown source arm for edge '${edgeSortKey edge}'";

  # normalize a raw contribution list to full contribution records (fills key/noDedup).
  normContribs = map (c: {
    inherit (c) content;
    key = c.key or null;
    noDedup = c.noDedup or false;
    provenance = c.provenance or { };
  });

  # ── the fold ─────────────────────────────────────────────────────────────────
  materialize =
    {
      edges,
      projection,
      combine ? { },
      interpret ? { },
    }:
    let
      isFn = builtins.isFunction projection;
      piFor = rootName: if isFn then projection rootName else projection;

      rootNamesOf = e: if e.target ? root then [ (renderName e.target.root) ] else [ ];
      distinctRoots = unique (concatMap rootNamesOf edges);
      defaultPi =
        if isFn then
          (if distinctRoots == [ ] then projection "" else piFor (builtins.head distinctRoots))
        else
          projection;
      piForEdge = e: if e.target ? root then piFor (renderName e.target.root) else defaultPi;

      # Seed the accumulator input cells from Π.contents (all relevant Πs agree by construction).
      allPis = if isFn then map piFor distinctRoots else [ projection ];
      seedContents = foldl' (a: pi: a // pi.contents) { } allPis;
      seededAcc = prelude.listToAttrs (
        concatMap (
          pos:
          map (
            channel:
            prelude.nameValuePair
              (cellKey {
                position = pos;
                inherit channel;
              })
              {
                seeds = seedContents.${pos}.${channel};
                edges = [ ];
              }
          ) (builtins.attrNames seedContents.${pos})
        ) (builtins.attrNames seedContents)
      );

      # write a producing-edge contribution list into a cell
      writeCell =
        acc: ref: sortKey: items:
        let
          k = cellKey ref;
          cur =
            acc.${k} or {
              seeds = [ ];
              edges = [ ];
            };
        in
        acc
        // {
          ${k} = cur // {
            edges = cur.edges ++ [
              {
                inherit sortKey items;
              }
            ];
          };
        };

      step =
        acc: edge:
        let
          pi = piForEdge edge;
          sortKey = edgeSortKey edge;
          # value arm carries value/key rather than content — surface it as a contribution here.
          rawContribs =
            if edge.source ? value then
              [
                {
                  inherit (edge.source.value) key;
                  content = edge.source.value.value;
                }
              ]
            else
              interpretSource acc pi interpret edge;
          contribs = normContribs rawContribs;
          adaptMaybe = c: if edge.adapt == null then c else edge.adapt c pi;
          place = c: setAttrByPath edge.path (adaptMaybe c);
          writes = writesOf edge;
        in
        if edge.mode == "merge" then
          # merge → write the source contributions into the target output (or output-arm) cell.
          foldl' (a: w: writeCell a w sortKey contribs) acc writes
        else if edge.mode == "nest" then
          # nest → place content at path, then write into the target root's input cell (nest∘merge).
          foldl' (
            a: w: writeCell a w sortKey (map (c: c // { content = place c.content; }) contribs)
          ) acc writes
        else
          # nest-verbatim → place keyed wrappers by reference, keys intact, dedup-exempt (corollary 3).
          foldl' (
            a: w:
            writeCell a w sortKey (
              map (
                c:
                c
                // {
                  content = place c.content;
                  noDedup = true;
                }
              ) contribs
            )
          ) acc writes;

      finalAcc = foldl' step seededAcc edges;

      # ── config = the per-root/per-channel OUTPUT cells + output-arm sinks ─────
      # Output cell combine: producing-edge sort-key order, then dedup (dedupMode) skipping verbatim
      # wrappers; content values only. A `combine.merge` override receives the ordered content list.
      combineOutput =
        pi: cell:
        let
          ordered = concatMap (ew: ew.items) (sort (a: b: a.sortKey < b.sortKey) cell.edges);
          deduped = if pi.dedupMode == "dedup" then dedupFirst ordered else ordered;
          contents = map (c: c.content) deduped;
        in
        if combine ? merge then combine.merge contents else contents;

      # collect every output cell -> { <rootName> = { <channel> = content; }; }
      outputCellKeys = filter (k: prelude.hasPrefix "out:" k) (builtins.attrNames finalAcc);
      rootConfig = foldl' (
        acc: k:
        let
          rest = prelude.removePrefix "out:" k; # "<rootName>/<channel>"
          m = builtins.match "(.*)/([^/]*)" rest;
          rootName = builtins.elemAt m 0;
          channel = builtins.elemAt m 1;
          pi = piFor rootName;
        in
        acc
        // {
          ${rootName} = (acc.${rootName} or { }) // {
            ${channel} = combineOutput pi finalAcc.${k};
          };
        }
      ) { } outputCellKeys;

      outArmKeys = filter (k: prelude.hasPrefix "outarm:" k) (builtins.attrNames finalAcc);
      outputsConfig = foldl' (
        acc: k:
        let
          armKey = prelude.removePrefix "outarm:" k;
        in
        acc
        // {
          ${armKey} = combineOutput defaultPi finalAcc.${k};
        }
      ) { } outArmKeys;
    in
    rootConfig // prelude.optionalAttrs (outArmKeys != [ ]) { outputs = outputsConfig; };
in
{
  inherit materialize;
  # readsOf/writesOf are public (§4.3): den-compat's differential tests and toposort both consume them.
  inherit (core) readsOf writesOf;
}
