///|
/// The properties.
///
/// Each is a claim about the whole library rather than about one input, and
/// each is checked over trees nobody wrote down. When one fails the tree is
/// shrunk first, so the report is a counterexample small enough to read rather
/// than the thirty nodes that happened to contain it.
///
/// The seed is a default argument on `check`, so reproducing a failure is a
/// one-literal edit.

///|
/// The default seed. Fixed, so a run is reproducible and a failure is not a
/// thing that happened once on someone's machine.
let default_seed : UInt64 = 0x5EED_4A7_0001UL

///|
/// Whether two trees are the same, ignoring where they came from.
///
/// Spans cannot be compared: a generated tree has none, a parsed one has real
/// offsets, and every property here compares one of each. Comparing the printed
/// form instead is not a weakening in any way that matters -- a difference the
/// printer cannot show is a difference nobody can observe from a library whose
/// output is text.
fn same(a : @ast.Document, b : @ast.Document) -> Bool {
  @write.document(a, style=Minified) == @write.document(b, style=Minified)
}

///|
/// Run one property over generated documents.
fn check(
  name : String,
  holds : (@ast.Document) -> Bool,
  runs? : Int = 120,
  max_size? : Int = 12,
  seed? : UInt64 = default_seed,
) -> Unit raise {
  let r = @prop.Rng::new(seed)
  for i in 0..<runs {
    let size = 1 + i % max_size
    let doc = @prop.gen_document(r, size)
    if !holds(doc) {
      let small = @prop.minimize(doc, @prop.shrink_document, x => !holds(x))
      fail(
        name +
        "\n  seed=" +
        seed.to_string() +
        " run=" +
        i.to_string() +
        " size=" +
        size.to_string() +
        "\n  minimal counterexample, as markup:\n" +
        @write.document(small, style=Pretty) +
        "\n  as shrubbery:\n" +
        @emit.document(small),
      )
    }
  }
}

///|
test "printing is a fixed point, in every mode" {
  for style in [@write.Style::Pretty, Compact, Minified] {
    check("print is stable (" + describe(style) + ")", doc => {
      let once = @write.document(doc, style~)
      let p = @parse.parse(once) catch { _ => return false }
      once == @write.document(p.document(), style~)
    })
  }
}

///|
fn describe(s : @write.Style) -> String {
  match s {
    Pretty => "pretty"
    Compact => "compact"
    Minified => "minified"
  }
}

///|
test "parsing what was printed gives back the same tree" {
  check("print then parse is the identity", doc => {
    let p = @parse.parse(@write.document(doc, style=Minified)) catch {
      _ => return false
    }
    same(doc, p.document())
  })
}

///|
test "the loop closes: markup, notation, markup" {
  check("lower(emit(t)) prints as t does", doc => {
    let shrub = @emit.document(doc)
    let l = @lower.lower_source(shrub) catch { _ => return false }
    same(doc, l.document())
  })
}

///|
test "nothing escapes the node it was put in" {
  // The property that is not about formatting. A tree built in memory and
  // printed is a template engine, and the question a template engine has to
  // answer is whether a value can break out of the node it was put in. Every
  // string the generator uses has ended a node it was not supposed to end in
  // some parser; the claim is that reparsing gives every one of them back
  // unchanged, in text and in an attribute value alike.
  check("text and attribute values survive printing", doc => {
    let printed = @write.document(doc, style=Minified)
    let p = @parse.parse(printed) catch { _ => return false }
    strings_of(doc) == strings_of(p.document())
  })
}

///|
/// Every text run and attribute value in a document, in order.
fn strings_of(doc : @ast.Document) -> String {
  let buf = StringBuilder()
  for c in doc.children {
    collect(c, buf)
  }
  buf.to_string()
}

///|
fn collect(n : @ast.Node, buf : StringBuilder) -> Unit {
  match n {
    Text(t) => {
      buf.write_string(t.text)
      buf.write_char('\u{1}')
    }
    Cdata(t, _) => {
      buf.write_string(t)
      buf.write_char('\u{1}')
    }
    Element(e) => {
      for a in e.attrs {
        buf.write_string(a.name.text())
        buf.write_char('\u{2}')
        buf.write_string(a.value.text())
        buf.write_char('\u{1}')
      }
      for c in e.children {
        collect(c, buf)
      }
    }
    _ => ()
  }
}

///|
test "lowering is total: any notation at all gives a document" {
  // The other direction of tolerance. Everything the emitter writes has to
  // come back, and so does everything it would never write -- which is what
  // the `survive` oracle checks over a corpus and this checks over trees.
  check("emit then lower never fails", doc => {
    let shrub = @emit.document(doc)
    let l = @lower.lower_source(shrub) catch { _ => return false }
    !l.has_errors()
  })
}

///|
test "shrinking makes progress" {
  // Not a property of the library: a property of the test machinery, and the
  // one that stops a failing property hanging the suite instead of reporting.
  let r = @prop.Rng::new(default_seed)
  for i in 0..<40 {
    let doc = @prop.gen_document(r, 1 + i % 10)
    let size = @prop.size_of(doc)
    for smaller in @prop.shrink_document(doc) {
      assert_true(@prop.size_of(smaller) < size)
    }
  }
}
