///|
test "the canonical form is unambiguous ASCII" {
  assert_eq(@sexp.Datum::Sym("hello").canonical(), "|hello|")
  assert_eq(@sexp.Datum::Sym("a|b\\c").canonical(), "|a\\|b\\\\c|")
  assert_eq(@sexp.Datum::Str("λ").canonical(), "\"\\u{3bb}\"")
  assert_eq(@sexp.Datum::Kw("style").canonical(), "#:|style|")
  assert_eq(@sexp.Datum::Bool_(true).canonical(), "#t")
  assert_eq(@sexp.Datum::Ch('A').canonical(), "#\\u{41}")
}

///|
test "a flonum is written as its bits, not as digits" {
  // 1.0 is 0x3FF0000000000000. Writing digits would put us in the business of
  // reproducing Racket's shortest-round-trip printer, which is not a thing the
  // parse oracle should depend on.
  assert_eq(@sexp.Datum::Flo(1.0).canonical(), "#f64:3ff0000000000000")
  assert_eq(@sexp.Datum::Flo(0.0).canonical(), "#f64:0000000000000000")
  // Negative zero is a different value and prints differently.
  assert_eq(@sexp.Datum::Flo(-0.0).canonical(), "#f64:8000000000000000")
  assert_eq(
    @sexp.Datum::Flo(@double.infinity).canonical(),
    "#f64:7ff0000000000000",
  )
}

///|
test "rationals are reduced, with the sign on the numerator" {
  let two = @bigint.BigInt::from_int(2)
  let four = @bigint.BigInt::from_int(4)
  let neg = @bigint.BigInt::from_int(-1)
  assert_eq(@sexp.Datum::of_ratio(two, four).canonical(), "1/2")
  assert_eq(@sexp.Datum::of_ratio(two, neg).canonical(), "-2")
  assert_eq(
    @sexp.Datum::of_ratio(@bigint.BigInt::from_int(3), neg * two).canonical(),
    "-3/2",
  )
  // A rational that reduces to an integer becomes one, as in Racket.
  assert_eq(@sexp.Datum::of_ratio(four, two).canonical(), "2")
}

///|
test "structure" {
  assert_eq(@sexp.Datum::Nil.canonical(), "()")
  assert_eq(
    @sexp.Datum::Pair(@sexp.Datum::of_int(1), @sexp.Datum::of_int(2)).canonical(),
    "(1 . 2)",
  )
  assert_eq(
    @sexp.Datum::Vec([@sexp.Datum::of_int(1), Sym("x")]).canonical(),
    "#(1 |x|)",
  )
}
