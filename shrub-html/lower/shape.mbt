///|
/// Recognising shapes in a shrubbery group.
///
/// Every one of these is a pattern match over a group's item array, written
/// once here so that the rules live in one place and a reader can check the
/// surface syntax against them without following the lowering.

///|
/// Split a group's items into the head and its trailing block.
///
/// The three structural laws of the shrubbery tree make this total: a `Block`
/// is the last item or the second-to-last with `Alts` after it, and `Alts` is
/// always last. So looking at the tail is enough, and there is no case where a
/// block hides in the middle.
fn split_block(
  items : ArrayView[@sast.Node],
) -> (ArrayView[@sast.Node], @sast.Node?, Bool) {
  let n = items.length()
  if n == 0 {
    return (items, None, false)
  }
  match items[n - 1].it {
    Alts(_) =>
      if n >= 2 {
        match items[n - 2].it {
          Block(_) => (items[0:n - 2], Some(items[n - 2]), true)
          _ => (items[0:n - 1], None, true)
        }
      } else {
        (items[0:0], None, true)
      }
    Block(_) => (items[0:n - 1], Some(items[n - 1]), false)
    _ => (items, None, false)
  }
}

///|
/// `Id(name)` immediately followed by `Parens`: a call.
///
/// Adjacency is not checked, and cannot be: shrubbery's tree does not record
/// whitespace, so `div ()` and `div()` are the same nodes. There is nothing for
/// the second spelling to mean instead, so nothing is lost.
fn as_call(
  items : ArrayView[@sast.Node],
) -> (String, ArrayView[@sast.Node], ArrayView[@sast.Node])? {
  match items {
    [{ it: Id(name), .. }, { it: Parens(args), .. }, ..] =>
      Some((name, args[:], items[2:]))
    _ => None
  }
}

///|
/// The single string literal inside a call's arguments, if that is all it has.
///
/// This is the literal escape: in a position where markup never admits a
/// string, one means "take this name exactly, with no transform". It is how
/// `element("side_bar")` and `attr("xlink:href", "#a")` say what `unkebab`
/// cannot.
fn literal_string(args : ArrayView[@sast.Node]) -> String? {
  match args {
    [{ it: Group([{ it: Lit(Str(s)), .. }]), .. }] => Some(s)
    _ => None
  }
}

///|
/// The two string literals inside a call's arguments.
fn literal_pair(args : ArrayView[@sast.Node]) -> (String, String)? {
  match args {
    [
      { it: Group([{ it: Lit(Str(a)), .. }]), .. },
      { it: Group([{ it: Lit(Str(b)), .. }]), .. },
    ] => Some((a, b))
    _ => None
  }
}

///|
/// An `@{...}` body, as one string.
///
/// At-notation is shrubbery's indentation-stripping literal text block, and it
/// is exactly what `script`, `style`, `pre` and `textarea` need. Its tree shape
/// is a `Parens` holding one `Group` holding one `Brackets` of string pieces,
/// with an explicit `"\n"` piece between lines -- so concatenating the pieces
/// reconstructs the text with its shared indentation already removed.
///
/// A body containing anything but string pieces -- an `@` escape with a nested
/// term in it -- answers `None`, and the caller falls back to reading it as
/// ordinary children.
fn as_at_text(node : @sast.Node) -> String? {
  let groups = match node.it {
    Parens(gs) => gs
    _ => return None
  }
  if groups.length() != 1 {
    return None
  }
  let inner = match groups[0].it {
    Group(xs) => xs
    _ => return None
  }
  if inner.length() != 1 {
    return None
  }
  let pieces = match inner[0].it {
    Brackets(ps) => ps
    _ => return None
  }
  let buf = StringBuilder()
  for p in pieces {
    match p.it {
      Group(xs) =>
        if xs.length() == 1 {
          match xs[0].it {
            Lit(Str(s)) => buf.write_string(s)
            _ => return None
          }
        } else {
          return None
        }
      _ => return None
    }
  }
  Some(buf.to_string())
}

///|
/// The groups inside a `Block`.
fn block_groups(node : @sast.Node) -> Array[@sast.Node] {
  match node.it {
    Block(gs) => gs
    _ => []
  }
}
