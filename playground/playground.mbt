///|
/// The playground's four conversions, compiled to wasm-gc.
///
/// It lives in the development module for the reason everything else here does:
/// it reaches the four published modules through their public API only, so
/// whatever the playground needs is by construction a name that has to stay
/// public. It is also the only consumer in this repository that depends on
/// BOTH bridges at once, which makes it the place where the "a module's
/// dependencies are fetched by every consumer" rule is finally paid rather than
/// argued about -- and paid by something nobody has to install.
///
/// `use-js-builtin-string` makes MoonBit's `String` the host's `String`, so
/// these signatures are what JavaScript sees: strings in, one string out. No
/// linear memory, no manual encoding, no glue beyond `WebAssembly.instantiate`.
///
/// Every function returns JSON rather than the converted text, because a
/// playground that only showed output would be hiding the more interesting
/// half. A failed conversion still has a tree, and a tolerant one still has
/// diagnostics; both come back, with the diagnostics already rendered by
/// `error-report` -- carets, line numbers and all.

///|
/// Shrubbery CSS to CSS.
pub fn css_of_shrubbery(src : String, style : String) -> String {
  let l = @shrubcss.lower(src) catch {
    e => return failure(e.diagnostic().kind.code())
  }
  let diagnostics = []
  for d in l.diagnostics() {
    diagnostics.push(render(id => d.to_report(id), src, "input.shrubcss"))
  }
  answer(@cssw.stylesheet(l.sheet(), style=css_style(style)), diagnostics)
}

///|
/// CSS to Shrubbery CSS.
pub fn shrubbery_of_css(src : String) -> String {
  let p = @cssparse.parse(src) catch {
    e => return failure(e.diagnostic().kind.code())
  }
  let diagnostics = []
  for d in p.diagnostics() {
    diagnostics.push(render(id => d.to_report(id), src, "input.css"))
  }
  answer(@cssemit.stylesheet(p.sheet()), diagnostics)
}

///|
/// Shrubbery HTML to HTML.
pub fn html_of_shrubbery(src : String, style : String) -> String {
  let l = @shrubhtml.lower(src) catch {
    e => return failure(e.diagnostic().kind.code())
  }
  let diagnostics = []
  for d in l.diagnostics() {
    diagnostics.push(render(id => d.to_report(id), src, "input.shrubhtml"))
  }
  answer(@htmlw.document(l.document(), style=html_style(style)), diagnostics)
}

///|
/// HTML to Shrubbery HTML.
pub fn shrubbery_of_html(src : String) -> String {
  let p = @htmlparse.parse(src) catch {
    e => return failure(e.diagnostic().kind.code())
  }
  let diagnostics = []
  for d in p.diagnostics() {
    diagnostics.push(render(id => d.to_report(id), src, "input.html"))
  }
  answer(@htmlemit.document(p.document()), diagnostics)
}

// ------------------------------------------------------------------ styles

///|
fn css_style(name : String) -> @cssw.Style {
  match name {
    "compact" => Compact
    "minified" => Minified
    _ => Pretty
  }
}

///|
fn html_style(name : String) -> @htmlw.Style {
  match name {
    "compact" => Compact
    "minified" => Minified
    _ => Pretty
  }
}

// ------------------------------------------------------------- diagnostics

///|
/// One diagnostic, rendered the way the command line renders it.
///
/// Taking a function rather than a `Report` because the four diagnostic types
/// are four different types in four modules -- deliberately, so that a consumer
/// can tell a notation problem from a markup one -- and the only thing they
/// share is knowing how to become a report. Passing the method is what lets
/// this be written once.
fn render(
  to_report : (@report.SourceId) -> @report.Report,
  src : String,
  name : String,
) -> String {
  let sources = @report.Sources::new()
  let id = sources.add(name, src)
  let config = {
    ..@render.default_config,
    theme: @style.mono_theme,
    color: Never,
  }
  @render.render_string(to_report(id), sources, config)
}

// -------------------------------------------------------------------- JSON

///|
/// `{"ok":true,"out":...,"diagnostics":[...]}`.
fn answer(out : String, diagnostics : Array[String]) -> String {
  let buf = StringBuilder()
  buf.write_string("{\"ok\":true,\"out\":")
  buf.write_string(quote(out))
  buf.write_string(",\"diagnostics\":[")
  let mut first = true
  for d in diagnostics {
    if !first {
      buf.write_char(',')
    }
    first = false
    buf.write_string(quote(d))
  }
  buf.write_string("]}")
  buf.to_string()
}

///|
/// What comes back when the conversion could not start at all.
///
/// Only reachable in strict mode, which the playground does not use -- but a
/// façade that raises has to be caught somewhere, and swallowing it would make
/// the page go blank with no explanation.
fn failure(code : String) -> String {
  "{\"ok\":false,\"out\":\"\",\"diagnostics\":[" + quote(code) + "]}"
}

///|
/// A JSON string literal.
///
/// Written here rather than taken from a library because this package must
/// build for wasm-gc with the JS string builtins, and the fewer things that are
/// in that build the fewer surprises there are in it.
fn quote(s : String) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.unsafe_get(i).to_int().unsafe_to_char()
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ =>
        if c.to_int() < 0x20 {
          buf.write_string("\\u00")
          let v = c.to_int()
          buf.write_char(hex_digit(v / 16))
          buf.write_char(hex_digit(v % 16))
        } else {
          buf.write_char(c)
        }
    }
    i = i + 1
  }
  buf.write_char('"')
  buf.to_string()
}

///|
fn hex_digit(v : Int) -> Char {
  if v < 10 {
    (48 + v).unsafe_to_char()
  } else {
    (87 + v).unsafe_to_char()
  }
}
