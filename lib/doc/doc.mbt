///|
/// A description of ALL the ways a piece of output may be laid out.
///
/// Deliberately small: five constructors, and `Or` is ordered — the
/// single-line reading first, the multi-line one second. That ordering is what
/// the renderer relies on, and it is why this is not a general pretty-printing
/// document type.
///
/// The value is a DAG rather than a tree: the two branches of an `Or` share
/// their sub-documents, and a tree view of a nested document can be
/// exponentially larger than the graph. Nothing here copies, so building one
/// costs what it looks like it costs.
pub(all) enum Doc {
  /// Printed literally.
  Str(String)
  /// A newline, then the current indentation as spaces.
  Nl
  /// Printed in order, at the same indentation.
  Seq(Array[Doc])
  /// Printed with the indentation increased by `n`.
  Nest(Int, Doc)
  /// Printed with the indentation set to the CURRENT column.
  Align(Doc)
  /// The single-line reading, then the multi-line one.
  Or(Doc, Doc)
}

///|
pub let empty : Doc = Seq([])

///|
/// Everything in order.
pub fn seq(docs : Array[Doc]) -> Doc {
  Seq(docs)
}

///|
/// `docs`, with `sep` between each pair.
pub fn join(docs : Array[Doc], sep : Doc) -> Doc {
  if docs.length() <= 1 {
    return Seq(docs)
  }
  let out = []
  for i in 0..<docs.length() {
    if i > 0 {
      out.push(sep)
    }
    out.push(docs[i])
  }
  Seq(out)
}

///|
/// The document as an S-expression, in the shape the reference prints.
///
/// For comparing a document against the reference's own, which is the only way
/// to tell a layout disagreement (the renderer chose differently) from a
/// construction disagreement (the documents were never the same).
pub fn Doc::to_sexpr(self : Doc) -> String {
  let buf = StringBuilder()
  self.write_sexpr(buf)
  buf.to_string()
}

///|
pub fn Doc::write_sexpr(self : Doc, buf : StringBuilder) -> Unit {
  match self {
    Str(s) => {
      buf.write_char('"')
      for c in s {
        match c {
          '"' => buf.write_string("\\\"")
          '\\' => buf.write_string("\\\\")
          '\n' => buf.write_string("\\n")
          _ => buf.write_char(c)
        }
      }
      buf.write_char('"')
    }
    Nl => buf.write_string("nl")
    Seq(docs) => {
      buf.write_string("(seq")
      for d in docs {
        buf.write_char(' ')
        d.write_sexpr(buf)
      }
      buf.write_char(')')
    }
    Nest(n, inner) => {
      buf.write_string("(nest \{n} ")
      inner.write_sexpr(buf)
      buf.write_char(')')
    }
    Align(inner) => {
      buf.write_string("(align ")
      inner.write_sexpr(buf)
      buf.write_char(')')
    }
    Or(a, b) => {
      buf.write_string("(or ")
      a.write_sexpr(buf)
      buf.write_char(' ')
      b.write_sexpr(buf)
      buf.write_char(')')
    }
  }
}
