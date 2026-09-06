///|
/// Build a page from nothing and print it.
///
/// No source text is involved, which is the point: this is what a template
/// engine does, and it is why the tree and the printer are packages a consumer
/// can take without the front end -- and without the diagnostic library, since
/// a tree built in memory has nothing to diagnose.
pub fn example() -> String {
  let text : @ast.Node = Text(@ast.Text::new("Hello, world"))
  let title : @ast.Node = Element({
    name: @ast.TagName::html("h1"),
    attrs: [],
    children: [text],
    closing: Explicit,
    span: @span.nowhere,
    name_span: @span.nowhere,
  })
  let body : @ast.Node = Element({
    name: @ast.TagName::html("main"),
    attrs: [
      {
        name: @ast.AttrName::plain("class"),
        value: Value("card", None),
        span: @span.nowhere,
      },
    ],
    children: [title],
    closing: Explicit,
    span: @span.nowhere,
    name_span: @span.nowhere,
  })
  @write.document({ children: [body], span: @span.nowhere, })
}
