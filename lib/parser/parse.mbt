///|
/// What to read.
///
/// The mode decides the shape of the answer, which is why it is a parameter
/// rather than something inferred: `Top` always gives a `multi`, `Text` always
/// gives a `brackets`.
pub(all) enum Mode {
  /// A whole document. Every group must start at the same column.
  Top
  /// As if the whole input were inside `@{`…`}`.
  Text
} derive(Eq)

///|
/// A successful parse, and anything reported along the way.
///
/// `diagnostics` is non-empty only in recovery mode, where parsing continues
/// past a failure so that a file with three mistakes reports three. Outside
/// recovery, the first failure is raised instead.
pub struct Parsed {
  root : @ast.Node
  diagnostics : Array[@err.Diagnostic]
}

///|
pub fn Parsed::root(self : Parsed) -> @ast.Node {
  self.root
}

///|
pub fn Parsed::diagnostics(self : Parsed) -> Array[@err.Diagnostic] {
  self.diagnostics
}

///|
/// Parse shrubbery notation.
///
/// `start_column` accounts for characters that logically precede the input, for
/// an embedder splicing this into something larger; it affects indentation only,
/// never the positions reported.
pub fn parse(
  src : String,
  mode? : Mode = Top,
  variant? : @lexer.Variant = @lexer.default_variant,
  start_column? : @column.Column = @column.zero,
  recover? : Bool = false,
) -> Parsed raise @err.ShrubberyError {
  let toks = @lexer.lex_all(src, variant~, start_column~)
  parse_tokens(toks, mode~, variant~, recover~)
}

///|
/// Parse an already-scanned token stream.
///
/// Exposed because a consumer that has its own reason to look at the tokens --
/// an editor, a highlighter -- should not have to scan twice.
pub fn parse_tokens(
  toks : Array[@lexer.Token],
  mode? : Mode = Top,
  variant? : @lexer.Variant = @lexer.default_variant,
  recover? : Bool = false,
) -> Parsed raise @err.ShrubberyError {
  // The end-of-input token has served its purpose in the scanner; the parser
  // asks "are there tokens left?" instead, as the reference does.
  let body = []
  for t in toks {
    if !(t.kind is EndOfInput) {
      body.push(t)
    }
  }
  let p = { toks: body, diags: [], recover, }
  let fallback = if body.length() > 0 {
    body[0].span
  } else {
    @basic.Span::at(@basic.start)
  }
  match mode {
    Top => {
      let result = p.parse_groups(0, {
        count: true,
        closer: Eof,
        paren_immed: NotImmed,
        column: None,
        bar_column: None,
        check_column: false,
        bar_closes: false,
        bar_closes_line: None,
        block_mode: NoBlock,
        can_empty: true,
        comma_time: false,
        sequence_mode: AnyNumber,
        last_line: Some(-1),
        delta: 0,
        commenting: None,
        tail_commenting: None,
        raw: RNil,
        variant,
      })
      match result.tail_commenting {
        Some(c) => p.fail_no_comment_group(c)
        None => ()
      }
      let items = bars_insert_alts(result.groups, fallback)
      let root = @ast.Node::new(Multi(items), span_over(items, fallback))
      root.meta.suffix = result.tail_raw.to_raw()
      normalize_group_raw(root)
      { root, diagnostics: p.diags, }
    }
    Text => {
      let seq = p.parse_text_sequence(0, Some(1), 0, None, true, variant)
      { root: seq.node, diagnostics: p.diags, }
    }
  }
}
