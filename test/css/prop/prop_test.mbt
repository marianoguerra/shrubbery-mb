///|
/// The properties.
///
/// Each is a claim about the whole library rather than about one input, and
/// each is checked over trees nobody wrote down. When one fails the tree is
/// shrunk first, so the report is a counterexample small enough to read rather
/// than the two hundred nodes that happened to contain it.
///
/// The seed is a default argument on `check`, so reproducing a failure is a
/// one-literal edit.

///|
/// The default seed. Fixed, so a run is reproducible and a failure is not a
/// thing that happened once on someone's machine.
let default_seed : UInt64 = 0x5EED_C55_0001UL

///|
/// Whether two trees are the same, ignoring where they came from.
///
/// Spans cannot be compared: a generated tree has none, a parsed one has real
/// offsets, and every property here compares one of each. Comparing the printed
/// form instead is not a weakening in any way that matters -- a difference the
/// printer cannot show is a difference nobody can observe from a library whose
/// output is text.
fn same(a : @ast.Stylesheet, b : @ast.Stylesheet) -> Bool {
  @write.stylesheet(a, style=Minified) == @write.stylesheet(b, style=Minified)
}

///|
/// Run one property over generated stylesheets.
fn check(
  name : String,
  holds : (@ast.Stylesheet) -> Bool,
  runs? : Int = 120,
  max_size? : Int = 14,
  seed? : UInt64 = default_seed,
) -> Unit raise {
  let r = Rng::new(seed)
  for i in 0..<runs {
    let size = 1 + i % max_size
    let sheet = gen_stylesheet(r, size)
    if !holds(sheet) {
      let small = minimize(sheet, shrink_sheet, x => !holds(x))
      fail(
        name +
        "\n  seed=" +
        seed.to_string() +
        " run=" +
        i.to_string() +
        " size=" +
        size.to_string() +
        "\n  minimal counterexample, as CSS:\n" +
        @write.stylesheet(small, style=Pretty) +
        "\n  as shrubbery:\n" +
        @emit.stylesheet(small),
      )
    }
  }
}

// ------------------------------------------------------------------ shrinking

///|
/// Smaller stylesheets that might still fail.
///
/// Every candidate is strictly smaller under `size_of`, which is what makes
/// `minimize` terminate; the test below asserts that rather than trusting it.
fn shrink_sheet(sheet : @ast.Stylesheet) -> Array[@ast.Stylesheet] {
  let out : Array[@ast.Stylesheet] = []
  let n = sheet.items.length()
  // Drop each item.
  if n > 1 {
    for i in 0..<n {
      let items : Array[@ast.TopItem] = []
      for j in 0..<n {
        if j != i {
          items.push(sheet.items[j])
        }
      }
      out.push({ items, span: sheet.span, })
    }
  }
  // Shrink each item in place.
  for i in 0..<n {
    match sheet.items[i] {
      Rule(r) =>
        for smaller in shrink_rule(r) {
          let items : Array[@ast.TopItem] = []
          for j in 0..<n {
            items.push(if j == i { Rule(smaller) } else { sheet.items[j] })
          }
          out.push({ items, span: sheet.span, })
        }
      _ => ()
    }
  }
  out
}

///|
fn shrink_rule(r : @ast.CssRule) -> Array[@ast.CssRule] {
  let out : Array[@ast.CssRule] = []
  match r {
    Style(s) => {
      // Fewer selectors.
      if s.selectors.length() > 1 {
        out.push(Style({ ..s, selectors: [s.selectors[0]], }))
      }
      // A smaller body: drop one item at a time.
      let n = s.body.length()
      if n > 1 {
        for i in 0..<n {
          let body : Array[@ast.BlockItem] = []
          for j in 0..<n {
            if j != i {
              body.push(s.body[j])
            }
          }
          out.push(Style({ ..s, body, }))
        }
      }
      // A simpler selector.
      match s.selectors[0] {
        Complex(left, _, _) => out.push(Style({ ..s, selectors: [left], }))
        _ => ()
      }
      // A shorter value on the first declaration.
      if n > 0 {
        match s.body[0] {
          Decl(d) =>
            if d.value.length() > 1 {
              let body : Array[@ast.BlockItem] = [
                Decl({ ..d, value: [d.value[0]], }),
              ]
              for j in 1..<n {
                body.push(s.body[j])
              }
              out.push(Style({ ..s, body, }))
            }
          _ => ()
        }
      }
    }
    // A wrapping rule shrinks to what it wraps.
    Media(m) =>
      for it in m.body {
        match it {
          Rule(inner) => out.push(inner)
          _ => ()
        }
      }
    Supports(s) =>
      for it in s.body {
        match it {
          Rule(inner) => out.push(inner)
          _ => ()
        }
      }
    _ => ()
  }
  out
}

