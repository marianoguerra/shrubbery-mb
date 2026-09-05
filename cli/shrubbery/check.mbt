///|
/// Parse, and render whatever goes wrong.
///
/// Answers 1 when anything was reported, so that a script can gate on it.
fn cmd_check(args : Array[String]) -> Int {
  let mut format : @render.Format = Rich
  let mut color : @style.ColorMode = Auto
  let files = []
  let mut i = 0
  while i < args.length() {
    match args[i] {
      "--error-format" | "--format" =>
        match args.get(i + 1) {
          Some("human") | Some("rich") => {
            format = Rich
            i = i + 2
          }
          Some("short") => {
            format = Short
            i = i + 2
          }
          Some("json") => {
            format = Json
            i = i + 2
          }
          Some(other) => {
            println("shrubbery: unknown error format '\{other}'")
            return 2
          }
          None => {
            println("shrubbery: --error-format needs a value")
            return 2
          }
        }
      "--color" =>
        match args.get(i + 1) {
          Some("always") => {
            color = Always
            i = i + 2
          }
          Some("never") => {
            color = Never
            i = i + 2
          }
          Some("auto") => {
            color = Auto
            i = i + 2
          }
          _ => {
            println("shrubbery: --color needs always, never or auto")
            return 2
          }
        }
      arg => {
        files.push(arg)
        i = i + 1
      }
    }
  }
  if files.length() == 0 {
    println("shrubbery: check needs at least one file")
    return 2
  }
  let sources = @report.Sources::new()
  let config = { ..@render.default_config, format, color, }
  let mut bad = false
  for path in files {
    let src = match read(path) {
      Some(s) => s
      None => {
        bad = true
        continue
      }
    }
    let id = sources.add(path, src)
    // Recovery mode: a file with three mistakes should report three, not stop
    // at the first.
    let diags = @parser.parse(src, recover=true).diagnostics() catch {
      ShrubberyError(d) => [d]
    }
    for d in diags {
      bad = true
      let buf = StringBuilder()
      @render.render(d.to_report(id), sources, config, buf, is_tty=true)
      print_trimmed(buf.to_string())
    }
  }
  if bad {
    1
  } else {
    0
  }
}

///|
fn print_trimmed(s : String) -> Unit {
  println(s.trim_end(chars="\n"))
}
