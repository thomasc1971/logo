# Upstream requests

Features this project needs from Ditty, portty, and coffer, with the
workaround in use today. When one lands upstream, the workaround
should be removed and the entry struck through.

Last reviewed against Ditty v0.9.0. Entry numbers are stable (other
docs cite them), so withdrawn and landed entries keep their number.

## Ditty

### ~~1. Numeric builtins (`sin`, `cos`, `sqrt`, `abs`, `expt`, …)~~ (landed in v0.8.0)

**Was:** turtle motion needed trig, `sqrt` and `abs`, and the rest of
the numeric tower was missing too. All of these were undefined in
v0.7.4: `abs sqrt sin cos atan atan2 expt exp log random float round
truncate ceiling`.
**Workaround then:** pure-Lisp implementations in `lisp/logo/math.lisp`
(Taylor series, Newton, LCG for `random`).
**Now:** all of them are builtins (`tan asin acos atan2 random-seed`
included). Logo calls them directly — there are no `logo-*` aliases —
and `math.lisp` keeps only the Logo angle convention (`logo-pi`,
degrees↔radians, heading wrap).

### ~~2. Float-aware `floor` (and unary `floor`)~~ (landed in v0.8.0)

**Was:** `floor` took exactly two arguments (`(floor 7.5)` was an
error) and truncated both to integers before dividing, so
`(floor 314.15 6.283)` returned `52` (`314/6`) and `(floor -7.5 1)`
returned `-7`, not `-8`.
**Workaround then:** `logo-real-floor` (truncate via `(floor x 1)`,
adjust for negatives).
**Now:** `(floor x)` and `(floor x y)` operate on floats and round
toward negative infinity; `ceiling`, `round` and `truncate` are
single-argument builtins too. The workaround and its `(floor x 1)`
call sites are gone. (Companion change: `quotient`, `remainder` and
`modulo` also work on floats and return the types Logo's primitives
document.)

### ~~3. `vector-length`~~ (withdrawn)

**Not needed.** `length` already accepts vectors (`builtin_length` has
a vector branch), so Logo can use `length` directly.

**Gotcha, not a request:** `(make-vector n)` with no fill argument
creates an _empty_ vector (`length` 0), so always pass a fill:
`(make-vector n 0)`. The parser keeps tracking lengths from the source
list; that is no longer required and can be simplified.

### ~~4. Cell size in pixels (`TIOCGWINSZ` `ws_xpixel`/`ws_ypixel`, or `CSI 14/16 t`)~~ (landed in v0.8.0 as `terminal-pixel-size`)

**Was:** the sixel backend had to size its bitmap to a fixed 480×360
because `terminal-size` returns only `(rows . cols)`.
**Now:** `(terminal-pixel-size)` returns `(width . height)` from
`ws_xpixel`/`ws_ypixel`, and `nil` when they are 0 (many terminals
report 0). Logo exposes both sizes through
`logo-graphics-pixel-size` and `logo-graphics-cell-size`, which read
them out of the capabilities alist (`pixel-size`, `cell-size`); the
sixel backend still draws at its fixed 480×360. When it switches over,
the `CSI 16 t` query stays the fallback for terminals that report no
pixel size.

### ~~5. Graphics capability query (DA1 `4` / XTSMGRAPHICS) + reply reading~~ (landed in v0.9.0 as the event loop's `capabilities` event)

**Was:** robust sixel detection needed a terminal round-trip, and
Ditty could only offer `set-terminal-raw` + `read-byte-timeout` in
Lisp. Logo therefore guessed from the environment (`PORTTY`,
`KITTY_WINDOW_ID`, `TERM_PROGRAM`, `TERM`) in
`logo-graphics-capabilities`, and shipped with a "query would be more
robust" caveat.
**Now:** the round-trip lives in Ditty's `terminal` library, in Lisp
(no C builtin): `terminal-capabilities` is the blocking form for
scripts, and inside `terminal-event-loop` the `:probe` option sends
`*terminal-probe*` once at startup and delivers a `capabilities`
event — `terminal-wait` keeps the loop poll-free. Tapestry passes that
event to the app's `update` as `((type . capabilities) (caps . ALIST))`;
Logo stores the alist under `'caps` in its model and picks its backend
from it, so the footer flips from `canvas` to `sixel` when the answer
arrives, and a terminal that never answers simply keeps the env-only
fallback. Headless code calls the pure
`terminal-capabilities-from-replies` with no replies (no I/O). The
kitty keyboard protocol is detected (and enabled) by the loop as well.
Logo's `getenv` heuristics are gone; the same rules live in Ditty's
`terminal-env-capabilities`.

### ~~6. Base64 over byte vectors (for kitty + iTerm2 backends)~~ (landed in v0.8.0 as `base64-encode`)

**Was:** the kitty graphics protocol (APC `G`) and iTerm2 inline
images (OSC 1337) both carry base64 payloads, and Ditty had no way to
produce one. (Kitty accepts raw RGB/RGBA pixels — `f=24`/`f=32` — so
no PNG was ever needed; only base64. Ditty strings cannot hold NUL
bytes, which is why the input has to be a byte vector.)
**Workaround then:** none; a pure-Lisp encoder over byte vectors was
possible but slow.
**Now:** `(base64-encode bytes)` takes a list or vector of integers
0–255 (or a string's UTF-8 bytes) and returns an RFC 4648 string. The
kitty backend can use it directly. iTerm2 still needs an image
container it decodes (an uncompressed BMP, or a stored-block PNG);
that encoder is pure Lisp, so it is no longer an upstream blocker.
iTerm2 also supports sixel (since 3.3, to be confirmed against a
current build), so the sixel backend may already cover it.

### ~~7. `string-prefix?` correctness~~ (withdrawn)

**Not a bug.** `(string-prefix? "abcd" "ab")` returns `nil` in v0.7.4.
The argument order is `(string-prefix? PREFIX STRING)`, as documented
and covered by Ditty's `tests/basic/strings.lisp`:
`(string-prefix? "hel" "hello")` is `#t`.

The original report most likely had the arguments reversed; it does
not reproduce on v0.7.4 (repo build or installed binary). Logo may use
`string-prefix?` normally; the `substring` workaround in
`tests/test-graphics.lisp` is unnecessary.

### 10. Multi-byte (UTF-8) keyboard input in `terminal-read-event`

**Need:** Logo's TUI input line accepts any one-character key _name_ as
typed text (`(and (= (length key) 1) …)`), so a non-ASCII letter such
as the `å` in `PRINT "blåbær` should arrive as one key named by that
character.
**Today:** `terminal-read-event` decodes input one byte at a time, so a
UTF-8 sequence arrives as several one-byte key events and the letter
inserts as two or three wrong characters. Workaround: none; the TUI
input line is ASCII-only. (On Windows, `read-byte` additionally
truncates wide characters.)
**Ideal:** the event parser assembles UTF-8 continuation bytes into a
single key whose name is the decoded character, so Logo's "one-character
key name means typed text" rule keeps working. Tracked in Ditty's
`TODO.md` under "Terminal input" ("Decode UTF-8 in the event parser").

## portty / coffer

### 8. Sixel on Windows/ConPTY (already tracked in portty)

portty's inline-image doc notes ConPTY strips DCS, so sixel needs the
bundled `conpty.dll`/`OpenConsole.exe` path. Logo's sixel backend
will inherit whatever portty ships; nothing Logo-side needed.

### 9. (No portty changes needed for v1)

Sixel decode (DCS, palette, Pan/Pad clamping), cell geometry, and
`PORTTY=1`/`PORTTY_WIDTH` env contracts are all already in place and
sufficient for the sixel backend.
