///|
test "a tree built by hand prints" {
  // The space is the printer's, not a mistake: terms in a group are separated
  // by one, and the notation has no idea that `greet` and `(...)` were meant
  // to be a call. Re-reading it gives back the same tree either way.
  inspect(@embed.example(), content="greet (\"world\")")
}
