# Contributing to Logo

## Development setup

Prerequisites:

- [Ditty](https://github.com/chestso/ditty) 0.9.0+ (`ditty` on
  `PATH`) — the interpreter; it must include the `terminal` library
  (graphics capability detection). Pure-Lisp project: nothing to
  compile.
- [Tapestry](https://github.com/chestso/tapestry) — only for the
  interactive TUI and `tests/test-tui.lisp`. Install it normally
  (`make install`) so `(require 'tapestry)` resolves via Ditty's
  library search path (XDG data dirs, `DITTY_LISP_PATH`).

## Compatibility targets

- **Mikro-Logo parity** is the primary track: complete the RC759
  Mikro-Logo from the [April 1985
  manual](docs/PICCOLINE_Mikro-Logo_Brugervejledning_apr1985.pdf), so
  that using it feels like sitting at a Piccoline. Cite the manual
  section in PRs and update the matching [ROADMAP.md](docs/ROADMAP.md)
  item.
- **Broader Logo** is the other track: English/UCBLogo-style support
  must remain first-class and keep growing. Never solve a Logo problem
  by narrowing the dialect to the RC759 subset.
- State which track a change serves. Shared parser/interpreter/canvas
  changes must keep both dialects passing.

## Running

```sh
bin/logo                              # interactive TUI
bin/logo examples/star.logo           # run a program
bin/logo -e 'FD 100 RT 90 FD 100'     # one-liner
bin/logo --backend sixel examples/house.logo
make check                            # full test suite
make run EXAMPLE=examples/spiral.logo
make format                           # format Lisp sources (Ditty's lisp-fmt)
make format-check                     # verify sources are lisp-fmt clean
```

## Testing

```sh
make check
DITTY_LISP_PATH="$PWD/lisp" ditty tests/test-parser.lisp
```

- Tests are self-contained Ditty Lisp files under `tests/`, in the
  Tapestry style: each loads `logo` via a `*load-pathname*`-relative
  path, defines `assert-equal`/`assert-true`, prints PASS/FAIL per
  assertion, and `(exit 1)` on any failure.
- Every test must run headlessly (no TTY): add tests for interpreter
  behaviour via `logo-run`/`logo-repl-eval`, for rendering via
  `canvas->braille-lines`, and for the TUI via the model functions
  (`logo-model-make`, `logo-tui-update`, `logo-tui-view`) — never via
  `app-run`.
- New example programs in `examples/` are picked up automatically by
  `tests/test-examples.lisp` (they must draw segments and print a
  transcript).

## Code style

- **Ditty dialect rules** (from Ditty's own AGENTS.md — these bite):
  - `let` is _parallel_ (CL-style): bindings cannot see each other.
    Use `let*` for sequential bindings. Named loops use `let loop`.
  - `set!`, not `setq`. `do`, not `dolist`. `progn`, not `begin`.
    `#t` as the `cond` default, not `t`.
  - Numerics are Ditty builtins (`abs`, `sqrt`, `sin`, `cos`, `expt`,
    `floor`, `quotient`, `remainder`, `modulo`, `random`, …) — call
    them directly; there are no `logo-*` aliases. `string` is still
    missing: use `char->string`. There is no `vector-length`; `length`
    works on lists, strings and vectors.
  - `make-vector` without a fill argument creates an _empty_ vector —
    always pass the fill: `(make-vector n 0)`.
  - `string-prefix?` takes `(PREFIX STRING)`:
    `(string-prefix? "he" "hello")` is `#t`.
- **Errors**: Ditty errors are values. Never destructure a sub-call
  result without an `error?` check, and never let a `condition-case`
  handler produce data that flows into destructuring code (handlers
  return the error object; callers check). See ARCHITECTURE.md.
- **Formatting**: `make format` formats in place, per file type (as in
  ditty/tapestry): Ditty Lisp with `lisp-fmt` (ships with Ditty,
  installed under `~/.local/share/ditty/lisp/`; `make format
LISP_FMT=/path/to/lisp-fmt.lisp` overrides), `emacs/*.el` with Emacs
  `indent-region`, `bin/logo` with `shfmt`, and Markdown with
  `prettier`. A missing tool skips that type with a warning.
  `make format-check` verifies cleanliness without modifying files —
  PRs must pass it. 2-space indent, kebab-case names, `logo-` prefix
  for module internals, public API exported from `lisp/logo.lisp`.
- **Parens**: if Ditty reports "Unclosed list", bisect by loading
  defun-by-defun (extract with `sed -n 'A,Bp'`); don't trust external
  paren counters around char literals (`#\(`) and docstrings.

## Adding a primitive

1. Add to `lisp/logo/primitives.lisp`: `logo-define-primitive` for a
   command, `logo-define-value-primitive` for a query.
2. It is automatically available to the parser (arity-driven) — no
   parser changes needed.
3. Add tests in `tests/test-interpreter.lisp` and document it in
   `docs/LANGUAGE.md`.

## Adding a graphics backend

1. Add `logo-render-<name>` in `lisp/logo/graphics.lisp`, dispatch in
   `logo-render`, capability in `logo-graphics-capabilities-from`.
2. Backends consume the canvas (`canvas-rasterize` gives you a 0/1
   grid); they must not mutate it.
3. The CLI `--backend` flag lives in `logo-main.lisp`.

## Pull requests

- `make check` must pass; `make format-check` must pass.
- Update [docs/ROADMAP.md](docs/ROADMAP.md) for progress on either
  track, `docs/LANGUAGE.md` for language changes, and
  `docs/UPSTREAM.md` for requests to Ditty/portty/coffer.
- Clear commit messages explaining _why_, including which track the
  change serves and the manual section for Mikro-Logo parity work.
