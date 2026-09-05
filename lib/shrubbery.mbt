// The façade: the handful of calls that cover the common case.
//
// It deliberately re-exports no TYPES. MoonBit has no way to do that, and
// fighting for one would be worse than the alternative: a package is the unit
// of naming here, so a consumer writes
//
//     import {
//       "marianoguerra/shrubbery" @shrub,
//       "marianoguerra/shrubbery/ast",
//     }
//
// and works in `@ast.Node` directly. That also keeps the cost honest -- a
// consumer that only builds trees never compiles the lexer, and `just
// embed-smoke` checks it.

///|
/// Parse shrubbery notation.
///
/// Raises on the first thing wrong, unless `recover` is set, in which case it
/// carries on and collects them — which is what an editor wants, and what makes
/// a file with three mistakes report three.
pub fn parse(
  src : String,
  variant? : @lexer.Variant = @lexer.default_variant,
  recover? : Bool = false,
) -> @parser.Parsed raise @err.ShrubberyError {
  @parser.parse(src, variant~, recover~)
}

///|
/// Parse a `@`-notation text body: the whole input as if it were inside
/// `@{`…`}`. The result is always a `Brackets`.
pub fn parse_text(
  src : String,
  variant? : @lexer.Variant = @lexer.default_variant,
  recover? : Bool = false,
) -> @parser.Parsed raise @err.ShrubberyError {
  @parser.parse(src, mode=Text, variant~, recover~)
}

///|
/// Scan without parsing.
///
/// Every code unit of the input belongs to exactly one token's text, so the
/// stream can be reassembled into the source exactly.
pub fn tokens(
  src : String,
  variant? : @lexer.Variant = @lexer.default_variant,
) -> Array[@lexer.Token] {
  @lexer.lex_all(src, variant~)
}

///|
/// The source a node came from, rebuilt from its metadata.
///
/// Exact for anything this library parsed, with one documented exception: a
/// `#{…}` escape is re-printed from the datum rather than kept verbatim, so a
/// multi-line escape comes back on one line. The reference does the same.
pub fn to_source(node : @ast.Node) -> String {
  node.to_source()
}

///|
/// Re-format a node, ignoring how it was originally written.
///
/// The contract is round-tripping: reading the output back with `parse`
/// produces the same tree. `width` applies to the pretty styles; `None` there
/// means "never break a line that could be one".
pub fn write(
  node : @ast.Node,
  style? : @write.Style = Flat,
  width? : Int? = None,
) -> String {
  @write.write(node, style~, width~)
}

///|
/// The layout document for a node, before a width is chosen.
///
/// For a consumer with its own renderer, or its own idea of what fits.
pub fn layout(node : @ast.Node, style? : @write.Style = Pretty) -> @doc.Doc {
  @write.to_doc(node, style~)
}

///|
/// Turn a diagnostic into a renderable report.
///
/// The one place this library mentions `error-report`. A consumer that wants
/// its own presentation reads `Diagnostic` instead and never calls this.
pub fn to_report(
  diagnostic : @err.Diagnostic,
  source : @report.SourceId,
) -> @report.Report {
  diagnostic.to_report(source)
}
