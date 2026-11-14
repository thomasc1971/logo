# Logo

A Logo turtle-graphics interpreter written in **Ditty Lisp**, with a
**Tapestry** TUI and terminal graphics designed for **portty**.

"Logo" is a programming language originally developed at MIT. This
project is not affiliated with or endorsed by MIT or the Logo Foundation.

The author learned Logo in Danish public school on a **Regnecentralen
RC759 Piccoline (1984–1989)** — Danish-designed, 8-bit-era school
computers with a 9-inch green-phosphor screen. This project is a love
letter to that machine: the same `FD 100 RT 90` immediacy, but running
in a modern GPU-accelerated terminal.

```logo
TO SQUARE :S
  REPEAT 4 [FD :S RT 90]
END

SQUARE 100
```

## Goals

Two goals guide the project:

1. **A complete RC759 Mikro-Logo.** The guiding specification is
   Regnecentralen's _PICCOLINE – Mikro-Logo – Brugervejledning_
   (April 1985), kept in the repository at
   [`docs/PICCOLINE_Mikro-Logo_Brugervejledning_apr1985.pdf`](docs/PICCOLINE_Mikro-Logo_Brugervejledning_apr1985.pdf).
   Mikro-Logo mode is not a themed subset: it must implement the whole
   system — Danish command words, the single-line command line with
   `;`, the modal `lær`/`ret` procedure editor, disk commands,
   messages and limits — so that using it feels like sitting at a
   Piccoline.
2. **Broader Logo.** The English `TO`/`END` dialect remains
   first-class, and support for standard/UCBLogo-style Logo keeps
   growing. The RC759 vocabulary and limits are a mode, not a cap on
   the interpreter.

See [docs/ROADMAP.md](docs/ROADMAP.md) for the milestones on both tracks.

## Quick start

