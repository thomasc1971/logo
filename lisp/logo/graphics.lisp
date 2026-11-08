;; graphics.lisp - Terminal graphics backends
;;
;; The canvas (canvas.lisp) is backend-independent. This module turns a
;; canvas into bytes for a specific terminal:
;;
;;   canvas   Braille text (U+2800). Works in EVERY terminal, including the
;;            RC759's spiritual successors. Default and fallback.
;;   sixel    DCS sixel bitmap (binary alpha, palette). Implemented here.
;;            portty (via coffer) decodes it; see
;;            portty/docs/inline-image-architecture.md.
;;   kitty    Kitty graphics protocol (APC G, PNG payload). PLANNED:
;;            needs a PNG encoder (zlib + base64), which Ditty does not
;;            provide yet. See docs/UPSTREAM.md.
;;   iterm2   iTerm2 inline images (OSC 1337, base64 PNG). PLANNED, same
;;            PNG pipeline as kitty.
;;
;; Capability detection is environment-based (PORTTY=1 is set by portty's
;; PTY layer, KITTY_WINDOW_ID by kitty, TERM_PROGRAM by iTerm2). A DA1 /
;; XTSMGRAPHICS query would be more robust; that needs a Ditty builtin to
;; read query replies, proposed in docs/UPSTREAM.md.
;;
;; Internal file: loaded by logo.lisp into the `logo` package.
(provide 'logo-graphics)

(defun logo-graphics-capabilities ()
  "Return an alist of graphics capabilities for the current terminal:
   (:sixel . #t/#f) (:kitty . #t/#f) (:iterm2 . #t/#f) (:canvas . #t)"
  (let* ((portty (getenv "PORTTY"))
         (kitty (getenv "KITTY_WINDOW_ID"))
         (term-program (getenv "TERM_PROGRAM"))
         (term (getenv "TERM")))
    (list
     (cons 'sixel
      (if
        (or (equal? portty "1")
            (and term (string-contains? (string-downcase term) "sixel")))
        #t
        #f))
     (cons 'kitty (if kitty #t #f))
     (cons 'iterm2 (if (equal? term-program "iTerm.app") #t #f))
     (cons 'canvas #t))))

(defun logo-graphics-backend ()
  "Return the best graphics backend symbol for this terminal.
   Prefers sixel (real pixels in portty), else canvas."
  (let* ((caps (logo-graphics-capabilities)))
    (if (cdr (assoc 'sixel caps)) 'sixel 'canvas)))

(defun logo-render (canvas backend cols rows &optional pixel-w pixel-h)
  "Render CANVAS with BACKEND. COLS/ROWS are character cells for canvas;
   PIXEL-W/PIXEL-H are pixels for sixel. Returns a string, or nil if the
   backend is not yet implemented (kitty, iterm2)."
  (cond
    ((eq? backend 'canvas) (canvas->braille-lines canvas cols rows))
    ((eq? backend 'sixel)
     (logo-render-sixel canvas (or pixel-w 480) (or pixel-h 360)))
    ((or (eq? backend 'kitty) (eq? backend 'iterm2)) nil)
    (#t (error (format nil "unknown graphics backend: ~a" backend)))))

;; ---------------------------------------------------------------------------
;; Sixel encoder
;; ---------------------------------------------------------------------------
(defun logo-render-sixel (canvas width height)
  "Encode CANVAS as a DCS sixel string of WIDTH x HEIGHT pixels.
   Single-color palette (index 1 = white, 0 = black background).
   Includes the Pan/Pad raster attributes (\"1;1;W;H) so coffer clamps
   the image to its declared size instead of rounding up to 6-row bands."
  (let* ((grid (canvas-rasterize canvas width height)))
    (let* ((out ""))
      (set! out (concat out "\033P9;1;0q")) ; DCS, sixel, no scrolling
      (set! out
       (concat out "\"1;1;" (number->string width) ";" (number->string height)))
      (set! out (concat out "#1;2;100;100;100")) ; palette: 1 = white
      (set! out (concat out "#0;2;0;0;0")) ; palette: 0 = black
      (set! out (concat out "#1")) ; select color 1
      (let loop ((band 0))
        (if (>= (* band 6) height)
          out
          (progn
            (set! out (concat out (logo-sixel-pad-line grid band width height)))
            (set! out (concat out "$"))
            (loop (+ band 1)))))
      (concat out "\033\\")))) ; ST

(defun logo-sixel-pad-line (grid band width height)
  "Build one sixel band line: '?' for empty columns, 63+bits for set ones."
  (let* ((line ""))
    (do ((x 0 (+ x 1))) ((>= x width) line)
      (let* ((bits 0))
        (do ((r 0 (+ r 1))) ((>= r 6))
          (let* ((y (+ (* band 6) r)))
            (when (and (< y height) (= (vector-ref (vector-ref grid y) x) 1))
              (set! bits (+ bits (ash 1 r))))))
        (set! line (concat line (char->string (code-char (+ 63 bits)))))))
    ;; Trim trailing '?' (empty sixels) for compactness.
    (let loop ((s line))
      (if (and (> (length s) 0) (char=? (string-ref s (- (length s) 1)) #\?))
        (loop (substring s 0 (- (length s) 1)))
        s))))
