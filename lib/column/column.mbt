///|
/// An indentation column.
///
/// Not a number. A tab advances to a stop that depends on what came before it,
/// so two columns reached through different mixes of tabs and spaces are only
/// PARTIALLY ordered: one is more indented than another only when it extends
/// the other's sequence. When neither extends the other, comparing them is an
/// error the user has to be told about — see `ColumnOrder::Incomparable`.
///
/// `Plain` is the case that happens on every line of every file anyone has
/// written, and is kept apart so it costs no allocation. `Tabbed` holds the
/// alternating run lengths — chars, tabs, chars, tabs, …, chars — LEFTMOST
/// first, so a comparison is a straight walk from the start of the line and an
/// append is a concatenation. (The reference stores the same list reversed; the
/// order here is the one that makes both operations read forwards.)
///
/// **Every entry is in half-columns.** A run of `n` tabs is stored as `2n`.
/// That uniformity is what makes the `+0.5` convention safe: a `|` at column N
/// takes part in comparisons as N.5, and storing tab counts in the same unit
/// means the half-column tolerance in `cmp` can never be triggered by a
/// difference of one tab, which it would if the two units were mixed.
pub enum Column {
  Plain(Int)
  Tabbed(Array[Int])
} derive(Eq, Debug)

///|
/// The result of comparing two columns.
///
/// Five answers, not three. `Incomparable` is the user-facing "incomparable
/// indentation due to mixed tabs" error, and making it a constructor is what
/// stops a caller quietly defaulting it to `Eq`. `Unordered` is the reference's
/// half-a-column-before-a-tab tolerance: every comparison of the pair is false,
/// but it is not an error. Collapsing the two would either turn a tolerated
/// case into a failure or a failure into silence.
pub(all) enum ColumnOrder {
  Lt
  Eq
  Gt
  Unordered
  Incomparable
} derive(Eq, Debug)

///|
/// A readable column, for a diagnostic or a test failure.
///
/// `4` for a plain column, `4.5` when the `|` half is on it, and
/// `2+tab+1` when there is a tab in the middle — which is the form that
/// makes an "incomparable indentation" message explain itself.
pub fn Column::to_display(self : Column) -> String {
  let runs = self.runs()
  let out = StringBuilder()
  for i in 0..<runs.length() {
    if i % 2 == 1 {
      out.write_string("+")
      out.write_string((runs[i] / 2).to_string())
      out.write_string("tab+")
    } else {
      out.write_string((runs[i] / 2).to_string())
      if runs[i] % 2 == 1 {
        out.write_string(".5")
      }
    }
  }
  out.to_string()
}

///|
pub let zero : Column = Plain(0)

///|
/// A column `n` whole character widths from the start of the line.
pub fn Column::of_chars(n : Int) -> Column {
  Plain(n * 2)
}

///|
/// The runs, leftmost first. `Plain` is the one-element case.
fn Column::runs(self : Column) -> Array[Int] {
  match self {
    Plain(n) => [n]
    Tabbed(rs) => rs
  }
}

///|
/// This column with `n` more character widths on its right.
pub fn Column::add_chars(self : Column, n : Int) -> Column {
  self.add_halves(n * 2)
}

///|
/// This column plus half a character width — the `|` convention.
///
/// A `|` at column N takes part in comparisons as N.5, which is what lets a
/// block's content and an alternative's `|` sit at the same visual column and
/// still be ordered against each other.
pub fn Column::half_up(self : Column) -> Column {
  self.add_halves(1)
}

///|
fn Column::add_halves(self : Column, n : Int) -> Column {
  match self {
    Plain(c) => Plain(c + n)
    Tabbed(rs) => {
      let out = rs.copy()
      out[out.length() - 1] = out[out.length() - 1] + n
      Tabbed(out)
    }
  }
}

///|
/// This column with one tab on its right.
///
/// The tab starts a new run, so everything before it becomes a fixed prefix
/// that a later column must reproduce exactly to be comparable at all.
pub fn Column::add_tab(self : Column) -> Column {
  let out = self.runs().copy()
  out.push(2)
  out.push(0)
  Tabbed(out)
}

///|
/// `other` placed to the RIGHT of `self`: `self` is the base, `other` the
/// offset added to it.
///
/// The reference's `column+`, with the arguments in the order the phrase
/// "column a plus b" suggests rather than the order the Racket takes them.
pub fn Column::plus(self : Column, other : Column) -> Column {
  match (self, other) {
    (Plain(a), Plain(b)) => Plain(a + b)
    _ => {
      let base = self.runs()
      let add = other.runs()
      let out = base.copy()
      // The two adjacent character runs meet and become one.
      out[out.length() - 1] = out[out.length() - 1] + add[0]
      for i in 1..<add.length() {
        out.push(add[i])
      }
      if out.length() == 1 {
        Plain(out[0])
      } else {
        Tabbed(out)
      }
    }
  }
}

///|
/// `self - other` in half-columns, or 0 when the two have different tab
/// structure.
///
/// Zero rather than an error because a difference across different tab
/// structures has no meaning to report — the reference makes the same choice.
pub fn Column::sub(self : Column, other : Column) -> Int {
  match (self, other) {
    (Plain(a), Plain(b)) => a - b
    (Tabbed(a), Tabbed(b)) => {
      if a.length() != b.length() {
        return 0
      }
      // Everything except the rightmost character run must match exactly.
      for i in 0..<(a.length() - 1) {
        if a[i] != b[i] {
          return 0
        }
      }
      a[a.length() - 1] - b[b.length() - 1]
    }
    _ => 0
  }
}

