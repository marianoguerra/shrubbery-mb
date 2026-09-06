///|
/// The library façade.
///
/// One import for the common path. A façade re-exports no TYPES -- a package is
/// the unit of naming in MoonBit -- so a consumer that names an
/// `@ast.Document` imports `marianoguerra/html/ast` as well. What this package
/// saves is having to know which of `parse`, `write` and `error` a given verb
/// lives in.

///|
/// Parse markup text: HTML, SVG or MathML.
///
/// Tolerant: malformed input produces diagnostics and a tree that still covers
/// the whole file, so this returns a document for any input at all. Pass
/// `strict=true` to have the first error raised instead.
pub fn parse(
  src : String,
  strict? : Bool = false,
) -> @parse.Parsed raise @error.HtmlError {
  @parse.parse(src, strict~)
}

///|
/// Parse markup text, raising on the first error.
pub fn parse_strict(src : String) -> @ast.Document raise @error.HtmlError {
  @parse.parse_strict(src)
}

///|
/// Print a document as markup.
pub fn to_html(
  doc : @ast.Document,
  style? : @write.Style = Pretty,
  whitespace? : @write.Whitespace = Css,
) -> String {
  @write.document(doc, style~, whitespace~)
}

///|
/// Tokenize markup text, for a consumer that wants the stream rather than a
/// tree.
pub fn tokens(src : String) -> Array[@token.Token] {
  @token.tokens(src)
}

///|
/// A typed reading of the tree, when one applies.
///
/// The lenses live in `html/value` and there are more; these are the ones a
/// caller reaches for first. Import that package directly for the rest --
/// `as_int`, `as_bool`, `elements`, `by_id`, `by_tag`, `display_of`.
pub fn attr(e : @ast.Element, name : String) -> String? {
  @value.attr(e, name)
}

///|
pub fn class_list(e : @ast.Element) -> Array[String] {
  @value.class_list(e)
}

///|
pub fn text_content(n : @ast.Node) -> String {
  @value.text_content(n)
}

///|
/// Turn a diagnostic into a renderable report.
pub fn to_report(
  d : @error.Diagnostic,
  source : @report.SourceId,
) -> @report.Report {
  d.to_report(source)
}
