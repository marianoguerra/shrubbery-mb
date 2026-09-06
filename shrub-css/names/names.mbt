///|
/// The vocabulary: what each name in the shrubbery surface means in CSS.
///
/// These tables are the syntax. The whole design rests on one rule -- write the
/// thing's name, not a symbol for it -- and the tables are where "the thing's
/// name" is decided. They are data rather than code so that a reader can check
/// the mapping at a glance and so that a disagreement about one entry is a
/// one-line change.
///
/// Nothing here is a *closed* set in the sense of rejecting what is missing. A
/// pseudo-class this table does not know is kept as an unknown pseudo-class, an
/// at-rule it does not know is kept unparsed. CSS grows faster than any table,
/// and a bridge that refused everything new would be wrong within a year.

// ------------------------------------------------------ identifier spelling

///|
/// A shrubbery identifier as a CSS identifier: `_` becomes `-`.
///
/// The transform is needed because `-` is an operator in shrubbery, so
/// `font-size` lexes as three tokens and the tree cannot tell it from
/// `font - size`.
///
/// A name that already contains a `-` is passed through untouched. That is not
/// a special case for tidiness: the only way a `-` can reach an identifier is
/// through a `#{...}` escape, which the lexer resolves to the symbol's own
/// name, and a name written that way was written literally on purpose.
pub fn unkebab(s : String) -> String {
  if s.contains("-") {
    s
  } else {
    s.replace_all(old="_", new="-")
  }
}

///|
/// A CSS identifier as a shrubbery identifier, or `None` if it cannot be one.
///
/// `None` exactly when the name contains a `_`, because `unkebab` would then
/// not invert: `side_bar` would come back as `side-bar`. The caller's answer to
/// `None` is the literal escape -- `ident("side_bar")`, `class("btn__x")` --
/// which is why this returns an option rather than guessing.
pub fn kebab(s : String) -> String? {
  if s.contains("_") {
    None
  } else {
    Some(s.replace_all(old="-", new="_"))
  }
}

// ----------------------------------------------------------------- units

///|
/// A unit call name as its CSS unit, or `None` if it is not a unit.
///
/// Almost all of them are the identity; the three that are not are the ones CSS
/// spells with a capital, which a shrubbery identifier can carry but which
/// would be an odd thing to type.
pub fn unit_of(name : String) -> String? {
  match name {
    "q" => Some("Q")
    "hz" => Some("Hz")
    "khz" => Some("kHz")
    _ => if is_plain_unit(name) { Some(name) } else { None }
  }
}

///|
/// The unit call for a CSS unit, or `None` if it has no short spelling.
///
/// `None` sends the caller to `dim(n, "unit")`, the escape for a unit this
/// table does not know -- which is how a stylesheet using a unit newer than
/// this library still round-trips.
pub fn unit_call(unit : String) -> String? {
  let call = match unit {
    "Q" => "q"
    "Hz" => "hz"
    "kHz" => "khz"
    _ => unit.to_lower()
  }
  // Only when the call names this exact spelling. CSS units are
  // case-insensitive, so `5EM` and `5em` mean the same thing -- but they are
  // not the same TEXT, and a bridge that quietly lower-cased one would rewrite
  // a line it was asked only to reformat. A non-canonical spelling takes the
  // `dim(n, "EM")` escape instead, which keeps it exactly.
  match unit_of(call) {
    Some(u) if u == unit => Some(call)
    _ => None
  }
}

///|
fn is_plain_unit(u : String) -> Bool {
  match u {
    // Absolute lengths.
    "px" | "cm" | "mm" | "in" | "pt" | "pc" => true
    // Font-relative.
    "em" | "rem" | "ex" | "rex" | "cap" | "rcap" | "ch" | "rch" => true
    "ic" | "ric" | "lh" | "rlh" => true
    // Viewport-relative, in all four flavours.
    "vw" | "vh" | "vi" | "vb" | "vmin" | "vmax" => true
    "svw" | "svh" | "svi" | "svb" | "svmin" | "svmax" => true
    "lvw" | "lvh" | "lvi" | "lvb" | "lvmin" | "lvmax" => true
    "dvw" | "dvh" | "dvi" | "dvb" | "dvmin" | "dvmax" => true
    // Container-relative.
    "cqw" | "cqh" | "cqi" | "cqb" | "cqmin" | "cqmax" => true
    // Angles, times, frequencies, resolutions, flex.
    "deg" | "grad" | "rad" | "turn" => true
    "s" | "ms" => true
    "dpi" | "dpcm" | "dppx" | "x" => true
    "fr" => true
    _ => false
  }
}

// -------------------------------------------------------- pseudo-classes

