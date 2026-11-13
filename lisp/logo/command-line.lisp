;; command-line.lisp - Headless Mikro-Logo command line buffer
;;
;; The RC759 command line is one line with a freely movable cursor
;; (manual §3): left/right, start/end, TEGN IND, SLET TEGN, backspace,
;; A1 (kill to end), and F1 recall. This module owns the buffer and the
;; cursor-editing semantics; tui.lisp maps terminal keys to these
;; operations and renders the inverse-video block cursor.
;;
;; State is a cons: (TEXT . CURSOR), where CURSOR is an index between 0
;; and (length TEXT) inclusive, the position of the block cursor. The
;; index counts characters, so multi-byte Danish letters take one place.
;;
;; Internal file: loaded by logo.lisp into the `logo` package.
(provide 'logo-command-line)

(defun logo-command-line-make (&optional text)
  "Create a command line holding TEXT with the cursor at the end."
  (let* ((s (if (null? text) "" text)))
    (cons s (length s))))

(defun logo-command-line-text (cl)
  (car cl))

(defun logo-command-line-cursor (cl)
  (cdr cl))

(defun logo-command-line-clamp (text cursor)
  "Clamp CURSOR to a valid index into TEXT."
  (max 0 (min (length text) cursor)))

(defun logo-command-line-with (cl text cursor)
  "Return CL holding TEXT with CURSOR clamped to the new text."
  (cons text (logo-command-line-clamp text cursor)))

(defun logo-command-line-set (cl text)
  "Replace CL's text with TEXT and put the cursor at the end."
  (logo-command-line-make text))

(defun logo-command-line-left (cl)
  "Move the cursor one position left, if possible (manual §3)."
  (logo-command-line-with cl (logo-command-line-text cl)
   (- (logo-command-line-cursor cl) 1)))

(defun logo-command-line-right (cl)
  "Move the cursor one position right, if possible (manual §3)."
  (logo-command-line-with cl (logo-command-line-text cl)
   (+ (logo-command-line-cursor cl) 1)))

(defun logo-command-line-start (cl)
  "Move the cursor to the start of the line (manual §3: up arrow)."
  (logo-command-line-with cl (logo-command-line-text cl) 0))

(defun logo-command-line-finish (cl)
  "Move the cursor to the end of the line (manual §3: down arrow)."
  (let* ((text (logo-command-line-text cl)))
    (logo-command-line-with cl text (length text))))

(defun logo-command-line-insert-text (cl text)
  "Insert TEXT at the cursor and leave the cursor after it."
  (let* ((s (logo-command-line-text cl))
         (at (logo-command-line-clamp s (logo-command-line-cursor cl)))
         (new (concat (substring s 0 at) text (substring s at (length s)))))
    (logo-command-line-with cl new (+ at (length text)))))

(defun logo-command-line-insert-space (cl)
  "Insert one blank at the cursor (manual §3: TEGN IND)."
  (logo-command-line-insert-text cl " "))

(defun logo-command-line-backspace (cl)
  "Delete the character left of the cursor and move it left (manual §3)."
  (let* ((s (logo-command-line-text cl))
         (at (logo-command-line-clamp s (logo-command-line-cursor cl))))
    (if (= at 0)
      (logo-command-line-with cl s at)
      (logo-command-line-with cl
       (concat (substring s 0 (- at 1)) (substring s at (length s)))
       (- at 1)))))

(defun logo-command-line-delete (cl)
  "Delete the character under the cursor (manual §3: SLET TEGN)."
  (let* ((s (logo-command-line-text cl))
         (at (logo-command-line-clamp s (logo-command-line-cursor cl))))
    (if (>= at (length s))
      (logo-command-line-with cl s at)
      (logo-command-line-with cl
       (concat (substring s 0 at) (substring s (+ at 1) (length s))) at))))

(defun logo-command-line-kill-to-end (cl)
  "Delete the rest of the line from the cursor (manual §3: A1)."
  (let* ((s (logo-command-line-text cl))
         (at (logo-command-line-clamp s (logo-command-line-cursor cl))))
    (logo-command-line-with cl (substring s 0 at) at)))
