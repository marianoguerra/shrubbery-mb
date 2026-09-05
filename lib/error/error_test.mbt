///|
fn span(a : Int, b : Int) -> @basic.Span {
  {
    start: {
      line: 1,
      pos: a + 1,
      idx: a,
      col0: a,
      col: @column.Column::of_chars(a),
    },
    end: {
      line: 1,
      pos: b + 1,
      idx: b,
      col0: b,
      col: @column.Column::of_chars(b),
    },
  }
}

///|
test "reference wording is reproduced exactly, typo included" {
  // These strings are the measuring instrument for the error-parity oracle.
  // Improving one is how that oracle silently stops measuring anything.
  assert_eq(
    @err.ErrorKind::ContinuationFollowedByToken.reference_text(),
    "line-continuing '\\' is followed by a another token on the same line",
  )
  assert_eq(
    @err.ErrorKind::WrongIndentation(missing_colon_hint=true).reference_text(),
    "wrong indentation (or missing `:` on previous line)",
  )
  assert_eq(
    @err.ErrorKind::MisplacedComma(paren_immed=false).reference_text(),
    "misplaced comma (not immediately within parentheses, brackets, or braces)",
  )
  assert_eq(
    @err.ErrorKind::MisplacedComma(paren_immed=true).reference_text(),
    "misplaced comma",
  )
  assert_eq(
    @err.ErrorKind::EmptyBlock(after=":", could_empty_if_start=true).reference_text(),
    "empty block not allowed after `:` (except with `«` and `»`, at top, or in an opener-closer pair)",
  )
  // The reference formats this one with `~s`, so the closer arrives quoted.
  assert_eq(
    @err.ErrorKind::DidNotFindMatching(expected=")").reference_text(),
    "did not find matching \")\"",
  )
}

///|
test "codes are stable identifiers, not derived from prose" {
  assert_eq(
    @err.ErrorKind::WrongIndentation(missing_colon_hint=true).code(),
    "shrubbery::wrong_indentation",
  )
  // Both spellings of the same failure share a code, because a consumer
  // suppressing it means the failure and not the wording.
  assert_eq(
    @err.ErrorKind::WrongIndentation(missing_colon_hint=false).code(),
    @err.ErrorKind::WrongIndentation(missing_colon_hint=true).code(),
  )
}

///|
test "a diagnostic renders through error-report" {
  let sources = @report.Sources::new()
  let id = sources.add("t.shrub", "hello:\n  world\n universe\n")
  let d = @err.Diagnostic::new(
    WrongIndentation(missing_colon_hint=false),
    span(16, 24),
    related=[(span(9, 14), "the first group is here")],
  )
  let config = {
    ..@render.default_config,
    theme: @style.mono_theme,
    color: Never,
  }
  inspect(
    @render.render_string(d.to_report(id), sources, config),
    content=(
      #|error[shrubbery::wrong_indentation]: this group is not indented like the ones around it
      #|  ╭─[ t.shrub:3:2 ]
      #|  │
      #|1 │ hello:
      #|2 │   world
      #|  │   ──┬──
      #|  │     ╰─ the first group is here
      #|3 │  universe
      #|  │  ───┬────
      #|  │     ╰─ this column does not line up
      #|  │
      #|  ├─ help: every group in a sequence starts at the same column
      #|  ╰─
      #|
    ),
  )
}
