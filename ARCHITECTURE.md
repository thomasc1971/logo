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

| File                          | Role                                                                                                        |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `lisp/logo.lisp`              | Entry point. Defines the `logo` package, loads modules in order (Tapestry pattern), exports the public API. |
| `lisp/logo/math.lisp`         | `logo-pi`, degree↔radian conversion, heading wrap. Numerics come from Ditty (see below).                    |
| `lisp/logo/canvas.lisp`       | Segment-list canvas, Bresenham rasterizer, Braille renderer. Zero terminal knowledge.                       |
| `lisp/logo/turtle.lisp`       | Turtle state as an alist; every op returns a new state.                                                     |
| `lisp/logo/primitives.lisp`   | Two registries: commands `(turtle args) -> turtle'`, queries `(turtle args) -> value`.                      |
| `lisp/logo/parser.lisp`       | English tokenizer + two-pass parser (scan `TO` arities, then arity-driven descent).                         |
| `lisp/logo/mikro.lisp`        | Mikro front end: line-aware tokenizer, infix expressions, block forms, procedure compiler.                  |
| `lisp/logo/interpreter.lisp`  | State-threading evaluator; `OUTPUT`/`STOP` as explicit signal values; procedure source store.               |
| `lisp/logo/repl.lisp`         | Headless one-line evaluation shared by the TUI and tests; dialect dispatch and output diffing.              |
| `lisp/logo/editor.lisp`       | Headless 21-line procedure-editor buffer and cursor/line operations; no Tapestry or terminal dependency.    |
| `lisp/logo/command-line.lisp` | Headless command-line buffer (text + cursor) and the manual §3 editing operations; no Tapestry dependency.  |
| `lisp/logo/graphics.lisp`     | Capability helpers over Ditty's `terminal` alist, canvas + sixel encoders.                                  |
| `lisp/logo/tui.lisp`          | Tapestry Elm app: model/update/view for the RC759 three-field screen, key mapping, editor view.             |
| `logo-main.lisp`              | CLI dispatch on `*command-line-args*` (TUI / file / `-e`, `--dialect`).                                     |

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

### Two dialects over one core; Mikro-Logo is the fidelity target

The interpreter core is dialect-agnostic: keyword matching, primitive
names and messages come from a dialect layer rather than being
hard-coded in the evaluator. Two dialects share the core:

- `logo` (English, UCBLogo tradition) — broad standard Logo support
  and the current default.
- `mikro` — complete RC759 Mikro-Logo from the April 1985 manual:
  Danish vocabulary, `;`-separated single-line command line, the modal
  `LÆR`/`RET` procedure editor, `:=` assignment, disk commands, limits
  and messages.

`mikro` is the project's fidelity target: "complete" means the whole
manual system, not a themed subset. `logo` must not shrink to that
subset; broader Logo coverage is a separate, ongoing goal. Never fork
the parser or interpreter to achieve either — mode-specific behavior
belongs in dialect tables and interpreter state/options, and shared
core changes must keep both dialects passing. Editor/dialog state lives
in the TUI model, so it stays headless-testable.

### Mikro lowers to the shared AST; the editor is headless

The Mikro surface is deliberately front-end work, not a second
interpreter. `mikro.lisp` tokenizes with line boundaries (the `BEGYND`
header ends at the newline, and one statement per line is enforced),
parses the manual's infix expression grammar, and emits the same AST
that `parser.lisp` produces. Relational expressions lower to
`MIKRO-*` value primitives returning `1`/`0`, conditions lower to
`MIKRO-NOT-ZERO`, and variable references lower to `(:mikro-var NAME)`
so an unbound Mikro variable reads as `0`. The evaluator, turtle and
canvas are untouched.

`editor.lisp` owns only the fixed 21-line page and cursor-editing
semantics. It has no Tapestry or terminal dependency, so its tests run
without a TTY. `command-line.lisp` is the same idea for the single
command line: a `(text . cursor)` pair and the manual §3 operations
(left/right/start/end, TEGN IND, SLET TEGN, backspace, A1). `tui.lisp`
is the adapter: it maps Tapestry key names to these operations and
renders both buffers with an inverse-video block cursor (Tapestry hides
the hardware cursor). The interpreter state keeps
canonical source text in a `sources` hash, which is what `RET` reopens.
A failed A4 stores the draft in the TUI model and sets a `blocked`
message in interpreter state; `logo-call-procedure` refuses to run any
user procedure until a later A4 clears it.

### Canvas, not pixels, as the interchange format

The turtle records segments, not pixels. Backends rasterize as they
see fit: Braille at 2×4 dots per cell for text mode, sixel at native
pixel size for portty. This keeps the interpreter testable headlessly
and the TUI backend-agnostic.

### Tapestry as the TUI shell, not a custom loop

The interactive app is an Elm Architecture program (`model/update/view`)
on Tapestry's `app-run`: raw terminal, alt screen, mouse/focus/paste
management, resize handling, and row-diff rendering belong to Tapestry.
Logo owns only the model (interpreter state + input + transcript) and
the view layout. The view follows the manual's three fields (message
line, drawing area, command line) but sizes itself from
`app-screen-size` rather than the RC759's fixed 80x25: the message and
command lines keep one row each and the drawing area takes the rest,
re-rendering the canvas at the new Braille resolution on resize. In
Mikro mode the top line shows the latest `skriv`/`sætning` output or
error (manual §3); the English dialect keeps its transcript in the
bottom rows of the drawing area. Tapestry symbols are referenced
qualified (`tapestry:...`) because `use-package` inside a function body
does not reliably extend the defining package; and the CLI requires
Tapestry _before_ Logo on the interactive path because Ditty resolves
`pkg:symbol` against packages existing at read time.

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

Tapestry addresses view rows absolutely and repaints only the rows that
changed. A future sixel canvas in the TUI therefore writes its DCS
sequence outside the view and calls `tapestry:app-invalidate`, which
makes the next render clear the screen and repaint the text rows; the
headless sixel path is unaffected.

The boundary is deliberate: Tapestry owns terminal mechanics and
rendering (`key-text`/`printable-key?` for insertable input, one string
per screen row, repainting only the rows that changed in one
synchronized write), while Logo owns policy (F5/F6, `LÆR`/`RET`, A1–A4,
the 21-line limit, compile errors). The editor buffer and Mikro front
end stay in Logo so they remain headless-testable; only generic
text-editing primitives would move upstream if a second Tapestry app
needed them.

## Invariants

- Turtle state is immutable: every op returns a new state. The TUI
  model holds it; tests thread it.
- The canvas is the only drawing record. Backends never mutate it.
- Headless code must not require Tapestry or a TTY: `logo` loads
  without either; only `logo-tui-main` requires Tapestry.
- `make check` must pass headlessly (no TTY, no display).
