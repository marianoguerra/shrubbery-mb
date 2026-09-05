///|
/// One line per report: `file:line:col: severity[code]: message`.
///
/// The format editors and `grep` already understand, so it is the one to reach
/// for in a `-f short` mode or a CI log. Related reports get their own lines
/// rather than being nested, because a nested line breaks the one property this
/// format exists for: that every line stands alone.
pub fn short(
  report : @report.Report,
  cache : &@report.SourceCache,
  config : Config,
  buf : StringBuilder,
  is_tty? : Bool = false,
) -> Unit {
  short_one(report, cache, config, buf, is_tty~)
  for rel in report.related {
    short_one(rel, cache, config, buf, is_tty~)
  }
}

///|
fn short_one(
  report : @report.Report,
  cache : &@report.SourceCache,
  config : Config,
  buf : StringBuilder,
  is_tty~ : Bool,
) -> Unit {
  let color = config.use_color(is_tty~)
  let theme = config.theme
  match locate(report, cache) {
    Some((name, line, col)) =>
      // 1-based column, which is what an editor jumping to the position wants.
      buf.write_string("\{name}:\{line}:\{col + 1}: ")
    None => ()
  }
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
}

///|
/// The file and position a report points at, if any.
fn locate(
  report : @report.Report,
  cache : &@report.SourceCache,
) -> (String, Int, Int)? {
  let label = report.anchor()
  match label {
    None => None
    Some(l) =>
      match cache.fetch(l.source) {
        None => None
        Some(src) => {
          let (line, col) = src.line_col(l.span.start)
          Some((src.name, line, col))
        }
      }
  }
}

///|
fn severity_style(
  theme : @style.Theme,
  severity : @report.Severity,
) -> @style.Style {
  match severity {
    Error => theme.error
    Warning => theme.warning
    Advice => theme.advice
  }
}
