///|
/// The html5lib tokenizer suite, run against our scanner.
///
/// The only place in this repository where an EXPECTED ANSWER is vendored
/// rather than computed. `shrubdiff.py` runs Racket and compares; `cssdiff.py`
/// compares the library against itself; `conform` asks a second implementation.
/// This reads a third thing: a suite of 6,806 cases, each an input and the token
/// stream the specification says it produces, maintained by the people who
/// maintain the tests every browser is checked against.
///
/// It is worth having for one reason above the others. The 2,231 named
/// character references are GENERATED, from `entities.json`, by a script -- and
/// nothing else here checks that a single one of them decodes correctly. This
/// checks all of them, in both spellings, in text and in attribute values.
///
/// Four kinds of case are skipped rather than failed, and each is a state this
/// tokenizer does not have because a markup tokenizer does not need it:
/// PLAINTEXT, and the CDATA section state. The count is reported, so a skip can
/// never be mistaken for a pass.

///|
/// Run one `.test` file and report how many of its cases agree.
fn html5lib(path : String, text : String) -> Unit {
  let doc = @json.parse(text) catch {
    _ => {
      println("!error not JSON")
      return
    }
  }
  let tests = match doc {
    Object(o) =>
      match o.get("tests") {
        Some(Array(a)) => a
        // `xmlViolation.test` names its cases differently, and tests a
        // serialisation policy rather than the tokenizer.
        _ => {
          println("!error no tests array")
          return
        }
      }
    _ => {
      println("!error not an object")
      return
    }
  }
  ignore(path)
  let mut ran = 0
  let mut passed = 0
  let mut skipped = 0
  let mut shown = 0
  for t in tests {
    let obj = match t {
      Object(o) => o
      _ => continue
    }
    let double = obj.get("doubleEscaped") is Some(True)
    let input = match obj.get("input") {
      Some(String(s)) => unescape(s, double)
      _ => continue
    }
    let expected = expected_of(obj, double)
    let last = match obj.get("lastStartTag") {
      Some(String(s)) => s
      _ => ""
    }
    for state in states_of(obj) {
      match start_for(state, last) {
        None => skipped = skipped + 1
        Some(start) => {
          ran = ran + 1
          let actual = canonical(@token.tokens(input, start~))
          if actual == expected {
            passed = passed + 1
          } else if shown < 4 {
            shown = shown + 1
            println("  FAIL " + describe(obj))
            println("    state:    " + state)
            println("    input:    " + show(input))
            println("    expected: " + show(expected))
            println("    actual:   " + show(actual))
          }
        }
      }
    }
  }
  println(
    "html5lib: " +
    passed.to_string() +
    "/" +
    ran.to_string() +
    " (" +
    skipped.to_string() +
    " skipped)",
  )
}

///|
fn describe(obj : Map[String, Json]) -> String {
  match obj.get("description") {
    Some(String(s)) => s
    _ => "(no description)"
  }
}

///|
/// The initial states a case names, defaulting to the data state.
fn states_of(obj : Map[String, Json]) -> Array[String] {
  match obj.get("initialStates") {
    Some(Array(a)) => {
      let out : Array[String] = []
      for s in a {
        match s {
          String(name) => out.push(name)
          _ => ()
        }
      }
      out
    }
    _ => ["Data state"]
  }
}

///|
/// The suite's state name as a scanner entry point, or `None` for one this
/// tokenizer does not have.
///
/// `lastStartTag` is what ends the run, and the suite always supplies it for a
/// non-data state. Without one there is nothing the raw text could end at, so
/// the case is skipped rather than guessed at.
fn start_for(state : String, last : String) -> @token.Start? {
  if state == "Data state" {
    return Some(Markup)
  }
  if last == "" {
    return None
  }
  match state {
    "RCDATA state" => Some(Escapable(last))
    "RAWTEXT state" | "Script data state" => Some(Raw(last))
    // PLAINTEXT never ends, and the CDATA section state is entered by the tree
    // builder from foreign content. Neither is a state a markup tokenizer has.
    _ => None
  }
}

// ------------------------------------------------------------- canonical form

///|
/// Field and record separators for the canonical form.
///
/// Control characters rather than punctuation, because every printable
/// character can appear inside a tag name, an attribute value or a comment --
/// this suite exists to try exactly those.
const FIELD : String = "\u{1}"

