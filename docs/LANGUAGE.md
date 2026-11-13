# Logo dialect

The Logo dialect implemented here: a pragmatic subset of UCBLogo /
classic school Logo, tuned for turtle graphics in a terminal. Words
are case-insensitive (uppercased by the reader). `\` starts a comment
to end of line.

## Dialects

One shared core, two dialects:

- **`logo`** (English, documented below) — the UCBLogo-style dialect
  this document specifies. It remains first-class and keeps growing.
- **`mikro`** — RC759 Mikro-Logo from Regnecentralen's April 1985
  manual ([PDF](PICCOLINE_Mikro-Logo_Brugervejledning_apr1985.pdf)):
  Danish vocabulary, the `;`-separated single-line command line, the
  modal `LÆR`/`RET` procedure editor, `:=` assignment, and the manual's
  expression and procedure rules. Using it should feel like sitting at a
  Piccoline.

The shared parser/interpreter/canvas core serves both. `mikro` lowers
its surface syntax into the same AST, so procedure calls, recursion and
turtle state behave the same. Start it with `logo --mikro` or
`logo --dialect mikro`. [ROADMAP.md](ROADMAP.md) tracks the remaining
Mikro work separately from broader Logo support. The manual is
authoritative for `mikro`; this file is authoritative for `logo`.

## Mikro-Logo dialect

### Command line

The command line is one line, executed whole on Return (manual §3).
Several statements are separated with `;`:

```
frem 100; venstre 90; frem 100
```

Procedure definitions are not allowed on the command line;
`sætning/begynd/slut er ikke tilladt` (appendix E.2.1). Use the editor.

### Procedures

```
begynd polygon side antal
   gentag antal
      frem side
      venstre 360/antal
   hertil
slut
```

- One statement per line; `;` is not allowed inside a procedure.
- Header `begynd name [param ...]`; at most 6 parameters; names start
  with a letter and are at most 16 characters.
- At most 21 lines total: header + at most 19 statement lines + `slut`.
- `slut` is optional when writing in the editor; A4 inserts it when
  there is room.
- The compiler stores canonical source with three spaces of indentation
  per nesting level. `RET` shows that canonical source.
- A procedure with the same name replaces the old one on a successful
  A4.

### Expressions

Mikro expressions are integer-only and infix. The manual forbids spaces
inside an expression; this implementation accepts them too, which is a
deliberate relaxation.

| Operators                  | Precedence                             |
| -------------------------- | -------------------------------------- |
| `(` … `)`                  | grouping                               |
| `^`                        | power, right-associative               |
| `*` `/`                    | multiplication, division               |
| `+` `-`                    | addition, subtraction, unary sign      |
| `=` `<` `>` `<=` `>=` `<>` | one relational operator; yields 1 or 0 |

Examples: `360/antal`, `side+2`, `x<10`, `(antal<10)*(side>20)`.
Relational operators yield `1`/`0`, `0` is false, and an unbound
variable reads as `0` (manual §4.1).

`tlf(expr)` is the random function (`RANDOM`).

### Statements and commands

| Mikro                          | English core            | Notes                                 |
| ------------------------------ | ----------------------- | ------------------------------------- |
| `frem` / `fr`                  | `FD`                    |                                       |
| `tilbage` / `tb`               | `BK`                    |                                       |
| `venstre` / `ve`               | `LT`                    |                                       |
| `højre` / `hø`                 | `RT`                    |                                       |
| `tegn`                         | `PD`                    |                                       |
| `slet`                         | `PU`                    | pen-up; erase mode is not implemented |
| `løft`                         | `PU`                    |                                       |
| `start`                        | clear + home + pen down |                                       |
| `viskud`                       | `CS`                    | keeps position                        |
| `hjem`                         | `HOME`                  |                                       |
| `sætxy`                        | move to x, y            |                                       |
| `sætx` / `sæty`                | `SETX` / `SETY`         |                                       |
| `drejtil`                      | `SETH`                  |                                       |
| `hvor x y h`                   | assigns x, y, heading   |                                       |
| `pilind` / `pilud`             | show/hide turtle flag   | not drawn                             |
| `skriv expr`                   | `PRINT`                 | writes to the transcript              |
| `sætning text`                 | `PRINT` text            | writes to the transcript              |
| `x := expr`, `x = expr`        | assignment              |                                       |
| `stop`                         | `STOP`                  |                                       |
| `hvis` / `ellers` / `sluthvis` | `IF` / `IFELSE`         |                                       |
| `gentag` / `hertil`            | `REPEAT`                |                                       |

Known deviations while the rest of the manual is implemented:

- `slet` lifts the pen instead of selecting erase mode; the canvas has
  no erase operation yet.
- `skriv`/`sætning` go to the transcript, not the RC759 top message
  line.
- `udport`, input sentences, disk commands, `lav`, `list`, `hvilke`,
  `glem`, `kopi`, `fortryd`, `tegnigen`, `status`, `hjælp` and `farvel`
  from the manual are not implemented yet (`farvel` quits the TUI).
- Physical A1–A4 keys do not exist on modern terminals; the editor uses
  `C-k`, `C-d`, `C-o`, `C-s` as equivalents (see below).

### The LÆR/RET editor

`lær` (F5) opens a blank 21-line page with `begynd` on the first line.
`ret name` (F6) opens an existing procedure; bare `ret` asks for a name.
The editor replaces the drawing area; ESC abandons the edit.

| Key                   | Action                                                                                                                             |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `←` / `→` / `↑` / `↓` | move the block cursor; left at column 0 goes to the previous line's last character, right from the last character to the next line |
| Return                | move to the start of the next line; on the last line, A4                                                                           |
| Backspace / Delete    | delete left / under the cursor; join lines at the boundaries                                                                       |
| Insert                | insert one blank at the cursor                                                                                                     |
| `C-k`                 | A1: delete rest of line                                                                                                            |
| `C-d`                 | A2: delete line                                                                                                                    |
| `C-o`                 | A3: insert blank line                                                                                                              |
| `C-s`                 | A4: compile and save                                                                                                               |
| `ESC`                 | abandon                                                                                                                            |

A4 inserts `slut` when needed, indents the source, and compiles it. A
compile error appears in the top message line; the editor closes, the
draft is kept, and no user procedure runs until the error is fixed.
`ret name` reopens the failed draft, and `ESC` keeps the previous
definition intact. Limits and messages follow manual §4.4.4/§5.1.1 and
appendix E.

## Coordinates and heading

- Origin at canvas centre, `x` right, `y` up.
- Heading `0` = north (up), clockwise positive (`RT 90` faces east).
- Turtle starts at `(0, 0)` facing north, pen down.

## Commands (primitives)

| Word                    | Arity | Effect                                     |
| ----------------------- | ----- | ------------------------------------------ |
| `FD` / `FORWARD`        | 1     | Move forward, drawing if pen down          |
| `BK` / `BACK`           | 1     | Move backward                              |
| `RT` / `RIGHT`          | 1     | Turn clockwise                             |
| `LT` / `LEFT`           | 1     | Turn counter-clockwise                     |
| `SETH` / `SETHEADING`   | 1     | Set heading                                |
| `SETX`                  | 1     | Move to x (draws if pen down)              |
| `SETY`                  | 1     | Move to y                                  |
| `HOME`                  | 0     | Go to origin, face north                   |
| `CS` / `CLEAN`          | 0     | Clear the drawing                          |
| `PU` / `PENUP`          | 0     | Pen up                                     |
| `PD` / `PENDOWN`        | 0     | Pen down                                   |
| `ST` / `SHOWTURTLE`     | 0     | Show turtle (state only; not rendered)     |
| `HT` / `HIDETURTLE`     | 0     | Hide turtle                                |
| `SETPC` / `SETPENCOLOR` | 1     | Pen colour: `[r g b]` list, number, or nil |
| `SETBG`                 | 1     | Background colour (recorded on canvas)     |
| `PRINT` / `PR` / `SHOW` | 1     | Print one value to the transcript          |

## Queries (value primitives)

`XCOR`, `YCOR`, `HEADING`, `PENDOWNP` (0 args);
`SUM`, `PRODUCT`, `COUNT`, `FIRST`, `LAST`, `BUTLAST`, `ABS`, `RANDOM`
(1 arg; `SUM`/`PRODUCT` take a list or a bare number);
`DIFFERENCE`, `QUOTIENT`, `REMAINDER`, `MODULO`, `GREATER?`, `LESS?`,
`EQUAL?` (2 args). Queries can be used as arguments: `PRINT SUM [1 2 3]`.

`QUOTIENT` truncates toward zero and returns an integer (`QUOTIENT 7 2`
is `3`); `REMAINDER` keeps the dividend's sign (`REMAINDER -7 2` is
`-1`); `MODULO` keeps the divisor's sign (`MODULO -7 2` is `1`). All
three take floats (`REMAINDER 7.5 2` is `1.5`) and satisfy
`a = b * QUOTIENT a b + REMAINDER a b`.

`RANDOM n` returns an integer in `[0, n)`; `n` must be positive.
Seeding is from Lisp with Ditty's `random-seed`; a Logo `SEED`
primitive is planned.

## Special forms

- `TO name :params body END` — define a procedure. Procedures are
  indexed before parsing, so calls may precede definitions.
- `OUTPUT expr` — return a value from the current procedure.
- `STOP` — exit the current procedure.
- `REPEAT n [body]` — run body n times.
- `IF cond [body]`, `IFELSE cond [then] [else]` — truthiness: only
  `#f`/nil is false (conditions are usually `PENDOWNP` or comparisons).
