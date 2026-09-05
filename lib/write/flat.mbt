///|
/// Write a shrubbery on one line, with `«»`, `;` and `,` doing all the
/// grouping.
///
/// This is the reading that does not care where it ends up: no line break and
/// no column carries meaning, so re-indenting the result, or wrapping it, or
/// pasting it into a file with a different indentation cannot change what it
/// says. That is why it is the default for writing a shrubbery down to be read
/// back later.
fn write_flat(
  node : @ast.Node,
  buf : StringBuilder,
  before_block~ : Bool,
) -> Unit {
  match node.it {
    Op(name) =>
      // An operator made only of colons, written just before a block, would
      // run into the block's own `:`.
      if before_block && all_colons(name) {
        buf.write_string(name)
        buf.write_char(' ')
      } else {
        buf.write_string(name)
      }
    Id(_) | Kw(_) | Lit(_) | Parsed(_) => buf.write_string(atom_text(node.it))
    Alts(blocks) => {
      let mut first = true
      for b in blocks {
        if !first {
          buf.write_char(' ')
        }
        first = false
        buf.write_string("|« ")
        let groups = b.children()
        for i in 0..<groups.length() {
          if i > 0 {
            buf.write_string("; ")
          }
          write_flat(groups[i], buf, before_block=false)
        }
        buf.write_string(" »")
      }
    }
    Multi(groups) =>
      for i in 0..<groups.length() {
        if i > 0 {
          buf.write_string("; ")
        }
        write_flat(groups[i], buf, before_block=false)
      }
    _ => write_flat_compound(node, buf)
  }
}

///|
fn write_flat_compound(node : @ast.Node, buf : StringBuilder) -> Unit {
  let children = node.children()
  let (open, close, sep) = match node.it {
    Group(_) => ("", "", " ")
    Block(_) =>
      (
        if children.length() == 0 {
          ":«"
        } else {
          ":« "
        },
        if children.length() == 0 {
          "»"
        } else {
          " »"
        },
        "; ",
      )
    Parens(_) => ("(", ")", ", ")
    Brackets(_) => ("[", "]", ", ")
    Braces(_) => ("{", "}", ", ")
    Quotes(_) => ("'«", "»'", "; ")
    _ => ("", "", " ")
  }
  buf.write_string(open)
  for i in 0..<children.length() {
    let child = children[i]
    let next_is_block = i + 1 < children.length() &&
      children[i + 1].it is Block(_)
    // A block joins what precedes it without a separator -- it is part of the
    // same group, and its own `:` is the join. A sequence of alternatives does
    // NOT: `a |« b »` needs the space.
    if i > 0 && !(child.it is Block(_)) {
      buf.write_string(sep)
    }
    write_flat(child, buf, before_block=next_is_block)
  }
  buf.write_string(close)
}

///|
fn all_colons(name : String) -> Bool {
  if name.length() == 0 {
    return false
  }
  for c in name {
    if c != ':' {
      return false
    }
  }
  true
}
