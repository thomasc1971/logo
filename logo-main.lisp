;; logo-main.lisp - Command-line entry point for Logo
;;
;; Run via bin/logo (which sets DITTY_LISP_PATH), or directly:
;;   ditty logo-main.lisp -- FILE.logo
;;   ditty logo-main.lisp -- -e "FD 100 RT 90 FD 100"
;;   ditty logo-main.lisp                     ; interactive TUI
;;
;; *command-line-args* is set by ditty to the args after `--`.
;;
;; The interactive path requires Tapestry BEFORE Logo: tui.lisp refers to
;; Tapestry symbols qualified (tapestry:...), and Ditty's reader resolves
;; pkg:symbol against packages that exist at read time. Headless paths
;; do not need Tapestry at all.
(if (null? *command-line-args*)
  (require 'tapestry))

(require 'logo)

(use-package 'logo)

(define *logo-version* "0.1.0")

(defun logo-usage ()
  "Print usage and exit."
  (princ
   (concat
    "logo " *logo-version* " - Logo turtle graphics (Ditty Lisp)\n"
    "\n"
    "Usage:\n"
    "  logo                  Interactive TUI (Tapestry)\n"
    "  logo FILE.logo        Run a Logo program, print the picture\n"
    "  logo -e \"CODE\"      Run Logo code, print the picture\n"
    "  logo --backend B FILE Run with graphics backend B\n"
    "                        (canvas [default], sixel, kitty, iterm2)\n"
    "  logo --help           This message\n"
    "  logo --version        Print version\n")))

(defun logo-render-and-print (state backend)
  "Render STATE's canvas with BACKEND and print picture + transcript.
   STATE may be an error object (parse/eval/file errors arrive as
   values); report it cleanly and exit non-zero instead of crashing
   while destructuring it as a state."
  (if (error? state)
    (progn (princ (format nil "Error: ~a~%" (error-message state))) (exit 1))
    (logo-render-state state backend)))

(defun logo-render-state (state backend)
  "Render a valid STATE's canvas with BACKEND and print picture + transcript."
  (let* ((turtle (logo-interp-turtle state))
         (canvas (turtle-canvas turtle)))
    (if (eq? backend 'sixel)
      (progn (princ (logo-render-sixel canvas 480 360)) (princ "\n"))
      (let ((lines (canvas->braille-lines canvas 60 15)))
        (let loop ((rest lines))
          (if (null? rest)
            nil
            (progn (princ (car rest)) (princ "\n")
              (loop (cdr rest)))))))
    (let loop ((rest (turtle-output turtle)))
      (if (null? rest)
        nil
        (progn (princ (car rest)) (princ "\n")
          (loop (cdr rest)))))))

(defun logo-main ()
  "Dispatch on *command-line-args*."
  (let ((args *command-line-args*))
    (cond
      ((null? args)
       (logo-tui-main))
      ((or (equal? (car args) "--help") (equal? (car args) "-h"))
       (logo-usage))
      ((or (equal? (car args) "--version") (equal? (car args) "-V"))
       (princ (concat "logo " *logo-version* "\n")))
      (#t
       ;; Parse options: --backend B, -e CODE, FILE...
       (let loop ((rest args)
                  (backend 'canvas)
                  (code nil)
                  (files nil))
         (if (null? rest)
           (cond
             (code
              (logo-render-and-print (logo-run code) backend))
             ((not (null? files))
              (let ((state (logo-run-file (car files))))
                (logo-render-and-print state backend)))
             (#t (progn (logo-usage) (exit 1))))
           (let ((arg (car rest)))
             (cond
               ((equal? arg "--backend")
                (loop (cddr rest)
                 (if (equal? (cadr rest) "sixel")
                   'sixel
                   (if (equal? (cadr rest) "kitty")
                     'kitty
                     (if (equal? (cadr rest) "iterm2") 'iterm2 'canvas)))
                 code files))
               ((equal? arg "-e")
                (loop (cddr rest) backend (cadr rest) files))
               (#t
                (loop (cdr rest) backend code (append files (list arg))))))))))))

(logo-main)