- `RUN [body]` — execute a bracketed instruction list.
- `MAKE :var expr` — assign a global. `THING :var` / `THING "var"` —
  read a variable (also usable as an expression: `PRINT THING :X`).
- `LOCAL [:a :b]` — declare locals in the current procedure.

## Data

- Numbers: integers and floats, optional leading `-`.
- Strings: `"like this"` (no escapes).
- Lists: `[1 2 [nested]]` — evaluated element-wise; bare words in a
  list are kept as name strings (`PRINT [HELLO WORLD]`).
- Variables: `:name`. Bare words in argument position: variable value
  if bound, else a zero-argument procedure call, else the word itself
  as a string (`PRINT HELLO` prints `HELLO`).

## Examples

See `examples/`: `square.logo`, `house.logo`, `spiral.logo`,
`star.logo`, `circle.logo`.

## Not yet implemented (planned)

- **Remaining Mikro-Logo** — erase mode for `slet`, input sentences
  (`henttal`, `henttast`, `læstast`), `udport`, disk and procedure
  administration (`gem`, `hent`, `tilføj`, `fjern`, `disk`, `lav`,
  `list`, `plist`, `hvilke`, `glem`, `kopi`, `fortryd`, `tegnigen`,
  `status`, `hjælp`), the full appendix E message catalogue, and the
  remaining Piccoline screen chrome. See [ROADMAP.md](ROADMAP.md) and
  the [manual](PICCOLINE_Mikro-Logo_Brugervejledning_apr1985.pdf).
- Broader Logo: `SEED`/`RANDOM` seeding from Logo, `LABEL`/`GPRINT`,
  text output on the canvas (`SETPC` is recorded but not yet rendered
  per-colour), multi-turtle, `BYE`.
