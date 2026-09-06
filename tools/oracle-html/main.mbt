///|
/// The markup oracle: the binary `tools/htmldiff.py` drives.
///
/// It lives in the development module, not in a published CLI, for the reason
/// the whole dev module exists: it reaches the libraries through their public
/// API only, so whatever the harness needs is by construction a name that has
/// to stay public. Putting these subcommands in `shrubbery-cli` instead would
/// also make every CLI user fetch the markup modules.
///
/// Output is batched: one process for a whole corpus, with a `==== path`
/// header before each answer. That is the same shape `tools/shrubdiff.py` and
/// `tools/cssdiff.py` already consume, and it exists because starting a process
/// per file dominates the runtime of a several-hundred-file corpus.
///
/// Every subcommand answers for every file, including the ones that fail. A
/// file that cannot be read at all answers `!error <what>`, so a corpus entry
/// never silently disappears from a comparison.
fn main {
  let args = @env.args()
  if args.length() < 3 {
    println("usage: oracle-html <command> FILE...")
    println("")
    println("  print      markup -> markup, in all three modes")
    println("  roundtrip  markup -> markup -> markup; the two must agree")
    println("  loop       markup -> shrubbery -> markup; must equal `print`")
    println("  lower      Shrubbery HTML -> markup")
    println("  emit       markup -> Shrubbery HTML")
    println("  conform    our output must mean what the input meant")
    println("  html5lib   run an html5lib tokenizer .test file")
    println("  survive    parse anything at all, and say so")
    println("  diagnose   the diagnostic codes a file produces")
    return
  }
  let cmd = args[1]
  for path in args[2:] {
    println("==== " + path)
    let src = read(path)
    match src {
      None => println("!error cannot read file")
      Some(text) =>
        match cmd {
          "print" => print_modes(text)
          "roundtrip" => roundtrip(text)
          "loop" => markup_loop(text)
          "lower" => lower_shrub(text)
          "emit" => emit_shrub(text)
          "conform" => conform(text)
          "html5lib" => html5lib(path, text)
          "survive" => survive(text)
          "diagnose" => diagnose(text)
          other => println("!error unknown command " + other)
        }
    }
  }
}

///|
/// Write a block that already ends in a newline, without adding another.
///
/// The printers end their output with one; `println` would add a second, and a
/// golden file would then record a blank line that means nothing.
fn put(text : String) -> Unit {
  if text.has_suffix("\n") {
    println(text.clamped_view(end=text.length() - 1).to_owned())
  } else {
    println(text)
  }
}

///|
fn read(path : String) -> String? {
  Some(@fs.read_file_to_string(path)) catch {
    _ => None
  }
}

///|
/// Markup in all three printing modes.
///
/// Three rather than one because they are three different claims: pretty output
/// is what a person reads, minified is what has to stay correct with every
/// optional token removed, and compact sits between them. A bug that only shows
/// when a space is dropped shows here.
fn print_modes(src : String) -> Unit {
  let p = @parse.parse(src) catch {
    e => {
      println("!error " + e.diagnostic().kind.code())
      return
    }
  }
  println("--- pretty")
  put(@write.document(p.document(), style=Pretty))
  println("--- compact")
  put(@write.document(p.document(), style=Compact))
  println("--- minified")
  println(@write.document(p.document(), style=Minified))
}

///|
/// Parse, print, parse, print: the second pair must equal the first.
///
/// This is the printer's fixed-point property, and it catches the class of bug
/// where output is valid but not stable -- a printer that added a space each
/// time round would pass every single-pass test and fail this one.
fn roundtrip(src : String) -> Unit {
  for style in ["pretty", "minified"] {
    let s : @write.Style = if style == "pretty" { Pretty } else { Minified }
    match print_once(src, s) {
      None => {
        println("!error " + style + " first pass")
        continue
      }
      Some(a) =>
        match print_once(a, s) {
          None => println("!error " + style + " second pass")
          Some(b) =>
            if a == b {
              println(style + ": stable")
            } else {
              println(style + ": NOT STABLE")
              println("  once:  " + a)
              println("  twice: " + b)
            }
        }
    }
  }
}

///|
fn print_once(src : String, style : @write.Style) -> String? {
  let p = @parse.parse(src) catch { _ => return None }
  Some(@write.document(p.document(), style~))
}

///|
/// The whole point, checked on one file: markup the short way and markup the
/// long way round through the notation must be the same markup.
///
/// "The same" needs three qualifications, and every one of them is the
/// notation's design rather than a bug in the bridge:
///
///   * shrubbery has no end tags, so an implied one comes back explicit;
///   * a void element's slash is a house style, and `<br/>` comes back `<br>`;
///   * a shrubbery string holds a value and not a spelling, so `&copy;` comes
///     back as the character.
///
/// So the baseline is the tree with those three already normalised away, and
/// the normalisation is applied to BOTH sides rather than excusing one. That is
/// what makes a file that does not close a BUG: everything the notation is
/// known to be unable to say has been taken out of the comparison, so what is
/// left is something the bridge got wrong.
fn markup_loop(src : String) -> Unit {
  let p = @parse.parse(src) catch {
    e => {
      println("!error markup " + e.diagnostic().kind.code())
      return
    }
  }
  let direct = @write.document(normalise(p.document()), style=Minified)
  let shrub = @emit.document(p.document())
  let l = @lower.lower_source(shrub) catch {
    e => {
      println("!error lower " + e.diagnostic().kind.code())
      return
    }
  }
  let detour = @write.document(normalise(l.document()), style=Minified)
  if direct == detour {
    println("loop: closed")
  } else {
    println("loop: OPEN")
    println("  direct: " + direct)
    println("  detour: " + detour)
  }
}

