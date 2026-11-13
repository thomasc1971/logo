;; test-editor.lisp - Headless tests for the 21-line procedure editor buffer
(define *test-dir* (or (file-name-directory *load-pathname*) ""))

(set! *load-path* (cons (concat *test-dir* "../lisp/") *load-path*))

(require 'logo)

(use-package 'logo)

(define passed 0)

(define failed 0)

(defun assert-equal (expected actual description)
  (if (equal? expected actual)
    (progn (format #t "PASS: ~a~%" description) (set! passed (+ passed 1)))
    (progn (format #t "FAIL: ~a~%" description)
      (format #t "  Expected: ~s~%" expected)
      (format #t "  Actual:   ~s~%" actual)
      (set! failed (+ failed 1)))))

(defun assert-true (actual description)
  (assert-equal #t (if actual #t #f) description))

(define (line e n) (list-ref (logo-editor-lines e) n))

(define (set-cursor e r c) (logo-editor-set-cursor e r c))

;; ---------------------------------------------------------------------------
;; Page and cursor
;; ---------------------------------------------------------------------------
(define learn (logo-editor-learn))

(assert-equal 21 (length (logo-editor-lines learn))
 "LÆR page has 21 lines")
(assert-equal "begynd " (line learn 0) "LÆR page starts with BEGYND")
(assert-equal 0 (logo-editor-row learn) "cursor starts on the header")
(assert-equal 7 (logo-editor-col learn) "cursor starts after BEGYND")

(define typed (logo-editor-insert-text learn "polygon side antal"))

(assert-equal "begynd polygon side antal" (line typed 0)
 "typing inserts at the cursor")
(assert-equal 25 (logo-editor-col typed) "typing advances the cursor")

(define next (logo-editor-return typed))

(assert-equal 'update (car next) "Return on a non-last line moves down")
(assert-equal 1 (logo-editor-row (cdr next)) "Return moves to the next row")
(assert-equal 0 (logo-editor-col (cdr next)) "Return moves to column zero")

(define last (set-cursor typed 20 0))

(assert-equal 'commit (car (logo-editor-return last))
 "Return on the last page line means A4")

;; Left from the first character goes to the previous line's last character.
(define line1 (logo-editor-insert-text (cdr (logo-editor-return typed)) "frem"))

(define wrapped (logo-editor-move-left (set-cursor line1 1 0)))

(assert-equal 0 (logo-editor-row wrapped) "left at line start wraps up")
(assert-equal 24 (logo-editor-col wrapped)
 "left at line start lands on the previous last character")

;; Right from the last character goes to the next line's first character.
(define from-end (logo-editor-move-right (set-cursor line1 0 24)))

(assert-equal 1 (logo-editor-row from-end) "right at last char wraps down")
(assert-equal 0 (logo-editor-col from-end) "right wraps to column zero")

;; Up/down clamp the column to the target line.
(define short (logo-editor-insert-text (cdr (logo-editor-return typed)) "x"))

(define down (logo-editor-move-down (set-cursor short 0 25)))

(assert-equal 1 (logo-editor-row down) "down moves one row")
(assert-equal 1 (logo-editor-col down) "down clamps to the target line length")

;; ---------------------------------------------------------------------------
;; Insert, delete and line operations
;; ---------------------------------------------------------------------------
(define joined
  (logo-editor-insert-text (cdr (logo-editor-return typed)) "frem"))

(define back (logo-editor-backspace (set-cursor joined 1 0)))

(assert-equal "begynd polygon side antalfrem" (line back 0)
 "Backspace at column zero joins with the previous line")
(assert-equal 0 (logo-editor-row back) "Backspace joins into the previous row")
(assert-equal 25 (logo-editor-col back) "Backspace lands at the join point")

(define del (logo-editor-delete (set-cursor joined 0 25)))

(assert-equal "begynd polygon side antalfrem" (line del 0)
 "Delete at end of line joins the next line")

(define killed (logo-editor-kill-to-end (set-cursor typed 0 7)))

(assert-equal "begynd " (line killed 0) "A1 delete-rest-of-line")

(define three-lines
  (logo-editor-ret (list "begynd x" "   frem 1" "   frem 2" "slut") "X"))

(define deleted-line (logo-editor-delete-line (set-cursor three-lines 1 0)))

(assert-equal "   frem 2" (line deleted-line 1)
 "A2 shifts following lines up")
(assert-equal "" (line deleted-line 20) "A2 leaves a blank last line")

(define inserted-line (logo-editor-insert-line (set-cursor typed 1 0)))

(assert-equal "" (line inserted-line 1) "A3 inserts a blank line")
(assert-equal "begynd polygon side antal" (line inserted-line 0)
 "A3 keeps preceding lines")

(define full
  (logo-editor-ret
   (let loop ((n 0)
              (out nil))
     (if (= n 21) (reverse out) (loop (+ n 1) (cons "x" out))))
   "FULL"))

(assert-equal "For mange linier"
 (logo-editor-error (logo-editor-insert-line full))
 "A3 refuses to lose a non-blank last line")

(define spaced (logo-editor-insert-space (set-cursor typed 0 7)))

(assert-equal "begynd  polygon side antal" (line spaced 0)
 "Insert key inserts one blank")

(define ret (logo-editor-ret (list "begynd x" "   frem 1" "slut") "X"))

(assert-equal "begynd x" (line ret 0) "RET loads the stored source")
(assert-equal "X" (logo-editor-name ret) "RET remembers the procedure name")

(assert-true
 (string-prefix? "begynd x\n   frem 1\nslut" (logo-editor-text ret))
 "editor text joins the page with newlines")

(assert-equal 21 (length (logo-editor-lines ret)) "RET page stays 21 lines")

(format #t "~%Passed: ~a, Failed: ~a~%" passed failed)

(if (> failed 0) (exit 1) (exit 0))
