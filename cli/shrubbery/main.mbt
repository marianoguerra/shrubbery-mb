///|
/// The `shrubbery` command.
///
/// Two audiences, and the split is deliberate. `check` and `fmt` are for a
/// person; `tokens`, `parse`, `source`, `print` and `doc` are the other half of
/// the differential harness, and their output formats are shared with
/// `tools/oracle/` rather than chosen for looks. Changing one of those changes
/// what the suite compares.
fn main {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    @sys.exit(2)
  }
  let rest = args[2:].to_owned()
  let code = match args[1] {
    "check" => cmd_check(rest)
    "fmt" => cmd_fmt(rest)
    "tokens" => cmd_tokens(rest)
    "parse" => cmd_parse(rest)
    "source" => cmd_source(rest)
    "print" => cmd_print(rest)
    "doc" => cmd_doc(rest)
    "help" | "--help" | "-h" => {
      usage()
      0
    }
    other => {
      println("shrubbery: unknown command '\{other}'")
      usage()
      2
    }
  }
  if code != 0 {
    @sys.exit(code)
  }
}

///|
fn usage() -> Unit {
  println("usage: shrubbery <command> [options] FILE...")
  println("")
  println("  check    parse and report any problem, with the source shown")
  println("             --error-format human|short|json   (default: human)")
  println("             --color always|never|auto         (default: auto)")
  println("  fmt      re-format, ignoring how the source was written")
  println("             --style flat|pretty|armoured|multiline")
  println("             --width N        (pretty styles; omit to never break)")
  println("             --write          rewrite the file in place")
  println("")
  println("  The rest drive the differential suite, and their output formats")
  println("  are shared with tools/oracle/:")
  println("")
  println("  tokens   the token stream, one per line")
  println("  parse    the parse tree in canonical form, or `!error <message>`")
  println("  source   the source rebuilt from the tree's metadata")
  println("  print    every layout mode, one per line")
  println("  doc      the layout document, to compare with the reference's")
}

///|
/// Read a file, or report why not.
fn read(path : String) -> String? {
  Some(@fs.read_file_to_string(path)) catch {
    _ => {
      println("shrubbery: cannot read \{path}")
      None
    }
  }
}
