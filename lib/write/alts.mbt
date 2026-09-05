///|
/// A sequence of `|` alternatives.
fn build_alts(
  blocks : Array[@ast.Node],
  target : Target,
  head~ : Bool,
) -> Built {
  let armor = target is ArmorDoc
  let prefer_multi = target is MultiDoc
  let mut singles : Array[@doc.Doc]? = Some([])
  let multis : Array[@doc.Doc] = []
  let mut any_quotes = false
  for block in blocks {
    let groups = block.children()
    let mut sub_singles : Array[@doc.Doc]? = Some([])
    let sub_multis : Array[@doc.Doc] = []
    let mut all_atoms = true
    let mut one_atom = false
    for i in 0..<groups.length() {
      let r = build(
        groups[i],
        target,
        non_tail=false,
        head=false,
        before_block=false,
      )
      if r.quotes {
        any_quotes = true
      }
      if !r.is_atom {
        all_atoms = false
      }
      if i == 0 {
        one_atom = r.is_atom
      }
      match (sub_singles, r.single) {
        (Some(acc), Some(s)) => acc.push(s)
        _ => sub_singles = None
      }
      sub_multis.push(r.multi)
    }
    if groups.length() == 0 {
      // An alternative with nothing in it can only be written with `«»`.
      match singles {
        Some(acc) => acc.push(Str("|«»"))
        None => ()
      }
      multis.push(Str("|«»"))
      continue
    }
    // Single line: `| a; b`, or `|« a; b »` when a piece is not self-delimiting
    // and could otherwise run into what follows.
    let single = match sub_singles {
      Some(parts) if !prefer_multi || (parts.length() == 1 && one_atom) => {
        let line = @doc.join(parts, Str("; "))
        Some(
          if all_atoms {
            @doc.Doc::Seq([Str("| "), line])
          } else {
            Seq([Str("|« "), line, Str(" »")])
          },
        )
      }
      _ => None
    }
    match (singles, single) {
      (Some(acc), Some(s)) => acc.push(s)
      _ => singles = None
    }
    if prefer_multi {
      let stacked : @doc.Doc = Seq([Str("| "), Align(@doc.join(sub_multis, Nl))])
      multis.push(
        match (sub_singles, sub_multis.length()) {
          (Some(parts), 1) if one_atom =>
            Or(Seq([Str("| "), parts[0]]), stacked)
          _ => stacked
        },
      )
    } else {
      // The `|` itself is added by the caller, which is what lets the armoured
      // and plain forms differ only in their separator.
      multis.push(
        Nest(
          2,
          Seq([
            Nl,
            @doc.join(sub_multis, if armor { Seq([Str(";"), Nl]) } else { Nl }),
          ]),
        ),
      )
    }
  }
  let single : @doc.Doc? = if prefer_multi {
    None
  } else {
    match singles {
      Some(parts) => Some(@doc.join(parts, Str(" ")))
      None => None
    }
  }
  let multi : @doc.Doc = if prefer_multi {
    Seq([if head { @doc.empty } else { Nl }, Align(@doc.join(multis, Nl))])
  } else {
    Seq([
      Nl,
      Align(
        if armor {
          let out : Array[@doc.Doc] = [Str("|«")]
          for i in 0..<multis.length() {
            if i > 0 {
              out.push(Seq([Nl, Str("»"), Nl, Str("|«")]))
            }
            out.push(multis[i])
          }
          out.push(Nl)
          out.push(Str("»"))
          Seq(out)
        } else {
          let out : Array[@doc.Doc] = [Str("|")]
          for i in 0..<multis.length() {
            if i > 0 {
              out.push(Seq([Nl, Nl, Str("|")]))
            }
            out.push(multis[i])
          }
          Seq(out)
        },
      ),
    ])
  }
  { single, multi, quotes: any_quotes, is_atom: false, }
}

///|
/// A whole document: a sequence of groups.
fn build_multi(groups : Array[@ast.Node], target : Target) -> Built {
  let armor = target is ArmorDoc
  let prefer_multi = target is MultiDoc
  let mut singles : Array[@doc.Doc]? = Some([])
  let multis : Array[@doc.Doc] = []
  let mut any_quotes = false
  for i in 0..<groups.length() {
    let r = build(
      groups[i],
      target,
      // Every group but the last is followed by something, so an unarmoured
      // single-line block inside it still needs its `«»`.
      non_tail=i != groups.length() - 1,
      head=false,
      before_block=false,
    )
    if r.quotes {
      any_quotes = true
    }
    match (singles, r.single) {
      (Some(acc), Some(s)) => acc.push(s)
      _ => singles = None
    }
    multis.push(r.multi)
  }
  let single : @doc.Doc? = match singles {
    Some(parts) =>
      if !prefer_multi || parts.length() <= 1 {
        Some(@doc.join(parts, Str("; ")))
      } else {
        None
      }
    None => None
  }
  let multi : @doc.Doc = if armor {
    Seq([
      Str(";«"),
      Nest(2, Seq([Nl, @doc.join(multis, Seq([Str(";"), Nl]))])),
      Nl,
      Str("»"),
    ])
  } else {
    @doc.join(multis, Nl)
  }
  { single, multi, quotes: any_quotes, is_atom: false, }
}
