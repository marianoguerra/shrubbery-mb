///|
/// Which emitter to use.
///
/// `Rich` is for a person reading a terminal; `Short` is for a machine reading
/// lines, and for `grep`; `Compact` is `Rich` without the source snippet, for
/// when the source is not available or a hundred reports are being listed;
/// `Json` is for a tool.
pub(all) enum Format {
  Rich
  Compact
  Short
  Json
} derive(Eq, Debug)

///|
pub(all) struct Config {
  format : Format
  chars : @style.CharSet
  theme : @style.Theme
  color : @style.ColorMode
  /// Columns a tab advances to. 8 unless the consumer knows better; a tab in a
  /// source line is expanded to spaces before rendering, because a caret cannot
  /// be positioned under a character whose width depends on the terminal.
  tab_width : Int
  /// Source lines to show either side of a labelled line.
  context_lines : Int
}

///|
pub let default_config : Config = {
  format: Rich,
  chars: @style.unicode_chars,
  theme: @style.default_theme,
  color: Auto,
  tab_width: 8,
  context_lines: 1,
}

///|
/// Resolve `Auto` against what only the caller can know.
///
/// This library never touches a file descriptor -- it has no dependency that
/// would let it -- so `is_tty` is a parameter. Guessing here would either strip
/// colour from a terminal or write escape codes into a redirected file, and
/// both are worse than asking.
pub fn Config::use_color(self : Config, is_tty~ : Bool) -> Bool {
  match self.color {
    Always => true
    Never => false
    Auto => is_tty
  }
}