///|
/// A pseudo-class that takes no arguments: `hover()`, `first_child()`.
pub fn is_simple_pseudo(name : String) -> Bool {
  match name {
    "active" | "any-link" | "autofill" | "blank" | "checked" | "current" => true
    "default" | "defined" | "disabled" | "empty" | "enabled" => true
    "first" | "first-child" | "first-of-type" | "focus" => true
    "focus-visible" | "focus-within" | "fullscreen" | "future" => true
    "host" | "hover" | "in-range" | "indeterminate" | "invalid" => true
    "last-child" | "last-of-type" | "left" | "link" | "local-link" => true
    "modal" | "only-child" | "only-of-type" | "optional" => true
    "out-of-range" | "past" | "paused" | "picture-in-picture" => true
    "placeholder-shown" | "playing" | "popover-open" | "read-only" => true
    "read-write" | "required" | "right" | "root" | "scope" | "target" => true
    "target-within" | "user-invalid" | "user-valid" | "valid" => true
    "visited" | "open" | "closed" | "muted" | "seeking" | "buffering" => true
    "stalled" | "volume-locked" => true
    _ => false
  }
}

///|
/// A pseudo-class whose argument is a selector list: `not(...)`, `is(...)`.
pub fn is_selector_pseudo(name : String) -> Bool {
  match name {
    "is" | "where" | "not" | "has" | "host" | "host-context" => true
    "matches" | "any" | "slotted" => true
    _ => false
  }
}

///|
/// A pseudo-class taking an `An+B` formula.
pub fn is_nth_pseudo(name : String) -> Bool {
  match name {
    "nth-child" | "nth-last-child" | "nth-of-type" => true
    "nth-last-of-type" | "nth-col" | "nth-last-col" => true
    _ => false
  }
}

// ------------------------------------------------------- pseudo-elements

///|
/// A pseudo-element name, written `element(before)`.
///
/// Pseudo-elements need their own word rather than a bare call, because CSS
/// spends an entire extra colon distinguishing them from pseudo-classes and a
/// bare `before()` would throw that distinction away. The call has to spend a
/// word where CSS spent a character.
pub fn is_pseudo_element(name : String) -> Bool {
  match name {
    "before" | "after" | "first-line" | "first-letter" => true
    "marker" | "placeholder" | "selection" | "backdrop" => true
    "file-selector-button" | "target-text" | "grammar-error" => true
    "spelling-error" | "cue" | "cue-region" | "details-content" => true
    "view-transition" | "search-text" | "checkmark" | "picker-icon" => true
    _ => false
  }
}

///|
/// A pseudo-element that takes arguments: `element(part(x))`.
pub fn is_pseudo_element_fn(name : String) -> Bool {
  match name {
    "part" | "slotted" | "highlight" | "picker" => true
    "view-transition-group" | "view-transition-image-pair" => true
    "view-transition-old" | "view-transition-new" | "cue" => true
    _ => false
  }
}

// -------------------------------------------------------------- at-rules

///|
/// An at-rule name, written as a call: `media(...)`, `font_face()`.
pub fn is_at_rule(name : String) -> Bool {
  match name {
    "media" | "supports" | "container" | "layer" | "keyframes" => true
    "font-face" | "font-feature-values" | "font-palette-values" => true
    "counter-style" | "page" | "property" | "scope" => true
    "starting-style" | "import" | "charset" | "namespace" => true
    "document" | "viewport" | "position-try" | "view-transition" => true
    // The escape for an at-rule this table does not know. It has to be here,
    // because this predicate is what makes `statement` dispatch to the at-rule
    // path at all.
    "at" => true
    _ => false
  }
}

// ---------------------------------------------------------- combinators

///|
/// The relation a shrubbery keyword names.
///
/// Relations are keywords rather than calls because a combinator sits BETWEEN
/// its operands, where a call cannot reach without swallowing them both:
/// `child(a, b)` destroys a chain the moment it has three parts. `~name` is
/// shrubbery's own syntax for a name used as a marker, so the form is the
/// notation's rather than an invention.
pub fn combinator_of(keyword : String) -> Combinator? {
  match keyword {
    "in" => Some(Descendant)
    "child" => Some(Child)
    "next" => Some(NextSibling)
    "sibling" => Some(SubsequentSibling)
    "column" => Some(Column)
    _ => None
  }
}

///|
/// The keyword for a relation.
pub fn combinator_keyword(c : Combinator) -> String {
  match c {
    Descendant => "in"
    Child => "child"
    NextSibling => "next"
    SubsequentSibling => "sibling"
    Column => "column"
  }
}

///|
/// The relations, named here rather than imported, so that this package has no
/// dependencies and can be read on its own.
///
/// It mirrors `@ast.Combinator` exactly; `lower` and `emit` convert between
/// them. The duplication buys a table anyone can check without following an
/// import.
pub(all) enum Combinator {
  Descendant
  Child
  NextSibling
  SubsequentSibling
  Column
} derive(Eq, Debug)

// ------------------------------------------------------- reserved callables

///|
/// A call name that means something other than a CSS function.
///
/// The bridge has to know these before it can decide whether `x(1)` is a unit,
/// a qualifier or an ordinary CSS function call -- and the answer differs by
/// position, so each caller consults the table it needs rather than one shared
/// one. This predicate exists for the reverse direction: when printing a CSS
/// function whose name collides with a bridge word, the name has to be escaped
/// rather than emitted bare.
pub fn is_reserved_call(name : String) -> Bool {
  match name {
    "class" | "id" | "any" | "parent" | "ns" | "has_attr" | "element" => true
    "hex" | "percent" | "important" | "dim" | "ident" | "tag" => true
    _ => is_plain_unit(name)
  }
}
