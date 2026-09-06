///|
/// A CSS syntax tree.
///
/// The shape follows lightningcss for vocabulary -- typed selectors, typed
/// at-rule preludes, n-ary conditions -- and biome for tolerance: every enum a
/// parse can fail inside of has a `Bogus` member, so a parse always yields a
/// tree rather than an error, and the tree always covers the whole file.
///
/// It is a SEMANTIC tree, not a lossless one. `parse` then `write` gives back
/// CSS that means the same thing, not the same bytes: the printer decides
/// layout, and a declaration's original spacing is not recorded. Two things are
/// preserved anyway, because losing them is a semantic loss rather than a
/// formatting one:
///
///   * a number keeps its source spelling in `Number::repr`, so `1.50` and
///     `+1` and `1e3` survive a round trip;
///   * a hex colour keeps its digits and their case.
///
/// lightningcss quantises colours to `RGBA{u8,u8,u8,u8}`, which makes `#fff`,
/// `#ffffff` and `white` indistinguishable. That is right for a minifier and
/// wrong for anything that has to hand the stylesheet back to a person, so the
/// typed reading of a value lives in `css/value` as a lens over the syntax
/// rather than in the syntax itself.
///
/// Nothing here depends on `error-report`: a `Bogus` carries an `@kind.ErrorKind`,
/// which is a plain closed enum, so building a tree and printing it links
/// neither the diagnostic library nor the parser.

///|
/// What could not be parsed, kept so that the tree covers the whole source.
///
/// `text` is the exact source the node replaced. Keeping it is what lets the
/// printer echo an unparsable region verbatim instead of deleting it -- a
/// stylesheet with one vendor hack the parser does not know should come back
/// with that hack still in it.
pub(all) struct Bogus {
  kind : @kind.ErrorKind
  span : @span.Span
  text : String
} derive(Eq)

///|
pub fn Bogus::new(
  kind : @kind.ErrorKind,
  span : @span.Span,
  text? : String = "",
) -> Bogus {
  { kind, span, text, }
}

///|
/// A `/* ... */` comment.
///
/// `text` is the body, without the delimiters. Comments are attached to the
/// construct they precede rather than being free-floating, because a printer
/// that keeps them has to know where to put them back.
pub(all) struct Comment {
  text : String
  span : @span.Span
} derive(Eq)

// ---------------------------------------------------------------- stylesheet

///|
pub(all) struct Stylesheet {
  items : Array[TopItem]
  span : @span.Span
} derive(Eq)

///|
pub(all) enum TopItem {
  Rule(CssRule)
  Comment(Comment)
  Bogus(Bogus)
} derive(Eq)

///|
/// A rule, at any level.
///
/// Style rules and at-rules are one enum rather than two because CSS nesting
/// lets either appear wherever the other can, and splitting them would mean
/// every body was a pair of lists that had lost their relative order.
pub(all) enum CssRule {
  Style(StyleRule)
  Media(MediaRule)
  Supports(SupportsRule)
  Container(ContainerRule)
  Layer(LayerRule)
  Keyframes(KeyframesRule)
  FontFace(DeclBlock)
  Page(PageRule)
  Property(PropertyRule)
  Import(ImportRule)
  Charset(String, @span.Span)
  Namespace(NamespaceRule)
  Scope(ScopeRule)
  StartingStyle(Array[BlockItem], @span.Span)
  CounterStyle(String, DeclBlock)
  /// An at-rule whose name this library does not know, kept with its prelude
  /// unparsed. `block` distinguishes `@x { ... }` from `@x ...;`, which you
  /// must know in order to print it back.
  Unknown(UnknownAtRule)
  Bogus(Bogus)
} derive(Eq)

