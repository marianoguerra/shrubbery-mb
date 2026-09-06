///|
/// What went wrong, as a closed set.
///
/// This package has no dependencies at all, and that is deliberate: the tree
/// stores a kind on every `Bogus` node, so if kinds lived beside the
/// `Diagnostic` that renders them, building a tree would link the diagnostic
/// library. Splitting the *name* of a problem from the *reporting* of one is
/// what keeps `ast` and `write` free of `error-report`.
///
/// The names are the specification's. WHATWG names roughly seventy parse
/// errors -- `eof-in-tag`, `abrupt-closing-of-empty-comment`,
/// `unexpected-solidus-in-tag` -- and taking those names costs nothing and buys
/// a message that is greppable against the spec and comparable against any
/// other parser's output. Where a kind has no counterpart there, because it is
/// about the markup tree rather than the token stream, the name is ours and
/// says so by being ordinary English.
pub(all) enum ErrorKind {
  /// The input ended in the middle of a tag.
  EofInTag
  /// The input ended inside a comment.
  EofInComment
  /// The input ended inside a `script` or `style` body.
  EofInRawText(String)
  /// The input ended inside a doctype.
  EofInDoctype
  /// An element was opened and never closed. Carries the tag name.
  UnclosedElement(String)
  /// An end tag whose name is not the innermost open element. Carries the
  /// name written and the name expected.
  MismatchedEndTag(String, String)
  /// An end tag with nothing open to close.
  StrayEndTag(String)
  /// `</br>`, `</img>`: an end tag for an element that cannot have one.
  EndTagForVoid(String)
  /// `<br>text</br>`: children given to an element that cannot have any.
  ChildrenOnVoid(String)
  /// `<div/>`. The slash is ignored in HTML; in foreign content it is not.
  /// A warning, because the markup still means something definite.
  NonVoidSelfClosing(String)
  /// `<div class="a" class="b">`. The first wins, per the specification.
  DuplicateAttribute(String)
  /// A `/` inside a tag that is not the `/` of `/>`.
  UnexpectedSolidusInTag
  /// `<>`, `</>`: a tag with no name.
  MissingTagName
  /// `</ div>`: an end tag whose name does not start with a letter.
  InvalidFirstCharacterOfTagName
  /// A `=` where an attribute name was expected.
  UnexpectedEqualsSignBeforeAttributeName
  /// A `"`, `'` or `<` inside an unquoted attribute value.
  UnexpectedCharacterInUnquotedAttributeValue
  /// `<!-->` or `<!--->`.
  AbruptClosingOfEmptyComment
  /// `<!--` containing `<!--`.
  NestedComment
  /// `--!>` instead of `-->`.
  IncorrectlyClosedComment
  /// `<!x`, `<?php`: not a comment, not a doctype, not a tag. Kept as a
  /// comment, which is what the specification calls a bogus comment.
  BogusComment
  /// `<![CDATA[` outside foreign content, where it is a bogus comment.
  CdataInHtmlContent
  /// A doctype that is not the first thing in the document.
  DoctypeNotFirst
  /// A doctype whose name or identifiers could not be read.
  MalformedDoctype
  /// `&notaname;`. Kept as literal text, per the specification.
  UnknownNamedCharacterReference(String)
  /// `&amp` without the `;`. Resolved anyway in text, per the specification;
  /// a warning, because it is legal and ambiguous rather than wrong.
  MissingSemicolonAfterCharacterReference
  /// `&#xZZ;`, `&#;`: a numeric reference with no digits.
  AbsenceOfDigitsInNumericCharacterReference
  /// `&#x110000;`, `&#xD800;`: a numeric reference outside the scalar range.
  /// Replaced with U+FFFD, per the specification.
  CharacterReferenceOutsideUnicodeRange
  /// A literal NUL in the input, replaced with U+FFFD.
  UnexpectedNullCharacter
  /// A `</script` that a raw-text body cannot contain, found while PRINTING.
  /// There is no escape for it, so the printer refuses rather than emitting
  /// markup that means something else.
  UnprintableRawText(String)
  /// Anything else that could not be read. Carries what was expected.
  Unexpected(String)
} derive(Eq, Debug)

///|
/// A stable identifier for this kind.
///
/// Stable is the whole point: it goes in `error[...]` headers, in JSON output
/// and in a harness's expectations, so it must not change when the prose does.
/// Written out rather than derived from the variant name, so that renaming a
/// variant is a local edit and not a silent break of everything downstream that
/// matched on the string.
pub fn ErrorKind::code(self : ErrorKind) -> String {
  let name = match self {
    EofInTag => "eof_in_tag"
    EofInComment => "eof_in_comment"
    EofInRawText(_) => "eof_in_raw_text"
    EofInDoctype => "eof_in_doctype"
    UnclosedElement(_) => "unclosed_element"
    MismatchedEndTag(_, _) => "mismatched_end_tag"
    StrayEndTag(_) => "stray_end_tag"
    EndTagForVoid(_) => "end_tag_for_void"
    ChildrenOnVoid(_) => "children_on_void"
    NonVoidSelfClosing(_) => "non_void_self_closing"
    DuplicateAttribute(_) => "duplicate_attribute"
    UnexpectedSolidusInTag => "unexpected_solidus_in_tag"
    MissingTagName => "missing_tag_name"
    InvalidFirstCharacterOfTagName => "invalid_first_character_of_tag_name"
    UnexpectedEqualsSignBeforeAttributeName =>
      "unexpected_equals_sign_before_attribute_name"
    UnexpectedCharacterInUnquotedAttributeValue =>
      "unexpected_character_in_unquoted_attribute_value"
    AbruptClosingOfEmptyComment => "abrupt_closing_of_empty_comment"
    NestedComment => "nested_comment"
    IncorrectlyClosedComment => "incorrectly_closed_comment"
    BogusComment => "bogus_comment"
    CdataInHtmlContent => "cdata_in_html_content"
    DoctypeNotFirst => "doctype_not_first"
    MalformedDoctype => "malformed_doctype"
    UnknownNamedCharacterReference(_) => "unknown_named_character_reference"
    MissingSemicolonAfterCharacterReference =>
      "missing_semicolon_after_character_reference"
    AbsenceOfDigitsInNumericCharacterReference =>
      "absence_of_digits_in_numeric_character_reference"
    CharacterReferenceOutsideUnicodeRange =>
      "character_reference_outside_unicode_range"
    UnexpectedNullCharacter => "unexpected_null_character"
    UnprintableRawText(_) => "unprintable_raw_text"
    Unexpected(_) => "unexpected"
  }
  "html::" + name
}

///|
/// Whether this kind is a hard error or something a tolerant parse may carry.
///
/// The distinction is what makes strict mode meaningful, and here it carries
/// more weight than it does in CSS: most of these are recoveries rather than
/// failures. A stray `</div>` is what half the web looks like, and a library
/// that refused it would be a library nobody could point at a real page.
pub fn ErrorKind::is_warning(self : ErrorKind) -> Bool {
  match self {
    NonVoidSelfClosing(_)
    | DuplicateAttribute(_)
    | MissingSemicolonAfterCharacterReference
    | UnknownNamedCharacterReference(_)
    | UnexpectedNullCharacter
    | StrayEndTag(_)
    | BogusComment
    | DoctypeNotFirst => true
    _ => false
  }
}
