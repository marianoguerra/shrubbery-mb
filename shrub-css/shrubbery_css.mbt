///|
/// The bridge, in one import.
///
/// Like the other façades here it re-exports no types -- a package is the unit
/// of naming in MoonBit -- so a consumer that names a `@ast.Stylesheet` imports
/// `marianoguerra/css/ast` too. What this saves is knowing which package a verb
/// lives in.

///|
/// Shrubbery CSS source, as CSS.
///
/// The headline function, and the one most callers want: notation in, CSS out.
/// Tolerant -- a source with one mistake still produces a stylesheet with
/// everything else intact -- so a caller who needs to know asks
/// `lower`, which hands back the diagnostics alongside the tree.
pub fn to_css(
  src : String,
  style? : @write.Style = Pretty,
) -> String raise @error.ShrubCssError {
  let l = @lower.lower_source(src)
  @write.stylesheet(l.sheet(), style~)
}

///|
/// Shrubbery CSS source, as a CSS syntax tree, with everything noticed on the
/// way.
pub fn lower(
  src : String,
  strict? : Bool = false,
) -> @lower.Lowered raise @error.ShrubCssError {
  @lower.lower_source(src, strict~)
}

///|
/// Turn a bridge diagnostic into a renderable report.
pub fn to_report(
  d : @error.Diagnostic,
  source : @report.SourceId,
) -> @report.Report {
  d.to_report(source)
}

///|
/// CSS source, as shrubbery CSS.
///
/// The other headline function, and the one that closes the loop: hand it CSS
/// and it hands back notation that lowers to the same tree.
///
/// It is a normalisation, not an inverse. Two things do not survive the detour,
/// and neither can be helped: a number's source spelling, because shrubbery's
/// literal holds a value rather than a spelling (`1.50` comes back `1.5`, `+1`
/// comes back `1`), and a comment's placement, since CSS comments become line
/// comments. Everything else round-trips.
pub fn to_shrubbery(css : String) -> String raise @csserror.CssError {
  let p = @parse.parse(css)
  @emit.stylesheet(p.sheet())
}

///|
/// A CSS syntax tree as shrubbery CSS.
pub fn emit(sheet : @ast.Stylesheet) -> String {
  @emit.stylesheet(sheet)
}