// ----------------------------------------------------------------- properties

///|
/// Parse what was printed and get the same tree back.
///
/// The base claim the whole CSS module rests on. It is stated over generated
/// trees rather than generated TEXT because the tree is what equality is
/// meaningful on -- comparing two strings would only say the printer is a
/// function.
test "P1: printing then parsing is the identity" {
  check("P1", sheet => {
    let text = @write.stylesheet(sheet, style=Pretty)
    let back = @parse.parse(text) catch { _ => return false }
    same(back.sheet(), sheet)
  })
}

///|
/// The three modes differ in whitespace and in nothing else.
test "P2: every printing mode means the same thing" {
  check("P2", sheet => {
    let pretty = @parse.parse(@write.stylesheet(sheet, style=Pretty)) catch {
      _ => return false
    }
    let mini = @parse.parse(@write.stylesheet(sheet, style=Minified)) catch {
      _ => return false
    }
    let compact = @parse.parse(@write.stylesheet(sheet, style=Compact)) catch {
      _ => return false
    }
    same(pretty.sheet(), mini.sheet()) && same(pretty.sheet(), compact.sheet())
  })
}

///|
/// Whatever the library prints, it accepts without complaint.
///
/// Separate from P1 because it is a different failure: P1 catches output that
/// parses to the wrong tree, this catches output that a strict caller would
/// reject outright.
test "P5: printed output parses strictly" {
  check("P5", sheet => {
    let text = @write.stylesheet(sheet, style=Pretty)
    let p = @parse.parse(text) catch { _ => return false }
    !p.has_errors()
  })
}

///|
/// The bridge is the identity on trees it can represent.
///
/// This is the strongest property here: it runs the tree through a different
/// syntax entirely and back, so it fails if either direction of the bridge is
/// wrong, and it fails on inputs no hand-written case reaches.
test "P3: emitting then lowering is the identity" {
  check("P3", sheet => {
    let shrub = @emit.stylesheet(sheet)
    let back = @lower.lower_source(shrub) catch { _ => return false }
    same(back.sheet(), sheet)
  })
}

// -------------------------------------------------------------- meta-properties

///|
/// The generator is deterministic.
///
/// Without this a failing seed proves nothing, because the next run would draw
/// something else -- so the whole harness rests on it.
test "the same seed draws the same tree" {
  for size in [1, 5, 14] {
    let a = gen_stylesheet(Rng::new(default_seed), size)
    let b = gen_stylesheet(Rng::new(default_seed), size)
    assert_eq(
      @write.stylesheet(a, style=Minified),
      @write.stylesheet(b, style=Minified),
    )
  }
}

///|
/// Every shrink candidate is strictly smaller.
///
/// This is `minimize`'s termination argument, checked rather than assumed. The
/// fuel bound would stop a runaway anyway, but a shrinker that did not make
/// progress would silently return the original tree and make every failure
/// report useless.
test "shrinking strictly decreases size" {
  let r = Rng::new(default_seed)
  for _ in 0..<60 {
    let sheet = gen_stylesheet(r, 12)
    let before = size_of(sheet)
    for candidate in shrink_sheet(sheet) {
      let after = size_of(candidate)
      if after >= before {
        fail(
          "a shrink candidate was not smaller: " +
          before.to_string() +
          " -> " +
          after.to_string() +
          "\n" +
          @write.stylesheet(candidate, style=Minified),
        )
      }
    }
  }
}

///|
/// The generator actually reaches the shapes the properties are meant to cover.
///
/// Without this a property can pass vacuously on a variant that is never drawn,
/// which is the failure mode of a generator nobody checks.
test "the generator covers the shapes it claims to" {
  let r = Rng::new(default_seed)
  let mut saw_media = false
  let mut saw_supports = false
  let mut saw_keyframes = false
  let mut saw_nested = false
  let mut saw_important = false
  let mut saw_custom = false
  for _ in 0..<400 {
    let sheet = gen_stylesheet(r, 12)
    let text = @write.stylesheet(sheet, style=Minified)
    if text.contains("@media") {
      saw_media = true
    }
    if text.contains("@supports") {
      saw_supports = true
    }
    if text.contains("@keyframes") {
      saw_keyframes = true
    }
    if text.contains("!important") {
      saw_important = true
    }
    if text.contains("--") {
      saw_custom = true
    }
    for item in sheet.items {
      match item {
        Rule(Style(s)) =>
          for it in s.body {
            if it is Rule(_) {
              saw_nested = true
            }
          }
        _ => ()
      }
    }
  }
  assert_true(saw_media)
  assert_true(saw_supports)
  assert_true(saw_keyframes)
  assert_true(saw_nested)
  assert_true(saw_important)
  assert_true(saw_custom)
}
