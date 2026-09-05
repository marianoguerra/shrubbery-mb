///|
/// Move every element's prefix onto the element before it, and lift a group's
/// outermost prefix and suffix onto the group itself.
///
/// The concatenation is unchanged — this pass moves text between adjacent
/// nodes, never adds or drops any — so source reproduction is exact with or
/// without it. What it fixes is WHERE the text sits, which is what a consumer
/// reading one node's metadata sees. Without it, the comment written after a
/// term is found on the term after that.
///
/// The reference does the same and states the one deliberate omission: a
/// `parens`, `block` or `alts` keeps its leading prefix and trailing suffix
/// INSIDE, because moving them out would put them on the wrong side of the
/// delimiter.
fn normalize_group_raw(node : @ast.Node) -> Unit {
  match node.it {
    // A document's own suffix is already the end-of-file trail, so nothing is
    // lifted onto it here.
    Multi(children) => {
      let _ = shift_prefix_to_suffix(children, extract_suffix=false)
    }
    Group(children) => {
      let carried = shift_prefix_to_suffix(children, extract_suffix=true)
      match carried {
        Some(suffix) => node.meta.suffix = suffix.combine(node.meta.suffix)
        None => ()
      }
      if children.length() > 0 {
        let first = anchor_of(children[0])
        node.meta.prefix = node.meta.prefix.combine(first.meta.prefix)
        first.meta.prefix = Empty
      }
    }
    Parens(children)
    | Brackets(children)
    | Braces(children)
    | Quotes(children)
    | Block(children)
    | Alts(children) => {
      let _ = shift_prefix_to_suffix(children, extract_suffix=false)
    }
    _ => ()
  }
}

///|
/// Where an element's prefix and suffix actually live.
///
/// For a compound the properties are on the node itself; for an operator they
/// are on the operator rather than on the `op` wrapper the reference writes.
/// Both are already true of this representation, so this is the identity — it
/// exists to say so at the one place that would otherwise have to guess.
fn anchor_of(node : @ast.Node) -> @ast.Node {
  node
}

///|
/// Returns the suffix lifted off the last element, when asked for it.
fn shift_prefix_to_suffix(
  elems : Array[@ast.Node],
  extract_suffix~ : Bool,
) -> @raw.Raw? {
  for e in elems {
    normalize_group_raw(e)
  }
  if elems.length() == 0 {
    return None
  }
  for i in 1..<elems.length() {
    let next = anchor_of(elems[i])
    if !next.meta.prefix.is_empty() {
      let prev = anchor_of(elems[i - 1])
      prev.meta.suffix = prev.meta.suffix.combine(next.meta.prefix)
      next.meta.prefix = Empty
    }
  }
  if !extract_suffix {
    return None
  }
  let last = anchor_of(elems[elems.length() - 1])
  if last.meta.suffix.is_empty() {
    None
  } else {
    let suffix = last.meta.suffix
    last.meta.suffix = Empty
    Some(suffix)
  }
}
