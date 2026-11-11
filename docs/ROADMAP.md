# Roadmap

## v0.1 — foundation (done)

- Pure-Lisp interpreter on Ditty: parser, evaluator, `TO`/`OUTPUT`/
  `STOP`, `REPEAT`/`IF`/`RUN`, `MAKE`/`THING`, recursion.
- Pure turtle + segment canvas, Bresenham rasterizer, Braille backend.
- Sixel encoder for portty/coffer.
- Tapestry Elm TUI with persistent REPL state, history, transcript.
- Headless test suite (134 assertions), examples, docs, MIT licence.

## v0.2 — language completeness

- Danish aliases (`FREM`, `TILBAGE`, `HØJRE`, `VENSTRE`, `GENTAG`,
  `HVIS`, …) as a locale table over the English registry — a nod to
  the RC759 classroom.
- `SEED` for `RANDOM`; `LABEL`/`GPRINT`; `SETPC` actually rendered
  (per-segment colour in the Braille backend via coloured cells, and
  palette registers in sixel).
- Procedure introspection (`TEXT`, `NAME`, `CONTENTS`) — cheap once
  the proc table exists.
- Error messages with Logo source positions (parser currently reports
  token-level errors only).

## v0.3 — graphics backends

- Kitty + iTerm2 backends: Ditty 0.8's `base64-encode` supplies the
  payload; kitty takes raw RGBA, so no PNG is required. iTerm2 also
  needs a simple image encoder (BMP or stored-block PNG).
- Pixel-accurate canvas sizing from `terminal-pixel-size`
  (UPSTREAM.md #4); capability queries (#5) are doable from Lisp with
  `set-terminal-raw` + `read-byte-timeout`.
- Turtle glyph rendering (the little triangle) in Braille/sixel.

## v1.0 — polish

- Emacs major mode beyond the stub (`emacs/logo-mode.el`): font-lock
  for primitives/special forms, indentation for `TO...END`/`[...]`.
- Farewell to the Piccoline: a `PICCO` mode with green-phosphor
  palette and scanlines in the TUI? (Colour via Tapestry styles.)
- Packaging: install target (`make install` → `~/.local/share/ditty/lisp/`),
  `logo.desktop` entry, man page.
