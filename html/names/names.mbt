///|
/// The vocabulary: what each name in HTML, SVG and MathML means to a parser
/// that is not building a document tree.
///
/// These tables are the part of the WHATWG tree-construction algorithm that is
/// *data*. Keeping them here, apart from the parser, is what lets the parser be
/// a markup parser rather than a browser: it consults a table to decide that an
/// open `<li>` is closed by the next `<li>`, and it consults nothing at all
/// about the adoption agency or foster parenting, which are algorithms and
/// deliberately out of scope.
///
/// This package has no dependencies. Every consumer of the module needs it --
/// the tokenizer to know where raw text ends, the printer to know what may be
/// laid out -- and none of them should link a diagnostic library to ask.

// ------------------------------------------------------------ content models

///|
/// An element that cannot have children or an end tag.
///
/// The five legacy names are here because a parser meets them in real archives
/// and a parser that treated `<frame>` as an open element would swallow the
/// rest of the file into it.
pub fn is_void(name : String) -> Bool {
  match name {
    "area"
    | "base"
    | "br"
    | "col"
    | "embed"
    | "hr"
    | "img"
    | "input"
    | "link"
    | "meta"
    | "source"
    | "track"
    | "wbr"
    | "basefont"
    | "bgsound"
    | "frame"
    | "keygen"
    | "param" => true
    _ => false
  }
}

///|
/// An element whose content is text that is never escaped and never contains
/// markup: it ends at the first matching end tag and at nothing else.
///
/// This is the one place where lexing depends on a name, which is why the
/// tokenizer has to know the table rather than being able to scan blindly.
pub fn is_raw_text(name : String) -> Bool {
  match name {
    "script" | "style" | "xmp" | "iframe" | "noembed" | "noframes" => true
    _ => false
  }
}

///|
/// An element whose content is text with character references but no markup.
///
/// The difference from raw text is exactly one thing -- `&amp;` resolves -- and
/// it is the difference between a `<title>` that can contain an ampersand and
/// one that cannot.
pub fn is_escapable_raw_text(name : String) -> Bool {
  match name {
    "textarea" | "title" => true
    _ => false
  }
}

///|
/// An element whose text content is significant down to the last space.
///
/// A printer may not touch whitespace inside one of these, and the fact that a
/// newline immediately after the open tag is eaten by every parser is the
/// reason `write` emits two when it wants one.
pub fn is_preformatted(name : String) -> Bool {
  match name {
    "pre" | "textarea" | "listing" | "plaintext" | "xmp" => true
    _ => false
  }
}

// ------------------------------------------------------------ implied ends

///|
/// Whether this element may be closed by something other than its own end tag.
///
/// The set is the specification's "generate implied end tags" plus the table
/// elements, and being on it is what makes `Closing::Implied` reachable. An
/// element not on it that meets an end tag for something else is a diagnostic,
/// not a silent reshuffle.
pub fn auto_closes(name : String) -> Bool {
  match name {
    "p"
    | "li"
    | "dt"
    | "dd"
    | "option"
    | "optgroup"
    | "rt"
    | "rp"
    | "rb"
    | "rtc"
    | "td"
    | "th"
    | "tr"
    | "thead"
    | "tbody"
    | "tfoot"
    | "caption"
    | "colgroup"
    | "head"
    | "body"
    | "html" => true
    _ => false
  }
}

///|
/// Whether an open `open` is closed by an incoming start tag `incoming`.
///
/// This is the whole of tree construction that this library performs, and the
/// line is drawn where the specification itself stops stating rules and starts
/// stating algorithms. Everything here is a lookup; nothing here reorders a
/// node or invents one.
pub fn implies_close(open : String, incoming : String) -> Bool {
  match open {
    "p" => closes_paragraph(incoming)
    "li" => incoming == "li"
    "dt" | "dd" => incoming == "dt" || incoming == "dd"
    "option" => incoming == "option" || incoming == "optgroup"
    "optgroup" => incoming == "optgroup"
    "rt" | "rp" | "rb" | "rtc" =>
      incoming == "rt" ||
      incoming == "rp" ||
      incoming == "rb" ||
      incoming == "rtc"
    "td" | "th" =>
      incoming == "td" ||
      incoming == "th" ||
      incoming == "tr" ||
      is_table_section(incoming)
    "tr" => incoming == "tr" || is_table_section(incoming)
    "thead" | "tbody" | "tfoot" => is_table_section(incoming)
    "caption" =>
      is_table_section(incoming) || incoming == "tr" || incoming == "colgroup"
    "colgroup" => incoming != "col"
    "head" => incoming == "body"
    _ => false
  }
}