///|
const RECORD : String = "\u{2}"

///|
/// A marker for `null`, which JSON has and a canonical string does not.
const NIL : String = "\u{3}"

///|
/// Our token stream, in the suite's vocabulary.
///
/// Four translations, each of them a place where this tokenizer deliberately
/// answers a different question than the specification's:
///
///   * `RawText` is character data. The specification emits character tokens
///     for a `<script>` body; this emits one node, because the parser wants it
///     whole.
///   * `Cdata` becomes the bogus comment the specification's tokenizer would
///     emit in HTML content. This tokenizer defers that decision to the parser,
///     which knows the namespace -- and every case in this suite is in HTML
///     content, so the HTML reading is the right one to compare.
///   * `Bogus` is nothing. It marks a region the specification discards -- a tag
///     that ran to end of input -- and exists only so the printer can echo the
///     source. The specification emits no token, and neither does this.
///   * Adjacent character runs are joined, which the suite's own harness does
///     too: where a stream is split is not observable.
fn canonical(tokens : Array[@token.Token]) -> String {
  let parts : Array[String] = []
  let text = StringBuilder()
  let mut pending_text = false
  fn flush() {
    if pending_text {
      let s = text.to_string()
      if s.length() > 0 {
        parts.push("C" + FIELD + s)
      }
      text.reset()
      pending_text = false
    }
  }

  for t in tokens {
    match t.kind {
      Text(s, _) => {
        text.write_string(s)
        pending_text = true
      }
      RawText(s) => {
        text.write_string(s)
        pending_text = true
      }
      StartTag(name, attrs, self_closing) => {
        flush()
        parts.push(start_tag_form(name, attrs, self_closing))
      }
      EndTag(name) => {
        flush()
        parts.push("E" + FIELD + name)
      }
      Comment(data) => {
        flush()
        parts.push("M" + FIELD + data)
      }
      Cdata(data) => {
        flush()
        parts.push("M" + FIELD + "[CDATA[" + data + "]]")
      }
      Doctype(name, public_id, system_id, quirks) => {
        flush()
        parts.push(
          "D" +
          FIELD +
          (if name.length() == 0 { NIL } else { name }) +
          FIELD +
          opt(public_id) +
          FIELD +
          opt(system_id) +
          FIELD +
          (if quirks { "0" } else { "1" }),
        )
      }
      Bogus(_, _) => ()
      Eof => flush()
    }
  }
  flush()
  join(parts)
}

///|
/// A start tag, with its attributes sorted.
///
/// Sorted because the suite's expected form is a JSON object and an object has
/// no order, while our stream has source order. Sorting is the only comparison
/// that can be right for both.
fn start_tag_form(
  name : String,
  attrs : Array[@token.RawAttr],
  self_closing : Bool,
) -> String {
  let pairs : Array[String] = []
  for a in attrs {
    let value = match a.value {
      Some(v) => v
      None => ""
    }
    pairs.push(a.name + "\u{4}" + value)
  }
  pairs.sort()
  let buf = StringBuilder()
  buf.write_string("S")
  buf.write_string(FIELD)
  buf.write_string(name)
  for p in pairs {
    buf.write_string(FIELD)
    buf.write_string(p)
  }
  if self_closing {
    buf.write_string(FIELD)
    buf.write_string("/")
  }
  buf.to_string()
}

///|
/// The suite's expected output, in the same canonical form.
fn expected_of(obj : Map[String, Json], double : Bool) -> String {
  let out : Array[String] = match obj.get("output") {
    Some(Array(items)) => {
      let parts : Array[String] = []
      let text = StringBuilder()
      let mut pending = false
      for item in items {
        let row = match item {
          Array(r) => r
          _ => continue
        }
        if row.length() == 0 {
          continue
        }
        let tag = match row[0] {
          String(s) => s
          _ => continue
        }
        if tag == "Character" {
          match row[1] {
            String(s) => {
              text.write_string(unescape(s, double))
              pending = true
            }
            _ => ()
          }
          continue
        }
        if pending {
          let s = text.to_string()
          if s.length() > 0 {
            parts.push("C" + FIELD + s)
          }
          text.reset()
          pending = false
        }
        match expected_row(tag, row, double) {
          Some(form) => parts.push(form)
          None => ()
        }
      }
      if pending {
        let s = text.to_string()
        if s.length() > 0 {
          parts.push("C" + FIELD + s)
        }
      }
      parts
    }
    _ => []
  }
  join(out)
}

