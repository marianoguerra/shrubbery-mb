///|
/// The token stream.
///
/// A markup tokenizer, not the WHATWG one. The specification's tokenizer has
/// eighty states because it is one half of a machine whose other half is the
/// tree builder, and the two share a mode: the tokenizer asks the tree builder
/// which namespace it is in, and the tree builder puts the tokenizer into raw
/// text when it inserts a `<script>`. That coupling is what makes a conforming
/// parser a single object rather than a pipeline.
///
/// Here the coupling is smaller and it is kept inside the tokenizer: the one
/// thing lexing depends on is the name of the last start tag, because that is
/// what decides where a raw-text body ends. Everything else -- namespaces, case
/// adjustment, which elements may nest -- is the parser's, and the token stream
/// is a plain array the way `css/token`'s is.
///
/// The tokenizer never fails. Anything it cannot read becomes a `Bogus` token
/// carrying the source it covered, so the stream always spans the whole input
/// and the parser decides what a failure means rather than having that decided
/// for it two layers down.

///|
/// An attribute as written, before the parser knows its namespace.
///
/// `name` is ASCII-lowercased, which is right for HTML and wrong for SVG --
/// `viewBox` arrives here as `viewbox`. Restoring it needs the namespace, which
/// needs the element stack, which is the parser's. Doing it here would mean
/// lowercasing and then un-lowercasing, or not lowercasing and getting HTML
/// wrong; doing it there is one table lookup at the point where the answer is
/// known.
pub(all) struct RawAttr {
  name : String
  /// The decoded value. `None` is a valueless attribute -- `disabled` -- which
  /// is not the same as `Some("")`, which is `disabled=""`.
  value : String?
  /// The source spelling of the value, when decoding was not the identity.
  raw : String?
  span : @span.Span
} derive(Eq, Debug)

///|
/// Where a scan begins.
///
/// Ordinary markup, almost always. The other two exist because the content
/// model of an element is decided by the element that opened it, and a scan can
/// begin already INSIDE one -- `innerHTML` on a `<title>`, a fragment handed to
/// a template engine, a conformance suite naming an initial state. The tag is
/// carried rather than the state, because what ends a raw-text run is that
/// element's own end tag and nothing else.
pub(all) enum Start {
  Markup
  /// References resolve, markup does not: `title`, `textarea`.
  Escapable(String)
  /// Nothing resolves and nothing is markup: `script`, `style`.
  Raw(String)
} derive(Eq, Debug)

///|
pub(all) enum TokenKind {
  /// A start tag: the lowercased name, its attributes in source order, and
  /// whether it was written with a `/`. What that `/` means depends on the
  /// namespace, which is why it is carried rather than acted on.
  StartTag(String, Array[RawAttr], Bool)
  EndTag(String)
  /// Character data: decoded, then the source spelling when decoding was not
  /// the identity.
  Text(String, String?)
  /// The body of a `script` or `style`, verbatim.
  RawText(String)
  Comment(String)
  /// A doctype: name, public identifier, system identifier, and whether it
  /// forces quirks mode.
  ///
  /// The last is the tokenizer's answer and not the tree's: `@ast.Doctype`
  /// records what was WRITTEN, and quirks mode is a question about the document
  /// rather than about the markup. The tokenizer is answerable for it because
  /// the specification sets the flag while scanning, and a conformance suite
  /// checks it.
  Doctype(String, String?, String?, Bool)
  Cdata(String)
  /// A region that is not any of the above, kept with the source it covered so
  /// that the printer can echo it.
  Bogus(@kind.ErrorKind, String)
  Eof
} derive(Eq, Debug)

///|
pub(all) struct Token {
  kind : TokenKind
  span : @span.Span
} derive(Eq, Debug)

///|
/// Everything noticed while scanning, in source order.
///
/// The tokenizer collects rather than raises for the reason the CSS one does:
/// a malformed character reference is a warning about six characters, and
/// making it stop the scan would mean a page with one `&copy` in it produced no
/// tokens at all.
pub(all) struct Scanned {
  tokens : Array[Token]
  problems : Array[(@kind.ErrorKind, @span.Span)]
}

///|
/// Whether this token is whitespace-only character data.
///
/// Asked by the parser at exactly one place -- deciding whether text before
/// `<html>` is worth keeping -- and by tests. A method rather than a free
/// function so that it reads as a property of the token.
pub fn Token::is_whitespace(self : Token) -> Bool {
  match self.kind {
    Text(t, _) => {
      let n = t.length()
      let mut i = 0
      while i < n {
        let c = t.unsafe_get(i).to_int().unsafe_to_char()
        if c != ' ' && c != '\t' && c != '\n' && c != '\r' && c != '\u{0C}' {
          return false
        }
        i = i + 1
      }
      true
    }
    _ => false
  }
}

///|
/// A one-line rendering of a token, for the harness and for tests.
pub fn TokenKind::to_debug(self : TokenKind) -> String {
  match self {
    StartTag(name, attrs, sc) => {
      let buf = StringBuilder()
      buf.write_string("start ")
      buf.write_string(name)
      for a in attrs {
        buf.write_char(' ')
        buf.write_string(a.name)
        match a.value {
          Some(v) => {
            buf.write_char('=')
            buf.write_string(v)
          }
          None => ()
        }
      }
      if sc {
        buf.write_string(" /")
      }
      buf.to_string()
    }
    EndTag(name) => "end " + name
    Text(t, _) => "text " + t
    RawText(t) => "rawtext " + t
    Comment(t) => "comment " + t
    Doctype(n, _, _, quirks) =>
      "doctype " + n + (if quirks { " (quirks)" } else { "" })
    Cdata(t) => "cdata " + t
    Bogus(k, t) => "bogus " + k.code() + " " + t
    Eof => "eof"
  }
}

///|
/// A whole stream, one token per line.
pub fn dump(tokens : Array[Token]) -> String {
  let buf = StringBuilder()
  for t in tokens {
    buf.write_string(t.kind.to_debug())
    buf.write_char('\n')
  }
  buf.to_string()
}
