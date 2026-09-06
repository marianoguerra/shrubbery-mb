///|
/// At-rules.
///
/// The shape is decided before the name is: an at-rule runs to either a `;` or
/// a `{ ... }`, and which one it is has to be known before the prelude can be
/// interpreted. That is biome's split -- `UnknownBlockAtRule` versus
/// `UnknownValueAtRule` -- and it is the reason an at-rule nobody knows can
/// still be printed back correctly.

///|
fn Parser::parse_at_rule(
  self : Parser,
  name : String,
) -> @ast.CssRule? raise @err.CssError {
  let start = self.cur().span.start
  self.pos = self.pos + 1
  let prelude_start = self.pos
  let mut depth = 0
  let mut has_block = false
  while !self.at_eof() {
    let k = self.peek()
    if depth == 0 {
      if k == LBrace {
        has_block = true
        break
      }
      if k == Semicolon {
        break
      }
      if k == RBrace {
        break
      }
    }
    if k.is_opener() {
      depth = depth + 1
    } else if k == RParen || k == RBracket || k == RBrace {
      if depth > 0 {
        depth = depth - 1
      }
    }
    self.pos = self.pos + 1
  }
  let prelude = self.toks[prelude_start:self.pos]
  let lower = name.to_lower()
  let rule = self.build_at_rule(name, lower, prelude, has_block, start)
  // Consume whatever ended the prelude.
  if !has_block && self.peek() == Semicolon {
    self.pos = self.pos + 1
  }
  rule
}

///|
fn Parser::build_at_rule(
  self : Parser,
  name : String,
  lower : String,
  prelude : ArrayView[@token.Token],
  has_block : Bool,
  start : Int,
) -> @ast.CssRule? raise @err.CssError {
  match (lower, has_block) {
    ("media", true) => {
      let queries = self.parse_media_list(prelude, start)
      let body = self.parse_block()
      Some(Media({ queries, body, span: self.span_from(start), }))
    }
    ("supports", true) => {
      let condition = self.parse_condition(prelude, start)
      let body = self.parse_block()
      Some(Supports({ condition, body, span: self.span_from(start), }))
    }
    ("container", true) => {
      let (cname, rest) = split_container_name(prelude)
      let condition = self.parse_condition(rest, start)
      let body = self.parse_block()
      Some(
        Container({ name: cname, condition, body, span: self.span_from(start), }),
      )
    }
    ("keyframes", true) | ("-webkit-keyframes", true) => {
      let kname : @ast.KeyframesName = match first_meaningful(prelude) {
        Some(Ident(n)) => Ident(n)
        Some(Str(s)) => Str(s)
        _ => {
          self.error(BadAtRulePrelude(name), span_of_view(prelude, start))
          Ident("")
        }
      }
      let frames = self.parse_keyframes_body(start)
      Some(Keyframes({ name: kname, frames, span: self.span_from(start), }))
    }
    ("font-face", true) => Some(FontFace(self.parse_decl_block(start)))
    ("counter-style", true) => {
      let cname = match first_meaningful(prelude) {
        Some(Ident(n)) => n
        _ => ""
      }
      Some(CounterStyle(cname, self.parse_decl_block(start)))
    }
    ("property", true) => {
      let pname = match first_meaningful(prelude) {
        Some(Ident(n)) => n
        _ => ""
      }
      Some(
        Property({
          name: pname,
          decls: self.parse_decl_block(start),
          span: self.span_from(start),
        }),
      )
    }
    ("page", true) => {
      let selectors = page_selectors(prelude)
      let body = self.parse_block()
      Some(Page({ selectors, body, span: self.span_from(start), }))
    }
    ("starting-style", true) => {
      let body = self.parse_block()
      Some(StartingStyle(body, self.span_from(start)))
    }
    ("scope", true) => {
      let (s, e) = self.split_scope(prelude, start)
      let body = self.parse_block()
      Some(Scope({ start: s, end: e, body, span: self.span_from(start), }))
    }
    ("layer", true) => {
      let names = layer_names(prelude)
      let body = self.parse_block()
      Some(Layer({ names, body: Some(body), span: self.span_from(start), }))
    }
    ("layer", false) =>
      Some(
        Layer({
          names: layer_names(prelude),
          body: None,
          span: self.span_from(start),
        }),
      )
    ("charset", false) =>
      match first_meaningful(prelude) {
        Some(Str(s)) => Some(Charset(s, self.span_from(start)))
        _ => {
          self.error(BadAtRulePrelude(name), span_of_view(prelude, start))
          Some(
            Unknown({
              name,
              prelude: self.values_of(prelude),
              block: None,
              span: self.span_from(start),
            }),
          )
        }
      }
    ("namespace", false) => {
      let (prefix, url) = namespace_parts(prelude)
      match url {
        Some(u) =>
          Some(Namespace({ prefix, url: u, span: self.span_from(start), }))
        None => {
          self.error(BadAtRulePrelude(name), span_of_view(prelude, start))
          Some(
            Unknown({
              name,
              prelude: self.values_of(prelude),
              block: None,
              span: self.span_from(start),
            }),
          )
        }
      }
    }
    ("import", false) => self.parse_import(name, prelude, start)
    _ => {
      // Not a name this library knows, or a known name in the wrong shape.
      // Either way the rule is kept verbatim -- the diagnostic says which.
      if is_known_at_rule(lower) {
        self.error(BadAtRuleShape(name), self.span_from(start))
      } else {
        self.error(
          UnknownAtRule(name),
          @span.Span::new(start, start + 1 + name.length()),
        )
      }
      let block = if has_block { Some(self.parse_block()) } else { None }
      Some(
        Unknown({
          name,
          prelude: self.values_of(prelude),
          block,
          span: self.span_from(start),
        }),
      )
    }
  }
}

