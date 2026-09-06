///|
/// A deterministic generator, and the machinery a property needs around it.
///
/// There is no property-testing framework in this workspace, and adding a
/// dependency for one would be paid for by every consumer of whichever module
/// carried it. So this is the minimum that is genuinely useful, and it lives in
/// the development module, where a dependency costs nobody and where reaching
/// the libraries through their public API keeps that API honest.
///
/// The precedent is `lib/write/write_test.mbt`, which states a property as a
/// helper and drives it over a fixed list. This adds the two things that
/// list cannot give: inputs nobody thought to write down, and a shrinker, so
/// that when one fails the report is small enough to read.

///|
/// splitmix64. Small, fast, and good enough -- the generator is looking for
/// counterexamples, not modelling anything.
struct Rng {
  mut state : UInt64
}

///|
pub fn Rng::new(seed : UInt64) -> Rng {
  { state: seed, }
}

///|
pub fn Rng::next(self : Rng) -> UInt64 {
  self.state = self.state + 0x9E3779B97F4A7C15UL
  let mut z = self.state
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL
  z ^ (z >> 31)
}

///|
/// A number in `[0, n)`. `n <= 0` gives 0, so a caller never has to guard.
pub fn Rng::below(self : Rng, n : Int) -> Int {
  if n <= 0 {
    0
  } else {
    (self.next() % n.to_uint64()).to_int()
  }
}

///|
pub fn Rng::bool(self : Rng) -> Bool {
  self.below(2) == 0
}

///|
/// One of `xs`. Empty is a caller error; it would mean a generator with no
/// alternatives, which is a bug rather than an input.
pub fn[T] Rng::pick(self : Rng, xs : Array[T]) -> T {
  xs[self.below(xs.length())]
}

///|
/// One of `alts`, by weight.
///
/// Weights exist so that a leaf can be made common and a deeply recursive
/// alternative rare, which is what keeps generated trees a useful shape rather
/// than either trivial or enormous.
pub fn[T] Rng::weighted(self : Rng, alts : Array[(Int, T)]) -> T {
  let mut total = 0
  for a in alts {
    total = total + a.0
  }
  let mut roll = self.below(total)
  for a in alts {
    roll = roll - a.0
    if roll < 0 {
      return a.1
    }
  }
  alts[alts.length() - 1].1
}

///|
/// Greedily shrink a failing value to a smaller one that still fails.
///
/// First-failing-candidate rather than best: the point is a report small enough
/// to read, and searching for the true minimum costs far more than it returns.
/// `fuel` bounds it whatever the shrinker does, so a shrink that fails to make
/// progress cannot hang the suite -- and `size` is asserted to strictly
/// decrease by a test of its own, so it should not be able to anyway.
pub fn[T] minimize(
  x : T,
  shrink : (T) -> Array[T],
  fails : (T) -> Bool,
  fuel? : Int = 400,
) -> T {
  let mut cur = x
  let mut left = fuel
  while left > 0 {
    let mut moved = false
    for candidate in shrink(cur) {
      if fails(candidate) {
        cur = candidate
        moved = true
        break
      }
    }
    if !moved {
      break
    }
    left = left - 1
  }
  cur
}
