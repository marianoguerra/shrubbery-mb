///|
/// The library façade.
///
/// One import for the common path. A façade re-exports no TYPES -- a package is
/// the unit of naming in MoonBit -- so a consumer that names an `@ast.Stylesheet`
/// imports `marianoguerra/css/ast` as well. What this package saves is having
/// to know which of `parse`, `write` and `error` a given verb lives in.

///|
/// Parse CSS text.
///
/// Tolerant: malformed input produces `Bogus` nodes and diagnostics rather than
/// a failure, so this returns a stylesheet for any input at all. Pass
/// `strict=true` to have the first error raised instead.
pub fn parse(
  src : String,
  strict? : Bool = false,
) -> @parse.Parsed raise @error.CssError {
  @parse.parse(src, strict~)
}

///|
/// Parse CSS text, raising on the first error.
pub fn parse_strict(src : String) -> @ast.Stylesheet raise @error.CssError {
  @parse.parse_strict(src)
}

///|
/// Print a stylesheet as CSS.
pub fn to_css(
  sheet : @ast.Stylesheet,
  style? : @write.Style = Pretty,
) -> String {
  @write.stylesheet(sheet, style~)
}

///|
/// Tokenize CSS text, for a consumer that wants the stream rather than a tree.
pub fn tokens(src : String) -> Array[@token.Token] {
  @token.tokenize(src)
}

///|
/// A typed reading of a value, when one applies.
///
/// The lenses live in `css/value` and there are many; these three are the ones
/// a caller reaches for first. Import that package directly for the rest --
/// `as_angle`, `as_time`, `as_var`, `as_keyword`, `to_rgba` and the unit table.
pub fn as_length(v : @ast.ComponentValue) -> @value.Dimension? {
  @value.as_length(v)
}

///|
pub fn as_color(v : @ast.ComponentValue) -> @value.Color? {
  @value.as_color(v)
}

///|
/// How specific a selector is, computed on demand.
pub fn specificity(s : @ast.Selector) -> @value.Specificity {
  @value.specificity(s)
}

///|
/// Turn a diagnostic into a renderable report.
pub fn to_report(
  d : @error.Diagnostic,
  source : @report.SourceId,
) -> @report.Report {
  d.to_report(source)
}
