;; test-command-line.lisp - Headless tests for the command line buffer
;;
;; The RC759 command line is one line with a movable cursor (manual §3);
;; these tests exercise the buffer operations without Tapestry.
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

(define (text cl) (logo-command-line-text cl))

(define (at cl) (logo-command-line-cursor cl))

;; ---------------------------------------------------------------------------
;; Creation and cursor clamping
;; ---------------------------------------------------------------------------
(define empty (logo-command-line-make))

(assert-equal "" (text empty) "a new line is empty")
(assert-equal 0 (at empty) "an empty line has the cursor at zero")

(define typed (logo-command-line-make "frem 100"))

(assert-equal "frem 100" (text typed) "make stores the text")
(assert-equal 8 (at typed) "make puts the cursor at the end")

;; ---------------------------------------------------------------------------
;; Moving (manual §3: arrows, start, end)
;; ---------------------------------------------------------------------------
(define left (logo-command-line-left typed))

(assert-equal 7 (at left) "left moves the cursor one position left")
(assert-equal "frem 100" (text left) "moving left leaves the text")

(define leftmost
  (let loop ((cl typed)
             (n 0))
    (if (>= n 20) cl (loop (logo-command-line-left cl) (+ n 1)))))

(assert-equal 0 (at leftmost) "left clamps at the start of the line")

(define rightmost
  (let loop ((cl leftmost)
             (n 0))
    (if (>= n 20) cl (loop (logo-command-line-right cl) (+ n 1)))))

(assert-equal 8 (at rightmost) "right clamps at the end of the line")
(assert-equal 0 (at (logo-command-line-start typed))
 "start moves the cursor to the start of the line")
(assert-equal 8 (at (logo-command-line-finish leftmost))
 "finish moves the cursor to the end of the line")

;; ---------------------------------------------------------------------------
;; TEGN IND, typing, SLET TEGN and backspace
;; ---------------------------------------------------------------------------
(define home (logo-command-line-start typed))

(define spaced (logo-command-line-insert-space home))

(assert-equal " frem 100" (text spaced)
 "TEGN IND inserts a blank at the cursor")
(assert-equal 1 (at spaced) "TEGN IND leaves the cursor after the blank")

(define inserted (logo-command-line-insert-text home "slet; "))

(assert-equal "slet; frem 100" (text inserted)
 "typing inserts at the cursor, not at the end")
(assert-equal 6 (at inserted) "typing leaves the cursor after the text")

(define under (logo-command-line-delete inserted))

(assert-equal "slet; rem 100" (text under)
 "SLET TEGN deletes the char at the cursor")
(assert-equal 6 (at under) "SLET TEGN leaves the cursor in place")

(define back (logo-command-line-backspace inserted))

(assert-equal "slet;frem 100" (text back)
 "backspace deletes the character left of the cursor")
(assert-equal 5 (at back) "backspace moves the cursor left")
(assert-equal "slet; frem 100"
 (text (logo-command-line-backspace (logo-command-line-start inserted)))
 "backspace at column zero does nothing")

(define at-end (logo-command-line-finish typed))

(assert-equal "frem 10" (text (logo-command-line-backspace at-end))
 "backspace at the end deletes the last character")

;; ---------------------------------------------------------------------------
;; A1: kill the rest of the line
;; ---------------------------------------------------------------------------
(define killed (logo-command-line-kill-to-end left))

(assert-equal "frem 10" (text killed) "A1 deletes the rest of the line")
(assert-equal 7 (at killed) "A1 leaves the cursor where it stood")
(assert-equal ""
 (text (logo-command-line-kill-to-end (logo-command-line-start typed)))
 "A1 at the start clears the line")

;; ---------------------------------------------------------------------------
;; Replacement and stale cursors
;; ---------------------------------------------------------------------------
(define replaced (logo-command-line-set typed "ho"))

(assert-equal "ho" (text replaced) "set replaces the text")
(assert-equal 2 (at replaced) "set puts the cursor at the end")
(assert-equal "hojem" (text (logo-command-line-insert-text replaced "jem"))
 "typing after set builds on the new text")
(assert-equal 0 (at (logo-command-line-left (logo-command-line-make "x")))
 "left from one character lands on column zero")

;; A cursor past the end is clamped rather than ignored.
(define stale (logo-command-line-with typed "ho" 9))

(assert-equal 2 (at stale) "a stale cursor is clamped to the new length")

(format #t "~%Passed: ~a, Failed: ~a~%" passed failed)

(if (> failed 0) (exit 1) 0)
