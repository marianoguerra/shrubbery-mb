///|
/// Recognising shapes in a shrubbery group.
///
/// Every one of these is a pattern match over a group's item array, written
/// once here so that the rules live in one place and a reader can check the
/// surface syntax against them without following the lowering.

///|
/// Split a group's items into the head, its trailing block, and whether it had
/// alternatives.
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
/// whitespace, so `class (card)` and `class(card)` are the same nodes. That is
/// fine here -- there is nothing for the second spelling to mean instead --
/// and it is the same fact that makes an explicit relation keyword necessary
/// in a selector.
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
/// `Op("--")` then `Id`: a custom property or a dashed identifier.
///
/// The two can never be confused with an ordinary name: a shrubbery identifier
/// may not begin with `-`, and `--` on its own is not a property.
fn as_dashed(items : ArrayView[@sast.Node]) -> String? {
  match items {
    [{ it: Op("--"), .. }, { it: Id(n), .. }] => Some("--" + @names.unkebab(n))
    _ => None
  }
}

///|
/// The single string literal inside a call's arguments, if that is all it has.
///
/// This is the literal escape: in a position where CSS never admits a string,
/// one means "take this name exactly, with no transform". It is how
/// `class("btn__primary")` and `ident("side_bar")` say what `kebab` cannot.
fn literal_string(args : ArrayView[@sast.Node]) -> String? {
  match args {
    [{ it: Group([{ it: Lit(Str(s)), .. }]), .. }] => Some(s)
    _ => None
  }
}

///|
/// The single bare identifier inside a call's arguments.
fn single_ident(args : ArrayView[@sast.Node]) -> String? {
  match args {
    [{ it: Group([{ it: Id(n), .. }]), .. }] => Some(n)
    _ => None
  }
}

///|
/// A call argument that names something: an identifier, transformed, or a
/// string, taken literally.
fn name_arg(args : ArrayView[@sast.Node]) -> String? {
  match single_ident(args) {
    Some(n) => Some(@names.unkebab(n))
    None => literal_string(args)
  }
}

///|
/// The single number inside a call's arguments, with its source spelling.
fn single_number(args : ArrayView[@sast.Node]) -> @ast.Number? {
  match args {
    [{ it: Group([n]), .. }] => number_of(n)
    _ => None
  }
}

///|
/// A shrubbery literal as a CSS number, keeping how it was written.
///
/// A rational is deliberately NOT handled here: `1/2` lexes as one `Rat`
/// literal, and in CSS that is two numbers with a slash between them. It is
/// unfolded where values are lowered, so `1/2` and `1 / 2` produce the same
/// three components.
fn number_of(n : @sast.Node) -> @ast.Number? {
  match n.it {
    Lit(Int_(i)) => {
      let repr = i.to_string()
      Some({ repr, value: bigint_to_double(i), is_int: true, })
    }
    Lit(Flo(f)) =>
      Some({ repr: @swrite.double_to_string(f), value: f, is_int: false, })
    _ => None
  }
}

///|
fn bigint_to_double(i : @bigint.BigInt) -> Double {
  @string.parse_double(i.to_string()) catch {
    _ => 0.0
  }
}

///|
/// The groups inside a `Parens` or `Brackets`, as views.
fn arg_groups(args : ArrayView[@sast.Node]) -> Array[ArrayView[@sast.Node]] {
  let out : Array[ArrayView[@sast.Node]] = []
  for g in args {
    match g.it {
      Group(xs) => out.push(xs[:])
      _ => out.push(one(g))
    }
  }
  out
}

///|
/// A single node as a one-element view, for the case where a group's contents
/// arrive unwrapped.
fn one(n : @sast.Node) -> ArrayView[@sast.Node] {
  let a : Array[@sast.Node] = [n]
  a[:]
}

///|
/// The span covering a run of nodes, or a fallback when it is empty.
fn span_of(
  items : ArrayView[@sast.Node],
  fallback : @basic.Span,
) -> @basic.Span {
  if items.length() == 0 {
    fallback
  } else {
    items[0].span.merge(items[items.length() - 1].span)
  }
}
