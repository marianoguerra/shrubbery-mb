///|
/// A mutational fuzzer, for the property no generator can state.
///
/// Everything else here generates a well-formed tree and checks that something
/// is preserved. This does the opposite: it takes text that is nearly CSS,
/// breaks it, and checks that the library still comes back. Tolerant parsing is
/// a promise about *any* input, and the only way to test a promise about any
/// input is to try inputs nobody would write.
///
/// The mutations are the ones that historically break parsers: delete a
/// character, duplicate one, insert a structural character somewhere it does
/// not belong, truncate mid-token, and splice two files together. Structural
/// characters are weighted heavily, because an unbalanced brace is what turns a
/// recovery loop into a hang.
///
/// It is seeded and deterministic, so a crash is reproducible from the printed
/// seed rather than being a thing that happened once.

///|
/// Text to break: small, and covering every construct the parser branches on.
fn seeds() -> Array[String] {
  [
    ".card { display: grid; gap: 1rem }", "@media (width <= 40rem) { .c { p: 1rem } }",
    "@supports not (display: grid) { a { b: c } }", "@keyframes fade { from { o: 0 } to { o: 1 } }",
    "@import url(\"a.css\") layer(base) screen;", "a:not(.x, .y)::before { content: \"\\2197\" }",
    "input[type=\"text\" i]:nth-child(2n-1) { border: 1px solid #ccc }", ":root { --brand: oklch(0.62 0.19 258); color: var(--brand, red) }",
    "a { b: calc(100% - 2rem) / 1 2 3 !important }", "@font-face { src: url(a.woff2) format(\"woff2\") }",
    "/* comment */ a { /* inner */ b: c }", "@unknown x y { a { b: c } } @other;",
    "svg|circle, *|a, |b { x: y }", "a { color: red; &:hover { color: blue } margin: 0 }",
  ]
}

///|
/// The characters that break structure rather than content.
fn structural() -> Array[String] {
  [
    "{", "}", "(", ")", "[", "]", ";", ":", ",", "\"", "'", "\\", "/", "*", "@",
    "#", "!", "\n", " ",
  ]
}

///|
/// One mutation of `src`.
fn mutate(r : Rng, src : String, others : Array[String]) -> String {
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
    // Duplicate a run: the cheapest way to unbalance a bracket.
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
    // Truncate, which lands mid-token as often as not.
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
/// P6: a tolerant parse terminates and yields a stylesheet, whatever it is
/// given -- and whatever it yields can be printed, and printed again.
test "fuzz: the CSS parser survives anything" {
  let r = Rng::new(default_seed)
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
    // Printing must survive whatever came back, in every mode, and reparsing
    // that must survive too -- which is where an unbalanced `Bogus` would show.
    let out = @write.stylesheet(p.sheet(), style=Minified)
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
/// The input here is shrubbery rather than CSS, so most of it is nowhere near
/// Shrubbery CSS -- which is the point. `test/corpus` already proves this over
/// 696 real files; this covers the shapes a hand-written corpus does not have.
test "fuzz: the lowering survives anything the notation accepts" {
  let r = Rng::new(default_seed + 1UL)
  let base = [
    "class(card):\n  gap: rem(1)\n", "media(width <= rem(40)):\n  a:\n    b: c\n",
    "[h1, h2]:\n  a: b\n", "nav ~in a hover():\n  color: hex(fff)\n", "at(\"x\", y):\n  a: b\n",
    "a:\n  p: [1, 2] / 3 important()\n", "keyframes(f):\n  percent(0):\n    o: 0\n",
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
    let _ = @write.stylesheet(l.sheet(), style=Minified)
  }
}
