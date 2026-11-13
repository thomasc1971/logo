# Roadmap

Two tracks share one core:

- **Mikro-Logo (primary).** Complete the RC759 Mikro-Logo described in
  Regnecentralen's April 1985 _PICCOLINE – Mikro-Logo – Brugervejledning_
  ([manual](PICCOLINE_Mikro-Logo_Brugervejledning_apr1985.pdf)). "Complete"
  means the whole system — Danish vocabulary, command line, modal
  procedure editor, disk commands, messages, limits and screen behaviour —
  so that using it feels like sitting at a Piccoline, not like using a
  modern lookalike.
- **Broader Logo.** Keep and grow the English, UCBLogo-style Logo
  dialect. The RC759 subset must never become the limit of the
  interpreter.

## v0.1 — foundation (done)

- Pure-Lisp interpreter on Ditty: parser, evaluator, `TO`/`OUTPUT`/
  `STOP`, `REPEAT`/`IF`/`RUN`, `MAKE`/`THING`, recursion.
- Pure turtle + segment canvas, Bresenham rasterizer, Braille backend.
- Sixel encoder for portty/coffer.
- Tapestry Elm TUI with persistent REPL state, history, transcript.
- Headless test suite (142 assertions), examples, docs, MIT licence.

## v0.2 — dialects and command-line parity

- Split literal/keyword matching into explicit dialects: `logo`
  (English, current default) and `mikro` (Danish). One shared
  parser/interpreter/canvas core; the dialect is selected by CLI flag
  and TUI mode, never by forking the interpreter.
- Mikro-Logo vocabulary from manual appendix F.1: `FREM`/`FR`,
  `TILBAGE`/`TB`, `VENSTRE`/`VE`, `HØJRE`/`HØ`, `TEGN`, `SLET`, `LØFT`,
  `START`, `VISKUD`, `HJEM`, `SÆTXY`, `SÆTX`, `SÆTY`, `DREJTIL`,
  `HVOR`, `PILIND`, `PILUD`, `SKRIV`, `SÆTNING`, `UDPORT`,
  `HVIS`/`ELLERS`/`SLUTHVIS`, `GENTAG`/`HERTIL`, `BEGYND`/`SLUT`,
  `STOP`.
- Mikro-Logo command-line semantics: one line executed whole on Return,
  `;` between statements, cursor editing, F1 recall of the previous
  statement line, ESC cancel, and no procedure definition at the
  prompt.
- Assignment in Mikro-Logo syntax: `variabel := udtryk` and
  `variabel = udtryk`.
- Parse procedure calls against definitions already in interpreter
  state, so a procedure defined in one submission can be called from
  later ones (needed at the Mikro-Logo command line and by the broader
  Logo REPL alike).
- English dialect keeps `TO`/`END`, bracket lists, `MAKE`/`THING` and
  remains the default until the Mikro mode is complete.

## v0.3 — procedure editor and screen parity

- Modal procedure editor invoked by `LÆR` (F5), `RET` (F6) and `LAV`;
  it occupies the drawing area, so the current drawing is hidden while
  editing.
- Cursor editing with the Piccoline key set; `A1` delete rest of line,
  `A2` delete line, `A3` insert blank line, `A4` compile/save, ESC
  abandon.
- Editor rules from the manual: one statement per line, at most 21
  lines (header + 19 statements + `SLUT`), at most 6 parameters,
  procedure names starting with a letter, automatic `SLUT`,
  automatic indentation, compile errors in the top message line, and
  no procedure execution until the error is fixed.
- Piccoline screen model: top status/message line, drawing area, bottom
  command line.
- Procedure administration: `LIST` (F2), `PLIST`, `HVILKE` (F3),
  `GLEM` (F4), `KOPI` (F7), `FORTRYD` (F8), `TEGNIGEN`, `STATUS`,
  `FARVEL`.

## v0.4 — disk, hardware and messages

- Procedure files: `GEM` (F11), `HENT` (F10), `TILFØJ` (F12), `FJERN`,
  `DISK` (F9) / `PDISK`.
- The Danish message catalogue from manual appendix E, including
  resource limits ("Ikke mere lager", "Ikke plads til denne linie",
  "For mange procedurer", …).
- Input sentences (`HENTTAL`, `HENTTAST`, `LÆSTAST`) and `UDPORT`
  implemented where a terminal/port analogue exists; document any
  deliberate stub for hardware the modern terminal lacks.
- Turtle markers `PILIND`/`PILUD` and the live `PIL` command.
- Piccoline presentation options: green-phosphor palette and optional
  scanlines in the TUI.

## v1.0 — Mikro-Logo complete

Acceptance criteria for "complete":

- Every sentence and command in manual appendix F.1/F.2 is implemented,
  or explicitly stubbed with the manual's observable behaviour where
  the RC759 hardware has no analogue.
- Every limit and message in appendix E is reproduced.
- The full `LÆR`/`RET` workflow, including the error-retry loop, matches
  the manual.
- Manual walkthrough: the manual's examples can be typed into the
  Piccoline-mode TUI and produce the documented results.
- `docs/LANGUAGE.md` carries a command-by-command Mikro-Logo mapping.

## Broader Logo track (continuous)

- UCBLogo-style coverage: `SEED` for `RANDOM`; `LABEL`/`GPRINT`;
  procedure introspection (`TEXT`, `NAME`, `CONTENTS`); more list/word
  primitives; source positions in error messages.
- `SETPC` actually rendered: per-segment colour in the Braille backend
  (coloured cells) and palette registers in sixel.
- `SETBG` and canvas colours in the bitmap backends.
- Keep the English dialect documented and tested independently of
  Mikro-Logo mode; RC759 fidelity must not remove or constrain
  standard Logo behaviour.

## Shared platform (both tracks)

- Kitty + iTerm2 backends: Ditty's `base64-encode` supplies the
  payload; kitty takes raw RGBA, iTerm2 needs a simple image encoder
  (BMP or stored-block PNG).
- Pixel-accurate canvas sizing from the capabilities alist
  (`logo-graphics-pixel-size`, UPSTREAM.md #4); the sixel backend
  consumes the reported size.
- Turtle glyph rendering (the little triangle) in Braille and sixel.
- Emacs major mode beyond the stub (`emacs/logo-mode.el`): font-lock
  for both dialects, indentation for `TO...END` / `BEGYND...SLUT` and
  brackets.
- Packaging: `make install` → `~/.local/share/ditty/lisp/`,
  `logo.desktop` entry, man page.
