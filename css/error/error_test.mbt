///|
/// Diagnostics, end to end: a kind becomes a report becomes rendered text.
///
/// The rendering test is the one that matters. Every other layer can be right
/// while the spans are off by one, and only drawing the caret shows that.

///|
fn sp(a : Int, b : Int) -> @span.Span {
  @span.Span::new(a, b)
}

///|
fn mono() -> @render.Config {
  { ..@render.default_config, theme: @style.mono_theme, color: Never, }
}

///|
test "codes are stable and namespaced" {
  assert_eq(@kind.ErrorKind::BadDeclaration.code(), "css::bad_declaration")
  assert_eq(
    @kind.ErrorKind::UnknownAtRule("tailwind").code(),
    "css::unknown_at_rule",
  )
  // The payload does not reach the code: two unknown at-rules are the same
  // kind of problem, and a harness matching on the code should see one.
  assert_eq(
    @kind.ErrorKind::UnknownAtRule("a").code(),
    @kind.ErrorKind::UnknownAtRule("b").code(),
  )
}

///|
test "severity follows from the kind, not from the call site" {
  let warn = @err.Diagnostic::of_kind(UnknownAtRule("tailwind"), sp(0, 9))
  let err = @err.Diagnostic::of_kind(BadDeclaration, sp(0, 3))
  assert_eq(warn.severity, Warning)
  assert_eq(err.severity, Error)
}

///|
test "a diagnostic renders through error-report" {
  let sources = @report.Sources::new()
  let id = sources.add("t.css", ".card {\n  color red;\n}\n")
  let d = @err.Diagnostic::new(ExpectedColon, sp(16, 19))
  inspect(
    @render.render_string(d.to_report(id), sources, mono()),
    content=(
      #|error[css::expected_colon]: a declaration needs a `:` between the property and the value
      #|  ╭─[ t.css:2:9 ]
      #|  │
      #|1 │ .card {
      #|2 │   color red;
      #|  │         ─┬─
      #|  │          ╰─ this needs a `:`
      #|3 │ }
      #|  ╰─
      #|
    ),
  )
}

///|
test "a warning names what it kept, and says so" {
  let sources = @report.Sources::new()
  let id = sources.add("t.css", "@tailwind base;\n")
  let d = @err.Diagnostic::of_kind(UnknownAtRule("tailwind"), sp(0, 9))
  inspect(
    @render.render_string(d.to_report(id), sources, mono()),
    content=(
      #|warning[css::unknown_at_rule]: `@tailwind` is not an at-rule this library knows
      #|  ╭─[ t.css:1:1 ]
      #|  │
      #|1 │ @tailwind base;
      #|  │ ────┬────
      #|  │     ╰─ kept as written
      #|  │
      #|  ├─ help: its prelude and block are kept unparsed, so nothing is lost
      #|  ╰─
      #|
    ),
  )
}

///|
test "a related label points at the second place worth looking" {
  let sources = @report.Sources::new()
  let id = sources.add("t.css", ".a {\n  color: red !important blue;\n}\n")
  let d = @err.Diagnostic::new(ImportantNotLast, sp(28, 32), related=[
    (sp(7, 17), "the declaration this belongs to"),
  ])
  inspect(
    @render.render_string(d.to_report(id), sources, mono()),
    content=(
      #|error[css::important_not_last]: `!important` must be the last thing in a value
      #|  ╭─[ t.css:2:24 ]
      #|  │
      #|1 │ .a {
      #|2 │   color: red !important blue;
      #|  │   ────┬─────           ─┬──
      #|  │       │                 ╰─ this comes after `!important`
      #|  │       ╰─ the declaration this belongs to
      #|3 │ }
      #|  │
      #|  ├─ help: write `color: red !important`
      #|  ╰─
      #|
    ),
  )
}

///|
test "strict mode raises, and the diagnostic survives the raise" {
  let d = @err.Diagnostic::of_kind(BadSelector, sp(0, 4))
  let caught = (fn() -> @err.Diagnostic? {
    (fn() -> Unit raise @err.CssError { d.raise_() })() catch {
      e => return Some(e.diagnostic())
    }
    None
  })()
  match caught {
    Some(got) => {
      assert_eq(got.kind, @kind.ErrorKind::BadSelector)
      assert_eq(got.span, sp(0, 4))
    }
    None => fail("raise_ did not raise")
  }
}
