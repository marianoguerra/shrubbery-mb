///|
/// Typed readings of an untyped tree.
///
/// The AST stores every declaration value as a generic component-value list.
/// That is what makes coverage total -- a vendor hack, a property added last
/// month and a value behind a flag all parse -- and it is also why asking "what
/// length is this" needs somewhere to live.
///
/// Here. Every function in this package is a **lens**: a pure function from a
/// `ComponentValue` to an optional typed reading, computed on demand and stored
/// nowhere. That is deliberately the opposite of lightningcss, which types five
/// hundred properties in the tree itself and therefore cannot represent what its
/// tables do not know. biome takes this approach too, layering `value_ext.rs`
/// over its untyped tree, and it is the one that keeps the two questions apart:
/// the parser decides what the text SAYS, and a lens decides what it MEANS.
///
/// Nothing here can fail loudly. A lens returns `None` when the value is not
/// the thing asked about, which is an answer rather than an error -- `as_length`
/// on the identifier `auto` is a perfectly ordinary question with a perfectly
/// ordinary negative answer.

// ------------------------------------------------------------------- numbers

///|
/// The number a value is, if it is one.
///
/// A percentage is deliberately NOT a number: `50%` and `50` mean different
/// things everywhere in CSS, and folding them here would make every caller
/// re-check which it had.
pub fn as_number(v : @ast.ComponentValue) -> Double? {
  match v {
    Num(n) => Some(n.value)
    _ => None
  }
}

///|
/// The integer a value is, if it is exactly one.
///
/// `is_int` rather than a floor: `2.0` is written as a number with a fractional
/// part, and a grammar asking for an integer should not silently accept it.
pub fn as_integer(v : @ast.ComponentValue) -> Int? {
  match v {
    Num(n) => if n.is_int { Some(n.value.to_int()) } else { None }
    _ => None
  }
}

///|
/// The percentage a value is, as its face value: `50%` gives 50, not 0.5.
///
/// Face value because that is what the source said, and a caller dividing by a
/// hundred is doing so for a reason this package cannot know.
pub fn as_percentage(v : @ast.ComponentValue) -> Double? {
  match v {
    Percentage(n) => Some(n.value)
    _ => None
  }
}

// ---------------------------------------------------------------- dimensions

///|
/// What kind of quantity a unit measures.
///
/// The grouping is the one CSS's own grammars use: a property takes a length,
/// or an angle, or a time -- never "a dimension".
pub(all) enum UnitKind {
  Length
  Angle
  Time
  Frequency
  Resolution
  Flex
  /// A unit no table here knows. Kept as a kind rather than a failure, because
  /// CSS gains units and a lens that refused an unknown one would be wrong
  /// every time it did.
  Unknown
} derive(Eq, Debug)

///|
/// A dimension: a number and the unit it was written with.
pub(all) struct Dimension {
  value : Double
  unit : String
  kind : UnitKind
} derive(Eq, Debug)

///|
/// The dimension a value is, if it is one.
pub fn as_dimension(v : @ast.ComponentValue) -> Dimension? {
  match v {
    Dimension(n, u) => Some({ value: n.value, unit: u, kind: unit_kind(u), })
    _ => None
  }
}

///|
/// The length a value is.
///
/// A bare `0` counts: CSS lets a zero length omit its unit, and a caller
/// asking for a length would otherwise have to special-case the one number that
/// is always allowed.
pub fn as_length(v : @ast.ComponentValue) -> Dimension? {
  match v {
    Dimension(n, u) =>
      if unit_kind(u) is Length {
        Some({ value: n.value, unit: u, kind: Length, })
      } else {
        None
      }
    Num(n) =>
      if n.value == 0.0 {
        Some({ value: 0.0, unit: "px", kind: Length, })
      } else {
        None
      }
    _ => None
  }
}

///|
pub fn as_angle(v : @ast.ComponentValue) -> Dimension? {
  as_dimension_of(v, Angle)
}

///|
pub fn as_time(v : @ast.ComponentValue) -> Dimension? {
  as_dimension_of(v, Time)
}

///|
pub fn as_resolution(v : @ast.ComponentValue) -> Dimension? {
  as_dimension_of(v, Resolution)
}

///|
fn as_dimension_of(v : @ast.ComponentValue, want : UnitKind) -> Dimension? {
  match as_dimension(v) {
    Some(d) => if d.kind == want { Some(d) } else { None }
    None => None
  }
}

