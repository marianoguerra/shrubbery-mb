///|
/// One diagnostic, rendered, so that the span arithmetic is checked by drawing
/// the caret rather than by asserting about numbers.

///|
/// The span of the first group in a parsed shrubbery source.
///
/// Taken from a real parse rather than hand-built: `@basic.Pos` carries five
/// fields in three different units, and a hand-made one would prove only that
/// the test and the renderer agree with each other.
fn first_span(src : String) -> @basic.Span raise {
  @shrub.parse(src).root().children()[0].span
}

///|
test "codes are namespaced apart from the CSS layer's" {
  assert_eq(
    @kind.ErrorKind::AltsUnsupported.code(),
    "shrubcss::alts_unsupported",
  )
  assert_eq(
    @kind.ErrorKind::ColonPseudo("a", "hover").code(),
    "shrubcss::colon_pseudo",
  )
}

///|
test "the hazard diagnostic names the fix" {
  let src = "a: hover\n"
  let sources = @report.Sources::new()
  let id = sources.add("t.shrubcss", src)
  let d = @err.Diagnostic::new(ColonPseudo("a", "hover"), first_span(src))
  let config = {
    ..@render.default_config,
    theme: @style.mono_theme,
    color: Never,
  }
  inspect(
    @render.render_string(d.to_report(id), sources, config),
    content=(
      #|error[shrubcss::colon_pseudo]: `a:` reads as a declaration of the property `a`
      #|  ╭─[ t.shrubcss:1:1 ]
      #|  │
      #|1 │ a: hover
      #|  │ ───┬────
      #|  │    ╰─ `hover` was read as the value
      #|  │
      #|  ├─ help: a pseudo-class is a call: write `hover()`
      #|  ╰─
      #|
    ),
  )
}

///|
test "a sigil diagnostic says what to type instead" {
  let src = ".card:\n  color: red\n"
  let sources = @report.Sources::new()
  let id = sources.add("t.shrubcss", src)
  let d = @err.Diagnostic::new(SigilSelector("."), first_span(src))
  let config = {
    ..@render.default_config,
    theme: @style.mono_theme,
    color: Never,
  }
  let out = @render.render_string(d.to_report(id), sources, config)
  assert_true(out.contains("write `class(card)` for `.card`"))
}
