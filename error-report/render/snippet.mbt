///|
/// Draw one file's frame, source lines and annotations.
fn write_snippet(
  snip : Snippet,
  config : Config,
  buf : StringBuilder,
  color~ : Bool,
  indent~ : String,
) -> Unit {
  let chars = config.chars
  let theme = config.theme
  let gutter = theme.gutter
  let pad = " ".repeat(snip.gutter_width + 1)

  // ╭─[ name:line:col ]
  buf.write_string(indent)
  buf.write_string(pad)
  gutter.write(buf, "\{chars.top_left}\{chars.hbar}[ ", color~)
  buf.write_string("\{snip.src.name}:\{snip.anchor_line}:\{snip.anchor_col}")
  gutter.write(buf, " ]", color~)
  buf.write_char('\n')
  blank_gutter(buf, indent, pad, config, color)

  let mut prev = -1
  for line in snip.lines {
    if prev >= 0 && line > prev + 1 {
      buf.write_string(indent)
      buf.write_string(pad)
      gutter.write(buf, chars.ellipsis.to_string(), color~)
      buf.write_char('\n')
    }
    prev = line
    write_source_line(snip, line, config, buf, color~, indent~)
    write_underlines(snip, line, config, buf, color~, indent~)
    write_block_messages(snip, line, config, buf, color~, indent~)
  }
}

///|
fn blank_gutter(
  buf : StringBuilder,
  indent : String,
  pad : String,
  config : Config,
  color : Bool,
) -> Unit {
  buf.write_string(indent)
  buf.write_string(pad)
  config.theme.gutter.write(buf, config.chars.vbar.to_string(), color~)
  buf.write_char('\n')
}

///|
/// ` 12 │ ` — the line number, right-aligned, and the frame bar.
fn write_line_head(
  snip : Snippet,
  line : Int?,
  config : Config,
  buf : StringBuilder,
  color~ : Bool,
  indent~ : String,
) -> Unit {
  buf.write_string(indent)
  let label = match line {
    Some(l) => (l + 1).to_string()
    None => ""
  }
  let width = snip.gutter_width
  for _ in 0..<(width - label.length()) {
    buf.write_char(' ')
  }
  config.theme.gutter.write(buf, label, color~)
  buf.write_char(' ')
  config.theme.gutter.write(buf, config.chars.vbar.to_string(), color~)
  buf.write_char(' ')
}

///|
/// The left margin: one column per concurrent multi-line label.
fn write_margin(
  snip : Snippet,
  line : Int,
  config : Config,
  buf : StringBuilder,
  color~ : Bool,
  closing? : Int = -1,
) -> Unit {
  if snip.margin_width == 0 {
    return
  }
  let chars = config.chars
  // On a closing row the elbow is drawn at `closing` and everything to its
  // right -- including the separator that normally follows the margin -- is
  // filled with the horizontal rule, so the corner runs unbroken into the
  // message. Anything else leaves a gap that reads as two separate marks.
  let mut closing_style = config.theme.gutter
  for c in 0..<snip.margin_width {
    let mut drawn = false
    for b in snip.blocks {
      if b.margin != c {
        continue
      }
      if c == closing {
        closing_style = label_style(config, b.style)
        closing_style.write(buf, chars.elbow.to_string(), color~)
        drawn = true
        break
      }
      if line >= b.start_line && line <= b.end_line {
        let ch = if line == b.start_line {
          chars.multi_top
        } else if line == b.end_line {
          chars.multi_end
        } else {
          chars.multi_mid
        }
        label_style(config, b.style).write(buf, ch.to_string(), color~)
        drawn = true
        break
      }
    }
    if !drawn {
      if c > closing && closing >= 0 {
        closing_style.write(buf, chars.hbar.to_string(), color~)
      } else {
        buf.write_char(' ')
      }
    }
  }
  if closing >= 0 {
    closing_style.write(buf, chars.hbar.to_string(), color~)
  } else {
    buf.write_char(' ')
  }
}

///|
fn write_source_line(
  snip : Snippet,
  line : Int,
  config : Config,
  buf : StringBuilder,
  color~ : Bool,
  indent~ : String,
) -> Unit {
  write_line_head(snip, Some(line), config, buf, color~, indent~)
  write_margin(snip, line, config, buf, color~)
  let (text, _) = expand_tabs(snip.src.line_text(line), config.tab_width)
  config.theme.source.write(buf, text, color~)
  buf.write_char('\n')
}