///|
/// The same document with the three things the notation cannot say taken out.
///
/// Applied to both sides of the loop, so that what remains to compare is only
/// what the bridge is answerable for.
fn normalise(doc : @ast.Document) -> @ast.Document {
  { children: normalise_nodes(doc.children), span: doc.span, }
}

///|
fn normalise_nodes(nodes : Array[@ast.Node]) -> Array[@ast.Node] {
  let out : Array[@ast.Node] = []
  for n in nodes {
    match n {
      Element(e) => {
        let closing : @ast.Closing = match e.closing {
          Implied | Unclosed => Explicit
          SelfClosing =>
            if e.name.ns == Html && @names.is_void(e.name.name) {
              Void
            } else {
              SelfClosing
            }
          other => other
        }
        let attrs : Array[@ast.Attribute] = []
        for a in e.attrs {
          let value : @ast.AttrValue = match a.value {
            Value(v, _) => Value(v, None)
            Empty => Empty
          }
          attrs.push({ ..a, value, })
        }
        out.push(
          Element({
            ..e,
            closing,
            attrs,
            children: normalise_nodes(e.children),
          }),
        )
      }
      Text(t) => out.push(Text({ ..t, raw: None, }))
      other => out.push(other)
    }
  }
  out
}

///|
fn lower_shrub(src : String) -> Unit {
  let l = @lower.lower_source(src) catch {
    e => {
      println("!error " + e.diagnostic().kind.code())
      return
    }
  }
  for d in l.diagnostics() {
    println("! " + d.kind.code())
  }
  put(@write.document(l.document(), style=Pretty))
}

///|
fn emit_shrub(src : String) -> Unit {
  let p = @parse.parse(src) catch {
    e => {
      println("!error " + e.diagnostic().kind.code())
      return
    }
  }
  put(@emit.document(p.document()))
}

///|
/// The only oracle here with an external reference, and the one that makes the
/// markup-tree decision honest.
///
/// Everything else in this file compares the library against itself. This asks
/// a CONFORMING parser -- `moonbit-community/html`, eighty tokenizer states and
/// twenty-three insertion modes -- whether our output still means what the
/// input meant: parse both with it, and compare the document trees it builds.
///
/// That is the only property a formatter actually owes anyone. It does not
/// require our tree to be a document tree, which it deliberately is not; it
/// requires our tree to be document-EQUIVALENT. Every file where the adoption
/// agency or foster parenting changes the answer shows up here as a number
/// rather than as a paragraph of hand-waving, which is what the CSS half had to
/// settle for -- CSS has no reference implementation in MoonBit and this does.
///
/// The comparison is on `dump()`, which is the html5lib tree format: element
/// names with their namespaces, attributes sorted, text and comments in
/// document order. Comparing `Document::equal` instead would be the same claim
/// with an unreadable failure.
///
/// Printed with `whitespace=Strict`, and that is the whole design of this
/// oracle rather than a convenience. The default policy is ALLOWED to drop
/// whitespace between block-level children -- that is what a formatter is for,
/// and the dropped text nodes are real DOM nodes, so the document changes and
/// changes correctly. Measuring the tree and the policy in one number would
/// mean neither could be read. So the policy is turned off here and measured by
/// `roundtrip` instead, and what is left is the sharper claim: with the printer
/// told to move nothing, our tree round-trips through a conforming parser
/// EXACTLY, and any difference at all is a bug.
fn conform(src : String) -> Unit {
  let before = @html5.parse(src)
  let p = @parse.parse(src) catch {
    e => {
      println("!error markup " + e.diagnostic().kind.code())
      return
    }
  }
  let out = @write.document(p.document(), style=Minified, whitespace=Strict)
  let after = @html5.parse(out)
  if before.dump() == after.dump() {
    println("conform: same")
  } else {
    println("conform: DIFFERENT")
    println("  ours: " + out)
    println("--- the reference reads the input as")
    put(before.dump())
    println("--- and our output as")
    put(after.dump())
  }
}

///|
/// Parse it, print it, parse that: the claim is only that nothing crashes.
///
/// The cheapest oracle and the one that catches the most, because it can be
/// pointed at anything -- the notation's own 696-file corpus, the CSS corpus,
/// files that are not markup at all -- and a tolerant parser's whole promise is
/// about inputs nobody would write.
fn survive(src : String) -> Unit {
  let p = @parse.parse(src) catch {
    e => {
      println("!error " + e.diagnostic().kind.code())
      return
    }
  }
  let out = @write.document(p.document(), style=Minified)
  let again = @parse.parse(out) catch {
    e => {
      println("!error reparse " + e.diagnostic().kind.code())
      return
    }
  }
  ignore(again)
  // Lowering the same bytes as if they were notation: almost none of any
  // corpus is valid Shrubbery HTML, which is exactly what makes it a free
  // adversarial input for the bridge.
  let l = @lower.lower_source(src) catch {
    e => {
      println("!error lower " + e.diagnostic().kind.code())
      return
    }
  }
  ignore(@write.document(l.document(), style=Minified))
  println("survive: ok")
}

///|
/// Just the codes, for the buckets whose point is which diagnostics fire.
fn diagnose(src : String) -> Unit {
  let p = @parse.parse(src) catch {
    e => {
      println("!raised " + e.diagnostic().kind.code())
      return
    }
  }
  let ds = p.diagnostics()
  if ds.length() == 0 {
    println("(none)")
    return
  }
  for d in ds {
    println(d.kind.code())
  }
}
