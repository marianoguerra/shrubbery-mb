///|
fn col(text : String) -> @column.Column {
  let (_, c) = @column.count_graphemes(text)
  c
}

///|
test "a column with no tab in it is just a count" {
  assert_eq(col("   "), @column.Column::of_chars(3))
  assert_eq(col(""), @column.zero)
  // One cluster, two code points.
  assert_eq(col("a\u{0301}"), @column.Column::of_chars(1))
}

///|
test "count_graphemes counts all three line terminators" {
  let (lines, c) = @column.count_graphemes("a\nb\r\nc\rd")
  assert_eq(lines, 3)
  // The column resets at each break, so only `d` is left.
  assert_eq(c, @column.Column::of_chars(1))
}

///|
test "a tab makes the prefix before it load-bearing" {
  // Both are "one tab in", but they got there over different prefixes, so
  // neither extends the other and comparing them is a mixed-tab error.
  assert_eq(col(" \t").cmp(col("  \t")), Incomparable)
  // Same prefix, so they are ordered normally.
  assert_eq(col(" \t").cmp(col(" \t ")), Lt)
  assert_eq(col(" \t ").cmp(col(" \t")), Gt)
  assert_eq(col(" \t").cmp(col(" \t")), Eq)
}

///|
test "a column is greater than any prefix of itself" {
  assert_true(col("  \t  ").gt(col("  \t")))
  assert_true(col("  ").lt(col("  \t")))
}

///|
test "the half column is ordered inside a character width" {
  let two = @column.Column::of_chars(2)
  assert_true(two.lt(two.half_up()))
  assert_true(two.half_up().lt(@column.Column::of_chars(3)))
}

///|
test "half a column before a tab is tolerated, not an error" {
  // `|` at the column a tab starts from: the reference answers every
  // comparison with false and does NOT complain.
  let order = col(" ").half_up().cmp(col(" \t"))
  assert_eq(order, Unordered)
  assert_false(col(" ").half_up().lt(col(" \t")))
  assert_false(col(" ").half_up().gt(col(" \t")))
  // `<=` is the NEGATION of `>`, so it is true here while `Lt || Eq` is false.
  assert_true(col(" ").half_up().le(col(" \t")))
  assert_true(col(" ").half_up().ge(col(" \t")))
}

///|
test "plus places its argument to the right" {
  assert_eq(
    @column.Column::of_chars(2).plus(@column.Column::of_chars(3)),
    @column.Column::of_chars(5),
  )
  // " \t" then "  " is the same column as "  " typed after " \t".
  assert_eq(col(" \t").plus(col("  ")), col(" \t  "))
}

///|
test "sub is zero across different tab structure" {
  assert_eq(@column.Column::of_chars(5).sub(@column.Column::of_chars(2)), 6)
  assert_eq(col(" \t  ").sub(col(" \t")), 4)
  assert_eq(col(" \t").sub(col("  \t")), 0)
}

///|
test "floor drops the half" {
  assert_eq(
    @column.Column::of_chars(2).half_up().floor(),
    @column.Column::of_chars(2),
  )
  assert_eq(col(" \t ").half_up().floor(), col(" \t "))
}