///|
fn is_table_section(name : String) -> Bool {
  name == "thead" || name == "tbody" || name == "tfoot"
}

///|
/// The specification's list of start tags that close an open paragraph.
///
/// It is long, arbitrary, and exactly the list -- shortening it to "any block
/// element" would be tidier and would get `<p>a<span>` wrong in the other
/// direction, because the rule is about these names and not about display.
fn closes_paragraph(incoming : String) -> Bool {
  match incoming {
    "address"
    | "article"
    | "aside"
    | "blockquote"
    | "center"
    | "details"
    | "dialog"
    | "dir"
    | "div"
    | "dl"
    | "dt"
    | "dd"
    | "fieldset"
    | "figcaption"
    | "figure"
    | "footer"
    | "form"
    | "h1"
    | "h2"
    | "h3"
    | "h4"
    | "h5"
    | "h6"
    | "header"
    | "hgroup"
    | "hr"
    | "li"
    | "main"
    | "menu"
    | "nav"
    | "ol"
    | "p"
    | "pre"
    | "search"
    | "section"
    | "summary"
    | "table"
    | "ul" => true
    _ => false
  }
}

// ---------------------------------------------------------------- display

///|
/// The default `display` of an element, coarsened to what a printer needs.
///
/// Four values rather than CSS's twenty, because the only question asked of
/// this table is whether whitespace around an element may be rearranged. That
/// is also why it is here and not derived from the CSS module: the answer is a
/// property of the HTML element, not of any stylesheet, and reaching for `css`
/// to ask it would put a dependency in the manifest for a lookup table.
pub(all) enum Display {
  /// Whitespace at the edges is insignificant; the printer may indent.
  Block
  /// Whitespace at the edges is significant.
  Inline
  /// Whitespace inside is significant down to the last space.
  Pre
  /// Not rendered: whitespace around it is insignificant either way.
  None_
} derive(Eq, Debug)

///|
pub fn display_of(name : String) -> Display {
  if is_preformatted(name) {
    return Pre
  }
  match name {
    "script"
    | "style"
    | "head"
    | "title"
    | "meta"
    | "link"
    | "base"
    | "template" => None_
    "html"
    | "body"
    | "address"
    | "article"
    | "aside"
    | "blockquote"
    | "center"
    | "dd"
    | "details"
    | "dialog"
    | "dir"
    | "div"
    | "dl"
    | "dt"
    | "fieldset"
    | "figcaption"
    | "figure"
    | "footer"
    | "form"
    | "h1"
    | "h2"
    | "h3"
    | "h4"
    | "h5"
    | "h6"
    | "header"
    | "hgroup"
    | "hr"
    | "li"
    | "main"
    | "menu"
    | "nav"
    | "ol"
    | "p"
    | "search"
    | "section"
    | "summary"
    | "ul"
    | "table"
    | "thead"
    | "tbody"
    | "tfoot"
    | "tr"
    | "td"
    | "th"
    | "caption"
    | "colgroup"
    | "col"
    | "legend"
    | "optgroup"
    | "option" => Block
    _ => Inline
  }
}

// -------------------------------------------------------------- namespaces