///|
fn Parser::span_from(self : Parser, start : Int) -> @span.Span {
  @span.Span::new(start, self.prev_end())
}

///|
fn is_known_at_rule(lower : String) -> Bool {
  lower == "media" ||
  lower == "supports" ||
  lower == "container" ||
  lower == "keyframes" ||
  lower == "font-face" ||
  lower == "counter-style" ||
  lower == "property" ||
  lower == "page" ||
  lower == "starting-style" ||
  lower == "scope" ||
  lower == "layer" ||
  lower == "charset" ||
  lower == "namespace" ||
  lower == "import"
}

///|
fn first_meaningful(toks : ArrayView[@token.Token]) -> @token.TokenKind? {
  for t in toks {
    if !t.is_trivia() {
      return Some(t.kind)
    }
  }
  None
}

///|
/// A block that may hold only declarations.
fn Parser::parse_decl_block(
  self : Parser,
  start : Int,
) -> @ast.DeclBlock raise @err.CssError {
  let items = self.parse_block()
  // A nested rule here is not a CSS error the parser can fix, but it is one it
  // must not silently accept: the printer would emit something invalid.
  for it in items {
    match it {
      Rule(_) => self.error(RuleInDeclarationContext, self.span_from(start))
      _ => ()
    }
  }
  { decls: items, span: self.span_from(start), }
}

///|
fn Parser::parse_keyframes_body(
  self : Parser,
  start : Int,
) -> Array[@ast.KeyframeBlock] raise @err.CssError {
  let frames : Array[@ast.KeyframeBlock] = []
  if self.peek() != LBrace {
    return frames
  }
  self.pos = self.pos + 1
  while true {
    self.skip_trivia()
    if self.at_eof() {
      self.error(UnclosedBlock("{"), self.span_from(start))
      return frames
    }
    if self.peek() == RBrace {
      self.pos = self.pos + 1
      return frames
    }
    let fstart = self.cur().span.start
    let sel_start = self.pos
    while !self.at_eof() && self.peek() != LBrace && self.peek() != RBrace {
      self.pos = self.pos + 1
    }
    let selectors = self.keyframe_selectors(
      self.toks[sel_start:self.pos],
      fstart,
    )
    if self.peek() != LBrace {
      continue
    }
    let decls = self.parse_decl_block(fstart)
    frames.push({ selectors, decls, span: self.span_from(fstart), })
  }
  frames
}

///|
fn Parser::keyframe_selectors(
  self : Parser,
  toks : ArrayView[@token.Token],
  at : Int,
) -> Array[@ast.KeyframeSelector] raise @err.CssError {
  let out : Array[@ast.KeyframeSelector] = []
  for t in toks {
    match t.kind {
      Ident(w) => {
        let l = w.to_lower()
        if l == "from" {
          out.push(From)
        } else if l == "to" {
          out.push(To)
        } else {
          self.error(BadKeyframeSelector, t.span)
        }
      }
      Percentage(r, v) =>
        out.push(Percentage({ repr: r, value: v, is_int: false, }))
      Comma | Whitespace | Comment(_) => ()
      _ => self.error(BadKeyframeSelector, t.span)
    }
  }
  if out.length() == 0 {
    self.error(BadKeyframeSelector, @span.Span::at(at))
  }
  out
}

///|
fn Parser::parse_import(
  self : Parser,
  name : String,
  prelude : ArrayView[@token.Token],
  start : Int,
) -> @ast.CssRule? raise @err.CssError {
  let c = { toks: prelude, pos: 0, }
  let url = match c.next_meaningful() {
    Some(Str(s)) => s
    Some(Url(u)) => u
    // `url("a.css")` -- a quoted body makes this a function call, not a `Url`
    // token, so both spellings have to be unwrapped to the same string.
    Some(Function(f)) if f.to_lower() == "url" => {
      let args = c.take_group()
      match first_meaningful(args) {
        Some(Str(s)) => s
        Some(Url(u)) => u
        _ => ""
      }
    }
    _ => {
      self.error(BadAtRulePrelude(name), span_of_view(prelude, start))
      return Some(
        Unknown({
          name,
          prelude: self.values_of(prelude),
          block: None,
          span: self.span_from(start),
        }),
      )
    }
  }
  let mut layer : @ast.LayerName?? = None
  let mut supports : @ast.Condition? = None
  let media_from = c.pos
  while true {
    match c.next_meaningful() {
      None => break
      Some(Ident(w)) =>
        if w.to_lower() == "layer" && layer is None {
          layer = Some(None)
        } else {
          c.pos = c.pos - 1
          break
        }
      Some(Function(f)) => {
        let l = f.to_lower()
        let args = c.take_group()
        if l == "layer" {
          layer = Some(Some({ parts: layer_parts(args), }))
        } else if l == "supports" {
          supports = Some(self.parse_condition(args, start))
        } else {
          break
        }
      }
      Some(_) => {
        c.pos = c.pos - 1
        break
      }
    }
  }
  ignore(media_from)
  let media = self.parse_media_list(c.rest(), start)
  Some(Import({ url, layer, supports, media, span: self.span_from(start), }))
}
