///|
/// What can go wrong turning shrubbery into CSS.
///
/// A separate set from `@css.kind`, and deliberately so: these are problems
/// with the *bridge*, not with CSS. "This is not a selector" is a CSS
/// complaint; "`|` has no meaning in Shrubbery CSS" is one only this layer can
/// make. Sharing one enum would mean either half growing variants the other
/// can never produce.
///
/// No dependencies, for the same reason `@css.kind` has none: a lowered tree
/// stores kinds on its `Bogus` nodes, and naming a problem must not link a
/// renderer.
pub(all) enum ErrorKind {
  /// A group that should have opened a block did not.
  ExpectedBlock
  /// A block with nothing before it.
  HeadlessBlock
  /// `|` alternatives. Reserved: they have no CSS reading at all.
  AltsUnsupported
  /// `{ }`. CSS's braces became blocks, so these mean nothing here.
  BracesUnsupported
  /// `'...'`. The quote form has no CSS reading.
  QuotesUnsupported
  /// A declaration outside any rule.
  DeclarationAtTopLevel
  /// A rule where only declarations belong.
  RuleInDeclarationContext
  /// Two type selectors touching: `a b` where a relation was meant.
  TypeSelectorNotFirst
  /// A relation keyword at the start or end of a selector, or two in a row.
  DanglingCombinator
  /// A `~name` that is not a relation.
  StrayKeyword(String)
  /// `.card` written with the CSS sigil rather than as `class(card)`.
  SigilSelector(String)
  /// `>` or `+` used as a combinator, where a relation keyword is meant.
  OperatorCombinator(String)
  /// A call in selector position whose name means nothing here.
  UnknownSelectorCall(String)
  /// A call whose arguments are the wrong shape for its name.
  BadCallShape(String)
  /// `hex(007700)`: the leading zeros are already gone by the time this layer
  /// sees it, so the digits cannot be recovered.
  HexDigitsLost
  /// A `dim(n, "unit")` whose unit is not one CSS knows.
  UnknownUnit(String)
  /// A value where a selector belongs, or the reverse.
  BadSelector
  /// A bare term in a rule body, with no value and no block.
  BareTermInBlock(String)
  /// `a: hover` -- a rule that reads as a declaration of an unknown property.
  ColonPseudo(String, String)
  /// More than one group in a value block: the `;` hazard.
  SemicolonDeclarations
  /// An `An+B` formula that did not parse.
  BadAnB
  /// A shrubbery construct with no CSS reading at all.
  Unsupported(String)
} derive(Eq, Debug)

///|
/// A stable identifier, namespaced apart from `css::` so a consumer can tell
/// which layer complained.
pub fn ErrorKind::code(self : ErrorKind) -> String {
  let name = match self {
    ExpectedBlock => "expected_block"
    HeadlessBlock => "headless_block"
    AltsUnsupported => "alts_unsupported"
    BracesUnsupported => "braces_unsupported"
    QuotesUnsupported => "quotes_unsupported"
    DeclarationAtTopLevel => "declaration_at_top_level"
    RuleInDeclarationContext => "rule_in_declaration_context"
    TypeSelectorNotFirst => "type_selector_not_first"
    DanglingCombinator => "dangling_combinator"
    StrayKeyword(_) => "stray_keyword"
    SigilSelector(_) => "sigil_selector"
    OperatorCombinator(_) => "operator_combinator"
    UnknownSelectorCall(_) => "unknown_selector_call"
    BadCallShape(_) => "bad_call_shape"
    HexDigitsLost => "hex_digits_lost"
    UnknownUnit(_) => "unknown_unit"
    BadSelector => "bad_selector"
    BareTermInBlock(_) => "bare_term_in_block"
    ColonPseudo(_, _) => "colon_pseudo"
    SemicolonDeclarations => "semicolon_declarations"
    BadAnB => "bad_anb"
    Unsupported(_) => "unsupported"
  }
  "shrubcss::" + name
}
