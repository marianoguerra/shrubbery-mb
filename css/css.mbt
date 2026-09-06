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
/// Turn a diagnostic into a renderable report.
pub fn to_report(
  d : @error.Diagnostic,
  source : @report.SourceId,
) -> @report.Report {
  d.to_report(source)
}
