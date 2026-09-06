///|
/// Tokenizer tests.
///
/// These check the stream, not the tree: what the scanner decides is a tag and
/// what it decides is text, which is where the parser's every later decision
/// comes from. The cases are the ones where the same bytes could plausibly mean
/// something else.

///|
test "a tag, its attributes, and text" {
  inspect(
    @token.dump(@token.tokens("<p class=\"a\" id=x>hi</p>")),
    content=(
      #|start p class=a id=x
      #|text hi
      #|end p
      #|eof
      #|
    ),
  )
}

///|
test "a valueless attribute is not an empty one" {
  let ts = @token.tokens("<input disabled value=\"\">")
  match ts[0].kind {
    StartTag(_, attrs, _) => {
      assert_eq(attrs[0].value, None)
      assert_eq(attrs[1].value, Some(""))
    }
    _ => fail("expected a start tag")
  }
}

///|
test "the second of two identical attributes is dropped" {
  let s = @token.tokenize("<a href=\"one\" href=\"two\">")
  match s.tokens[0].kind {
    StartTag(_, attrs, _) => {
      assert_eq(attrs.length(), 1)
      assert_eq(attrs[0].value, Some("one"))
    }
    _ => fail("expected a start tag")
  }
  assert_eq(s.problems[0].0.code(), "html::duplicate_attribute")
}

///|
test "a script body is not markup" {
  inspect(
    @token.dump(@token.tokens("<script>if (a<b) { x() }</script>")),
    content=(
      #|start script
      #|rawtext if (a<b) { x() }
      #|end script
      #|eof
      #|
    ),
  )
}

///|
test "a title body resolves references and is not markup" {
  inspect(
    @token.dump(@token.tokens("<title>a &amp; b</title>")),
    content=(
      #|start title
      #|text a & b
      #|end title
      #|eof
      #|
    ),
  )
}

///|
test "longest match wins among named references" {
  inspect(
    @token.dump(@token.tokens("<p>&notin;</p>")),
    content=(
      #|start p
      #|text ∉
      #|end p
      #|eof
      #|
    ),
  )
}

///|
test "a reference without its semicolon still resolves in text" {
  let s = @token.tokenize("<p>&amp</p>")
  inspect(
    @token.dump(s.tokens),
    content=(
      #|start p
      #|text &
      #|end p
      #|eof
      #|
    ),
  )
  assert_eq(
    s.problems[0].0.code(),
    "html::missing_semicolon_after_character_reference",
  )
}

///|
test "and does not resolve in an attribute value followed by a letter" {
  match @token.tokens("<a href=\"?a=1&ampx=2\">")[0].kind {
    StartTag(_, attrs, _) => assert_eq(attrs[0].value, Some("?a=1&ampx=2"))
    _ => fail("expected a start tag")
  }
}

///|
test "the Windows-1252 remapping is what makes real pages readable" {
  inspect(
    @token.dump(@token.tokens("&#147;quoted&#148;")),
    content=(
      #|text “quoted”
      #|eof
      #|
    ),
  )
}

///|
test "a bare ampersand is text, and keeps its spelling" {
  match @token.tokens("a & b")[0].kind {
    Text(t, raw) => {
      assert_eq(t, "a & b")
      assert_eq(raw, None)
    }
    _ => fail("expected text")
  }
}

///|
test "a decoded run keeps the spelling it had" {
  match @token.tokens("a &amp; b")[0].kind {
    Text(t, raw) => {
      assert_eq(t, "a & b")
      assert_eq(raw, Some("a &amp; b"))
    }
    _ => fail("expected text")
  }
}

///|
test "a self-closing tag says so, and the parser decides what it means" {
  match @token.tokens("<circle />")[0].kind {
    StartTag(name, _, sc) => {
      assert_eq(name, "circle")
      assert_true(sc)
    }
    _ => fail("expected a start tag")
  }
}

///|
test "a comment, and one that closes before it opens" {
  inspect(
    @token.dump(@token.tokens("<!-- x --><!-->")),
    content=(
      #|comment  x 
      #|comment 
      #|eof
      #|
    ),
  )
}

///|
test "a processing instruction is a bogus comment, not a tag" {
  let s = @token.tokenize("<?php echo 1; ?>")
  inspect(
    @token.dump(s.tokens),
    content=(
      #|comment ?php echo 1; ?
      #|eof
      #|
    ),
  )
  assert_eq(s.problems[0].0.code(), "html::bogus_comment")
}

///|
test "a doctype, plain and legacy" {
  inspect(
    @token.dump(@token.tokens("<!DOCTYPE html>")),
    content=(
      #|doctype html
      #|eof
      #|
    ),
  )
  match
    @token.tokens(
      "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01//EN\" \"http://www.w3.org/TR/html4/strict.dtd\">",
    )[0].kind {
    Doctype(name, public_id, system_id) => {
      assert_eq(name, "html")
      assert_eq(public_id, Some("-//W3C//DTD HTML 4.01//EN"))
      assert_eq(system_id, Some("http://www.w3.org/TR/html4/strict.dtd"))
    }
    _ => fail("expected a doctype")
  }
}

///|
test "an unterminated tag ends the stream rather than looping" {
  let s = @token.tokenize("<div class=\"a")
  assert_eq(s.tokens.length(), 2)
  assert_eq(s.problems[0].0.code(), "html::eof_in_tag")
}
