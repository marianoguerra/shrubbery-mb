///|
/// The commands that drive the differential suite.
///
/// Their output formats are shared with `tools/oracle/`, not chosen for looks:
/// a file's records are compared line for line against what the reference
/// produced. Changing one of these changes what the suite compares, so change
/// the oracle in the same commit or the goldens stop meaning anything.
///
/// Every one takes many files in one process. There are 696 of them and both
/// sides pay process startup, which is the difference between a gate people run
/// and one they stop running.
fn cmd_tokens(files : Array[String]) -> Int {
  each_file(files, (path, src) => {
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
    ignore(path)
    print_trimmed(buf.to_string())
  })
}

///|
/// The parse tree, or the failure.
///
/// A rejected file prints `!error <message>` rather than exiting, so that ONE
/// comparison covers both parse parity and error parity: a port that accepted a
/// file the reference rejects, or rejected one it accepts, differs here rather
/// than in a second oracle that could disagree with this one.
fn cmd_parse(files : Array[String]) -> Int {
  each_file(files, (_, src) => {
    let line = @parser.parse(src).root().canonical() catch {
        ShrubberyError(d) => "!error " + d.kind.reference_text()
      }
    println(line)
  })
}

///|
/// The source rebuilt from the tree.
///
/// Between `<<<<` and `>>>>`, with a NUL before the closing marker, so that
/// trailing whitespace and a missing final newline survive the harness reading
/// it back.
fn cmd_source(files : Array[String]) -> Int {
  each_file(files, (_, src) => {
    let rebuilt = @parser.parse(src).root().to_source() catch {
        _ => {
          println("!error")
          return
        }
      }
    println("<<<<")
    println(rebuilt + "\u{0}")
    println(">>>>")
  })
}

///|
/// The eleven layout modes, in the order the reference's own suite runs them.
let print_modes : Array[(String, @write.Style, Int?)] = [
  ("flat", Flat, None),
  ("pretty", Pretty, None),
  ("pretty-0", Pretty, Some(0)),
  ("pretty-40", Pretty, Some(40)),
  ("armor", Armoured, None),
  ("armor-0", Armoured, Some(0)),
  ("armor-40", Armoured, Some(40)),
  ("multi", PreferMultiline, None),
  ("multi-0", PreferMultiline, Some(0)),
  ("multi-40", PreferMultiline, Some(40)),
  ("pretty-120", Pretty, Some(120)),
]

///|
/// One record per mode, newlines escaped, so that a record is a line and a
/// divergence names the mode it happened in.
fn cmd_print(files : Array[String]) -> Int {
  each_file(files, (_, src) => {
    let root = @parser.parse(src).root() catch {
      _ => {
        println("!error")
        return
      }
    }
    let buf = StringBuilder()
    for m in print_modes {
      let (name, style, width) = m
      buf.write_string(name)
      buf.write_char('\t')
      escape_lines(buf, @write.write(root, style~, width~))
      buf.write_char('\n')
    }
    print_trimmed(buf.to_string())
  })
}

///|
/// The layout document rather than a layout of it.
///
/// The debugging tool for the printer: it separates a LAYOUT disagreement --
/// the renderer chose differently -- from a CONSTRUCTION one, where the two
/// documents were never the same to begin with.
fn cmd_doc(args : Array[String]) -> Int {
  if args.length() < 2 {
    println("usage: shrubbery doc <pretty|armor|multi> FILE...")
    return 2
  }
  let style : @write.Style = match args[0] {
    "armor" => Armoured
    "multi" => PreferMultiline
    _ => Pretty
  }
  each_file(args[1:].to_owned(), (_, src) => {
    let root = @parser.parse(src).root() catch {
      _ => {
        println("!error")
        return
      }
    }
    println(@write.to_doc(root, style~).to_sexpr())
  })
}

///|
/// Run `body` over each file, with the `==== path` header the harness splits
/// on. Unreadable files get a marker rather than stopping the batch.
fn each_file(files : Array[String], body : (String, String) -> Unit) -> Int {
  for path in files {
    println("==== \{path}")
    match read_quiet(path) {
      Some(src) => body(path, src)
      None => println("!!!! cannot read")
    }
  }
  0
}

///|
fn read_quiet(path : String) -> String? {
  Some(@fs.read_file_to_string(path)) catch {
    _ => None
  }
}

///|
/// The escaping `@sexp.Datum::canonical` uses, so both sides of a comparison
/// are all-ASCII and an encoding difference in transit cannot look like a
/// lexing difference.
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

///|
fn escape_lines(buf : StringBuilder, s : String) -> Unit {
  for c in s {
    match c {
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\\' => buf.write_string("\\\\")
      _ => buf.write_char(c)
    }
  }
}