///|
/// An SVG element name whose correct spelling is not its lowercasing.
///
/// HTML lowercases every tag name it reads, and SVG has thirty-seven names that
/// are not lowercase. Without this table `<linearGradient>` comes back as
/// `<lineargradient>`, which is a different element that does not exist.
pub fn svg_tag(lower : String) -> String? {
  match lower {
    "altglyph" => Some("altGlyph")
    "altglyphdef" => Some("altGlyphDef")
    "altglyphitem" => Some("altGlyphItem")
    "animatecolor" => Some("animateColor")
    "animatemotion" => Some("animateMotion")
    "animatetransform" => Some("animateTransform")
    "clippath" => Some("clipPath")
    "feblend" => Some("feBlend")
    "fecolormatrix" => Some("feColorMatrix")
    "fecomponenttransfer" => Some("feComponentTransfer")
    "fecomposite" => Some("feComposite")
    "feconvolvematrix" => Some("feConvolveMatrix")
    "fediffuselighting" => Some("feDiffuseLighting")
    "fedisplacementmap" => Some("feDisplacementMap")
    "fedistantlight" => Some("feDistantLight")
    "fedropshadow" => Some("feDropShadow")
    "feflood" => Some("feFlood")
    "fefunca" => Some("feFuncA")
    "fefuncb" => Some("feFuncB")
    "fefuncg" => Some("feFuncG")
    "fefuncr" => Some("feFuncR")
    "fegaussianblur" => Some("feGaussianBlur")
    "feimage" => Some("feImage")
    "femerge" => Some("feMerge")
    "femergenode" => Some("feMergeNode")
    "femorphology" => Some("feMorphology")
    "feoffset" => Some("feOffset")
    "fepointlight" => Some("fePointLight")
    "fespecularlighting" => Some("feSpecularLighting")
    "fespotlight" => Some("feSpotLight")
    "fetile" => Some("feTile")
    "feturbulence" => Some("feTurbulence")
    "foreignobject" => Some("foreignObject")
    "glyphref" => Some("glyphRef")
    "lineargradient" => Some("linearGradient")
    "radialgradient" => Some("radialGradient")
    "textpath" => Some("textPath")
    _ => None
  }
}

///|
/// An SVG or MathML attribute name whose correct spelling is not its
/// lowercasing.
///
/// Same table, same reason, one namespace larger: MathML contributes exactly
/// one entry, `definitionURL`, and it is the entry everyone forgets.
pub fn foreign_attr(lower : String) -> String? {
  match lower {
    "attributename" => Some("attributeName")
    "attributetype" => Some("attributeType")
    "basefrequency" => Some("baseFrequency")
    "baseprofile" => Some("baseProfile")
    "calcmode" => Some("calcMode")
    "clippathunits" => Some("clipPathUnits")
    "definitionurl" => Some("definitionURL")
    "diffuseconstant" => Some("diffuseConstant")
    "edgemode" => Some("edgeMode")
    "filterunits" => Some("filterUnits")
    "glyphref" => Some("glyphRef")
    "gradienttransform" => Some("gradientTransform")
    "gradientunits" => Some("gradientUnits")
    "kernelmatrix" => Some("kernelMatrix")
    "kernelunitlength" => Some("kernelUnitLength")
    "keypoints" => Some("keyPoints")
    "keysplines" => Some("keySplines")
    "keytimes" => Some("keyTimes")
    "lengthadjust" => Some("lengthAdjust")
    "limitingconeangle" => Some("limitingConeAngle")
    "markerheight" => Some("markerHeight")
    "markerunits" => Some("markerUnits")
    "markerwidth" => Some("markerWidth")
    "maskcontentunits" => Some("maskContentUnits")
    "maskunits" => Some("maskUnits")
    "numoctaves" => Some("numOctaves")
    "pathlength" => Some("pathLength")
    "patterncontentunits" => Some("patternContentUnits")
    "patterntransform" => Some("patternTransform")
    "patternunits" => Some("patternUnits")
    "pointsatx" => Some("pointsAtX")
    "pointsaty" => Some("pointsAtY")
    "pointsatz" => Some("pointsAtZ")
    "preservealpha" => Some("preserveAlpha")
    "preserveaspectratio" => Some("preserveAspectRatio")
    "primitiveunits" => Some("primitiveUnits")
    "refx" => Some("refX")
    "refy" => Some("refY")
    "repeatcount" => Some("repeatCount")
    "repeatdur" => Some("repeatDur")
    "requiredextensions" => Some("requiredExtensions")
    "requiredfeatures" => Some("requiredFeatures")
    "specularconstant" => Some("specularConstant")
    "specularexponent" => Some("specularExponent")
    "spreadmethod" => Some("spreadMethod")
    "startoffset" => Some("startOffset")
    "stddeviation" => Some("stdDeviation")
    "stitchtiles" => Some("stitchTiles")
    "surfacescale" => Some("surfaceScale")
    "systemlanguage" => Some("systemLanguage")
    "tablevalues" => Some("tableValues")
    "targetx" => Some("targetX")
    "targety" => Some("targetY")
    "textlength" => Some("textLength")
    "viewbox" => Some("viewBox")
    "viewtarget" => Some("viewTarget")
    "xchannelselector" => Some("xChannelSelector")
    "ychannelselector" => Some("yChannelSelector")
    "zoomandpan" => Some("zoomAndPan")
    _ => None
  }
}