///|
/// Round down to a whole character width.
pub fn Column::floor(self : Column) -> Column {
  match self {
    Plain(n) => Plain(n / 2 * 2)
    Tabbed(rs) => {
      let out = rs.copy()
      let last = out.length() - 1
      out[last] = out[last] / 2 * 2
      Tabbed(out)
    }
  }
}

///|
/// Compare two columns.
///
/// Walks both run lists from the start of the line. A list that runs out while
/// the other continues is the smaller column — it is a prefix of the other,
/// which is exactly what "less indented" means here.
///
/// Where the two diverge, one case is tolerated and the rest are errors. The
/// tolerated case is a half-column difference in the LAST run of the shorter
/// side: that is a `|` sitting half a column before a tab, and the reference
/// answers every comparison about it with false rather than complaining.
/// Everything else is a genuine mixed-tab ambiguity, and the user is told.
pub fn Column::cmp(self : Column, other : Column) -> ColumnOrder {
  match (self, other) {
    (Plain(a), Plain(b)) => if a < b { Lt } else if a > b { Gt } else { Eq }
    _ => {
      let a = self.runs()
      let b = other.runs()
      let n = if a.length() < b.length() { a.length() } else { b.length() }
      for i in 0..<n {
        if a[i] == b[i] {
          continue
        }
        if a[i] > b[i] {
          // `b` has no further run, so `a` simply extends past where `b` ends.
          if i == b.length() - 1 {
            return Gt
          }
          // Half a column up, and nothing after it on this side: a `|` sitting
          // just before a tab. Tolerated, and every comparison of the pair is
          // false. One half-unit, so a one-tab difference can never land here.
          return if a[i] == b[i] + 1 && i == a.length() - 1 {
            Unordered
          } else {
            Incomparable
          }
        }
        if i == a.length() - 1 {
          return Lt
        }
        return if a[i] + 1 == b[i] && i == b.length() - 1 {
          Unordered
        } else {
          Incomparable
        }
      }
      // One is a prefix of the other, or they are identical.
      if a.length() == b.length() {
        Eq
      } else if a.length() > b.length() {
        Gt
      } else {
        Lt
      }
    }
  }
}

///|
/// `self < other`, in the reference's sense: `Unordered` and `Incomparable`
/// are both false here, and only `Incomparable` is worth reporting.
pub fn Column::lt(self : Column, other : Column) -> Bool {
  self.cmp(other) is Lt
}

///|
pub fn Column::gt(self : Column, other : Column) -> Bool {
  self.cmp(other) is Gt
}

///|
pub fn Column::eq(self : Column, other : Column) -> Bool {
  self.cmp(other) is Eq
}

///|
/// `self <= other`, defined as the reference defines it: NOT `other < self`.
///
/// That is not the same as `Lt || Eq`. When the pair is `Unordered` — a `|`
/// half a column before a tab — `other < self` is false, so `<=` is true, while
/// `Lt || Eq` would be false. The reference leans on that, so the definition
/// has to be the negated one.
pub fn Column::le(self : Column, other : Column) -> Bool {
  !other.cmp(self).is_lt()
}

///|
pub fn Column::ge(self : Column, other : Column) -> Bool {
  !other.cmp(self).is_gt()
}

///|
pub fn ColumnOrder::name(self : ColumnOrder) -> String {
  match self {
    Lt => "Lt"
    Eq => "Eq"
    Gt => "Gt"
    Unordered => "Unordered"
    Incomparable => "Incomparable"
  }
}

///|
fn ColumnOrder::is_lt(self : ColumnOrder) -> Bool {
  self is Lt
}

///|
fn ColumnOrder::is_gt(self : ColumnOrder) -> Bool {
  self is Gt
}

///|
/// Walk `text` from `(lines, col)`, returning where it ends up.
///
/// The reference's `count-graphemes`, and the only place a column is advanced
/// over source text. Three things it must get right, all of which are silent
/// when wrong:
///
///   * `\r\n` is ONE line break, and a lone `\r` is one too.
///   * A tab starts a new run rather than advancing to a fixed stop.
///   * Everything else advances by one per EXTENDED GRAPHEME CLUSTER, not one
///     per code point.
///
/// It iterates clusters rather than asking for the next boundary at each
/// position, which lets the segmenter make a single pass. That is sound because
/// `\r\n`, a lone `\r`, a lone `\n` and a tab are each a cluster of their
/// own under UAX #29, so no cluster ever straddles a case boundary here.
pub fn count_graphemes(
  text : String,
  lines? : Int = 0,
  col? : Column = zero,
) -> (Int, Column) {
  let mut out_lines = lines
  let mut out_col = col
  for span in @unicode.grapheme_spans(text) {
    let (start, end) = span
    let first = text.at(start)
    if first == 0x0D || first == 0x0A {
      // A `\r\n` cluster and a lone terminator alike: one line, column reset.
      out_lines = out_lines + 1
      out_col = zero
    } else if first == 0x09 && end - start == 1 {
      out_col = out_col.add_tab()
    } else {
      out_col = out_col.add_chars(1)
    }
  }
  (out_lines, out_col)
}