Prerequisites: [Ditty](https://github.com/chestso/ditty) 0.9.0+ — the
release whose `terminal` library detects graphics capabilities — on your
`PATH`. The interactive TUI also needs
[Tapestry](https://github.com/chestso/tapestry) and Ditty 0.9.0.14+
(Tapestry's row-diff renderer uses `terminal-write`, `:on-idle` and
`:no-wrap`); headless runs work with 0.9.0.
Install both from source (`./autogen.sh`, configure, `make`, `make install`);
Ditty's library search path (XDG data dirs, `DITTY_LISP_PATH`) then resolves
`(require 'logo)` and `(require 'tapestry)` for `bin/logo` and `make check`.

```sh
bin/logo                              # interactive TUI
bin/logo --mikro                      # RC759 Mikro-Logo mode
bin/logo examples/star.logo           # run a program, print the picture
bin/logo -e 'REPEAT 4 [FD 80 RT 90]'  # one-liner
bin/logo --backend sixel examples/star.logo   # sixel bitmap (portty)
bin/logo --help
make check                            # run the test suite
```

The interactive TUI (Tapestry Elm application):

- three-field Piccoline screen (manual §3): a top message line, a
  drawing area that takes every row the terminal has to spare, and the
  command line at the bottom. The 80x25 RC759 is the reference, not a
  requirement: larger terminals get a larger picture, shorter ones keep
  the message and command lines and give the picture the rows in
  between. In English the transcript tail shares the bottom of the
  drawing area; in Mikro the top line carries the latest `skriv` output
  or error, as on the RC759
- the English prompt is `? ` with history (`↑`/`↓`); in Mikro mode it is
  `LOGO>`, with a movable block cursor instead
- Tapestry repaints only the rows that changed, in one synchronized
  write, so typing does not clear and redraw the whole screen
- type Logo commands, press Enter; `q` or Esc on an empty line quits
  (English dialect)
- UTF-8 input: a non-ASCII letter such as `å` in `PRINT "blåbær"` arrives
  as one character and backspaces as one (needs a Ditty after v0.9.0)
- `--mikro` switches to the Danish dialect and Danish interface text
  (`frem`, `venstre`, `gentag`/`hertil`, `hvis`/`ellers`/`sluthvis`,
  infix expressions, `;`-separated command lines, `Fejl:` messages, and
  the modal `lær`/`ret` procedure editor with its Danish A-key legend).
  `farvel` quits. The command line follows the manual's editing keys:
  `←`/`→`, `↑`/`↓` for start/end, Insert, Delete, Backspace, and F1 to
  recall the previous sentence line.
- single-line command input: `MAKE` variables and turtle state persist
  across lines. In English, a `TO ... END` definition must be called in
  the same submission (procedure definitions in earlier submissions are
  not yet visible to the parser; see [docs/ROADMAP.md](docs/ROADMAP.md)).
  In Mikro mode, editor-defined procedures are visible to later lines.

## What it is

- **Interpreter** (`lisp/logo/`): tokenizer + arity-driven parser,
  evaluator with procedures, `REPEAT`/`IF`/`RUN`, `MAKE`/`THING`,
  recursion via `OUTPUT`/`STOP`. One shared core serves two dialects:
  the English `logo` dialect and the RC759 `mikro` dialect (Danish
  vocabulary, line-oriented infix expressions and control blocks).
  Pure Lisp on Ditty — no C code.
- **Turtle + canvas**: pure functional turtle state; a backend-
  independent canvas (segment list) rasterized by Bresenham.
- **Graphics backends** (`graphics.lisp`): `canvas` (Braille U+2800,
  works in every terminal), `sixel` (DCS bitmap, decoded by portty via
  coffer), `kitty` / `iterm2` (planned — Ditty 0.8 provides
  `base64-encode`; see [docs/UPSTREAM.md](docs/UPSTREAM.md)).
- **TUI** (`tui.lisp`): Tapestry Elm app implementing the Piccoline's
  three-field screen — message line, drawing area, command line — with
  the drawing area sized from the terminal instead of a hard-coded
  80x25. Mikro mode uses Danish interface text and includes the `LOGO>`
  command line with a block cursor and the manual's editing keys
  (including F1 recall), plus the modal `lær`/`ret` procedure editor: a
  21-line page, cursor editing, the A1–A4 legend above the command line,
  automatic `slut` and three-space indentation, and the
  compile-error/retry loop.

The `logo` dialect is documented in
[docs/LANGUAGE.md](docs/LANGUAGE.md); the April 1985 manual is the
reference for the `mikro` dialect
([PDF](docs/PICCOLINE_Mikro-Logo_Brugervejledning_apr1985.pdf)). Where
this project needs features from Ditty or portty/coffer, they are
tracked in [docs/UPSTREAM.md](docs/UPSTREAM.md) and
[docs/ROADMAP.md](docs/ROADMAP.md).

## Layout

```
bin/logo              launcher (sets DITTY_LISP_PATH, execs ditty)
logo-main.lisp        CLI entry point (also the ditty script)
lisp/logo.lisp        public API: package, module loader, exports
lisp/logo/
  math.lisp           logo-pi, degrees/radians, heading wrap (Ditty has the math)
  canvas.lisp         segment canvas, Bresenham rasterizer, Braille output
  turtle.lisp         pure turtle state and motion
  primitives.lisp     command + value-primitive registries
  parser.lisp         English tokenizer, two-pass arity-driven parser
  mikro.lisp          Mikro-Logo front end and procedure compiler
  interpreter.lisp    evaluator (TO/OUTPUT/STOP as explicit signal values)
  repl.lisp           headless one-line REPL evaluation
  editor.lisp         headless 21-line procedure-editor buffer
  graphics.lisp       capability detection, canvas + sixel backends
  tui.lisp            Tapestry Elm application
examples/*.logo       square, house, spiral, star, circle
tests/test-*.lisp     headless test suites (make check)
docs/                 LANGUAGE, UPSTREAM, ROADMAP, Mikro-Logo manual
emacs/logo-mode.el    Emacs major mode (font-lock)
```

## License

MIT — see [COPYING](COPYING).
