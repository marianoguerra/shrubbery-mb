///|
/// A single-line label, resolved to display columns on one line.
priv struct InlineLabel {
  line : Int
  start_col : Int
  end_col : Int
  style : @report.LabelStyle
  message : String?
  priority : Int
}

///|
/// A label whose span crosses a line boundary. Drawn as a bracket in a left
/// margin rather than as an underline, because an underline cannot express
/// "from here to there" across lines without lying about the columns in
/// between.
priv struct BlockLabel {
  start_line : Int
  end_line : Int
  /// Which margin column this label's bracket occupies. Assigned so that two
  /// overlapping block labels never share one.
  margin : Int
  style : @report.LabelStyle
  message : String?
}

///|
/// Everything the snippet renderer needs about one source file.
priv struct Snippet {
  src : @report.Source
  inline : Array[InlineLabel]
  blocks : Array[BlockLabel]
  /// Ascending, deduplicated line numbers to print.
  lines : Array[Int]
  margin_width : Int
  gutter_width : Int
  /// Where the frame header points.
  anchor_line : Int
  anchor_col : Int
}

///|
/// The human-facing renderer: a headed message and an annotated source snippet.
pub fn rich(
  report : @report.Report,
  cache : &@report.SourceCache,
  config : Config,
  buf : StringBuilder,
  is_tty? : Bool = false,
) -> Unit {
  rich_at(report, cache, config, buf, is_tty~, indent="")
}

///|
/// `rich`, with every line prefixed by `indent`.
///
/// Related reports are rendered through this at a deeper indent, which is what
/// makes "see also" nesting readable without a second code path.
fn rich_at(
  report : @report.Report,
  cache : &@report.SourceCache,
  config : Config,
  buf : StringBuilder,
  is_tty~ : Bool,
  indent~ : String,
) -> Unit {
  let color = config.use_color(is_tty~)
  let theme = config.theme
  let chars = config.chars

  // Header: `error[code]: message`
  buf.write_string(indent)
  severity_style(theme, report.severity).write(
    buf,
    report.severity.name(),
    color~,
  )
  match report.code {
    Some(code) => theme.code.write(buf, "[\{code}]", color~)
    None => ()
  }
  buf.write_string(": ")
  theme.message.write(buf, report.message, color~)
  buf.write_char('\n')

  let snippets = if config.format is Compact {
    []
  } else {
    build_snippets(report, cache, config)
  }
  for snip in snippets {
    write_snippet(snip, config, buf, color~, indent~)
  }

  // Trailer. When a snippet was drawn the trailer hangs off its frame; with no
  // snippet it is indented under the header instead, since there is no frame to
  // hang from.
  let framed = snippets.length() > 0
  let pad = if framed {
    " ".repeat(snippets[snippets.length() - 1].gutter_width + 1)
  } else {
    "  "
  }
  let has_trailer = report.help is Some(_) ||
    report.notes.length() > 0 ||
    report.url is Some(_)
  if framed && has_trailer {
    buf.write_string(indent)
    buf.write_string(pad)
    theme.gutter.write(buf, chars.vbar.to_string(), color~)
    buf.write_char('\n')
  }
  match report.help {
    Some(h) =>
      trailer_line(
        buf,
        indent,
        pad,
        framed,
        config,
        color,
        theme.help,
        "help",
        h,
      )
    None => ()
  }
  for n in report.notes {
    trailer_line(buf, indent, pad, framed, config, color, theme.note, "note", n)
  }
  match report.url {
    Some(u) =>
      trailer_line(buf, indent, pad, framed, config, color, theme.url, "see", u)
    None => ()
  }
  if framed {
    buf.write_string(indent)
    buf.write_string(pad)
    theme.gutter.write(buf, "\{chars.bottom_left}\{chars.hbar}", color~)
    buf.write_char('\n')
  }
  for rel in report.related {
    rich_at(rel, cache, config, buf, is_tty~, indent=indent + "  ")
  }
}

///|
fn trailer_line(
  buf : StringBuilder,
  indent : String,
  pad : String,
  framed : Bool,
  config : Config,
  color : Bool,
  style : @style.Style,
  tag : String,
  text : String,
) -> Unit {
  buf.write_string(indent)
  buf.write_string(pad)
  if framed {
    config.theme.gutter.write(
      buf,
      "\{config.chars.left_tee}\{config.chars.hbar} ",
      color~,
    )
  } else {
    buf.write_string("  ")
  }
  style.write(buf, "\{tag}: ", color~)
  buf.write_string(text)
  buf.write_char('\n')
}

///|
/// Group the report's labels by source and resolve every one to line/column.
///
/// Sources come out in first-appearance order rather than sorted: the producer
/// put the primary label first for a reason, and reordering by file name would
/// bury it.
fn build_snippets(
  report : @report.Report,
  cache : &@report.SourceCache,
  config : Config,
) -> Array[Snippet] {
  let order : Array[@report.SourceId] = []
  let grouped : Map[@report.SourceId, Array[@report.Label]] = Map([])
  for label in report.labels {
    match grouped.get(label.source) {
      Some(a) => a.push(label)
      None => {
        order.push(label.source)
        grouped[label.source] = [label]
      }
    }
  }
  let out : Array[Snippet] = []
  for id in order {
    match cache.fetch(id) {
      // A label pointing at a source the cache does not have is not an error:
      // it means the caller chose not to supply that file. Drop the snippet and
      // keep the message, which is still worth printing.
      None => ()
      Some(src) => out.push(build_snippet(src, grouped[id], config))
    }
  }
  out
}

