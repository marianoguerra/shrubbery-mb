///|
/// The running example: an indentation complaint, with two
/// labels on different lines and a help line.
fn fixture() -> (@report.Sources, @report.SourceId) {
  let sources = @report.Sources::new()
  let id = sources.add(
    "example.txt",
    (
      #|hello:
      #|  world
      #| universe
      #|done
      #|
    ),
  )
  (sources, id)
}

///|
fn plain_config() -> @render.Config {
  { ..@render.default_config, theme: @style.mono_theme, color: Never, }
}

///|
test "rich: two labels on different lines" {
  let (sources, id) = fixture()
  let report = @report.Report::error("wrong indentation")
    .with_code("demo::wrong_indentation")
    .with_label(
      @report.Label::primary(
        id,
        @report.Span::of_range(9, 14),
        message="this group starts here",
      ),
    )
    .with_label(
      @report.Label::secondary(
        id,
        @report.Span::of_range(16, 24),
        message="but this one is less indented",
      ),
    )
    .with_help("indent every group in a block to the same column")
  inspect(
    @render.render_string(report, sources, plain_config()),
    content=(
      #|error[demo::wrong_indentation]: wrong indentation
      #|  ╭─[ example.txt:2:3 ]
      #|  │
      #|1 │ hello:
      #|2 │   world
      #|  │   ──┬──
      #|  │     ╰─ this group starts here
      #|3 │  universe
      #|  │  ───┬────
      #|  │     ╰─ but this one is less indented
      #|4 │ done
      #|  │
      #|  ├─ help: indent every group in a block to the same column
      #|  ╰─
      #|
    ),
  )
}

///|
test "rich: two labels on one line share the underline row" {
  let sources = @report.Sources::new()
  let id = sources.add("pair.txt", "f(x, y)\n")
  let report = @report.Report::error("two problems here")
    .with_label(
      @report.Label::primary(
        id,
        @report.Span::of_range(2, 3),
        message="this one",
      ),
    )
    .with_label(
      @report.Label::secondary(
        id,
        @report.Span::of_range(5, 6),
        message="and this one",
      ),
    )
  inspect(
    @render.render_string(report, sources, plain_config()),
    content=(
      #|error: two problems here
      #|  ╭─[ pair.txt:1:3 ]
      #|  │
      #|1 │ f(x, y)
      #|  │   ┬  ┬
      #|  │   │  ╰─ and this one
      #|  │   ╰─ this one
      #|  ╰─
      #|
    ),
  )
}

///|
test "rich: a multi-line label is a margin bracket, not an underline" {
  let sources = @report.Sources::new()
  let id = sources.add(
    "multi.txt",
    (
      #|outer(
      #|  a,
      #|  b
      #|
    ),
  )
  let report = @report.Report::error("unclosed delimiter")
    .with_label(
      @report.Label::primary(
        id,
        @report.Span::of_range(0, 16),
        message="this is never closed",
      ),
    )
    .with_note("every opener needs its closer on the same nesting level")
  inspect(
    @render.render_string(report, sources, plain_config()),
    content=(
      #|error: unclosed delimiter
      #|  ╭─[ multi.txt:1:1 ]
      #|  │
      #|1 │ ╭ outer(
      #|2 │ │   a,
      #|3 │ ├   b
      #|  │ ╰─ this is never closed
      #|  │
      #|  ├─ note: every opener needs its closer on the same nesting level
      #|  ╰─
      #|
    ),
  )
}

///|
test "rich: a tab is expanded before the caret is placed" {
  let sources = @report.Sources::new()
  // The label covers `y`, which sits after a tab. A renderer that counted code
  // units instead of display columns would put the caret at column 2.
  let id = sources.add("tabs.txt", "x\ty\n")
  let report = @report.Report::error("tab alignment").with_label(
    @report.Label::primary(id, @report.Span::of_range(2, 3), message="here"),
  )
  inspect(
    @render.render_string(report, sources, plain_config()),
    content=(
      #|error: tab alignment
      #|  ╭─[ tabs.txt:1:3 ]
      #|  │
      #|1 │ x       y
      #|  │         ┬
      #|  │         ╰─ here
      #|  ╰─
      #|
    ),
  )
}

///|
test "rich: a wide character costs two columns" {
  let sources = @report.Sources::new()
  // `世界` is two columns each, so the caret under `!` belongs at column 5.
  let id = sources.add("wide.txt", "世界!\n")
  let report = @report.Report::error("wide characters").with_label(
    @report.Label::primary(id, @report.Span::of_range(2, 3), message="here"),
  )
  inspect(
    @render.render_string(report, sources, plain_config()),
    content=(
      #|error: wide characters
      #|  ╭─[ wide.txt:1:3 ]
      #|  │
      #|1 │ 世界!
      #|  │     ┬
      #|  │     ╰─ here
      #|  ╰─
      #|
    ),
  )
}

///|
test "short and json are one line each" {
  let (sources, id) = fixture()
  let report = @report.Report::error("wrong indentation")
    .with_code("demo::wrong_indentation")
    .with_label(
      @report.Label::primary(id, @report.Span::of_range(16, 24), message="here"),
    )
  inspect(
    @render.render_string(report, sources, { ..plain_config(), format: Short, }),
    content=(
      #|example.txt:3:2: error[demo::wrong_indentation]: wrong indentation
      #|
    ),
  )
  inspect(
    @render.render_string(report, sources, { ..plain_config(), format: Json, }),
    content=(
      #|{"severity":"error","code":"demo::wrong_indentation","message":"wrong indentation","labels":[{"style":"primary","offset":16,"length":8,"file":"example.txt","line":3,"column":1,"end_line":3,"end_column":9,"message":"here"}]}
      #|
    ),
  )
}
