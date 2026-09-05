// The command-line tool, separated from the library so that `moonbitlang/x`
// (filesystem and process access) is a cost only the people who want a binary
// pay. Everything about the notation itself is in `marianoguerra/shrubbery`.
name = "marianoguerra/shrubbery-cli"

version = "0.1.0"

import {
  "marianoguerra/shrubbery@0.1.0",
  "marianoguerra/error-report@0.1.0",
  "moonbitlang/x@0.5.1",
}

readme = "README.md"

repository = ""

license = "Apache-2.0"

keywords = [ "shrubbery", "rhombus", "cli", "formatter", "parser" ]

preferred_target = "wasm"

description = "The shrubbery command-line tool: parse, print, format and check Shrubbery notation"
