///|
/// The `shrubbery` command.
///
/// Its first job is to be the other half of the differential harness: the
/// harness runs this over a corpus and compares what it prints against what the
/// reference printed. Everything it can do is therefore something the harness
/// needs to compare, and the output formats are shared with `tools/oracle/`
/// rather than chosen for looks.
fn main {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    return
  }
  match args[1] {
    "tokens" => cmd_tokens(args[2:].to_owned())
    "help" | "--help" | "-h" => usage()
    other => {
      println("shrubbery: unknown command '\{other}'")
      usage()
    }
  }
}

///|
fn usage() -> Unit {
  println("usage: shrubbery tokens FILE...")
  println("")
  println("  tokens   dump the token stream, one token per line, as")
  println("           name TAB line TAB column TAB text TAB value")
}

///|
/// Dump tokens for each file, with a `==== path` header between them.
///
/// Many files in one process on purpose: the harness compares 632 of them, and
/// paying process startup per file — on either side — is the difference
/// between a gate people run and one they stop running.
fn cmd_tokens(files : Array[String]) -> Unit {
  for path in files {
    println("==== \{path}")
    let src = @fs.read_file_to_string(path) catch {
      _ => {
        println("!!!! cannot read")
        continue
      }
    }
    let buf = StringBuilder()
    for t in @lexer.lex_all(src) {
      if t.kind is EndOfInput {
        continue
      }
      buf.write_string(t.kind.kind_name())
      buf.write_char('\t')
      buf.write_string(t.line().to_string())
      buf.write_char('\t')
      buf.write_string(t.column().to_display())
      buf.write_char('\t')
      buf.write_string(escape_text(t.raw_text()))
      buf.write_char('\t')
      match t.kind {
        Literal(d) => buf.write_string(d.canonical())
        _ => buf.write_char('-')
      }
      buf.write_char('\n')
    }
    println(buf.to_string().trim_end(chars="\n"))
  }
}

///|
/// The same escaping `@sexp.Datum::canonical` uses for strings, so that both
/// sides of the comparison are all-ASCII and an encoding difference in transit
/// cannot look like a lexing difference.
fn escape_text(s : String) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  for c in s {
    let u = c.to_int()
    if c == '\\' || c == '"' || c == '|' {
      buf.write_char('\\')
      buf.write_char(c)
    } else if u >= 0x20 && u < 0x7F {
      buf.write_char(c)
    } else {
      buf.write_string("\\u{")
      buf.write_string(u.to_string(radix=16))
      buf.write_char('}')
    }
  }
  buf.write_char('"')
  buf.to_string()
}
