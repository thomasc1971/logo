# AGENTS.md

Agent-oriented guide for working in this repository.

## Project summary

Logo is a Logo turtle-graphics interpreter written entirely in Ditty
Lisp (`lisp/logo/`), with a Tapestry TUI (`tui.lisp`) and terminal
graphics backends (`graphics.lisp`) targeting portty (sixel now,
kitty/iTerm2 planned). Inspired by the Regnecentralen RC759 Piccoline
(1984–1989) school computer. MIT licensed. No C code, no build step —
Ditty is the runtime.

## Build & run

```sh
bin/logo                        # interactive TUI (needs Tapestry + TTY)
bin/logo examples/star.logo     # headless run, prints Braille picture
bin/logo -e 'FD 100 RT 90'      # one-liner
make check                      # test suite (headless, 142 assertions)
make run EXAMPLE=examples/spiral.logo
```

`bin/logo` sets `DITTY_LISP_PATH=$ROOT/lisp` (plus any caller-supplied
`DITTY_LISP_PATH`) and execs `ditty logo-main.lisp -- "$@"`.
`logo-main.lisp` dispatches on `*command-line-args*`; with no args it
requires Tapestry _before_ Logo (Ditty resolves `pkg:symbol` against
packages existing at read time) and starts the TUI.

## Testing

```sh
make check
DITTY_LISP_PATH="$PWD/lisp" ditty tests/test-parser.lisp
```

- `tests/test-*.lisp` are self-contained: load `logo` via
  `*load-pathname*`-relative path, define local assert helpers, print
  PASS/FAIL, `(exit 1)` on failure. All must run headlessly.
- `tests/test-tui.lisp` needs Tapestry; it exercises the Elm model
  functions directly, never `app-run`.
- `tests/test-examples.lisp` runs every `examples/*.logo`.

## Architecture (short version)

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full picture.

```
source -> parser (arity-driven, 2-pass) -> AST -> interpreter
  -> turtle (immutable alist state) -> canvas (segments)
  -> backends: Braille (always), sixel (portty), kitty/iterm2 (planned)
  -> Tapestry Elm TUI (model/update/view)
```

## Critical gotchas (read before editing)

1. **Ditty `let` is parallel.** `(let ((a 1) (b (+ a 1))) ...)` fails.
   Use `let*` for sequential bindings; `let loop` for named loops.
2. **Ditty errors are values + condition-case substitutes.** Errors
   flow as ordinary values through unchecked frames; `car`/`cdr` on an
   error object makes a confusing secondary error. Guard every
   destructure with `error?`. `condition-case` handler results are
   substituted _at the error site_ and execution resumes — handlers
   must return the error object itself, never data that flows into
   destructuring code. `OUTPUT`/`STOP` are explicit signal values
   (`(logo-output STATE . VALUE)`), not exceptions.
3. **Ditty builtins** (Ditty 0.9+?, which ships the numeric tower and
   the `terminal` library — TODO: pin the exact minimum): call `abs`,
   `sqrt`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`,
   `exp`, `log`, `expt`, `float`, `floor`, `round`, `truncate`,
   `ceiling`, `quotient`, `remainder`, `modulo`, `random` and
   `random-seed` directly — there are no `logo-*` math aliases.
   `string` is still missing (use `char->string`). `length` works on
   vectors (there is no `vector-length`). `(make-vector n)` with no
   fill is an _empty_ vector. `let`/`progn` do not check error
   propagation. `string-prefix?` is `(string-prefix? PREFIX STRING)`.
4. **Tapestry symbols**: use qualified `tapestry:...` in `tui.lisp`;
   `use-package` inside a function body does not reliably extend the
   defining package. Headless code must load without Tapestry.
5. **Paren debugging**: extract defuns with `sed -n 'A,Bp'` and load
   each with ditty; external paren counters mishandle `#\(` char
   literals and docstrings.
6. **Terminal capabilities are Ditty's job.** `lisp/logo.lisp` requires
   Ditty's `terminal` library _before_ any file that mentions
   `terminal:` (the reader resolves package-qualified symbols at read
   time). In the TUI the capabilities arrive as a `capabilities`
   message and live in the model under `'caps`; headless code uses the
   pure `terminal-capabilities-from-replies` env-only fallback. Never
   block or poll for terminal replies, and never add `getenv`
   heuristics to Logo — they belong in Ditty's `terminal` library.

## Conventions

- Modules are internal files loaded by `lisp/logo.lisp` into the
  `logo` package (Tapestry pattern); public API is exported there.
  Add new public functions to the export list.
- New primitives: register in `primitives.lisp`, test in
  `test-interpreter.lisp`, document in `docs/LANGUAGE.md`.
- New backends: `graphics.lisp` + CLI flag in `logo-main.lisp`.
- Upstream needs (Ditty/portty/coffer) go in `docs/UPSTREAM.md`, not
  as TODOs scattered in code.