///|
/// The body of a rule: declarations and nested rules, in source order.
///
/// One sequence rather than two fields, because the cascade is order-sensitive
/// and CSS nesting interleaves them. lightningcss splits `!important` out into
/// a second vector for the same reason a minifier would; that reordering is
/// unrecoverable, so importance is a field on `Declaration` here.
pub(all) enum BlockItem {
  Decl(Declaration)
  Rule(CssRule)
  Comment(Comment)
  Bogus(Bogus)
} derive(Eq)

///|
/// A block that may hold only declarations -- `@font-face`, `@page`, a
/// keyframe. Typed separately so the parser can refuse a nested rule there
/// rather than accepting one and printing something invalid.
pub(all) struct DeclBlock {
  decls : Array[BlockItem]
  span : @span.Span
} derive(Eq)

///|
pub(all) struct StyleRule {
  selectors : Array[Selector]
  body : Array[BlockItem]
  span : @span.Span
} derive(Eq)

// -------------------------------------------------------------- declarations

///|
pub(all) struct Declaration {
  property : PropertyName
  value : Array[ComponentValue]
  important : Bool
  span : @span.Span
} derive(Eq)

///|
/// `Custom` carries the leading `--`, so that the two cases never have to be
/// re-joined to be printed and a `--` can never be lost.
pub(all) enum PropertyName {
  Ident(String)
  Custom(String)
} derive(Eq)

///|
pub fn PropertyName::text(self : PropertyName) -> String {
  match self {
    Ident(s) => s
    Custom(s) => s
  }
}

// --------------------------------------------------------------------- values

///|
/// A number, with the spelling it had in the source.
///
/// `repr` exists because CSS distinguishes `1` from `1.0` nowhere semantically
/// but everywhere visually, and a formatter that rewrote every number would
/// produce a diff on every line of a file it was asked only to reindent.
/// `value` is what arithmetic uses; `repr` is what the printer emits.
pub(all) struct Number {
  repr : String
  value : Double
  is_int : Bool
} derive(Eq)

///|
pub fn Number::of_int(n : Int) -> Number {
  { repr: n.to_string(), value: n.to_double(), is_int: true, }
}

///|
/// A component value: the generic model that every declaration value uses.
///
/// Generic rather than per-property, and that is the load-bearing choice in the
/// whole design. lightningcss types some five hundred properties, which buys
/// static guarantees and costs the ability to represent anything the table does
/// not know -- a vendor hack, a property added last month, a value behind a
/// flag. A stylesheet full of those is not an edge case, it is Tuesday.
///
/// The typed reading is recovered on demand by the lenses in `css/value`
/// (`as_length`, `as_color`, ...), the way biome layers `value_ext.rs` over its
/// untyped tree. That keeps coverage total and makes the typed view something
/// you opt into per question rather than something the parser must decide up
/// front for every property in existence.
pub(all) enum ComponentValue {
  /// A bare identifier, including a `--dashed-ident`.
  Ident(String)
  /// A quoted string, decoded.
  Str(String)
  Num(Number)
  /// A number with a unit: `10px`, `1.5rem`, `200ms`.
  Dimension(Number, String)
  Percentage(Number)
  /// The digits of a hex colour, without the `#`, case preserved.
  Hex(String)
  /// A `url(...)`, decoded, quoted or not.
  Url(String)
  Function(String, Array[ComponentValue])
  /// A parenthesised group that is not a function call.
  Paren(Array[ComponentValue])
  Bracket(Array[ComponentValue])
  /// A `,` separating values inside a list.
  Comma
  /// A `/`, which means something different in `grid-area`, in `font` and in
  /// `rgb(... / ...)` -- so it is kept as itself rather than interpreted.
  Slash
  /// Any other operator run: `+`, `-`, `*`, `<`, `=`.
  Delim(String)
  Bogus(Bogus)
} derive(Eq)

// ------------------------------------------------------------------ selectors

