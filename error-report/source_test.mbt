///|
test "line index recognises all three terminators" {
  let src = @report.Source::new("t", "a\nb\r\nc\rd")
  assert_eq(src.line_count(), 4)
  assert_eq(src.line_text(0), "a")
  assert_eq(src.line_text(1), "b")
  assert_eq(src.line_text(2), "c")
  assert_eq(src.line_text(3), "d")
}

///|
test "a file ending in a newline has a final empty line" {
  let src = @report.Source::new("t", "a\n")
  assert_eq(src.line_count(), 2)
  assert_eq(src.line_text(1), "")
  // An end-of-input caret has somewhere to go.
  assert_eq(src.line_col(2), (2, 0))
}

///|
test "columns are code points, not code units" {
  // Each `𝔸` is one code point and two UTF-16 code units.
  let src = @report.Source::new("t", "𝔸𝔸x")
  assert_eq(src.line_col(4), (1, 2))
  assert_eq(src.offset_of_char(2), 4)
  assert_eq(src.span_of_chars(2, 3), @report.Span::of_range(4, 5))
}

///|
test "an offset past the end clamps rather than failing" {
  let src = @report.Source::new("t", "ab")
  assert_eq(src.line_of(99), 0)
  assert_eq(src.slice(@report.Span::of_range(1, 99)), "b")
  assert_eq(src.offset_of_char(99), 2)
}

///|
test "spans" {
  let a = @report.Span::of_range(2, 5)
  let b = @report.Span::of_range(5, 7)
  assert_eq(a.end(), 5)
  assert_false(a.overlaps(b))
  assert_true(a.overlaps(@report.Span::of_range(4, 6)))
  assert_eq(a.merge(b), @report.Span::of_range(2, 7))
  // An insertion point has no extent, so nothing is inside it.
  assert_false(@report.Span::at(3).overlaps(@report.Span::at(3)))
  assert_true(@report.Span::at(3).is_empty())
  // A backwards range is empty, not negative.
  assert_eq(@report.Span::of_range(5, 2).len, 0)
}

///|
test "a report keeps its data separable from its prose" {
  let sources = @report.Sources::new()
  let id = sources.add("t", "let x = 1\n")
  let r = @report.Report::warning("unused binding")
    .with_code("demo::unused")
    .with_label(@report.Label::primary(id, @report.Span::of_range(4, 5)))
    .with_fix({
      source: id,
      span: @report.Span::of_range(4, 5),
      replacement: "_x",
      description: "prefix with an underscore",
    })
  // A consumer that wants structure never has to read the rendered text.
  assert_eq(r.severity, Warning)
  assert_eq(r.code, Some("demo::unused"))
  assert_eq(r.fixes[0].replacement, "_x")
  assert_true(r.anchor() is Some(_))
}

///|
test "anchor prefers a primary label but never gives up" {
  let sources = @report.Sources::new()
  let id = sources.add("t", "ab\n")
  let only_secondary = @report.Report::error("m").with_label(
    @report.Label::secondary(id, @report.Span::at(1)),
  )
  assert_true(only_secondary.anchor() is Some(_))
  assert_true(@report.Report::error("m").anchor() is None)
}
