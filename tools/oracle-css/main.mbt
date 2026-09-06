///|
/// The CSS oracle: the binary `tools/cssdiff.py` drives.
///
/// It lives in the development module, not in a published CLI, for the reason
/// the whole dev module exists: it reaches the three libraries through their
/// public API only, so whatever the harness needs is by construction a name
/// that has to stay public. Putting these subcommands in `shrubbery-cli`
/// instead would also make every CLI user fetch the CSS modules.
///
/// Output is batched: one process for a whole corpus, with a `==== path`
/// header before each answer. That is the same shape `tools/shrubdiff.py`
/// already consumes, and it exists because starting a process per file
/// dominates the runtime of a 350-file corpus.
///
/// Every subcommand answers for every file, including the ones that fail.
/// A file that cannot be read at all answers `!error <what>`, so a corpus
/// entry never silently disappears from a comparison.
fn main {
  let args = @env.args()
  if args.length() < 3 {
    println("usage: oracle-css <command> FILE...")
    println("")
    println("  print      CSS -> CSS, in all three modes")
    println("  roundtrip  CSS -> CSS -> CSS; the two must agree")
    println("  loop       CSS -> shrubbery -> CSS; must equal `print` pretty")
    println("  lower      shrubbery CSS -> CSS")
    println("  emit       CSS -> shrubbery CSS")
    println("  diagnose   the diagnostic codes a file produces")
    return
  }
  let cmd = args[1]
  for path in args[2:] {
    println("==== " + path)
    let src = read(path)
    match src {
      None => println("!error cannot read file")
      Some(text) =>
        match cmd {
          "print" => print_modes(text)
          "roundtrip" => roundtrip(text)
          "loop" => css_loop(text)
          "lower" => lower_shrub(text)
          "emit" => emit_shrub(text)
          "diagnose" => diagnose(text)
          other => println("!error unknown command " + other)
        }
    }
  }
}

///|
/// Write a block that already ends in a newline, without adding another.
///
/// The printers end their output with one; `println` would add a second, and a
/// golden file would then record a blank line that means nothing.
fn put(text : String) -> Unit {
  if text.has_suffix("\n") {
    println(text.clamped_view(end=text.length() - 1).to_owned())
  } else {
    println(text)
  }
}

///|
fn read(path : String) -> String? {
  Some(@fs.read_file_to_string(path)) catch {
    _ => None
  }
}

///|
/// CSS in all three printing modes.
///
/// Three modes rather than one because they are three different claims: pretty
/// output is what a person reads, minified is what has to stay correct with
/// every optional token removed, and compact sits between them. A bug that
/// only shows when a space is dropped shows here.
fn print_modes(src : String) -> Unit {
  let p = @parse.parse(src) catch {
    e => {
      println("!error " + e.diagnostic().kind.code())
      return
    }
  }
  println("--- pretty")
  put(@write.stylesheet(p.sheet(), style=Pretty))
  println("--- compact")
  println(@write.stylesheet(p.sheet(), style=Compact))
  println("--- minified")
  println(@write.stylesheet(p.sheet(), style=Minified))
}

///|
/// Parse, print, parse, print: the second pair must equal the first.
///
/// This is the printer's fixed-point property, and it catches the class of bug
/// where output is valid but not stable -- a printer that adds a space each
/// time round would pass every single-pass test and fail this one.
fn roundtrip(src : String) -> Unit {
  for style in ["pretty", "minified"] {
    let s : @write.Style = if style == "pretty" { Pretty } else { Minified }
    let once = print_once(src, s)
    match once {
      None => {
        println("!error " + style + " first pass")
        continue
      }
      Some(a) =>
        match print_once(a, s) {
          None => println("!error " + style + " second pass")
          Some(b) =>
            if a == b {
              println(style + ": stable")
            } else {
              println(style + ": NOT STABLE")
              println("  once:  " + a)
              println("  twice: " + b)
            }
        }
    }
  }
}

///|
fn print_once(src : String, style : @write.Style) -> String? {
  let p = @parse.parse(src) catch { _ => return None }
  Some(@write.stylesheet(p.sheet(), style~))
}

///|
/// The whole point, checked on one file: CSS the short way and CSS the long
/// way round through the notation must be the same CSS.
fn css_loop(src : String) -> Unit {
  let p = @parse.parse(src) catch {
    e => {
      println("!error css " + e.diagnostic().kind.code())
      return
    }
  }
  let direct = @write.stylesheet(p.sheet(), style=Minified)
  let shrub = @emit.stylesheet(p.sheet())
  let l = @lower.lower_source(shrub) catch {
    e => {
      println("!error lower " + e.diagnostic().kind.code())
      return
    }
  }
  let detour = @write.stylesheet(l.sheet(), style=Minified)
  if direct == detour {
    println("loop: closed")
  } else {
    println("loop: OPEN")
    println("  direct: " + direct)
    println("  detour: " + detour)
  }
}

///|
fn lower_shrub(src : String) -> Unit {
  let l = @lower.lower_source(src) catch {
    e => {
      println("!error " + e.diagnostic().kind.code())
      return
    }
  }
  for d in l.diagnostics() {
    println("! " + d.kind.code())
  }
  put(@write.stylesheet(l.sheet(), style=Pretty))
}

///|
fn emit_shrub(src : String) -> Unit {
  let p = @parse.parse(src) catch {
    e => {
      println("!error " + e.diagnostic().kind.code())
      return
    }
  }
  put(@emit.stylesheet(p.sheet()))
}

///|
/// Just the codes, for the buckets whose point is which diagnostics fire.
fn diagnose(src : String) -> Unit {
  let p = @parse.parse(src) catch {
    e => {
      println("!raised " + e.diagnostic().kind.code())
      return
    }
  }
  let ds = p.diagnostics()
  if ds.length() == 0 {
    println("(none)")
    return
  }
  for d in ds {
    println(d.kind.code())
  }
}