///|
/// A selector.
///
/// `Complex` is left-nested by construction: its right operand is a `Compound`,
/// not a `Selector`, so `a > b + c` has exactly one shape and associativity
/// needs no normalisation pass. lightningcss stores a flat right-to-left
/// component vector, which is the right thing for a matcher and the wrong thing
/// for a printer; biome's recursion is what this follows.
pub(all) enum Selector {
  Simple(Compound)
  Complex(Selector, Combinator, Compound)
  /// A selector that starts with a combinator, as a nested rule may:
  /// `> .child`.
  Relative(Combinator, Selector)
  Bogus(Bogus)
} derive(Eq)

///|
pub(all) enum Combinator {
  Descendant
  Child
  NextSibling
  SubsequentSibling
  Column
} derive(Eq)

///|
/// One element's worth of selector: an optional type, then qualifiers.
pub(all) struct Compound {
  type_sel : TypeSelector?
  quals : Array[Qualifier]
  span : @span.Span
} derive(Eq)

///|
pub(all) enum TypeSelector {
  Universal(NsPrefix?)
  Named(NsPrefix?, String)
} derive(Eq)

///|
/// `|a` is `None_`, `*|a` is `Any`, `svg|a` is `Named`.
pub(all) enum NsPrefix {
  None_
  Any
  Named(String)
} derive(Eq)

///|
pub(all) enum Qualifier {
  Class(String)
  Id(String)
  Attr(AttrSelector)
  Pseudo(PseudoClass)
  Element(PseudoElement)
  /// The `&` nesting selector.
  Nesting
  Bogus(Bogus)
} derive(Eq)

///|
/// Grouped by the *shape* of the argument, not by the name -- biome's choice,
/// and the one that makes printing expressible. `Simple` takes nothing, `Sub`
/// takes a selector list, `Nth` takes `An+B` with an optional `of` clause.
pub(all) enum PseudoClass {
  Simple(String)
  Nth(String, AnB, Array[Selector]?)
  Sub(String, Array[Selector])
  Lang(Array[String])
  Dir(String)
  /// A name this library does not know, kept with its arguments unparsed
  /// rather than dropped.
  Unknown(String, Array[ComponentValue])
} derive(Eq)

///|
pub(all) struct AnB {
  a : Int
  b : Int
} derive(Eq)

///|
pub(all) enum PseudoElement {
  Simple(String)
  Sub(String, Array[Selector])
  Fn(String, Array[ComponentValue])
} derive(Eq)

///|
pub(all) struct AttrSelector {
  ns : NsPrefix?
  name : String
  matcher : (AttrOp, AttrValue)?
  case_ : AttrCase
} derive(Eq)

///|
pub(all) enum AttrOp {
  Exact
  Includes
  DashMatch
  Prefix
  Suffix
  Substring
} derive(Eq)

///|
pub fn AttrOp::text(self : AttrOp) -> String {
  match self {
    Exact => "="
    Includes => "~="
    DashMatch => "|="
    Prefix => "^="
    Suffix => "$="
    Substring => "*="
  }
}

///|
pub(all) enum AttrValue {
  Str(String)
  Ident(String)
} derive(Eq)

///|
pub(all) enum AttrCase {
  Default
  Insensitive
  Sensitive
} derive(Eq)

// ----------------------------------------------------------------- conditions

///|
/// A `@media`, `@supports` or `@container` condition.
///
/// `Operation` is n-ary and stored flattened: `a and b and c` is one node with
/// three children, not two nested nodes. biome nests them because its grammar
/// language cannot express an n-ary list with interleaved keywords; there is no
/// such constraint here, and the flat form is what makes the round-trip
/// property a plain equality instead of an equality-modulo-associativity.
pub(all) enum Condition {
  Feature(Feature)
  /// `@supports (display: grid)`.
  Decl(Declaration)
  /// `@supports selector(a > b)`.
  SelectorFn(Array[Selector])
  Operation(LogicalOp, Array[Condition])
  /// A condition this library could not read, kept unparsed. CSS itself
  /// requires an unknown condition to evaluate false rather than to invalidate
  /// the rule, so dropping it would change what the stylesheet means.
  Unknown(Array[ComponentValue])
  Bogus(Bogus)
} derive(Eq)

