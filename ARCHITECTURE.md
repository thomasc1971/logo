# Architecture

How Logo is put together and why. For the language itself see
[docs/LANGUAGE.md](docs/LANGUAGE.md); for build/test workflow see
[CONTRIBUTING.md](CONTRIBUTING.md).

## Layers

```
 Logo source ──▶ parser ──▶ AST ──▶ interpreter ──▶ turtle (pure state)
                                                          │
                                              canvas (segments) ◀─┘
                                                          │
              ┌───────────────────┬───────────────────────┴───────────────┐
              ▼                   ▼                                       ▼
        Braille text        sixel encoder                          (kitty/iterm2:
        (always works)      (DCS bitmap → portty/coffer)           planned, base64)
              │                   │
              ▼                   ▼
        Tapestry TUI panes    terminal (portty, kitty, iTerm2, xterm…)
```

Everything above the canvas is pure Lisp and headless-testable. The
only terminal-dependent code is the graphics backend selection and the
Tapestry view — both thin.

## Module map

| File                         | Role                                                                                                        |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `lisp/logo.lisp`             | Entry point. Defines the `logo` package, loads modules in order (Tapestry pattern), exports the public API. |
| `lisp/logo/math.lisp`        | `logo-pi`, degree↔radian conversion, heading wrap. Numerics come from Ditty (see below).                    |
| `lisp/logo/canvas.lisp`      | Segment-list canvas, Bresenham rasterizer, Braille renderer. Zero terminal knowledge.                       |
| `lisp/logo/turtle.lisp`      | Turtle state as an alist; every op returns a new state.                                                     |
| `lisp/logo/primitives.lisp`  | Two registries: commands `(turtle args) -> turtle'`, queries `(turtle args) -> value`.                      |
| `lisp/logo/parser.lisp`      | Tokenizer + two-pass parser (scan `TO` arities, then arity-driven descent).                                 |
| `lisp/logo/interpreter.lisp` | State-threading evaluator; `OUTPUT`/`STOP` as explicit signal values.                                       |
| `lisp/logo/graphics.lisp`    | Capability helpers over Ditty's `terminal` alist, canvas + sixel encoders.                                  |
| `lisp/logo/tui.lisp`         | Tapestry Elm app: model/update/view mirroring the RC759 split screen.                                       |
| `logo-main.lisp`             | CLI dispatch on `*command-line-args*` (TUI / file / `-e`).                                                  |

## Key design decisions

### Numerics come from Ditty; math.lisp keeps the angle convention

Ditty Lisp (0.9.0+, the supported minimum) ships the numeric tower:
`abs`, `sqrt`, `sin`, `cos`, `tan`, `atan`/`atan2`, `exp`, `log`,
`expt`, `float`, unary and float-aware `floor`/`ceiling`/`round`/
`truncate`, truncating `quotient`, `remainder`, `modulo`, and a seedable
`random`. Logo calls these directly — there are no `logo-*` aliases, so
a numeric fix lands once, upstream. `math.lisp` therefore only holds
what is Logo-specific: `logo-pi`, degrees↔radians (`logo-deg->rad`,
`logo-rad->deg`) and the `[0, 360)` heading wrap
(`logo-normalize-heading`). See docs/UPSTREAM.md #1/#2.

### Ditty errors are values; condition-case substitutes and resumes

Ditty error objects are ordinary values that propagate only through
frames that check them (`error?` guards are used at every destructure
point), _and_ `condition-case` substitutes the handler's result at the
error site and resumes execution — a handler result flowing into a
`let*` binding silently becomes data. Consequences:

- `OUTPUT`/`STOP` are explicit signal values `(logo-output STATE . VALUE)`
  / `(logo-stop . STATE)`, unwound by checks in the eval loops — never
  exceptions.
- Boundary code (`logo-repl-eval`, `logo-run`) wraps calls in
  `condition-case` whose handlers return the error object _itself_, then
  `error?`-checks it. Handlers must never produce data that flows into
  destructuring code.
- `car`/`cdr` on an error object yields a confusing secondary error, so
  every `(car result)`/`(cdr result)` in parser/interpreter is guarded.

### Arity-driven parsing

Logo is a flat instruction stream (`FD 100 RT 90`), not nested forms.
The parser needs each primitive's arity to know where one instruction
ends; procedure arities are unknown until seen, so pass 1 scans for
`TO ... END` to collect them, pass 2 does the arity-driven descent.
Unknown words are errors (catch typos early, like the RC759 did).

### Canvas, not pixels, as the interchange format

The turtle records segments, not pixels. Backends rasterize as they
see fit: Braille at 2×4 dots per cell for text mode, sixel at native
pixel size for portty. This keeps the interpreter testable headlessly
and the TUI backend-agnostic.

### Tapestry as the TUI shell, not a custom loop

The interactive app is an Elm Architecture program (`model/update/view`)
on Tapestry's `app-run`: raw terminal, alt screen, mouse/focus/paste
management, and resize handling belong to Tapestry. Logo owns only the
model (interpreter state + input + transcript) and the view layout.
Tapestry symbols are referenced qualified (`tapestry:...`) because
`use-package` inside a function body does not reliably extend the
defining package; and the CLI requires Tapestry _before_ Logo on the
interactive path because Ditty resolves `pkg:symbol` against packages
existing at read time.

## Graphics backends and portty

portty (via coffer) decodes four image protocols into one shared image
store: sixel (DCS), iTerm2 inline (OSC 1337), kitty graphics (APC `G`),
and Lottie (APC). Logo's backends:

- **canvas** — Braille text. Always available, every terminal.
- **sixel** — implemented. Single-colour palette, Pan/Pad raster
  attributes (`"1;1;WxH`) so coffer clamps to the declared size
  instead of rounding up to 6-row bands (portty's documented gotcha).
  Detected by Ditty's capability probe (DA1 `4`), with `PORTTY=1`
  (set by portty's PTY layer) as the environment fallback.
- **kitty / iterm2** — planned. Ditty 0.8's `base64-encode` covers
  the payload (it takes a byte vector, since Ditty strings cannot hold
  NUL bytes). Kitty accepts raw RGB(A) pixels, so only base64 is
  needed; iTerm2 additionally needs an image file (PNG stored blocks
  or BMP), which is pure Lisp. See docs/UPSTREAM.md #6.

Capability detection is delegated to Ditty's `terminal` library, which
probes the terminal once (kitty keyboard flags, `CSI 14/16 t`, DA1 `4`
for sixel) and folds in the environment. There is no query and no
blocking wait on Logo's side: in the TUI the answer arrives as a
`capabilities` message (`((type . capabilities) (caps . ALIST))`), the
model stores the alist under `'caps`, and the backend is recomputed
from it; headless code calls the pure
`terminal-capabilities-from-replies` with no replies, i.e. the
environment-only fallback. A terminal that never answers DA1 keeps the
fallback and simply stays on Braille. See docs/UPSTREAM.md #5.

## Invariants

- Turtle state is immutable: every op returns a new state. The TUI
  model holds it; tests thread it.
- The canvas is the only drawing record. Backends never mutate it.
- Headless code must not require Tapestry or a TTY: `logo` loads
  without either; only `logo-tui-main` requires Tapestry.
- `make check` must pass headlessly (no TTY, no display).
