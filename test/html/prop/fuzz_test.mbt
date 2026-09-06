///|
/// A mutational fuzzer, for the property no generator can state.
///
/// Everything else here generates a well-formed tree and checks that something
/// is preserved. This does the opposite: it takes text that is nearly markup,
/// breaks it, and checks that the library still comes back. Tolerant parsing is
/// a promise about *any* input, and the only way to test a promise about any
/// input is to try inputs nobody would write.
///
/// The mutations are the ones that historically break parsers: delete a
/// character, duplicate a run, insert a structural character somewhere it does
/// not belong, truncate mid-token, and splice two files together. Structural
/// characters are weighted heavily, because an unbalanced `<` is what turns a
/// recovery loop into a hang.
///
/// It is seeded and deterministic, so a crash is reproducible from the printed
/// seed rather than being a thing that happened once.

///|
/// Text to break: small, and covering every construct the parser branches on.
fn seeds() -> Array[String] {
  [
    "<div class=\"card\"><p>hi</p></div>", "<ul><li>one<li>two</ul>", "<table><tr><td>a<tr><td>b</table>",
    "<input type=checkbox checked><br/>", "<script>if (a < b) { f(\"</p>\") }</script>",
    "<style>.a > .b { c: \"d\" }</style>", "<!DOCTYPE html><html><head><title>T</title></head><body>x</body></html>",
    "<!-- a --><!--[if IE]>b<![endif]-->", "<svg viewBox=\"0 0 1 1\"><circle r=\"1\"/><![CDATA[x]]></svg>",
    "<math><mfrac><mi>a</mi><mn>2</mn></mfrac></math>", "<p>a &amp; b &nbsp; &notin; &#147; &#xZZ;</p>",
    "<a href=/x/ title='q'>link</a>", "<svg><foreignObject><br></foreignObject></svg>",
    "<textarea>&amp;</textarea><title>&lt;</title>", "<my-element attr=1><slot></slot></my-element>",
    "<?php echo 1; ?><!x><>",
  ]
}

///|
/// The characters that break structure rather than content.
fn structural() -> Array[String] {
  [
    "<", ">", "</", "/>", "=", "\"", "'", "&", ";", "#", "!", "-", "--", "[", "]",
    "\n", " ", "\u{0}",
  ]
}

///|
/// One mutation of `src`.
fn mutate(r : @prop.Rng, src : String, others : Array[String]) -> String {
  let n = src.length()
  if n == 0 {
    return r.pick(structural())
  }
  match r.below(6) {
    // Delete a character.
    0 => {
      let i = r.below(n)
      src.clamped_view(end=i).to_owned() +
      src.clamped_view(start=i + 1).to_owned()
    }
    // Duplicate a run: the cheapest way to unbalance a tag.
    1 => {
      let i = r.below(n)
      let len = 1 + r.below(6)
      let run = src.clamped_view(start=i, end=i + len).to_owned()
      src.clamped_view(end=i).to_owned() +
      run +
      src.clamped_view(start=i).to_owned()
    }
    // Insert a structural character.
    2 => {
      let i = r.below(n + 1)
      src.clamped_view(end=i).to_owned() +
      r.pick(structural()) +
      src.clamped_view(start=i).to_owned()
    }
    // Truncate, which lands mid-tag as often as not.
    3 => src.clamped_view(end=r.below(n)).to_owned()
    // Splice two seeds, so a construct ends inside another.
    4 => {
      let other = r.pick(others)
      let i = r.below(n)
      let j = r.below(other.length() + 1)
      src.clamped_view(end=i).to_owned() +
      other.clamped_view(start=j).to_owned()
    }
    // Repeat the whole thing, to find anything quadratic or stateful.
    _ => src + src
  }
}

///|
/// A tolerant parse terminates and yields a document, whatever it is given --
/// and whatever it yields can be printed, and reparsed.
test "fuzz: the markup parser survives anything" {
  let r = @prop.Rng::new(default_seed)
  let base = seeds()
  let mut src = r.pick(base)
  for _ in 0..<3000 {
    src = mutate(r, src, base)
    // Keep it from growing without bound: the doubling mutation is there to
    // find quadratic behaviour, not to run out of memory.
    if src.length() > 4000 {
      src = r.pick(base)
      continue
    }
    let p = @parse.parse(src) catch {
      // Tolerant mode must not raise. If it ever does, the input is the bug
      // report, so it goes in the message.
      e => {
        fail(
          "tolerant parse raised " + e.diagnostic().kind.code() + " on:\n" + src,
        )
        continue
      }
    }
    // Printing must survive whatever came back, and reparsing that must too --
    // which is where an unbalanced `Bogus` would show.
    let out = @write.document(p.document(), style=Minified)
    let _ = @parse.parse(out) catch {
      e =>
        fail(
          "reparsing our own output raised " +
          e.diagnostic().kind.code() +
          "\n  input:  " +
          src +
          "\n  output: " +
          out,
        )
    }
  }
}

///|
/// The same, for the bridge: a lowering must survive any notation at all.
///
/// The input here is shrubbery rather than markup, so most of it is nowhere
/// near Shrubbery HTML -- which is the point. `test/corpus` already proves this
/// over 696 real files; this covers the shapes a hand-written corpus does not
/// have.
test "fuzz: the lowering survives anything the notation accepts" {
  let r = @prop.Rng::new(default_seed + 1UL)
  let base = [
    "div(class: \"card\"):\n  p(): \"hi\"\n", "ul():\n  li(): \"one\"\n  li(): \"two\"\n",
    "input(type: \"checkbox\", checked)\n", "script():\n  @{\n    if (a < b) { go() }\n  }\n",
    "svg(viewBox: \"0 0 1 1\"):\n  circle(r: 1)\n", "comment(\" x \")\ndoctype()\n",
    "element(\"text\", x: 1):\n  \"a\"\n", "p(): \"a\" br() \"b\"\n",
  ]
  let mut src = r.pick(base)
  for _ in 0..<2000 {
    src = mutate(r, src, base)
    if src.length() > 3000 {
      src = r.pick(base)
      continue
    }
    let l = @lower.lower_source(src) catch {
      e => {
        fail("lowering raised " + e.diagnostic().kind.code() + " on:\n" + src)
        continue
      }
    }
    let _ = @write.document(l.document(), style=Minified)
  }
}

///|
/// And the loop, on whatever survived: notation out of a fuzzed document must
/// lower again.
///
/// The two above check that nothing crashes. This checks the harder thing: that
/// the notation the emitter writes for a tree it has never seen is notation the
/// lowering can read. A `Bogus` carrying arbitrary bytes is the interesting
/// case, and it is exactly what a fuzzed input produces.
test "fuzz: emitted notation always lowers" {
  let r = @prop.Rng::new(default_seed + 2UL)
  let base = seeds()
  let mut src = r.pick(base)
  for _ in 0..<1500 {
    src = mutate(r, src, base)
    if src.length() > 2000 {
      src = r.pick(base)
      continue
    }
    let p = @parse.parse(src) catch { _ => continue }
    let shrub = @emit.document(p.document())
    let l = @lower.lower_source(shrub) catch {
      e => {
        fail(
          "lowering our own notation raised " +
          e.diagnostic().kind.code() +
          "\n  input:    " +
          src +
          "\n  notation: " +
          shrub,
        )
        continue
      }
    }
    let _ = @write.document(l.document(), style=Minified)
  }
}
