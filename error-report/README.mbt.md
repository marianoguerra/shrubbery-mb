# error-report

Source-annotated diagnostic reports for MoonBit, in the lineage of Rust's
[miette](https://docs.rs/miette), [codespan-reporting](https://docs.rs/codespan-reporting)
and [ariadne](https://docs.rs/ariadne).

**Data first, renderers second.** A `Report` is a plain value: severity, a stable
code, a message, labelled spans, notes, a help line, and machine-applicable
fixes. A consumer that wants to build its own presentation reads the fields and
never calls a renderer. A consumer that just wants something good to print in a
terminal calls `render` and is done.

## Installing

```sh
moon add marianoguerra/error-report
```

The module name contains a dash, so it cannot be referenced under its default
alias. Give it one in the `moon.pkg` of each package that uses it:

```
import {
  "marianoguerra/error-report" @report,
  "marianoguerra/error-report/render",
}
```

## A report

```mbt check
///|
test {
  let sources = @report.Sources::new()
  let id = sources.add("greeting.txt", "hello:\n  world\n universe\n")
  let r = @report.Report::error("wrong indentation")
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
  let config = {
    ..@render.default_config,
    theme: @style.mono_theme,
    color: Never,
  }
  inspect(
    @render.render_string(r, sources, config),
    content=(
      #|error[demo::wrong_indentation]: wrong indentation
      #|  ╭─[ greeting.txt:2:3 ]
      #|  │
      #|1 │ hello:
      #|2 │   world
      #|  │   ──┬──
      #|  │     ╰─ this group starts here
      #|3 │  universe
      #|  │  ───┬────
      #|  │     ╰─ but this one is less indented
      #|  │
      #|  ├─ help: indent every group in a block to the same column
      #|  ╰─
      #|
    ),
  )
}
```

## A span that crosses lines

An underline cannot say "from here to there" across a line break without lying
about the columns in between, so a multi-line label is drawn as a bracket in a
left margin instead.

```mbt check
///|
test {
  let sources = @report.Sources::new()
  let id = sources.add("call.txt", "outer(\n  a,\n  b\n")
  let r = @report.Report::error("unclosed delimiter").with_label(
    @report.Label::primary(
      id,
      @report.Span::of_range(0, 16),
      message="this is never closed",
    ),
  )
  let config = {
    ..@render.default_config,
    theme: @style.mono_theme,
    color: Never,
  }
  inspect(
    @render.render_string(r, sources, config),
    content=(
      #|error: unclosed delimiter
      #|  ╭─[ call.txt:1:1 ]
      #|  │
      #|1 │ ╭ outer(
      #|2 │ │   a,
      #|3 │ ├   b
      #|  │ ╰─ this is never closed
      #|  ╰─
      #|
    ),
  )
}
```

## Other formats

`Format::Short` is one line per report, in the shape editors and `grep` already
understand. `Format::Json` is one JSON object per line. `Format::Compact` is the
headed message with no source snippet, for when the source is not to hand or a
hundred reports are being listed.

```mbt check
///|
test {
  let sources = @report.Sources::new()
  let id = sources.add("greeting.txt", "hello:\n  world\n universe\n")
  let r = @report.Report::error("wrong indentation")
    .with_code("demo::wrong_indentation")
    .with_label(@report.Label::primary(id, @report.Span::of_range(16, 24)))
  let config = {
    ..@render.default_config,
    theme: @style.mono_theme,
    color: Never,
    format: Short,
  }
  inspect(
    @render.render_string(r, sources, config),
    content=(
      #|greeting.txt:3:2: error[demo::wrong_indentation]: wrong indentation
      #|
    ),
  )
}
```

## Units

Every offset in this library is a **UTF-16 code unit** offset into the source
`String` — the unit `String::length`, `String::at` and `String::get_view` use, so
slicing carries no hidden conversion.

That will surprise anyone coming from a library in a language whose strings are
bytes. A producer counting something else converts once, at the boundary:
`Source::span_of_chars` takes code-point offsets, which is what Racket's
`port-next-location` and most hand-written lexers report. Converting at the
boundary is cheap; converting inside the renderer, on every label of every
report, is not.

Rendered **columns** are a third thing again: display columns, with tabs
expanded and East Asian Wide characters counted as two, so that a caret lands
under the character it means.

## Colour

`render` takes `is_tty` as a parameter rather than detecting it. This library
has no dependencies and so cannot see a file descriptor; guessing would either
strip colour from a terminal or write escape codes into a redirected file, and
both are worse than asking. `ColorMode::Auto` resolves against whatever the
caller passes.

## Extending

`SourceCache` is the single extension point — a trait over
`(SourceId) -> Source?`. Implement it to read from disk, or from an editor's
unsaved buffers. `Sources` is the in-memory implementation and is what most
callers want.

There is deliberately nothing else to extend: no callback into the consumer, and
no genericity over a consumer-supplied error type.

## Licence

Apache-2.0.
