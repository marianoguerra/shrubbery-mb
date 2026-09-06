///|
/// The bridge, in one import.
///
/// Like the other façades here it re-exports no types -- a package is the unit
/// of naming in MoonBit -- so a consumer that names an `@ast.Document` imports
/// `marianoguerra/html/ast` too. What this saves is knowing which package a
/// verb lives in.

///|
/// Shrubbery HTML source, as markup.
///
/// The headline function, and the one most callers want: notation in, HTML
/// out. Tolerant -- a source with one mistake still produces a document with
/// everything else intact -- so a caller who needs to know asks `lower`, which
/// hands back the diagnostics alongside the tree.
pub fn to_html(
  src : String,
  style? : @write.Style = Pretty,
  whitespace? : @write.Whitespace = Css,
) -> String raise @error.ShrubHtmlError {
  let l = @lower.lower_source(src)
  @write.document(l.document(), style~, whitespace~)
}

///|
/// Shrubbery HTML source, as a markup tree, with everything noticed on the way.
///
/// `hook` is where a raw-text element's body can be lowered by something else
/// -- shrubbery CSS inside `style()`, say. It is a parameter rather than a
/// dependency because a module's dependencies are fetched by every consumer,
/// and an HTML user should not pay for the CSS tables.
pub fn lower(
  src : String,
  strict? : Bool = false,
  hook? : @lower.RawTextHook? = None,
) -> @lower.Lowered raise @error.ShrubHtmlError {
  @lower.lower_source(src, strict~, hook~)
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
/// Markup source, as Shrubbery HTML.
///
/// The other headline function, and the one that closes the loop: hand it HTML
/// and it hands back notation that lowers to the same tree.
///
/// It is a normalisation, not an inverse. Three things do not survive the
/// detour, and none can be helped: a character reference's spelling, because a
/// shrubbery string holds a value rather than a spelling; a void element's
/// slash, because `<br/>` and `<br>` are one element and the notation has no
/// house styles; and an implied end tag, because the notation has no end tags
/// at all -- children are a block, and a block always closes.
pub fn to_shrubbery(html : String) -> String raise @htmlerror.HtmlError {
  let p = @parse.parse(html)
  @emit.document(p.document())
}

///|
/// A markup tree as Shrubbery HTML.
pub fn emit(doc : @ast.Document) -> String {
  @emit.document(doc)
}
