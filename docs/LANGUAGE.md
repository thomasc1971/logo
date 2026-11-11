# Logo dialect

The Logo dialect implemented here: a pragmatic subset of UCBLogo /
classic school Logo, tuned for turtle graphics in a terminal. Words
are case-insensitive (uppercased by the reader). `\` starts a comment
to end of line.

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

- Danish aliases (`FREM`, `HØJRE`, …) from the RC759 era — the
  registry makes these cheap; a locale table is planned.
- `SEED`/`RANDOM` seeding from Logo, `LABEL`/`GPRINT`, text output
  on the canvas (`SETPC` is recorded but not yet rendered per-colour),
  multi-turtle, `BYE`.