///|
fn build_snippet(
  src : @report.Source,
  labels : Array[@report.Label],
  config : Config,
) -> Snippet {
  let inline : Array[InlineLabel] = []
  let blocks : Array[BlockLabel] = []
  let must_show : Map[Int, Bool] = Map([])
  for label in labels {
    let start_line = src.line_of(label.span.start)
    // An empty span sits between two characters; a non-empty one ends at the
    // last character it covers. Using `end` directly for a non-empty span would
    // attribute a span ending exactly at a newline to the following line.
    let last = if label.span.len == 0 {
      label.span.start
    } else {
      label.span.end() - 1
    }
    let end_line = src.line_of(last)
    if start_line == end_line {
      let (start_col, end_col) = columns(src, start_line, label.span, config)
      inline.push({
        line: start_line,
        start_col,
        end_col,
        style: label.style,
        message: label.message,
        priority: label.priority,
      })
      must_show[start_line] = true
    } else {
      blocks.push({
        start_line,
        end_line,
        margin: 0,
        style: label.style,
        message: label.message,
      })
      must_show[start_line] = true
      must_show[end_line] = true
      // Show the interior only when it is short enough to be worth reading.
      // Past that it is noise, and the two ends plus an ellipsis say more.
      if end_line - start_line <= 8 {
        for l in (start_line + 1)..<end_line {
          must_show[l] = true
        }
      }
    }
  }
  assign_margins(blocks)
  let lines = expand_context(must_show, src, config.context_lines)
  let max_line = if lines.length() > 0 { lines[lines.length() - 1] } else { 0 }
  let (anchor_line, anchor_col) = src.line_col(
    if labels.length() > 0 {
      labels[0].span.start
    } else {
      0
    },
  )
  {
    src,
    inline,
    blocks,
    lines,
    margin_width: margin_width_of(blocks),
    gutter_width: digits(max_line + 1),
    anchor_line,
    anchor_col: anchor_col + 1,
  }
}

///|
/// Display columns of a span within one line, tabs expanded.
fn columns(
  src : @report.Source,
  line : Int,
  span : @report.Span,
  config : Config,
) -> (Int, Int) {
  let text = src.line_text(line)
  let line_start = src.line_starts[line]
  let (_, cols) = expand_tabs(text, config.tab_width)
  let s = clamp(span.start - line_start, 0, cols.length() - 1)
  let e = clamp(span.end() - line_start, 0, cols.length() - 1)
  let start_col = cols[s]
  // A zero-width span still needs one column to point at, or the caret has
  // nothing to sit under.
  let end_col = if cols[e] > start_col { cols[e] } else { start_col + 1 }
  (start_col, end_col)
}

///|
fn clamp(v : Int, lo : Int, hi : Int) -> Int {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}

///|
fn digits(n : Int) -> Int {
  let mut d = 1
  let mut v = n
  while v >= 10 {
    v = v / 10
    d = d + 1
  }
  d
}

///|
/// Give each block label a margin column, reusing a column once its previous
/// occupant has closed. Longest spans go furthest left, so brackets nest rather
/// than cross.
fn assign_margins(blocks : Array[BlockLabel]) -> Unit {
  blocks.sort_by((a, b) => {
    let da = a.end_line - a.start_line
    let db = b.end_line - b.start_line
    if da != db {
      db - da
    } else {
      a.start_line - b.start_line
    }
  })
  // `ends[i]` is the last line still occupied by margin column `i`.
  let ends : Array[Int] = []
  for i in 0..<blocks.length() {
    let b = blocks[i]
    let mut placed = -1
    for c in 0..<ends.length() {
      if ends[c] < b.start_line {
        placed = c
        break
      }
    }
    if placed < 0 {
      ends.push(b.end_line)
      placed = ends.length() - 1
    } else {
      ends[placed] = b.end_line
    }
    blocks[i] = { ..b, margin: placed, }
  }
}

///|
fn margin_width_of(blocks : Array[BlockLabel]) -> Int {
  let mut w = 0
  for b in blocks {
    if b.margin + 1 > w {
      w = b.margin + 1
    }
  }
  w
}

///|
/// Add `context` lines either side of every must-show line, clamp to the file,
/// and return them sorted.
fn expand_context(
  must_show : Map[Int, Bool],
  src : @report.Source,
  context : Int,
) -> Array[Int] {
  let want : Map[Int, Bool] = Map([])
  let last = src.line_count() - 1
  for line, _ in must_show {
    for l in (line - context)..<=(line + context) {
      if l < 0 || l > last {
        continue
      }
      // A file ending in a newline has a final empty line. It is real -- a
      // label can point at it, which is where an unexpected-end-of-input caret
      // goes -- but showing it as CONTEXT is pure noise: every snippet near the
      // end of a file would gain a blank row.
      if l == last && !must_show.contains(l) && src.line_text(l) == "" {
        continue
      }
      want[l] = true
    }
  }
  let out : Array[Int] = []
  for line, _ in want {
    out.push(line)
  }
  out.sort()
  out
}
