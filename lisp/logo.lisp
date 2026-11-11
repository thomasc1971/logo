;; logo.lisp - Public API for the Logo interpreter
;;
;; Single entry point, in the style of Tapestry's tapestry.lisp: defines the
;; `logo` package, loads the internal modules into it, exports the curated
;; public API.
;;
;; Usage:
;;   (require 'logo)
;;   (use-package 'logo)
;;   (logo-run "FD 100 RT 90 FD 100")
;;
;; Internal modules (math, canvas, turtle, primitives, parser, interpreter,
;; graphics, tui) are loaded here and are not meant to be loaded directly.
;;
;; Ditty's `terminal` library (graphics capability detection) ships with
;; Ditty, so it is required here: headless code may use it, unlike Tapestry.
;; The require must precede reading any file that mentions `terminal:` —
;; Ditty's reader resolves package-qualified symbols against packages that
;; exist at read time.
(require 'terminal)

(in-package "logo")

(define *logo-dir* (or (file-name-directory *load-pathname*) "./"))

(load (concat *logo-dir* "logo/math.lisp"))
(load (concat *logo-dir* "logo/canvas.lisp"))
(load (concat *logo-dir* "logo/turtle.lisp"))
(load (concat *logo-dir* "logo/primitives.lisp"))
(load (concat *logo-dir* "logo/parser.lisp"))
(load (concat *logo-dir* "logo/interpreter.lisp"))
(load (concat *logo-dir* "logo/graphics.lisp"))
(load (concat *logo-dir* "logo/tui.lisp"))

(export
 ;; math.lisp
 'logo-pi 'logo-deg->rad 'logo-rad->deg 'logo-normalize-heading
 ;; canvas.lisp
 'canvas-make 'canvas-width 'canvas-height 'canvas-segments
 'canvas-background 'canvas-add-segment 'canvas-clear 'canvas-bounds
 'canvas-rasterize 'canvas->braille-lines
 ;; turtle.lisp
 'turtle-make 'turtle-x 'turtle-y 'turtle-heading 'turtle-pen-down?
 'turtle-pen-color 'turtle-visible? 'turtle-canvas 'turtle-output
 'turtle-with 'turtle-forward 'turtle-move-to 'turtle-turn
 'turtle-set-heading 'turtle-clear 'turtle-home 'turtle-print
 ;; primitives.lisp
 'logo-primitive-arity
 ;; parser.lisp
 'logo-tokenize 'logo-parse
 ;; interpreter.lisp
 'logo-interp-make 'logo-interp-turtle 'logo-run 'logo-run-file
 'logo-eval-program 'logo-truthy?
 ;; graphics.lisp
 'logo-graphics-capabilities 'logo-graphics-backend 'logo-render
 'logo-render-sixel 'logo-graphics-capabilities-from
 'logo-graphics-backend-from 'logo-graphics-cell-size
 'logo-graphics-pixel-size
 ;; tui.lisp
 'logo-tui-main 'logo-repl-eval)

(provide 'logo)
