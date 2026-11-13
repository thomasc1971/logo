# AGENTS.md

Agent-oriented guide for working in this repository.

## Project summary

Logo is a Logo turtle-graphics interpreter written entirely in Ditty
Lisp (`lisp/logo/`), with a Tapestry TUI (`tui.lisp`) and terminal
graphics backends (`graphics.lisp`) targeting portty (sixel now,
kitty/iTerm2 planned). Inspired by the Regnecentralen RC759 Piccoline
(1984–1989) school computer. MIT licensed. No C code, no build step —
Ditty is the runtime.

## Guiding specification

[`docs/PICCOLINE_Mikro-Logo_Brugervejledning_apr1985.pdf`](docs/PICCOLINE_Mikro-Logo_Brugervejledning_apr1985.pdf)
— A/S Regnecentralen's _PICCOLINE – Mikro-Logo – Brugervejledning_
(April 1985) — is the **guiding specification for this project**. When
this repo does not answer a design or behavior question, follow the
manual: screen layout, command-line semantics (one line, executed whole
on Return, `;` between statements), the modal `lær`/`ret` procedure
editor with `begynd` … `slut`, Danish command words, error messages,
and limits such as one statement per line and at most 21 lines per
procedure.

Known deviations **in Mikro-Logo mode** (English `TO`/`END` keywords
there, a one-line REPL with no procedure editor, etc.) are gaps to
close, not precedents: do not invent behavior that contradicts the
manual. Deviations must be deliberate and documented, and modern
platform limits (Ditty, Tapestry, the terminal) take precedence only
where the RC759 hardware has no analogue.

**Two product goals, one core.**

1. **Complete Mikro-Logo.** The RC759 system must be implemented in
   full — Danish vocabulary, the single-line command line, the modal
   `LÆR`/`RET` procedure editor, disk commands, messages and the
   manual's limits — so that using it feels like sitting at a
   Piccoline, not like using a lookalike. "Close enough" is not done.
2. **Broader Logo.** The English, UCBLogo-style dialect must remain
   available and keep growing. Mikro-Logo fidelity must never become a
   cap on general Logo support.

Implement these as two dialects/modes over the shared parser,
interpreter and canvas core — not as a fork. `docs/ROADMAP.md` tracks
Mikro-Logo completion separately from broader Logo work.

The PDF is a scan of a Danish manual; extract text with
`pdftotext -layout`. Provenance:
<https://rc700.dk/documentation.php> (MD5
`8984ca01a444ca733fa5d86aec5600d1`). The dialects are documented in
[docs/LANGUAGE.md](docs/LANGUAGE.md).

## Documentation map

- `README.md` — human-facing overview and quick start.
- `ARCHITECTURE.md` — module map, invariants, design decisions.
- `docs/LANGUAGE.md` — language reference (`logo` dialect, `mikro`
  plan).
- `docs/ROADMAP.md` — Mikro-Logo completion and broader Logo tracks.
- `docs/UPSTREAM.md` — needs that belong in Ditty/portty/coffer.
- `docs/PICCOLINE_Mikro-Logo_Brugervejledning_apr1985.pdf` —
  authoritative Mikro-Logo specification.
- `CONTRIBUTING.md` — development setup, formatting, PR rules.

## Build & run

```sh
bin/logo                        # interactive TUI (needs Tapestry + TTY)
bin/logo examples/star.logo     # headless run, prints Braille picture
bin/logo -e 'FD 100 RT 90'      # one-liner
make check                      # full test suite (TUI tests need Tapestry)
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
  functions directly, never `app-run`. If Tapestry is not installed in
  Ditty's library path, point `DITTY_LISP_PATH` at both trees:
  `DITTY_LISP_PATH="$PWD/lisp:/path/to/tapestry/lisp" make check`.
- `tests/test-examples.lisp` runs every `examples/*.logo`.
- Add or update tests for every behavior change; a bug fix without a
  regression test is incomplete.

## Code style

Follow [CONTRIBUTING.md](CONTRIBUTING.md) for the full rules and run
`make format-check`. The essentials:

- 2-space indent, kebab-case names; internal helpers use the `logo-`
  prefix; public API is exported from `lisp/logo.lisp`.
- Ditty Lisp, not Common Lisp: `set!` not `setq`, `progn` not `begin`,
  `#t` as the `cond` default, `let*` for sequential bindings.
- Keep interpreter/turtle/canvas code pure where possible and thread
  state explicitly; never hide terminal or Tapestry dependencies in
  headless modules.
- Errors are values: check `error?` before destructuring any result
  (see gotcha 2 below).

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
3. **Ditty builtins** (Ditty 0.9.0+ ships the numeric tower and the
   `terminal` library): call `abs`,
   `sqrt`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`,
   `exp`, `log`, `expt`, `float`, `floor`, `round`, `truncate`,
   `ceiling`, `quotient`, `remainder`, `modulo`, `random` and
   `random-seed` directly — there are no `logo-*` math aliases.
   `string` is still missing (use `char->string`). `length` works on
   vectors (there is no `vector-length`). `(make-vector n)` with no
   fill is an _empty_ vector. `let`/`progn` do not check error
   propagation. `string-prefix?` is `(string-prefix? PREFIX STRING)`.
   Case folding and character classes are ASCII-only
   (`string-upcase`, `char-upcase`, `char-alphabetic?` leave `æ`/`ø`/`å`
   alone). Use `logo-upcase` for Danish words and `logo-letter?`
   for word characters; do not call the Ditty versions on user text.
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

- State which track a change serves: **Mikro-Logo parity** (cite the
  manual section) or **broader Logo**. Update `docs/ROADMAP.md` and,
  for language changes, `docs/LANGUAGE.md`; shared-core changes must
  keep both dialects passing.
- Modules are internal files loaded by `lisp/logo.lisp` into the
  `logo` package (Tapestry pattern); public API is exported there.
  Add new public functions to the export list.
- New primitives: register in `primitives.lisp`, test in
  `test-interpreter.lisp`, document in `docs/LANGUAGE.md`.
- New backends: `graphics.lisp` + CLI flag in `logo-main.lisp`.
- Upstream needs (Ditty/portty/coffer) go in `docs/UPSTREAM.md`, not
  as TODOs scattered in code.

## Commits and pull requests

- Before committing, `make check` and `make format-check` must pass.
- Commit subjects use a module prefix and imperative mood:
  `parser: ...`, `interpreter: ...`, `tui: ...`, `docs: ...`,
  `deps: ...`.
- Explain _why_ in the body, name the track the change serves, and
  cite the manual section for Mikro-Logo parity work.
- Keep docs in sync in the same commit: `docs/ROADMAP.md` for track
  progress, `docs/LANGUAGE.md` for language changes, and
  `docs/UPSTREAM.md` for requests to Ditty/portty/coffer.