///|
/// What a unit measures. Case-insensitive, as CSS units are.
pub fn unit_kind(unit : String) -> UnitKind {
  match unit.to_lower() {
    "px" | "cm" | "mm" | "q" | "in" | "pt" | "pc" => Length
    "em" | "rem" | "ex" | "rex" | "cap" | "rcap" => Length
    "ch" | "rch" | "ic" | "ric" | "lh" | "rlh" => Length
    "vw" | "vh" | "vi" | "vb" | "vmin" | "vmax" => Length
    "svw" | "svh" | "svi" | "svb" | "svmin" | "svmax" => Length
    "lvw" | "lvh" | "lvi" | "lvb" | "lvmin" | "lvmax" => Length
    "dvw" | "dvh" | "dvi" | "dvb" | "dvmin" | "dvmax" => Length
    "cqw" | "cqh" | "cqi" | "cqb" | "cqmin" | "cqmax" => Length
    "deg" | "grad" | "rad" | "turn" => Angle
    "s" | "ms" => Time
    "hz" | "khz" => Frequency
    "dpi" | "dpcm" | "dppx" | "x" => Resolution
    "fr" => Flex
    _ => Unknown
  }
}

// -------------------------------------------------------------------- colours

///|
/// A colour, as far as the syntax can say.
///
/// Syntactic rather than numeric, and that is the point. lightningcss quantises
/// every colour to `RGBA{u8,u8,u8,u8}`, which is right for a minifier and makes
/// `#fff`, `#ffffff` and `white` the same value -- so a formatter built on it
/// cannot give a stylesheet back the way it arrived. `to_rgba` below is
/// available for a caller that wants the numbers; the tree keeps the text.
pub(all) enum Color {
  /// `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, digits as written.
  Hex(String)
  /// A named colour, `transparent`, or `currentColor`.
  Named(String)
  /// `rgb(...)`, `oklch(...)`, `color-mix(...)` -- the function and its
  /// arguments, uninterpreted.
  Function(String, Array[@ast.ComponentValue])
} derive(Eq, Debug)

///|
/// The colour a value is, if it looks like one.
///
/// "Looks like" is honest about the limit: this cannot know whether a caller's
/// property takes a colour, only whether the value could be one. An identifier
/// is a colour if it is a known name, because `red` is and `auto` is not.
pub fn as_color(v : @ast.ComponentValue) -> Color? {
  match v {
    Hex(d) => if is_hex_digits(d) { Some(Hex(d)) } else { None }
    Ident(name) =>
      if is_color_name(name.to_lower()) {
        Some(Named(name))
      } else {
        None
      }
    Function(f, args) =>
      if is_color_function(f.to_lower()) {
        Some(Function(f, args))
      } else {
        None
      }
    _ => None
  }
}

