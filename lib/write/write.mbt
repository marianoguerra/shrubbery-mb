///|
/// How the output should be laid out.
pub(all) enum Style {
  /// One line, with `«»`, `;` and `,` doing the grouping. Reads back the same
  /// however it is later re-indented, which is what makes it the safe default
  /// for writing a shrubbery down to be read later.
  Flat
  /// Line breaks and indentation, falling back to one line where it fits.
  Pretty
  /// Pretty, but still line- and column-insensitive: `«»` rather than
  /// indentation.
  Armoured
  /// Pretty, and preferring line breaks to `«»` where either would do.
  PreferMultiline
} derive(Eq)

///|
/// Write a shrubbery.
///
/// The contract is round-tripping: reading the output back with `parse`
/// produces the same tree. `width` applies to the pretty styles; `None` there
/// means "never break a line that could be one", and `Some(0)` means "break
/// every line that could be broken".
pub fn write(
  node : @ast.Node,
  style? : Style = Flat,
  width? : Int? = None,
) -> String {
  match style {
    Flat => {
      let buf = StringBuilder()
      write_flat(node, buf, before_block=false)
      buf.to_string()
    }
    _ => @doc.render_string(to_doc(node, style~), width~)
  }
}

///|
/// The layout document for a shrubbery, before a width is chosen.
///
/// Exposed because the document is the interesting object: it describes every
/// legal layout at once, and a consumer with its own renderer -- or its own
/// idea of what fits -- can take it from here.
pub fn to_doc(node : @ast.Node, style? : Style = Pretty) -> @doc.Doc {
  let target = match style {
    Armoured => ArmorDoc
    PreferMultiline => MultiDoc
    _ => PlainDoc
  }
  let r = build(node, target, non_tail=false, head=true, before_block=false)
  match r.single {
    Some(single) => Or(single, r.multi)
    None => r.multi
  }
}

///|
/// Which of the three document readings is being built.
priv enum Target {
  /// Line breaks where they help, `«»` where they are needed.
  PlainDoc
  /// `«»` everywhere, so the output survives being re-indented.
  ArmorDoc
  /// Line breaks in preference to `«»`.
  MultiDoc
}

///|
/// What one term contributes.
priv struct Built {
  /// The single-line reading, when there is one. `None` in `MultiDoc` for a
  /// term that must break.
  single : @doc.Doc?
  /// The multi-line reading.
  multi : @doc.Doc
  /// Whether an unquoted `'` appears in either, which decides whether a
  /// surrounding `'…'` needs its guillemets.
  quotes : Bool
  /// Whether an enclosing `|` can do without `«»` around the single-line form.
  is_atom : Bool
}

///|
/// Both readings the same, and is_atom: an atom.
fn twice(text : String) -> Built {
  { single: Some(Str(text)), multi: Str(text), quotes: false, is_atom: true, }
}
