///|
/// Whether `u` falls in a range table.
///
/// Tables are flat `[lo, hi, lo, hi, ...]` arrays rather than arrays of pairs:
/// this is called once per source character, and the flat form keeps the search
/// to one array with no indirection and no per-entry allocation at module init.
fn in_table(table : FixedArray[Int], u : Int) -> Bool {
  let mut lo = 0
  let mut hi = table.length() / 2 - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    if u < table[mid * 2] {
      hi = mid - 1
    } else if u > table[mid * 2 + 1] {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
/// Racket's `char-alphabetic?` — the Unicode Alphabetic property.
///
/// Not the L\* general categories, which is what a hand-rolled table would
/// have implemented: Alphabetic also takes in Nl and the Other_Alphabetic
/// marks. The reference's identifier rule is written against this predicate, so
/// this is the one that has to agree.
pub fn is_alphabetic(c : Char) -> Bool {
  in_table(@tables.alphabetic, c.to_int())
}

///|
/// Racket's `char-numeric?`.
pub fn is_numeric(c : Char) -> Bool {
  in_table(@tables.numeric, c.to_int())
}

///|
/// Racket's `char-symbolic?` — Sm, Sc, Sk, So. Half of what an operator is made
/// of.
pub fn is_symbolic(c : Char) -> Bool {
  in_table(@tables.symbolic, c.to_int())
}

///|
/// Racket's `char-punctuation?` — Pc, Pd, Ps, Pe, Pi, Pf, Po. The other half.
pub fn is_punctuation(c : Char) -> Bool {
  in_table(@tables.punctuation, c.to_int())
}

///|
/// Racket's `char-whitespace?`.
pub fn is_whitespace(c : Char) -> Bool {
  in_table(@tables.whitespace, c.to_int())
}

///|
/// Whether `c` is an emoji all by itself.
///
/// These are identifier characters, and they are the reason the operator
/// character set has to subtract something from the symbol categories: without
/// this, every single-code-point emoji would lex as an operator.
pub fn is_one_char_emoji(c : Char) -> Bool {
  in_table(@tables.one_char_emoji, c.to_int())
}

///|
/// The length in UTF-16 code units of the longest emoji sequence starting at
/// `i`, or 0 if there is none.
///
/// Longest match, and it has to be: `👨‍👩‍👦` is one identifier character, and
/// stopping at the first `👨` would split it into three separated by
/// zero-width joiners, which are not identifier characters at all.
pub fn emoji_sequence_at(s : String, i : Int) -> Int {
  let n = s.length()
  let mut node = 0
  let mut pos = i
  let mut best = 0
  while pos < n {
    match s.get_char(pos) {
      None => break
      Some(ch) => {
        let width = if ch.to_int() > 0xFFFF { 2 } else { 1 }
        match edge(node, ch.to_int()) {
          None => break
          Some(next) => {
            node = next
            pos = pos + width
            if @tables.emoji_nodes[node * 3 + 2] == 1 {
              best = pos - i
            }
          }
        }
      }
    }
  }
  best
}

///|
/// The trie edge out of `node` labelled `cp`, by binary search over that node's
/// contiguous edge run.
fn edge(node : Int, cp : Int) -> Int? {
  let first = @tables.emoji_nodes[node * 3]
  let count = @tables.emoji_nodes[node * 3 + 1]
  let mut lo = 0
  let mut hi = count - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let k = @tables.emoji_edges[(first + mid) * 2]
    if cp < k {
      hi = mid - 1
    } else if cp > k {
      lo = mid + 1
    } else {
      return Some(@tables.emoji_edges[(first + mid) * 2 + 1])
    }
  }
  None
}

///|
/// The extended grapheme clusters of `s`, as `(start, end)` code-unit offsets.
///
/// Indentation columns advance one per grapheme cluster, not one per code
/// point — that is what the specification says and what the reference's
/// `string-grapheme-span` does. The distinction is invisible in ASCII and
/// decides the answer the moment a combining mark or a joined emoji appears
/// before a token on its line.
///
/// Offered as a whole-string iterator rather than a `next_boundary(s, i)` because
/// that is how it is used: a column is advanced over one token's text, and the
/// segmenter can then do its single pass instead of restarting at every
/// character.
pub fn grapheme_spans(s : String) -> Iter[(Int, Int)] {
  @grapheme.graphemes(s)
  .grapheme_indices()
  .map(t => {
    let (start, end, _) = t
    (start, end)
  })
}

///|
/// How many grapheme clusters `s` contains.
pub fn grapheme_count(s : String) -> Int {
  @grapheme.graphemes(s).length()
}