///|
/// A hex colour as its channels, if it is one this can resolve.
///
/// Only the hex form: resolving `oklch()` means implementing a colour space,
/// and resolving `red` means carrying the named-colour table's values. Both are
/// real work with real answers, and neither belongs behind a function that
/// looks this cheap.
pub fn to_rgba(c : Color) -> (Int, Int, Int, Int)? {
  match c {
    Hex(d) => {
      let n = d.length()
      if n == 3 || n == 4 {
        let r = hex1(d, 0)
        let g = hex1(d, 1)
        let b = hex1(d, 2)
        let a = if n == 4 { hex1(d, 3) } else { Some(15) }
        match (r, g, b, a) {
          (Some(r), Some(g), Some(b), Some(a)) =>
            Some((r * 17, g * 17, b * 17, a * 17))
          _ => None
        }
      } else if n == 6 || n == 8 {
        let r = hex2(d, 0)
        let g = hex2(d, 2)
        let b = hex2(d, 4)
        let a = if n == 8 { hex2(d, 6) } else { Some(255) }
        match (r, g, b, a) {
          (Some(r), Some(g), Some(b), Some(a)) => Some((r, g, b, a))
          _ => None
        }
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn hex1(s : String, i : Int) -> Int? {
  hex_value(s.unsafe_get(i).to_int().unsafe_to_char())
}

///|
fn hex2(s : String, i : Int) -> Int? {
  match (hex1(s, i), hex1(s, i + 1)) {
    (Some(a), Some(b)) => Some(a * 16 + b)
    _ => None
  }
}

///|
fn hex_value(c : Char) -> Int? {
  if c >= '0' && c <= '9' {
    Some(c.to_int() - 48)
  } else if c >= 'a' && c <= 'f' {
    Some(c.to_int() - 87)
  } else if c >= 'A' && c <= 'F' {
    Some(c.to_int() - 55)
  } else {
    None
  }
}

///|
fn is_hex_digits(d : String) -> Bool {
  let n = d.length()
  if !(n == 3 || n == 4 || n == 6 || n == 8) {
    return false
  }
  for c in d {
    if hex_value(c) is None {
      return false
    }
  }
  true
}

///|
/// The colour-valued functions. Names only: what they mean is a colour-space
/// question, and this package answers syntax questions.
fn is_color_function(f : String) -> Bool {
  match f {
    "rgb" | "rgba" | "hsl" | "hsla" | "hwb" => true
    "lab" | "lch" | "oklab" | "oklch" | "color" => true
    "color-mix" | "light-dark" | "device-cmyk" | "contrast-color" => true
    _ => false
  }
}

///|
/// Whether an identifier names a colour.
///
/// The CSS named colours, plus the three keywords that behave like one. Kept
/// as a list rather than derived, because there is no rule -- it is a list in
/// the specification too.
fn is_color_name(name : String) -> Bool {
  match name {
    "currentcolor" | "transparent" | "inherit" => true
    "black" | "silver" | "gray" | "grey" | "white" | "maroon" | "red" => true
    "purple" | "fuchsia" | "magenta" | "green" | "lime" | "olive" => true
    "yellow" | "navy" | "blue" | "teal" | "aqua" | "cyan" | "orange" => true
    "aliceblue" | "antiquewhite" | "aquamarine" | "azure" | "beige" => true
    "bisque" | "blanchedalmond" | "blueviolet" | "brown" | "burlywood" => true
    "cadetblue" | "chartreuse" | "chocolate" | "coral" | "cornflowerblue" =>
      true
    "cornsilk" | "crimson" | "darkblue" | "darkcyan" | "darkgoldenrod" => true
    "darkgray" | "darkgrey" | "darkgreen" | "darkkhaki" | "darkmagenta" => true
    "darkolivegreen" | "darkorange" | "darkorchid" | "darkred" => true
    "darksalmon" | "darkseagreen" | "darkslateblue" | "darkslategray" => true
    "darkslategrey" | "darkturquoise" | "darkviolet" | "deeppink" => true
    "deepskyblue" | "dimgray" | "dimgrey" | "dodgerblue" | "firebrick" => true
    "floralwhite" | "forestgreen" | "gainsboro" | "ghostwhite" | "gold" => true
    "goldenrod" | "greenyellow" | "honeydew" | "hotpink" | "indianred" => true
    "indigo" | "ivory" | "khaki" | "lavender" | "lavenderblush" => true
    "lawngreen" | "lemonchiffon" | "lightblue" | "lightcoral" => true
    "lightcyan" | "lightgoldenrodyellow" | "lightgray" | "lightgrey" => true
    "lightgreen" | "lightpink" | "lightsalmon" | "lightseagreen" => true
    "lightskyblue" | "lightslategray" | "lightslategrey" => true
    "lightsteelblue" | "lightyellow" | "limegreen" | "linen" => true
    "mediumaquamarine" | "mediumblue" | "mediumorchid" | "mediumpurple" => true
    "mediumseagreen" | "mediumslateblue" | "mediumspringgreen" => true
    "mediumturquoise" | "mediumvioletred" | "midnightblue" | "mintcream" => true
    "mistyrose" | "moccasin" | "navajowhite" | "oldlace" | "olivedrab" => true
    "orangered" | "orchid" | "palegoldenrod" | "palegreen" => true
    "paleturquoise" | "palevioletred" | "papayawhip" | "peachpuff" => true
    "peru" | "pink" | "plum" | "powderblue" | "rebeccapurple" => true
    "rosybrown" | "royalblue" | "saddlebrown" | "salmon" | "sandybrown" => true
    "seagreen" | "seashell" | "sienna" | "skyblue" | "slateblue" => true
    "slategray" | "slategrey" | "snow" | "springgreen" | "steelblue" => true
    "tan" | "thistle" | "tomato" | "turquoise" | "violet" | "wheat" => true
    "whitesmoke" | "yellowgreen" => true
    _ => false
  }
}

// ------------------------------------------------------------------ functions

///|
/// The arguments of a function call by this name, if that is what this is.
///
/// Case-insensitive, because CSS function names are.
pub fn as_function(
  v : @ast.ComponentValue,
  name : String,
) -> Array[@ast.ComponentValue]? {
  match v {
    Function(f, args) =>
      if f.to_lower() == name.to_lower() {
        Some(args)
      } else {
        None
      }
    _ => None
  }
}

///|
/// The custom property a `var()` reads, and its fallback.
pub fn as_var(v : @ast.ComponentValue) -> (String, Array[@ast.ComponentValue])? {
  match as_function(v, "var") {
    None => None
    Some(args) =>
      match args {
        [Ident(name), ..] =>
          if name.has_prefix("--") {
            let fallback : Array[@ast.ComponentValue] = []
            let mut seen_comma = false
            for a in args {
              if seen_comma {
                fallback.push(a)
              } else if a is Comma {
                seen_comma = true
              }
            }
            Some((name, fallback))
          } else {
            None
          }
        _ => None
      }
  }
}

///|
/// The url a value names, quoted or not -- both are the same node.
pub fn as_url(v : @ast.ComponentValue) -> String? {
  match v {
    Url(u) => Some(u)
    _ => None
  }
}

///|
/// The keyword a value is, lower-cased, if it is one of `allowed`.
///
/// The membership test is the caller's list, because "is this a keyword" has no
/// answer without knowing which property is being read.
pub fn as_keyword(v : @ast.ComponentValue, allowed : Array[String]) -> String? {
  match v {
    Ident(name) => {
      let lower = name.to_lower()
      for a in allowed {
        if a == lower {
          return Some(lower)
        }
      }
      None
    }
    _ => None
  }
}