///|
/// An element inside SVG or MathML whose children are HTML again.
///
/// `annotation-xml` is conditional in the specification -- it depends on its
/// `encoding` attribute -- and unconditional here, because the condition needs
/// the attribute list and this table takes a name. The caller that has the
/// attributes checks; the caller that does not gets the common answer.
pub fn is_integration_point(name : String) -> Bool {
  match name {
    "foreignobject"
    | "desc"
    | "title"
    | "annotation-xml"
    | "mtext"
    | "mi"
    | "mo"
    | "mn"
    | "ms" => true
    _ => false
  }
}

// ------------------------------------------------------ character references

///|
/// Every named reference, as a map, built once.
///
/// A map rather than a sorted array with a binary search, because the decoder's
/// hot path is "try 31 substrings and stop at the first hit" and a hash lookup
/// makes each of those a constant. Built from `packed_references`, which is one
/// string constant rather than four and a half thousand.
let references : Map[String, String] = build_references()

///|
fn build_references() -> Map[String, String] {
  let m : Map[String, String] = Map([])
  let s = packed_references
  let n = s.length()
  let mut i = 0
  while i < n {
    let name_start = i
    while i < n && s.unsafe_get(i).to_int() != 2 {
      i = i + 1
    }
    let name = s.clamped_view(start=name_start, end=i).to_owned()
    i = i + 1
    let value_start = i
    while i < n && s.unsafe_get(i).to_int() != 1 {
      i = i + 1
    }
    m[name] = s.clamped_view(start=value_start, end=i).to_owned()
    i = i + 1
  }
  m
}

///|
/// What a named reference resolves to, without the `&`.
///
/// The name may or may not carry its `;`: both spellings are in the table,
/// because HTML resolves `&amp` as well as `&amp;` and the two are not the same
/// entry -- `&not` exists and `&notin` exists, and which one `&notin` is
/// depends on whether the `;` was there.
pub fn named_reference(name : String) -> String? {
  references.get(name)
}

///|
/// The named reference for a character the printer would rather not emit as
/// itself, or `None` if there is no name for it.
///
/// This is the HTML counterpart of the CSS tree keeping a number's spelling.
/// Turning `&nbsp;` into an invisible byte loses nothing a browser can see and
/// everything the next person to edit the file can: a space that is not a space
/// becomes indistinguishable from one that is. So the printer names them, and
/// the ones with no name go out as numeric references.
pub fn reference_for_invisible(c : Char) -> String? {
  match c {
    '\u{A0}' => Some("nbsp")
    '\u{AD}' => Some("shy")
    '\u{200C}' => Some("zwnj")
    '\u{200D}' => Some("zwj")
    '\u{200E}' => Some("lrm")
    '\u{200F}' => Some("rlm")
    '\u{2060}' => Some("NoBreak")
    _ => None
  }
}

///|
/// Whether a character is one a reader could not see and could not type.
///
/// `is_invisible` and `reference_for_invisible` are two questions because the
/// answer to the second is `None` for four of these, and the printer still has
/// to escape them -- numerically.
pub fn is_invisible(c : Char) -> Bool {
  match c {
    '\u{A0}'
    | '\u{AD}'
    | '\u{200B}'
    | '\u{200C}'
    | '\u{200D}'
    | '\u{200E}'
    | '\u{200F}'
    | '\u{2028}'
    | '\u{2029}'
    | '\u{2060}'
    | '\u{FEFF}' => true
    _ => false
  }
}