///|
pub(all) enum LogicalOp {
  And
  Or
  Not
} derive(Eq)

///|
/// A media or container feature test, in all four shapes CSS gives it.
pub(all) enum Feature {
  /// `(hover)`
  Boolean(String)
  /// `(width: 40rem)`
  Plain(String, Array[ComponentValue])
  /// `(width <= 40rem)`
  Range(String, RangeOp, Array[ComponentValue])
  /// `(20rem <= width <= 40rem)`
  Interval(
    Array[ComponentValue],
    RangeOp,
    String,
    RangeOp,
    Array[ComponentValue]
  )
} derive(Eq)

///|
pub(all) enum RangeOp {
  Lt
  Le
  Gt
  Ge
  Eq
} derive(Eq)

///|
pub fn RangeOp::text(self : RangeOp) -> String {
  match self {
    Lt => "<"
    Le => "<="
    Gt => ">"
    Ge => ">="
    Eq => "="
  }
}

// -------------------------------------------------------------------- at-rules

///|
pub(all) struct MediaQuery {
  qualifier : MediaQualifier?
  media_type : String?
  condition : Condition?
} derive(Eq)

///|
pub(all) enum MediaQualifier {
  Only
  Not
} derive(Eq)

///|
pub(all) struct MediaRule {
  queries : Array[MediaQuery]
  body : Array[BlockItem]
  span : @span.Span
} derive(Eq)

///|
pub(all) struct SupportsRule {
  condition : Condition
  body : Array[BlockItem]
  span : @span.Span
} derive(Eq)

///|
pub(all) struct ContainerRule {
  name : String?
  condition : Condition
  body : Array[BlockItem]
  span : @span.Span
} derive(Eq)

///|
/// A dotted layer name: `base.theme` is `["base", "theme"]`.
pub(all) struct LayerName {
  parts : Array[String]
} derive(Eq)

///|
/// `body` is `None` for the statement form `@layer a, b;` and `Some` for the
/// block form. The two are different rules in CSS, not one rule with an
/// optional body, and the parser must know which it is to print it back.
pub(all) struct LayerRule {
  names : Array[LayerName]
  body : Array[BlockItem]?
  span : @span.Span
} derive(Eq)

///|
pub(all) enum KeyframesName {
  Ident(String)
  Str(String)
} derive(Eq)

///|
pub(all) enum KeyframeSelector {
  From
  To
  Percentage(Number)
} derive(Eq)

///|
pub(all) struct KeyframeBlock {
  selectors : Array[KeyframeSelector]
  decls : DeclBlock
  span : @span.Span
} derive(Eq)

///|
pub(all) struct KeyframesRule {
  name : KeyframesName
  frames : Array[KeyframeBlock]
  span : @span.Span
} derive(Eq)

///|
pub(all) struct PageRule {
  selectors : Array[String]
  body : Array[BlockItem]
  span : @span.Span
} derive(Eq)

///|
pub(all) struct PropertyRule {
  name : String
  decls : DeclBlock
  span : @span.Span
} derive(Eq)

///|
/// `layer` has three states and they are all different: absent, `layer`
/// (anonymous), and `layer(name)`. The nested option is what says so in the
/// type rather than in a comment.
pub(all) struct ImportRule {
  url : String
  layer : LayerName??
  supports : Condition?
  media : Array[MediaQuery]
  span : @span.Span
} derive(Eq)

///|
pub(all) struct NamespaceRule {
  prefix : String?
  url : String
  span : @span.Span
} derive(Eq)

///|
pub(all) struct ScopeRule {
  start : Array[Selector]?
  end : Array[Selector]?
  body : Array[BlockItem]
  span : @span.Span
} derive(Eq)

///|
pub(all) struct UnknownAtRule {
  name : String
  prelude : Array[ComponentValue]
  block : Array[BlockItem]?
  span : @span.Span
} derive(Eq)