///|
fn label_style(config : Config, style : @report.LabelStyle) -> @style.Style {
  match style {
    Primary => config.theme.primary
    Secondary => config.theme.secondary
  }
}

///|
/// The underline row for a line, then one row per label message.
fn write_underlines(
  snip : Snippet,
  line : Int,
  config : Config,
  buf : StringBuilder,
  color~ : Bool,
  indent~ : String,
) -> Unit {
  let here : Array[InlineLabel] = []
  for l in snip.inline {
    if l.line == line {
      here.push(l)
    }
  }
  if here.length() == 0 {
    return
  }
  // Left to right, and where two start at the same column the higher priority
  // is drawn last so it wins the overlap.
  here.sort_by((a, b) => {
    if a.start_col != b.start_col {
      a.start_col - b.start_col
    } else {
      a.priority - b.priority
    }
  })
  let chars = config.chars
  let width = {
    let mut w = 0
    for l in here {
      if l.end_col > w {
        w = l.end_col
      }
    }
    w
  }
  // `owner[c]` is the index into `here` of the label drawn at column `c`, or
  // -1. Building the row before writing it is what lets adjacent columns with
  // the same owner share one styled write instead of one per character.
  let row = Array::make(width, ' ')
  let owner = Array::make(width, -1)
  for i in 0..<here.length() {
    let l = here[i]
    let u = match l.style {
      Primary => chars.primary_underline
      Secondary => chars.secondary_underline
    }
    for c in l.start_col..<l.end_col {
      row[c] = u
      owner[c] = i
    }
    if l.message is Some(_) {
      row[stem_col(l)] = chars.stem_top
    }
  }
  write_line_head(snip, None, config, buf, color~, indent~)
  write_margin(snip, line, config, buf, color~)
  write_row(row, owner, here, config, buf, color~)
  buf.write_char('\n')

  // Messages, rightmost first, so each one's stem is shorter than the last.
  let with_msg : Array[Int] = []
  for i in 0..<here.length() {
    if here[i].message is Some(_) {
      with_msg.push(i)
    }
  }
  with_msg.sort_by((a, b) => stem_col(here[b]) - stem_col(here[a]))
  for k in 0..<with_msg.length() {
    let idx = with_msg[k]
    let l = here[idx]
    let col = stem_col(l)
    let row2 = Array::make(col + 1, ' ')
    let owner2 = Array::make(col + 1, -1)
    // Every message still to come keeps its stem alive through this row.
    for j in (k + 1)..<with_msg.length() {
      let other = with_msg[j]
      row2[stem_col(here[other])] = chars.stem
      owner2[stem_col(here[other])] = other
    }
    row2[col] = chars.elbow
    owner2[col] = idx
    write_line_head(snip, None, config, buf, color~, indent~)
    write_margin(snip, line, config, buf, color~)
    write_row(row2, owner2, here, config, buf, color~)
    label_style(config, l.style).write(buf, "\{chars.hbar} ", color~)
    buf.write_string(l.message.unwrap())
    buf.write_char('\n')
  }
}

///|
/// The column a label's message stem descends from: the middle of its
/// underline, which reads better than either end when several sit side by side.
fn stem_col(l : InlineLabel) -> Int {
  l.start_col + (l.end_col - l.start_col - 1) / 2
}

///|
/// Write a prepared row, one styled write per run of identical owner.
fn write_row(
  row : Array[Char],
  owner : Array[Int],
  labels : Array[InlineLabel],
  config : Config,
  buf : StringBuilder,
  color~ : Bool,
) -> Unit {
  let mut i = 0
  while i < row.length() {
    let o = owner[i]
    let mut j = i
    while j < row.length() && owner[j] == o {
      j = j + 1
    }
    let seg = StringBuilder()
    for k in i..<j {
      seg.write_char(row[k])
    }
    let text = seg.to_string()
    if o < 0 {
      buf.write_string(text)
    } else {
      label_style(config, labels[o].style).write(buf, text, color~)
    }
    i = j
  }
}

///|
/// Messages for multi-line labels that end on this line.
fn write_block_messages(
  snip : Snippet,
  line : Int,
  config : Config,
  buf : StringBuilder,
  color~ : Bool,
  indent~ : String,
) -> Unit {
  for b in snip.blocks {
    if b.end_line != line {
      continue
    }
    match b.message {
      None => ()
      Some(msg) => {
        write_line_head(snip, None, config, buf, color~, indent~)
        write_margin(snip, line, config, buf, color~, closing=b.margin)
        buf.write_char(' ')
        buf.write_string(msg)
        buf.write_char('\n')
      }
    }
  }
}
