///|
/// Machine-readable output: one JSON object per report, on one line.
///
/// Line-delimited rather than a single array, so a tool can stream results and
/// a build that dies half way still leaves valid records behind.
///
/// Positions are given twice on purpose. `offset`/`length` are the UTF-16 code
/// units this library works in; `line`/`column` are 1-based and 0-based
/// respectively, in code points, which is what a human-facing tool wants. A
/// consumer that needs one should not have to reconstruct it from the other,
/// because reconstructing it requires the source text and the whole point of
/// the JSON is to be usable without it.
pub fn json(
  report : @report.Report,
  cache : &@report.SourceCache,
  buf : StringBuilder,
) -> Unit {
  buf.write_string(report_json(report, cache).stringify())
  buf.write_char('\n')
}

///|
/// The JSON value for one report, related diagnostics nested inside it.
pub fn report_json(
  report : @report.Report,
  cache : &@report.SourceCache,
) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["severity"] = Json::string(report.severity.name())
  match report.code {
    Some(code) => obj["code"] = Json::string(code)
    None => ()
  }
  obj["message"] = Json::string(report.message)
  if report.labels.length() > 0 {
    obj["labels"] = Json::array(report.labels.map(l => label_json(l, cache)))
  }
  if report.notes.length() > 0 {
    obj["notes"] = Json::array(report.notes.map(n => Json::string(n)))
  }
  match report.help {
    Some(h) => obj["help"] = Json::string(h)
    None => ()
  }
  match report.url {
    Some(u) => obj["url"] = Json::string(u)
    None => ()
  }
  if report.fixes.length() > 0 {
    obj["fixes"] = Json::array(report.fixes.map(f => fix_json(f, cache)))
  }
  if report.related.length() > 0 {
    obj["related"] = Json::array(report.related.map(r => report_json(r, cache)))
  }
  Json::object(obj)
}

///|
fn label_json(label : @report.Label, cache : &@report.SourceCache) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["style"] = Json::string(
    match label.style {
      Primary => "primary"
      Secondary => "secondary"
    },
  )
  obj["offset"] = Json::number(label.span.start.to_double())
  obj["length"] = Json::number(label.span.len.to_double())
  add_position(obj, label.source, label.span, cache)
  match label.message {
    Some(m) => obj["message"] = Json::string(m)
    None => ()
  }
  Json::object(obj)
}

///|
fn fix_json(fix : @report.Fix, cache : &@report.SourceCache) -> Json {
  let obj : Map[String, Json] = Map([])
  obj["offset"] = Json::number(fix.span.start.to_double())
  obj["length"] = Json::number(fix.span.len.to_double())
  add_position(obj, fix.source, fix.span, cache)
  obj["replacement"] = Json::string(fix.replacement)
  obj["description"] = Json::string(fix.description)
  Json::object(obj)
}

///|
/// Add `file`, `line` and `column` when the source is available.
///
/// Silently absent rather than null when it is not: a report about a synthesized
/// node has no file, and a consumer checking `has key` reads better than one
/// checking `is not null`.
fn add_position(
  obj : Map[String, Json],
  id : @report.SourceId,
  span : @report.Span,
  cache : &@report.SourceCache,
) -> Unit {
  match cache.fetch(id) {
    None => ()
    Some(src) => {
      let (line, col) = src.line_col(span.start)
      let (end_line, end_col) = src.line_col(span.end())
      obj["file"] = Json::string(src.name)
      obj["line"] = Json::number(line.to_double())
      obj["column"] = Json::number(col.to_double())
      obj["end_line"] = Json::number(end_line.to_double())
      obj["end_column"] = Json::number(end_col.to_double())
    }
  }
}
