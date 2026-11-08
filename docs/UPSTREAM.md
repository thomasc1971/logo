# Upstream requests

Features this project needs from Ditty, portty, and coffer, with the
workaround in use today. When one lands upstream, the workaround
should be removed and the entry struck through.

## Ditty

### 1. Transcendental math builtins (`sin`, `cos`, `sqrt`, `abs`, `expt`)

**Need:** turtle motion needs all of them.
**Workaround:** pure-Lisp implementations in `lisp/logo/math.lisp`
(Taylor series, Newton, LCG for `random`).
**Ideal:** `sin`/`cos`/`sqrt`/`abs`/`expt`/`atan2` as builtins
(float arithmetic already exists); `logo/math.lisp` becomes aliases.

### 2. Float-aware `floor`

**Need:** `(floor 314.15 6.283)` returns `52` (arguments are truncated
to integers first: `314/6`). Range reduction and `REMAINDER` need
true float floor division.
**Workaround:** `logo-real-floor` (truncate via `(floor x 1)`, adjust
for negatives).

### 3. `vector-length`

**Need:** size of a vector (parser token vector, raster grid).
**Workaround:** track lengths alongside vectors (`length` of the
source list).

### 4. Cell size in pixels (`TIOCGWINSZ` `ws_xpixel`/`ws_ypixel`, or `CSI 14/16 t`)

**Need:** size a sixel/kitty/iTerm2 image to the terminal's real cell
geometry instead of a fixed 480×360.
**Workaround:** fixed pixel size in `logo-render-sixel`.
**Note:** portty reports _logical_ pixels (iTerm2 convention);
portty's `CSI 16 t` answer is the right source.

### 5. Graphics capability query (DA1 `4` / XTSMGRAPHICS) + reply reading

**Need:** robust sixel detection instead of environment heuristics.
**Workaround:** `PORTTY` / `KITTY_WINDOW_ID` / `TERM_PROGRAM` env vars
in `logo-graphics-capabilities`.
**Ideal:** a builtin to write a query and read the reply (needs raw
input interleaved with output — pairs with #6).

### 6. PNG/zlib/base64 builtins (for kitty + iTerm2 backends)

**Need:** encode a pixel buffer as PNG, base64 it, emit APC `G` /
OSC 1337. This is the sole blocker for the `kitty` and `iterm2`
backends (currently `nil` with a planned note).
**Workaround:** none in Lisp (a pure-Lisp PNG encoder is possible but
large: CRC32 + zlib DEFLATE stored blocks + Adler — a stored-block
encoder is ~150 lines and would work without any upstream change).

### 7. `string-prefix?` correctness

**Need:** `(string-prefix? "abcd" "ab")` currently returns `#t`.
**Workaround:** tests compare with `substring`.

## portty / coffer

### 8. Sixel on Windows/ConPTY (already tracked in portty)

portty's inline-image doc notes ConPTY strips DCS, so sixel needs the
bundled `conpty.dll`/`OpenConsole.exe` path. Logo's sixel backend
will inherit whatever portty ships; nothing Logo-side needed.

### 9. (No portty changes needed for v1)

Sixel decode (DCS, palette, Pan/Pad clamping), cell geometry, and
`PORTTY=1`/`PORTTY_WIDTH` env contracts are all already in place and
sufficient for the sixel backend.
