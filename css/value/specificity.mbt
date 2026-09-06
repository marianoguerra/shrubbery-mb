///|
/// Specificity.
///
/// Computed on demand rather than stored on the selector, which is the opposite
/// of lightningcss -- it caches specificity on every `Selector`, because a
/// matcher asks for it constantly. Nothing here matches anything, and a stored
/// field would have to be kept correct through every construction and every
/// rewrite for the benefit of a question nobody has asked yet.

///|
/// The three counts CSS compares, most significant first.
///
/// A triple rather than a packed integer: the packed form overflows on absurd
/// input and reads as a magic number when it does not, and comparing three
/// fields is not the expensive part of anything.
pub(all) struct Specificity {
  ids : Int
  classes : Int
  elements : Int
} derive(Eq, Debug)

///|
pub fn Specificity::zero() -> Specificity {
  { ids: 0, classes: 0, elements: 0, }
}

///|
pub fn Specificity::add(self : Specificity, other : Specificity) -> Specificity {
  {
    ids: self.ids + other.ids,
    classes: self.classes + other.classes,
    elements: self.elements + other.elements,
  }
}

///|
/// Whether this selector wins against that one.
pub fn Specificity::beats(self : Specificity, other : Specificity) -> Bool {
  if self.ids != other.ids {
    self.ids > other.ids
  } else if self.classes != other.classes {
    self.classes > other.classes
  } else {
    self.elements > other.elements
  }
}

///|
/// `(a, b, c)`, the way CSS writes it.
pub fn Specificity::to_triple(self : Specificity) -> (Int, Int, Int) {
  (self.ids, self.classes, self.elements)
}

///|
/// The specificity of a selector.
pub fn specificity(s : @ast.Selector) -> Specificity {
  match s {
    Simple(c) => compound_specificity(c)
    Complex(left, _, right) =>
      specificity(left).add(compound_specificity(right))
    // A combinator contributes nothing, so a relative selector is just its
    // right-hand side.
    Relative(_, inner) => specificity(inner)
    Bogus(_) => Specificity::zero()
  }
}

///|
/// The specificity of a selector LIST, which is not the sum.
///
/// A list has no single specificity -- each arm has its own, and the cascade
/// compares whichever one matched. This returns the highest, which is what
/// `:is()` and `:not()` contribute and what a caller asking "how specific is
/// this rule" almost always means.
pub fn max_specificity(sels : Array[@ast.Selector]) -> Specificity {
  let mut best = Specificity::zero()
  for s in sels {
    let sp = specificity(s)
    if sp.beats(best) {
      best = sp
    }
  }
  best
}

///|
fn compound_specificity(c : @ast.Compound) -> Specificity {
  let mut sp = match c.type_sel {
    // A type selector counts as an element; the universal selector counts as
    // nothing at all, which is the one exception in the whole calculation.
    Some(Named(_, _)) => { ids: 0, classes: 0, elements: 1, }
    Some(Universal(_)) => Specificity::zero()
    None => Specificity::zero()
  }
  for q in c.quals {
    sp = sp.add(qualifier_specificity(q))
  }
  sp
}

///|
fn qualifier_specificity(q : @ast.Qualifier) -> Specificity {
  match q {
    Id(_) => { ids: 1, classes: 0, elements: 0, }
    Class(_) => { ids: 0, classes: 1, elements: 0, }
    Attr(_) => { ids: 0, classes: 1, elements: 0, }
    Element(_) => { ids: 0, classes: 0, elements: 1, }
    // `&` takes the specificity of what it stands for, which is not known
    // here: this package sees one selector, not the rule around it. Zero is
    // the honest answer for a lens that cannot see the nesting.
    Nesting => Specificity::zero()
    Bogus(_) => Specificity::zero()
    Pseudo(p) => pseudo_specificity(p)
  }
}

///|
/// A pseudo-class's specificity, which is where CSS stops being uniform.
fn pseudo_specificity(p : @ast.PseudoClass) -> Specificity {
  match p {
    Simple(name) =>
      // The three that count as nothing, and everything else as a class.
      if is_zero_pseudo(name.to_lower()) {
        Specificity::zero()
      } else {
        { ids: 0, classes: 1, elements: 0, }
      }
    Sub(name, sels) => {
      let lower = name.to_lower()
      if lower == "where" {
        // `:where()` is the whole reason this function is not one line: it
        // contributes nothing, whatever is inside it.
        Specificity::zero()
      } else if lower == "is" || lower == "not" || lower == "has" {
        // These take the specificity of their most specific argument -- which
        // is exactly why a selector list may not be spelled `is(...)` in the
        // shrubbery syntax: it would change what the stylesheet matches.
        max_specificity(sels)
      } else {
        { ids: 0, classes: 1, elements: 0, }
      }
    }
    Nth(_, _, of_) =>
      match of_ {
        // `:nth-child(An+B of S)` is a class, plus the most specific arm of S.
        Some(sels) =>
          ({ ids: 0, classes: 1, elements: 0, } : Specificity).add(
            max_specificity(sels),
          )
        None => { ids: 0, classes: 1, elements: 0, }
      }
    Lang(_) | Dir(_) => { ids: 0, classes: 1, elements: 0, }
    Unknown(_, _) => { ids: 0, classes: 1, elements: 0, }
  }
}

///|
/// The pseudo-classes that contribute nothing.
fn is_zero_pseudo(name : String) -> Bool {
  match name {
    "where" | "host" | "host-context" | "slotted" => true
    _ => false
  }
}
