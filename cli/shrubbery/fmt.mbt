///|
/// Re-format, ignoring how the source was written.
///
/// The contract is the printer's: reading the output back gives the same tree.
/// A file that does not parse is reported and left alone -- reformatting
/// something you could not read is how a formatter loses someone's work.
fn cmd_fmt(args : Array[String]) -> Int {
  let mut style : @write.Style = Pretty
  let mut width : Int? = None
  let mut in_place = false
  let files = []
  let mut i = 0
  while i < args.length() {
    match args[i] {
      "--style" =>
        match args.get(i + 1) {
          Some("flat") => {
            style = Flat
            i = i + 2
          }
          Some("pretty") => {
            style = Pretty
            i = i + 2
          }
          Some("armoured") | Some("armored") => {
            style = Armoured
            i = i + 2
          }
          Some("multiline") => {
            style = PreferMultiline
            i = i + 2
          }
          _ => {
            println(
              "shrubbery: --style needs flat, pretty, armoured or multiline",
            )
            return 2
          }
        }
      "--width" =>
        match args.get(i + 1) {
          Some(v) =>
            match parse_width(v) {
              Some(w) => {
                width = Some(w)
                i = i + 2
              }
              None => {
                println("shrubbery: --width needs a number, got '\{v}'")
                return 2
              }
            }
          None => {
            println("shrubbery: --width needs a value")
            return 2
          }
        }
      "--write" | "-w" => {
        in_place = true
        i = i + 1
      }
      arg => {
        files.push(arg)
        i = i + 1
      }
    }
  }
  if files.length() == 0 {
    println("shrubbery: fmt needs at least one file")
    return 2
  }
  let mut bad = false
  for path in files {
    let src = match read(path) {
      Some(s) => s
      None => {
        bad = true
        continue
      }
    }
    let formatted = try
      @write.write(@parser.parse(src).root(), style~, width~) + "\n"
    catch {
      ShrubberyError(d) => {
        println("shrubbery: \{path}: \{d.kind.reference_text()}")
        bad = true
        continue
      }
    }
    if in_place {
      if formatted != src {
        @fs.write_string_to_file(path, formatted) catch {
          _ => {
            println("shrubbery: cannot write \{path}")
            bad = true
          }
        }
      }
    } else {
      print_trimmed(formatted)
    }
  }
  if bad {
    1
  } else {
    0
  }
}

///|
fn parse_width(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let mut v = 0
  for c in s {
    if c < '0' || c > '9' {
      return None
    }
    v = v * 10 + (c.to_int() - 48)
  }
  Some(v)
}
