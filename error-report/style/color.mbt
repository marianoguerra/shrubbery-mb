///|
/// When to emit ANSI escapes.
///
/// `Auto` is resolved by the CALLER, not here: this library cannot see a file
/// descriptor without a dependency, and guessing wrong either strips colour
/// from a terminal or writes escapes into a file. `Config::resolve_color` takes
/// the answer as a parameter for exactly that reason.
pub(all) enum ColorMode {
  Always
  Never
  Auto
} derive(Eq, Debug)

///|
/// The eight ANSI colours plus "leave it alone".
pub(all) enum Color {
  Default
  Black
  Red
  Green
  Yellow
  Blue
  Magenta
  Cyan
  White
} derive(Eq, Debug)

///|
pub(all) struct Style {
  color : Color
  bold : Bool
  dim : Bool
} derive(Eq, Debug)

///|
pub let plain : Style = { color: Default, bold: false, dim: false, }

///|
pub fn Style::of(
  color : Color,
  bold? : Bool = false,
  dim? : Bool = false,
) -> Style {
  { color, bold, dim, }
}

///|
fn Color::sgr(self : Color) -> String {
  match self {
    Default => ""
    Black => "30"
    Red => "31"
    Green => "32"
    Yellow => "33"
    Blue => "34"
    Magenta => "35"
    Cyan => "36"
    White => "37"
  }
}

///|
/// Whether this style would emit anything at all.
pub fn Style::is_plain(self : Style) -> Bool {
  self.color is Default && !self.bold && !self.dim
}

///|
/// Write `text` wrapped in this style's escapes, or bare when `color` is off.
///
/// Takes a sink rather than returning a String because a renderer writes
/// thousands of these and every one of them would otherwise be an allocation
/// that is immediately appended and dropped.
pub fn Style::write(
  self : Style,
  buf : StringBuilder,
  text : String,
  color~ : Bool,
) -> Unit {
  if !color || self.is_plain() {
    buf.write_string(text)
    return
  }
  buf.write_string("\u{1b}[")
  let mut first = true
  if self.bold {
    buf.write_string("1")
    first = false
  }
  if self.dim {
    if !first {
      buf.write_string(";")
    }
    buf.write_string("2")
    first = false
  }
  let c = self.color.sgr()
  if c != "" {
    if !first {
      buf.write_string(";")
    }
    buf.write_string(c)
  }
  buf.write_string("m")
  buf.write_string(text)
  buf.write_string("\u{1b}[0m")
}

///|
/// Which style each part of a report is drawn in.
pub(all) struct Theme {
  error : Style
  warning : Style
  advice : Style
  code : Style
  message : Style
  primary : Style
  secondary : Style
  gutter : Style
  source : Style
  help : Style
  note : Style
  url : Style
}

///|
/// The default theme: severity in bold colour, the frame dimmed, labels
/// coloured to match their severity so a primary underline reads as part of the
/// same message as the header.
pub let default_theme : Theme = {
  error: Style::of(Red, bold=true),
  warning: Style::of(Yellow, bold=true),
  advice: Style::of(Cyan, bold=true),
  code: Style::of(Default, dim=true),
  message: Style::of(Default, bold=true),
  primary: Style::of(Red),
  secondary: Style::of(Blue),
  gutter: Style::of(Blue, dim=true),
  source: plain,
  help: Style::of(Green),
  note: Style::of(Default, dim=true),
  url: Style::of(Cyan),
}

///|
/// Every part plain. Not the same as `color: Never` -- this is for a caller who
/// wants colour available but has chosen a monochrome look.
pub let mono_theme : Theme = {
  error: plain,
  warning: plain,
  advice: plain,
  code: plain,
  message: plain,
  primary: plain,
  secondary: plain,
  gutter: plain,
  source: plain,
  help: plain,
  note: plain,
  url: plain,
}
