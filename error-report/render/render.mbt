///|
/// Render a report in the configured format.
///
/// The one entry point a consumer needs. `is_tty` is asked for rather than
/// detected because this library cannot see a file descriptor without taking a
/// dependency -- see `Config::use_color`.
pub fn render(
  report : @report.Report,
  cache : &@report.SourceCache,
  config : Config,
  buf : StringBuilder,
  is_tty? : Bool = false,
) -> Unit {
  match config.format {
    Rich => rich(report, cache, config, buf, is_tty~)
    Compact => rich(report, cache, config, buf, is_tty~)
    Short => short(report, cache, config, buf, is_tty~)
    Json => json(report, cache, buf)
  }
}

///|
/// `render` into a fresh string.
pub fn render_string(
  report : @report.Report,
  cache : &@report.SourceCache,
  config : Config,
  is_tty? : Bool = false,
) -> String {
  let buf = StringBuilder()
  render(report, cache, config, buf, is_tty~)
  buf.to_string()
}
