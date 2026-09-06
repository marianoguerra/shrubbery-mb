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
  assert_eq(@kind.ErrorKind::EofInTag.code(), "html::eof_in_tag")
  assert_eq(
    @kind.ErrorKind::UnclosedElement("div").code(),
    "html::unclosed_element",
  )
  // The payload does not reach the code: two unclosed elements are the same
  // kind of problem, and a harness matching on the code should see one.
  assert_eq(
    @kind.ErrorKind::UnclosedElement("a").code(),
    @kind.ErrorKind::UnclosedElement("b").code(),
  )
}

///|
test "severity follows from the kind, not from the call site" {
  // A stray end tag is what a large fraction of the real web looks like.
  let warn = @err.Diagnostic::of_kind(StrayEndTag("span"), sp(0, 7))
  let err = @err.Diagnostic::of_kind(UnclosedElement("div"), sp(0, 5))
  assert_eq(warn.severity, Warning)
  assert_eq(err.severity, Error)
  assert_false(warn.is_error())
  assert_true(err.is_error())
}

///|
test "a diagnostic renders through error-report" {
  let sources = @report.Sources::new()
  let id = sources.add("t.html", "<div>\n  <span>x\n</div>\n")
  let d = @err.Diagnostic::new(UnclosedElement("span"), sp(9, 13))
  inspect(
    @render.render_string(d.to_report(id), sources, mono()),
    content=(
      #|error[html::unclosed_element]: this `<span>` is never closed
      #|  ╭─[ t.html:2:4 ]
      #|  │
      #|1 │ <div>
      #|2 │   <span>x
      #|  │    ─┬──
      #|  │     ╰─ opened here
      #|3 │ </div>
      #|  ╰─
      #|
    ),
  )
}

///|
test "a warning carries its help, which is the part worth reading" {
  let sources = @report.Sources::new()
  let id = sources.add("t.html", "<div/>\n")
  let d = @err.Diagnostic::of_kind(NonVoidSelfClosing("div"), sp(0, 6))
  inspect(
    @render.render_string(d.to_report(id), sources, mono()),
    content=(
      #|warning[html::non_void_self_closing]: the `/` in `<div/>` does nothing
      #|  ╭─[ t.html:1:1 ]
      #|  │
      #|1 │ <div/>
      #|  │ ──┬───
      #|  │   ╰─ read as a start tag
      #|  │
      #|  ├─ help: HTML has no self-closing tags: write `</div>`
      #|  ╰─
      #|
    ),
  )
}
