///|
/// Decide, for each `'`, whether it opens or closes.
///
/// `'` is its own opener and closer, so nesting is ambiguous on its face and
/// the decision needs context. The rule: a `'` outside quotes opens; inside
/// quotes it closes, UNLESS a bracket has been opened since the last `'`, in
/// which case it opens a nested quote. That is what makes `'a ('nested') b'`
/// read the way it looks, while two consecutive `'` with nothing between them
/// would otherwise be an opener and its own closer.
///
/// A separate pass rather than lexer state, so the scanner stays context-free
/// and this rule can be read and tested on its own.
pub fn rewrite_quotes(tokens : Array[Token]) -> Array[Token] {
  // Each entry is one level of quoting; the value counts brackets opened at
  // that level since the last `'`.
  let quote_depth : Array[Int] = []
  let out = []
  for t in tokens {
    match t.kind {
      SQuote =>
        if quote_depth.length() == 0 {
          quote_depth.push(0)
          out.push({ ..t, kind: Opener, })
        } else if quote_depth[quote_depth.length() - 1] > 0 {
          // A bracket is open at this level, so this `'` starts a nested quote
          // rather than closing the one we are in.
          quote_depth.push(0)
          out.push({ ..t, kind: Opener, })
        } else {
          let _ = quote_depth.pop()
          out.push({ ..t, kind: Closer, })
        }
      Opener => {
        bump(quote_depth, 1)
        out.push(t)
      }
      Closer => {
        bump(quote_depth, -1)
        out.push(t)
      }
      _ => out.push(t)
    }
  }
  out
}

///|
fn bump(stack : Array[Int], by : Int) -> Unit {
  if stack.length() > 0 {
    stack[stack.length() - 1] = stack[stack.length() - 1] + by
  }
}
