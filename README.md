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

## Quick start

Prerequisites: [Ditty](https://github.com/chestso/ditty) 0.9+? — the
release whose `terminal` library detects graphics capabilities — on your
`PATH` (for the interactive TUI also
[Tapestry](https://github.com/chestso/tapestry)).
Install both from source (`./autogen.sh`, configure, `make`, `make install`);
Ditty's library search path (XDG data dirs, `DITTY_LISP_PATH`) then resolves
`(require 'logo)` and `(require 'tapestry)` for `bin/logo` and `make check`.

```sh
bin/logo                              # interactive TUI
bin/logo examples/star.logo           # run a program, print the picture
bin/logo -e 'REPEAT 4 [FD 80 RT 90]'  # one-liner
bin/logo --backend sixel examples/star.logo   # sixel bitmap (portty)
bin/logo --help
make check                            # run the test suite
```

The interactive TUI (Tapestry Elm application):

- picture pane (Braille canvas, boxed) · transcript pane (PRINT output
  and errors) · `? ` prompt line with history (`↑`/`↓`)
- type Logo commands, press Enter; `q` or Esc on an empty line quits
- `TO ... END` definitions and `MAKE` variables persist across lines

## What it is

- **Interpreter** (`lisp/logo/`): tokenizer + arity-driven parser,
  evaluator with procedures, `REPEAT`/`IF`/`RUN`, `MAKE`/`THING`,
  recursion via `OUTPUT`/`STOP`. Pure Lisp on Ditty — no C code.
- **Turtle + canvas**: pure functional turtle state; a backend-
  independent canvas (segment list) rasterized by Bresenham.
- **Graphics backends** (`graphics.lisp`): `canvas` (Braille U+2800,
  works in every terminal), `sixel` (DCS bitmap, decoded by portty via
  coffer), `kitty` / `iterm2` (planned — Ditty 0.8 provides
  `base64-encode`; see [docs/UPSTREAM.md](docs/UPSTREAM.md)).
- **TUI** (`tui.lisp`): Tapestry Elm app mirroring the Piccoline's
  split screen — picture above, work area below.

The Logo dialect is documented in
[docs/LANGUAGE.md](docs/LANGUAGE.md); where this project needs features
from Ditty or portty/coffer, they are tracked in
[docs/UPSTREAM.md](docs/UPSTREAM.md) and
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
  parser.lisp         tokenizer, two-pass arity-driven parser
  interpreter.lisp    evaluator (TO/OUTPUT/STOP as explicit signal values)
  graphics.lisp       capability detection, canvas + sixel backends
  tui.lisp            Tapestry Elm application
examples/*.logo       square, house, spiral, star, circle
tests/test-*.lisp     headless test suites (make check)
docs/                 LANGUAGE, UPSTREAM, ROADMAP
emacs/logo-mode.el    Emacs major mode (font-lock)
```

## License

MIT — see [COPYING](COPYING).
