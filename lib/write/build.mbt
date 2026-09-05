///|
/// The layout table for one kind of compound.
///
/// Fifteen fields, because the reference decides all of this in one `case` and
/// the decisions are not independent: whether a form may be written on one
/// line depends on whether it is at the tail of its group, which depends on
/// whether the enclosing form armours itself, and so on. Splitting them apart
/// would mean recomputing the same conditions in five places.
priv struct Shape {
  /// Whether the multi-line reading is indented from the current column rather
  /// than from the enclosing indentation.
  align : Bool
  /// Opener for the multi-line reading; a pair when a `'…'` may need `«»`.
  open : (String, String)
  /// Opener for the single-line reading.
  line_open : (String, String)
  /// Separator with no space, used at a line break.
  sep : String
  /// Separator between terms on one line.
  sep_space : String
  /// Separator before a block, which joins rather than separates.
  block_sep_space : String
  line_close : (String, String)
  /// `None` where the form has no closer at all.
  close : (String, String)?
  /// Whether the multi-line reading is still one line, with `;` separators.
  one_line_ish : Bool
  is_quotes : Bool
  /// What to pass to children as "not at the tail".
  use_non_tail : Bool
  /// Whether a child at the end of this form is at the tail of its group.
  can_tail : Bool
  /// Whether this form's own delimiters make its contents unambiguous, so a
  /// child does not need `«»`.
  wraps : Bool
  /// Whether the single-line reading is refused outright.
  no_line : Bool
  /// Whether the multi-line reading is used even when a single line would fit.
  multi_just_multi : Bool
}

///|
/// Build both readings of a term.
fn build(
  node : @ast.Node,
  target : Target,
  non_tail~ : Bool,
  head~ : Bool,
  before_block~ : Bool,
) -> Built {
  match node.it {
    Op(name) =>
      if before_block && all_colons(name) {
        twice(name + " ")
      } else {
        twice(name)
      }
    Id(_) | Kw(_) | Lit(_) | Parsed(_) => twice(atom_text(node.it))
    Alts(blocks) => build_alts(blocks, target, head~)
    Multi(groups) => build_multi(groups, target)
    _ => build_compound(node, target, non_tail~, head~)
  }
}

///|
fn build_compound(
  node : @ast.Node,
  target : Target,
  non_tail~ : Bool,
  head~ : Bool,
) -> Built {
  let children = node.children()
  let armor = target is ArmorDoc
  let prefer_multi = target is MultiDoc
  let mt = children.length() == 0
  let a_mt = armor || mt
  let a_nt = armor || (non_tail && !prefer_multi)
  let shape = match node.it {
    Group(_) =>
      (
        {
          align: true,
          open: ("", ""),
          line_open: ("", ""),
          sep: "",
          sep_space: " ",
          block_sep_space: "",
          line_close: ("", ""),
          close: Some(("", "")),
          one_line_ish: true,
          is_quotes: false,
          use_non_tail: true,
          can_tail: !non_tail,
          wraps: false,
          no_line: false,
          multi_just_multi: false,
        } : Shape)
    Block(_) =>
      {
        align: false,
        open: (if a_mt { ":«" } else { ":" }, if a_mt { ":«" } else { ":" }),
        line_open: (
          if mt {
            ":«"
          } else if a_nt {
            ":« "
          } else {
            ": "
          },
          if mt {
            ":«"
          } else if a_nt {
            ":« "
          } else {
            ": "
          },
        ),
        sep: if armor {
          ";"
        } else {
          ""
        },
        sep_space: "; ",
        block_sep_space: "; ",
        line_close: (
          if mt {
            "»"
          } else if a_nt {
            " »"
          } else {
            ""
          },
          if mt {
            "»"
          } else if a_nt {
            " »"
          } else {
            ""
          },
        ),
        close: if a_mt {
          Some(("»", "»"))
        } else {
          None
        },
        one_line_ish: false,
        is_quotes: false,
        use_non_tail: true,
        can_tail: true,
        wraps: false,
        no_line: prefer_multi && (a_mt || children.length() >= 2),
        // A block is always written multi-line in multi-line mode. It must be
        // inside a group, and that group's own `or` is what lets the whole
        // thing come back onto one line when it fits.
        multi_just_multi: true,
      }
    Parens(_) => bracket_shape("(", ")")
    Brackets(_) => bracket_shape("[", "]")
    Braces(_) => bracket_shape("{", "}")
    Quotes(_) =>
      {
        align: false,
        open: ("'«", "'"),
        line_open: ("'«", "'"),
        sep: if armor {
          ";"
        } else {
          ""
        },
        sep_space: "; ",
        block_sep_space: "; ",
        line_close: ("»'", "'"),
        close: Some(("»'", "'")),
        one_line_ish: false,
        is_quotes: true,
        use_non_tail: true,
        can_tail: true,
        wraps: true,
        no_line: prefer_multi && children.length() >= 2,
        multi_just_multi: false,
      }
    _ => bracket_shape("(", ")")
  }
  assemble(children, shape, target, head~)
}

