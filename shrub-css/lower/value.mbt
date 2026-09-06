///|
/// Declaration values.
///
/// A value is the one group inside a declaration's block. Most of it lowers one
/// node at a time; the interesting cases are the calls that are not CSS
/// functions -- units, `percent`, `hex`, `important` -- and the rational
/// literal, which the shrubbery lexer produces for `1/2` and CSS reads as three
/// things.

///|
/// A value group, and whether `important()` was in it.
fn Lowerer::value_of(
  self : Lowerer,
  g : @sast.Node,
) -> (Array[@ast.ComponentValue], Bool) raise @err.ShrubCssError {
  let items = match g.it {
    Group(xs) => xs[:]
    _ => return ([], false)
  }
  self.values(items)
}

///|
fn Lowerer::values(
  self : Lowerer,
  items : ArrayView[@sast.Node],
) -> (Array[@ast.ComponentValue], Bool) raise @err.ShrubCssError {
  let out : Array[@ast.ComponentValue] = []
  let mut important = false
  let mut i = 0
  while i < items.length() {
    let rest = items[i:]
    // `--brand` in value position is a dashed identifier, which is what
    // `var(--brand)` wants.
    match
      as_dashed(rest[0:if rest.length() >= 2 { 2 } else { rest.length() }]) {
      Some(name) => {
        out.push(Ident(name))
        i = i + 2
        continue
      }
      None => ()
    }
    match as_call(rest) {
      Some((name, args, _)) => {
        match self.value_call(name, args, items[i]) {
          Call(v) => out.push(v)
          Important => important = true
        }
        i = i + 2
        continue
      }
      None => ()
    }
    let n = items[i]
    match n.it {
      Id(name) => out.push(Ident(@names.unkebab(name)))
      Lit(Str(s)) => out.push(Str(s))
      Lit(Int_(_)) | Lit(Flo(_)) =>
        match number_of(n) {
          Some(num) => out.push(Num(num))
          None => out.push(Bogus(self.bogus(BadSelector, n)))
        }
      // `1/2` is one rational literal to the lexer and three things to CSS.
      // Unfolding it here is what makes `1/2` and `1 / 2` agree.
      Lit(Rat(a, b)) => {
        out.push(
          Num({ repr: a.to_string(), value: bigint_to_double(a), is_int: true, }),
        )
        out.push(Slash)
        out.push(
          Num({ repr: b.to_string(), value: bigint_to_double(b), is_int: true, }),
        )
      }
      Op("/") => out.push(Slash)
      Op(o) => out.push(Delim(o))
      Parens(gs) => out.push(Paren(self.comma_list(gs[:])))
      // A bracket is CSS's comma-separated value list, which has no brackets
      // of its own -- so it is spliced in. CSS's own `[...]` is written
      // `bracket(...)`, because the two cannot share a spelling: a comma may
      // only appear inside a bracket, so the bracket has to mean the list.
      Brackets(gs) =>
        for v in self.comma_list(gs[:]) {
          out.push(v)
        }
      Block(_) => out.push(Bogus(self.bogus(SemicolonDeclarations, n)))
      Braces(_) => out.push(Bogus(self.bogus(BracesUnsupported, n)))
      Quotes(_) => out.push(Bogus(self.bogus(QuotesUnsupported, n)))
      Kw(k) => out.push(Bogus(self.bogus(StrayKeyword(k), n)))
      _ => out.push(Bogus(self.bogus(BadSelector, n)))
    }
    i = i + 1
  }
  (out, important)
}

///|
/// What a call in value position turned out to be.
priv enum CallResult {
  Call(@ast.ComponentValue)
  /// `important()` is not a value at all: it sets a flag on the declaration.
  Important
}