///|
fn expected_row(tag : String, row : Array[Json], double : Bool) -> String? {
  match tag {
    "StartTag" => {
      let name = str_at(row, 1, double)
      let pairs : Array[String] = []
      match row.get(2) {
        Some(Object(attrs)) =>
          for entry in attrs {
            let (k, v) = entry
            let value = match v {
              String(s) => unescape(s, double)
              _ => ""
            }
            pairs.push(unescape(k, double) + "\u{4}" + value)
          }
        _ => ()
      }
      pairs.sort()
      let buf = StringBuilder()
      buf.write_string("S")
      buf.write_string(FIELD)
      buf.write_string(name)
      for p in pairs {
        buf.write_string(FIELD)
        buf.write_string(p)
      }
      if row.get(3) is Some(True) {
        buf.write_string(FIELD)
        buf.write_string("/")
      }
      Some(buf.to_string())
    }
    "EndTag" => Some("E" + FIELD + str_at(row, 1, double))
    "Comment" => Some("M" + FIELD + str_at(row, 1, double))
    "DOCTYPE" =>
      Some(
        "D" +
        FIELD +
        json_opt(row.get(1), double) +
        FIELD +
        json_opt(row.get(2), double) +
        FIELD +
        json_opt(row.get(3), double) +
        FIELD +
        (if row.get(4) is Some(True) { "1" } else { "0" }),
      )
    _ => None
  }
}

///|
fn str_at(row : Array[Json], i : Int, double : Bool) -> String {
  match row.get(i) {
    Some(String(s)) => unescape(s, double)
    _ => ""
  }
}

///|
fn json_opt(v : Json?, double : Bool) -> String {
  match v {
    Some(String(s)) => unescape(s, double)
    _ => NIL
  }
}

///|
fn opt(v : String?) -> String {
  match v {
    Some(s) => s
    None => NIL
  }
}

///|
fn join(parts : Array[String]) -> String {
  let buf = StringBuilder()
  let mut first = true
  for p in parts {
    if !first {
      buf.write_string(RECORD)
    }
    first = false
    buf.write_string(p)
  }
  buf.to_string()
}

// -------------------------------------------------------------- escaping

///|
/// The suite's `doubleEscaped` form, undone.
///
/// A handful of cases put `\uXXXX` inside a JSON string so that the file itself
/// stays ASCII and so that a lone surrogate can be written down at all. JSON's
/// own unescaping has already run by the time this sees the string, so what is
/// left is a literal backslash-u that has to be resolved here.
fn unescape(s : String, double : Bool) -> String {
  if !double {
    return s
  }
  let buf = StringBuilder()
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.unsafe_get(i).to_int().unsafe_to_char()
    if c == '\\' && i + 5 < n + 1 && s.unsafe_get(i + 1).to_int() == 117 {
      let mut v = 0
      let mut k = 0
      let mut ok = true
      while k < 4 {
        let d = hex_digit(s.unsafe_get(i + 2 + k).to_int().unsafe_to_char())
        if d < 0 {
          ok = false
          break
        }
        v = v * 16 + d
        k = k + 1
      }
      if ok {
        // A lone surrogate is what several of these cases are ABOUT, and a
        // MoonBit string is UTF-16, so the code unit goes in as itself.
        buf.write_char(v.unsafe_to_char())
        i = i + 6
        continue
      }
    }
    buf.write_char(c)
    i = i + 1
  }
  buf.to_string()
}

///|
fn hex_digit(c : Char) -> Int {
  if c >= '0' && c <= '9' {
    c.to_int() - 48
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 87
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 55
  } else {
    -1
  }
}

///|
/// A canonical string, made readable for a failure report.
fn show(s : String) -> String {
  let buf = StringBuilder()
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.unsafe_get(i).to_int().unsafe_to_char()
    match c.to_int() {
      1 => buf.write_string(" | ")
      2 => buf.write_string("  //  ")
      3 => buf.write_string("(null)")
      4 => buf.write_string("=")
      10 => buf.write_string("\\n")
      13 => buf.write_string("\\r")
      code =>
        if code < 0x20 || code == 0x7F {
          buf.write_string("\\x" + code.to_string())
        } else {
          buf.write_char(c)
        }
    }
    i = i + 1
  }
  buf.to_string()
}
