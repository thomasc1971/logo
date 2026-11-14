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

**Mostly done.** The Mikro front end lowers Danish, line-oriented
syntax into the shared AST; the English dialect is unchanged.

- **Done:** dialect selection with `--mikro` / `--dialect mikro`; one
  shared parser/interpreter/canvas core.
- **Done:** Mikro vocabulary from appendix F.1: `FREM`/`FR`,
  `TILBAGE`/`TB`, `VENSTRE`/`VE`, `HØJRE`/`HØ`, `TEGN`, `LØFT`,
  `START`, `VISKUD`, `HJEM`, `SÆTXY`, `SÆTX`, `SÆTY`, `DREJTIL`,
  `HVOR`, `PILIND`, `PILUD`, `SKRIV`, `SÆTNING`,
  `HVIS`/`ELLERS`/`SLUTHVIS`, `GENTAG`/`HERTIL`, `BEGYND`/`SLUT`,
  `STOP`.
- **Done:** Mikro expression grammar (infix `+ - * / ^`, comparisons,
  parentheses, `tlf`), numeric truth (`0` false), default-zero
  variables.
- **Done:** command-line semantics for one line executed whole on
  Return, `;` between statements, ESC cancel, and rejection of
  procedure definitions at the prompt.
- **Done:** command-line cursor editing (manual §3): block cursor,
  left/right, up/down as start/end, TEGN IND, SLET TEGN, backspace, A1
  via `C-k`, and F1 recall of the previous sentence line (command lines
  are skipped). The prompt is `LOGO>`.
- **Done:** Danish letters fold case in command words and names, so
  `lær` is the same command as `LÆR` (Ditty's `string-upcase` is ASCII
  only).
- **Done:** assignment `variabel := udtryk` and `variabel = udtryk`.
- **Done:** parse Mikro calls against procedures already in interpreter
  state, so editor-defined procedures can be called from later lines.
- **Remaining:** erase mode for `SLET` (currently pen-up), `UDPORT`,
  and the input sentences.
- English dialect keeps `TO`/`END`, bracket lists, `MAKE`/`THING` and
  remains the default.

## v0.3 — procedure editor and screen parity

**LÆR/RET slice done; administration and `LAV` remain.**

- **Done:** modal procedure editor invoked by `LÆR` (F5) and `RET`
  (F6); it replaces the drawing area while editing. Bare `RET`/F6
  prompts for a procedure name.
- **Done:** cursor editing with the manual's semantics; modern
  equivalents are `C-k` (A1 delete rest of line), `C-d` (A2 delete
  line), `C-o` (A3 insert blank line), `C-s` (A4 compile/save), ESC
  abandon, and Return on the last line = A4.
- **Done:** editor rules: one statement per line, at most 21 lines
  (header + 19 statements + `SLUT`), at most 6 parameters, names
  starting with a letter, automatic `SLUT`, automatic three-space
  indentation, compile errors in the top message line, draft retention,
  and no procedure execution until the error is fixed.
- **Done:** source retention and canonical `RET` round-trip for
  editor-defined procedures.
- **Done:** Piccoline screen model: top message line, drawing area,
  bottom command line (manual §3). The layout is responsive rather than
  fixed at 80x25: the message and command lines keep one row each and
  the drawing area takes every row in between. In Mikro mode the top
  line shows the latest `skriv`/`sætning` output or error, the editor
  page replaces the drawing area, and its A1–A4 legend is the line just
  above the command line (manual §5.1.1, fig. 12).
- **Remaining:** `LAV`, `LIST` (F2), `PLIST`, `HVILKE` (F3), `GLEM`
  (F4), `KOPI` (F7), `FORTRYD` (F8), `TEGNIGEN`, `STATUS`, and physical
  A1–A4 key support where a terminal can report it.

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
