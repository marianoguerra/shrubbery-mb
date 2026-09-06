///|
test "a page built by hand prints" {
  inspect(
    @embed_html.example(),
    content=(
      #|<main class="card">
      #|  <h1>Hello, world</h1>
      #|</main>
      #|
    ),
  )
}