///|
/// A call in value position.
///
/// The order matters. A unit is checked before an ordinary function, but only
/// when its arguments are exactly one number -- so `s(0.2)` is two tenths of a
/// second while a hypothetical `s(a, b)` stays a function call. That guard is
/// what keeps short unit names from swallowing the function namespace.
fn Lowerer::value_call(
  self : Lowerer,
  name : String,
  args : ArrayView[@sast.Node],
  at : @sast.Node,
) -> CallResult raise @err.ShrubCssError {
  match name {
    "important" => if args.length() == 0 { return Important }
    "percent" =>
      match single_number(args) {
        Some(n) => return Call(Percentage(n))
        None => ()
      }
    "hex" => return Call(self.hex_of(args, at))
    "url" =>
      match literal_string(args) {
        Some(s) => return Call(Url(s))
        None => ()
      }
    "ident" =>
      match literal_string(args) {
        Some(s) => return Call(Ident(s))
        None => ()
      }
    "dim" => return Call(self.dim_of(args, at))
    "delim" =>
      match literal_string(args) {
        Some(s) => return Call(Delim(s))
        None => ()
      }
    "bracket" => return Call(Bracket(self.comma_list(args)))
    _ => ()
  }
  // A unit, if the name is one and the argument is a single number.
  match @names.unit_of(name) {
    Some(unit) =>
      match single_number(args) {
        Some(n) => return Call(Dimension(n, unit))
        None => ()
      }
    None => ()
  }
  Call(Function(@names.unkebab(name), self.comma_list(args)))
}

///|
/// `hex(f7f7f7)` and `hex("007700")`.
///
/// The string form is not a stylistic alternative -- it is required whenever
/// the digits start with a `0`, because by the time this layer runs the lexer
/// has already read `007700` as the integer 7700 and the zeros are gone. There
/// is no way to recover them, so this refuses rather than guessing, and the
/// diagnostic names the fix.
fn Lowerer::hex_of(
  self : Lowerer,
  args : ArrayView[@sast.Node],
  at : @sast.Node,
) -> @ast.ComponentValue raise @err.ShrubCssError {
  match literal_string(args) {
    Some(s) => return Hex(s)
    None => ()
  }
  match single_ident(args) {
    Some(n) => return Hex(n)
    None => ()
  }
  match single_number(args) {
    Some(n) =>
      if is_hex_length(n.repr.length()) {
        Hex(n.repr)
      } else {
        Bogus(self.bogus(HexDigitsLost, at))
      }
    None => Bogus(self.bogus(BadCallShape("hex"), at))
  }
}

///|
/// The digit counts CSS admits: `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`.
fn is_hex_length(n : Int) -> Bool {
  n == 3 || n == 4 || n == 6 || n == 8
}

///|
/// `dim(10, "newunit")`: the escape for a unit this library does not know.
fn Lowerer::dim_of(
  self : Lowerer,
  args : ArrayView[@sast.Node],
  at : @sast.Node,
) -> @ast.ComponentValue raise @err.ShrubCssError {
  let gs = arg_groups(args)
  if gs.length() == 2 {
    match (gs[0], gs[1]) {
      ([n], [{ it: Lit(Str(u)), .. }]) =>
        match number_of(n) {
          Some(num) => return Dimension(num, u)
          None => ()
        }
      _ => ()
    }
  }
  Bogus(self.bogus(BadCallShape("dim"), at))
}

///|
/// A call's or bracket's arguments, with commas put back between the groups.
///
/// Shrubbery turns `a, b` inside brackets into two groups, so the comma is
/// structural there and absent from the tree. CSS wants it as a component
/// value, since a comma means different things in different properties and the
/// generic value model does not interpret it.
fn Lowerer::comma_list(
  self : Lowerer,
  args : ArrayView[@sast.Node],
) -> Array[@ast.ComponentValue] raise @err.ShrubCssError {
  let out : Array[@ast.ComponentValue] = []
  let mut first = true
  for g in args {
    if !first {
      out.push(Comma)
    }
    first = false
    let items = match g.it {
      Group(xs) => xs[:]
      _ => one(g)
    }
    let (vs, _) = self.values(items)
    for v in vs {
      out.push(v)
    }
  }
  out
}
