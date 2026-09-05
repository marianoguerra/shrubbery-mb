///|
/// How far a measurement got.
///
/// Only `NoFit` is inspected -- the caller asks "did it fit?", and everything
/// that is not a refusal is a yes -- but the three are kept apart because the
/// difference is the algorithm: running out of document and reaching a line
/// break are different reasons to stop, and collapsing them would hide which
/// one the measurement found.
priv enum Fit {
  /// Reached the end of what there was to measure, at this column.
  Col(Int)
  /// A line break arrived in time, so what was measured fits.
  Fits
  /// The width was exceeded.
  NoFit
}

///|
/// What the renderer is doing.
priv enum Mode {
  /// Printing.
  Print
  /// Measuring the first branch of an `Or`: a line break inside it means it
  /// does NOT fit, because a single-line reading may not contain one.
  Single
  /// Measuring what FOLLOWS that branch: a line break here means the rest of
  /// the line ended in time, so the branch fits after all.
  Afterward
}

///|
/// What is left to lay out.
///
/// An explicit stack rather than a chain of closures. The obvious rendering of
/// this algorithm is continuation-passing, and it is what the reference uses;
/// in a language without a growable stack it overflows on a large file, because
/// the continuation for a sequence is one frame per element and none of them
/// returns until the document ends. Reifying it costs nothing and makes the
/// depth the document's NESTING rather than its length.
priv enum Cont {
  CNil
  CCons(Doc, Int, Cont)
  /// The end of a sequence. Carries the column the sequence STARTED at,
  /// because that is what the width is checked against there -- see
  /// `over_at`.
  CCheck(Int, Cont)
  /// The end of the branch being measured: everything after this belongs to
  /// what FOLLOWS it, and a line break there means the branch fits. Carries the
  /// column the `Or` started at, for the same reason.
  CMark(Int, Cont)
}

///|
/// Lay a document out at `width` and write it.
///
/// Greedy, and a single left-to-right pass. At each `Or` it measures the
/// single-line branch — and keeps measuring past it, until either a line break
/// arrives (it fits) or the width is exceeded (it does not) — and takes that
/// branch if it fits. Measuring past the branch is what stops a form from being
/// printed on one line only to push what follows it over the edge.
///
/// `width` of `None` means "never measure": always take the first branch, which
/// produces the single-line reading of the whole document.
/// Answers with the column the output ends at, which is what a caller
/// embedding this in something larger needs in order to keep laying out.
pub fn render(
  doc : Doc,
  buf : StringBuilder,
  width? : Int? = None,
  column? : Int = 0,
  indent? : Int = 0,
) -> Int {
  match run(CCons(doc, indent, CNil), buf, width, column, Print) {
    Col(c) => c
    // Unreachable in `Print` mode: only a measurement stops early.
    Fits | NoFit => column
  }
}

///|
pub fn render_string(
  doc : Doc,
  width? : Int? = None,
  column? : Int = 0,
  indent? : Int = 0,
) -> String {
  let buf = StringBuilder()
  let _ = render(doc, buf, width~, column~, indent~)
  buf.to_string()
}

///|
fn run(
  start : Cont,
  buf : StringBuilder,
  width : Int?,
  column : Int,
  mode0 : Mode,
) -> Fit {
  let mut k = start
  let mut col = column
  let mut mode = mode0
  // The width is checked against the column a frame STARTED at, not the one it
  // reaches. That is not a rounding choice: the reference's check closes over
  // the column its enclosing invocation was entered with, so an overrun is
  // noticed one frame after it happens, and a form whose single-line reading
  // ends past the width can still be taken when nothing follows it on the line.
  // Reproducing the rule means naming what those closures captured, which is
  // what `CCheck` and `CMark` carry.
  let over_at = (c : Int) => {
    !(mode is Print) &&
    (match width {
      Some(w) => c >= w
      None => false
    })
  }
  for ;; {
    match k {
      CNil => return Col(col)
      CCheck(started, rest) =>
        if over_at(started) {
          return NoFit
        } else {
          k = rest
        }
      CMark(started, rest) =>
        if over_at(started) {
          return NoFit
        } else {
          mode = Afterward
          k = rest
        }
      CCons(doc, indent, rest) =>
        match doc {
          Str(s) => {
            if over_at(col) {
              return NoFit
            }
            if mode is Print {
              buf.write_string(s)
            }
            // Columns are code points: a surrogate pair is one column, and it
            // is columns that decide whether a line fits.
            col = col + s.char_length()
            k = rest
          }
          Nl =>
            match mode {
              Print => {
                buf.write_char('\n')
                for _ in 0..<indent {
                  buf.write_char(' ')
                }
                col = indent
                k = rest
              }
              Single => return NoFit
              Afterward => return Fits
            }
          Seq(docs) => {
            let mut next = CCheck(col, rest)
            for i = docs.length() - 1; i >= 0; i = i - 1 {
              next = CCons(docs[i], indent, next)
            }
            k = next
          }
          Nest(n, inner) => k = CCons(inner, indent + n, rest)
          Align(inner) => k = CCons(inner, col, rest)
          Or(single, multi) =>
            if width is None || !(mode is Print) {
              k = CCons(single, indent, rest)
            } else {
              // Measure the single-line branch and then keep going into what
              // follows it, which is what `CMark` switches over.
              let fits = run(
                CCons(single, indent, CMark(col, rest)),
                buf,
                width,
                col,
                Single,
              )
              let branch = match fits {
                // Ran out of document, or reached a line break, before the
                // width did: the single-line reading is usable.
                Col(_) | Fits => single
                NoFit => multi
              }
              k = CCons(branch, indent, rest)
            }
        }
    }
  }
}
