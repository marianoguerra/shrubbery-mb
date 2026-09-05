///|
/// Build a shrubbery from nothing and print it.
///
/// No source text is involved, which is the point: this is what a code
/// generator does, and it is why the tree and the printer are packages a
/// consumer can take without the front end.
pub fn example() -> String {
  let zero : @basic.Pos = @basic.start
  let span : @basic.Span = { start: zero, end: zero, }
  let name = @ast.Node::new(Id("greet"), span)
  let who = @ast.Node::new(Lit(Str("world")), span)
  let args = @ast.Node::new(Group([who]), span)
  let parens = @ast.Node::new(Parens([args]), span)
  let group = @ast.Node::new(Group([name, parens]), span)
  let doc = @ast.Node::new(Multi([group]), span)
  @write.write(doc)
}
