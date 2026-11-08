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
        (always works)      (DCS bitmap → portty/coffer)           planned, PNG)
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
| `lisp/logo/math.lisp`        | `sin`/`cos`/`sqrt`/`abs`/random in pure Lisp. Ditty has floats but no transcendentals (see below).          |
| `lisp/logo/canvas.lisp`      | Segment-list canvas, Bresenham rasterizer, Braille renderer. Zero terminal knowledge.                       |
| `lisp/logo/turtle.lisp`      | Turtle state as an alist; every op returns a new state.                                                     |
| `lisp/logo/primitives.lisp`  | Two registries: commands `(turtle args) -> turtle'`, queries `(turtle args) -> value`.                      |
| `lisp/logo/parser.lisp`      | Tokenizer + two-pass parser (scan `TO` arities, then arity-driven descent).                                 |
| `lisp/logo/interpreter.lisp` | State-threading evaluator; `OUTPUT`/`STOP` as explicit signal values.                                       |
| `lisp/logo/graphics.lisp`    | Capability detection (`PORTTY`, `KITTY_WINDOW_ID`, `TERM_PROGRAM`), canvas + sixel encoders.                |
| `lisp/logo/tui.lisp`         | Tapestry Elm app: model/update/view mirroring the RC759 split screen.                                       |
| `logo-main.lisp`             | CLI dispatch on `*command-line-args*` (TUI / file / `-e`).                                                  |

## Key design decisions

### Ditty has no transcendentals — math.lisp fills the gap

Ditty Lisp has float literals and `+ - * /`, but no `sin`, `cos`,
`sqrt`, `abs`, `expt`, or `random`. Turtle graphics cannot live without
them, so they are implemented in pure Lisp: Taylor-series `sin`/`cos`
with range reduction, Newton `sqrt`, an LCG for `random`. Ditty's
`floor` also truncates float arguments to integers before dividing, so
`logo-real-floor` wraps it for float floor. A `float-math` builtin set
in Ditty would let this module shrink to aliases (docs/UPSTREAM.md).

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
  Detected via `PORTTY=1` (set by portty's PTY layer).
- **kitty / iterm2** — planned. Both need a PNG payload (zlib +
  base64), which Ditty does not provide. Tracked in docs/UPSTREAM.md
  as a Ditty builtin request; a pure-Lisp PNG encoder is the fallback.

Capability detection is environment-based (`PORTTY`, `KITTY_WINDOW_ID`,
`TERM_PROGRAM`, `TERM`). A terminal query (DA1 `4` for sixel,
XTSMGRAPHICS) would be more robust but needs a Ditty builtin to read
query replies — also in docs/UPSTREAM.md.

## Invariants

- Turtle state is immutable: every op returns a new state. The TUI
  model holds it; tests thread it.
- The canvas is the only drawing record. Backends never mutate it.
- Headless code must not require Tapestry or a TTY: `logo` loads
  without either; only `logo-tui-main` requires Tapestry.
- `make check` must pass headlessly (no TTY, no display).
