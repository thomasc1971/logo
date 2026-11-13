;; test-mikro.lisp - Mikro-Logo dialect front end and procedure compiler
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

(defun run-mikro (source)
  (logo-run source 200 200 'mikro))

(defun run-mikro-line (source)
  (logo-run source 200 200 'mikro 'command-line))

;; ---------------------------------------------------------------------------
;; Tokenizer and parser
;; ---------------------------------------------------------------------------
(assert-equal
 '((:word "FREM") (:num 10) (:semicolon) (:word "VENSTRE") (:num 90))
 (logo-mikro-tokenize "frem 10; venstre 90")
 "tokenizer keeps line and command boundaries")
(assert-equal
 '((cmd "FD" 10) (cmd "LT" 90) (cmd "FD" 10))
 (logo-mikro-parse "frem 10; venstre 90; frem 10" 'command-line)
 "command line parses semicolon-separated statements")
(assert-equal
 '((cmd "FD" (:call "QUOTIENT" (360 (:mikro-var "ANTAL")))))
 (logo-mikro-parse "frem 360/antal" 'command-line)
 "infix division")
(assert-equal
 '((cmd "FD" (:call "SUM" ((:list ((:mikro-var "SIDE") 2))))))
 (logo-mikro-parse "frem side+2" 'command-line)
 "infix addition")
(assert-equal
 '((cmd "FD" (:call "MIKRO-POW" (2 10))))
 (logo-mikro-parse "frem 2^10" 'command-line)
 "infix power")
(assert-equal
 '((cmd "FD" (:call "MIKRO-POW" (2 (:call "MIKRO-POW" (3 2))))))
 (logo-mikro-parse "frem 2^3^2" 'command-line)
 "power is right-associative")
(assert-equal
 '((cmd "FD" (:call "PRODUCT" ((:list (2 (:call "SUM" ((:list (3 4))))))))))
 (logo-mikro-parse "frem 2*(3+4)" 'command-line)
 "parentheses and precedence")
(assert-equal
 '((make (:word "X") (:call "SUM" ((:list ((:mikro-var "X") 1))))))
 (logo-mikro-parse "x:=x+1" 'command-line)
 "assignment with :=")
(assert-equal
 '((make (:word "X") 4))
 (logo-mikro-parse "x = 4" 'command-line)
 "assignment with =")
(assert-equal
 '((if (:call "MIKRO-NOT-ZERO" ((:call "MIKRO-LT" ((:mikro-var "X") 10))))
     ((cmd "FD" 10))))
 (logo-mikro-parse "hvis x<10; frem 10; sluthvis" 'command-line)
 "single-line HVIS")

;; ---------------------------------------------------------------------------
;; Interpreter
;; ---------------------------------------------------------------------------
(define polygon
  "begynd polygon side antal
   gentag antal
      frem side
      venstre 360/antal
   hertil
slut
polygon 20 8
")

(define polygon-state (run-mikro polygon))

(assert-true (not (error? polygon-state)) "polygon procedure runs")

(assert-equal 8
 (length
  (canvas-segments (turtle-canvas (logo-interp-turtle polygon-state))))
 "polygon 20 8 draws eight sides")

(define recursive
  "begynd spiral side vinkel
   hvis side>40
      stop
   ellers
      frem side
      venstre vinkel
      spiral side+2 vinkel
   sluthvis
slut
spiral 2 90
")

(define recursive-state (run-mikro recursive))

(assert-true (not (error? recursive-state)) "hvis/ellers/sluthvis and stop run")

(assert-equal 20
 (length
  (canvas-segments (turtle-canvas (logo-interp-turtle recursive-state))))
 "spiral stops after the condition becomes true")

(define repeat-line (run-mikro-line "gentag 4; frem 10; venstre 90; hertil\n"))

(assert-equal 4
 (length (canvas-segments (turtle-canvas (logo-interp-turtle repeat-line))))
 "single-line GENTAG executes")

(define ifelse-line
  (run-mikro-line "hvis 0; frem 10; ellers; frem 20; sluthvis\n"))

(assert-equal 1
 (length (canvas-segments (turtle-canvas (logo-interp-turtle ifelse-line))))
 "single-line HVIS/ELLERS executes the false branch")
(assert-equal 20.0 (turtle-y (logo-interp-turtle ifelse-line))
 "the else branch ran")

(define compare-state (run-mikro "skriv 9*9=81\nskriv 1<2\n"))

(assert-equal '("1" "1")
 (turtle-output (logo-interp-turtle compare-state))
 "relational operators produce numeric truth values")

(define default-state (run-mikro "skriv uinitialiseret+1\n"))

(assert-equal '("1") (turtle-output (logo-interp-turtle default-state))
 "unbound Mikro variables read as 0")

(define zero-state
  (run-mikro "begynd t x\nhvis x\nfrem 10\nsluthvis\nslut\nt 0\nt 1\n"))

(assert-equal 1
 (length (canvas-segments (turtle-canvas (logo-interp-turtle zero-state))))
 "zero is false and non-zero is true")

(define assignment-state (run-mikro "x:=5\nskriv x+2\n"))

(assert-equal '("7") (turtle-output (logo-interp-turtle assignment-state))
 "assignment and expression evaluation")

(define hvor-state
  (run-mikro "frem 10\nhvor x y h\nskriv x\nskriv y\nskriv h\n"))

(assert-equal '("0" "10" "0") (turtle-output (logo-interp-turtle hvor-state))
 "HVOR assigns x, y and heading")

;; ---------------------------------------------------------------------------
;; Procedure compiler
;; ---------------------------------------------------------------------------
(define compiled
  (logo-mikro-compile-lines
   (list "begynd polygon side antal" "gentag antal" "frem side"
    "venstre 360/antal" "hertil")))

(assert-equal 'ok (car compiled) "compiler succeeds")
(assert-equal "POLYGON" (cadr compiled) "compiler returns the name")
(assert-equal '("SIDE" "ANTAL") (caddr compiled) "compiler returns parameters")
(assert-equal
 '("begynd polygon side antal" "   gentag antal" "      frem side"
   "      venstre 360/antal" "   hertil" "slut")
 (list-ref compiled 4)
 "compiler auto-inserts SLUT and indents three spaces per level")

(define no-slut (logo-mikro-compile-lines (list "begynd x" "frem 1")))

(assert-equal 'ok (car no-slut) "compiler accepts a body without SLUT")

(define too-long
  (logo-mikro-compile-lines
   (cons "begynd x"
    (append
     (let loop ((n 0)
                (out nil))
       (if (= n 20) (reverse out) (loop (+ n 1) (cons "frem 1" out))))
     (list "slut")))))

(assert-equal 'error (car too-long) "compiler rejects more than 21 lines")
(assert-equal "For mange linier" (cadr too-long) "line-limit message")

(define too-many-params
  (logo-mikro-compile-lines (list "begynd x a b c d e f g" "slut")))

(assert-equal "Højst 6 parametre" (cadr too-many-params)
 "parameter-limit message")

(define bad-header (logo-mikro-compile-lines (list "to x" "frem 1" "slut")))

(assert-equal "Fejl i begynd" (cadr bad-header) "header error message")

(define two-statements
  (logo-mikro-compile-lines (list "begynd x" "frem 1 venstre 90" "slut")))

(assert-equal 'error (car two-statements)
 "compiler rejects two statements on one line")

(define known (make-hash-table))

(hash-set! known "POLYGON" 2)

(define calls-known
  (logo-mikro-compile-lines
   (list "begynd hus side" "polygon side 4" "slut") known))

(assert-equal 'ok (car calls-known)
 "compiler accepts calls to already-defined procedures")

;; Command-line definitions are forbidden.
(define command-def (logo-mikro-parse "begynd x\nfrem 1\nslut" 'command-line))

(assert-true (error? command-def) "BEGYND is rejected at the command line")

(assert-equal "sætning/begynd/slut er ikke tilladt"
 (error-message command-def) "command-line definition message")

(format #t "~%Passed: ~a, Failed: ~a~%" passed failed)

(if (> failed 0) (exit 1) (exit 0))