///|
fn bracket_shape(open : String, close : String) -> Shape {
  {
    align: false,
    open: (open, open),
    line_open: (open, open),
    sep: ",",
    sep_space: ", ",
    block_sep_space: ", ",
    line_close: (close, close),
    close: Some((close, close)),
    one_line_ish: false,
    is_quotes: false,
    use_non_tail: false,
    can_tail: true,
    wraps: true,
    no_line: false,
    multi_just_multi: false,
  }
}

///|
/// The five readings of a compound's contents, assembled into the two the
/// caller sees.
fn assemble(
  children : Array[@ast.Node],
  shape : Shape,
  target : Target,
  head~ : Bool,
) -> Built {
  let armor = target is ArmorDoc
  let prefer_multi = target is MultiDoc
  // One line, with separators.
  let mut singles : Array[@doc.Doc]? = Some([])
  // Multi-line, but still one line: separators are `;` rather than breaks.
  let semis : Array[@doc.Doc] = []
  // Multi-line, indented one past the opener -- the reading a bracketed form
  // falls back to before it gives up on the line entirely.
  let line_multi : Array[@doc.Doc] = []
  // Multi-line, indented two from the enclosing form.
  let multi : Array[@doc.Doc] = []
  let mut inner_quotes = false
  for i in 0..<children.length() {
    let last = i == children.length() - 1
    let next_is_block = !last && children[i + 1].it is Block(_)
    let next_is_alts = !last && children[i + 1].it is Alts(_)
    let r = build(
      children[i],
      target,
      non_tail=if last { !shape.can_tail } else { shape.use_non_tail },
      head=shape.wraps || (i == 0 && head),
      before_block=!last && next_is_block,
    )
    if r.quotes {
      inner_quotes = true
    }
    match (singles, r.single) {
      (Some(acc), Some(s)) => {
        acc.push(s)
        if !last {
          acc.push(
            Str(
              if next_is_block {
                shape.block_sep_space
              } else {
                shape.sep_space
              },
            ),
          )
        }
      }
      _ => singles = None
    }
    semis.push(r.multi)
    if !last {
      semis.push(
        Str(
          if next_is_block || next_is_alts {
            shape.block_sep_space
          } else {
            shape.sep_space
          },
        ),
      )
    }
    if last {
      line_multi.push(
        if i == 0 {
          r.multi
        } else {
          Nest(1, Seq([Nl, r.multi]))
        },
      )
      multi.push(Nest(2, Seq([Nl, r.multi])))
    } else {
      line_multi.push(
        Nest(
          1,
          Seq([if i == 0 { @doc.empty } else { Nl }, r.multi, Str(shape.sep)]),
        ),
      )
      multi.push(Nest(2, Seq([Nl, r.multi, Str(shape.sep)])))
    }
  }
  let quotes = shape.is_quotes || (!shape.wraps && inner_quotes)
  // A `'…'` whose contents expose a `'` needs its guillemets; otherwise the
  // plain form reads the same and is shorter.
  let sel = (p : (String, String)) => if inner_quotes { p.0 } else { p.1 }
  let line_open = sel(shape.line_open)
  let line_close = sel(shape.line_close)
  let open = sel(shape.open)
  let close = shape.close.map(sel)
  let line : @doc.Doc? = match singles {
    Some(parts) => {
      let out : Array[@doc.Doc] = [Str(line_open)]
      for p in parts {
        out.push(p)
      }
      out.push(Str(line_close))
      Some(Seq(out))
    }
    None => None
  }
  if children.length() == 0 {
    return {
      single: line,
      multi: match line {
        Some(l) => l
        None => Seq([Str(line_open), Str(line_close)])
      },
      quotes,
      is_atom: shape.wraps,
    }
  }
  let mut body : @doc.Doc = if shape.one_line_ish {
    let out : Array[@doc.Doc] = [Str(line_open)]
    for p in semis {
      out.push(p)
    }
    out.push(Str(line_close))
    Seq(out)
  } else {
    let out : Array[@doc.Doc] = [Str(open)]
    for p in multi {
      out.push(p)
    }
    match close {
      Some(c) => {
        out.push(Nl)
        out.push(Str(c))
      }
      None => ()
    }
    Seq(out)
  }
  if shape.align {
    body = Align(body)
  }
  if prefer_multi && shape.wraps {
    let out : Array[@doc.Doc] = [Str(line_open)]
    for p in line_multi {
      out.push(p)
    }
    out.push(Str(line_close))
    body = Or(body, Align(Seq(out)))
  }
  match line {
    Some(l) =>
      if !shape.no_line &&
        !shape.multi_just_multi &&
        (shape.wraps || shape.one_line_ish || multi.length() == 1) {
        body = Or(l, body)
      }
    None => ()
  }
  ignore(armor)
  {
    single: if shape.no_line {
      None
    } else {
      line
    },
    multi: body,
    quotes,
    is_atom: shape.wraps,
  }
}
