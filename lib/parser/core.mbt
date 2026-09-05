///|
/// A node's span, from the first token to the last.
fn span_of(start : @lexer.Token, end : @lexer.Token?) -> @basic.Span {
  match end {
    Some(e) => { start: start.span.start, end: e.span.end, }
    None => start.span
  }
}

///|
/// A span covering a run of nodes, or `fallback` when there are none.
fn span_over(nodes : Array[@ast.Node], fallback : @basic.Span) -> @basic.Span {
  if nodes.length() == 0 {
    return fallback
  }
  { start: nodes[0].span.start, end: nodes[nodes.length() - 1].span.end, }
}

///|
/// The node for one token: an atom, or the operator form.
fn leaf_of(t : @lexer.Token) -> @ast.Node {
  let shrub : @ast.Shrub = match t.kind {
    Identifier => Id(t.name())
    Keyword => Kw(strip_tilde(t))
    Operator => Op(t.name())
    Literal(d) => Lit(d)
    SExp(d) => Lit(d)
    _ => Id(t.text)
  }
  let node = @ast.Node::new(shrub, t.span)
  node.meta.raw = Str(t.raw_text())
  node
}

///|
/// A keyword's name has no `~`: `~style` is the keyword `style`. A `~#{name}`
/// escape has no `~` in its text either, so the name comes from the raw form.
fn strip_tilde(t : @lexer.Token) -> String {
  match t.value {
    Some(Sym(name)) => return name
    _ => ()
  }
  let s = t.text
  if s.has_prefix("~") {
    return s.clamped_view(start=1).to_owned()
  }
  s
}

///|
/// Give `node` the prefix in `pre`, keeping anything from an `@` onwards as the
/// inner prefix.
fn attach_prefix(node : @ast.Node, pre : RawList) -> Unit {
  attach_meta_prefix(node.meta, pre)
}

///|
fn attach_meta_prefix(meta : @raw.Meta, pre : RawList) -> Unit {
  let (before, inner) = pre.to_raw_split_at()
  meta.prefix = before.combine(meta.prefix)
  meta.inner_prefix = inner.combine(meta.inner_prefix)
}

///|
/// Turn the pending groups into finished ones.
fn to_group_nodes(gs : Array[PendingGroup]) -> Array[@ast.Node] {
  gs.map(g => {
    let node = @ast.Node::new(Group(g.items), g.span, meta=g.meta)
    node
  })
}

///|
/// Split a sequence of groups into a block and, if the groups were all `|`
/// alternatives, the alternatives that follow it.
///
/// The reference marks a group that came from a `|` with a temporary tag and
/// looks for it here; `PendingGroup::bar` is that mark, typed. Either every
/// group in the run is an alternative -- and the whole thing is an `alts` --
/// or a prefix of ordinary groups is the block and the alternatives follow it.
fn tag_as_block(
  gs : Array[PendingGroup],
  fallback : @basic.Span,
) -> (@ast.Node, Array[@ast.Node]) {
  // The longest prefix of ordinary groups.
  let mut split = 0
  while split < gs.length() && gs[split].bar is None {
    split = split + 1
  }
  let head = gs[0:split].to_owned()
  let bars = gs[split:].to_owned()
  // A run that starts with a bar must be all bars; anything else is a group
  // sequence the parser would not have produced.
  let all_bars = bars.length() > 0 && bars.iter().all(g => g.bar is Some(_))
  if !all_bars {
    let nodes = to_group_nodes(gs)
    return (@ast.Node::new(Block(nodes), span_over(nodes, fallback)), [])
  }
  let alt_blocks = bars.map(g => {
    let b = g.bar.unwrap()
    // The `|`'s own prefix belongs to the alternative it introduces.
    b.meta.prefix = g.meta.prefix.combine(b.meta.prefix)
    b
  })
  let alts = @ast.Node::new(Alts(alt_blocks), span_over(alt_blocks, fallback))
  if head.length() == 0 {
    (alts, [])
  } else {
    let nodes = to_group_nodes(head)
    (@ast.Node::new(Block(nodes), span_over(nodes, fallback)), [alts])
  }
}

///|
/// The top level: `tag_as_block`, but the block's groups stay as they are and
/// only the alternatives are wrapped.
fn bars_insert_alts(
  gs : Array[PendingGroup],
  fallback : @basic.Span,
) -> Array[@ast.Node] {
  let (block, alts) = tag_as_block(gs, fallback)
  let out = block.children()
  for a in alts {
    out.push(a)
  }
  out
}
