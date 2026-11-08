# Logo - Makefile
#
# This is a pure-Lisp project: Ditty Lisp is the interpreter, there is no C
# to compile. The Makefile only runs tests, examples, and formatting.
#
#   make check         run the test suite
#   make run           run an example (EXAMPLE=examples/star.logo)
#   make format        format all sources in place (per-type formatters)
#   make format-check  verify all sources are formatter-clean (no changes)
#   make clean         remove test/output artefacts
#
# Formatting is per file type (as in ditty/tapestry):
#   *.lisp (+ logo-main.lisp)  Ditty's lisp-fmt (ships with Ditty)
#   emacs/*.el                 Emacs indent-region (batch)
#   bin/logo                   shfmt (extensionless shell script)
#   *.md, docs/*.md            prettier
# Each tool is optional: if it is not installed, that type is skipped
# with a warning (format-check likewise skips what it cannot verify).

DITTY ?= ditty
ROOT := $(shell pwd)

# Library search path: this repo's lisp/, plus whatever the caller put
# on DITTY_LISP_PATH (e.g. an installed Tapestry), so `(require ...)`
# resolves through Ditty's library search path.
LISP_PATH := $(ROOT)/lisp$(if $(DITTY_LISP_PATH),:$(DITTY_LISP_PATH),)

TESTS := $(sort $(wildcard tests/test-*.lisp))

# Sources by formatter. lisp-fmt targets Ditty's dialect, so Emacs Lisp
# (emacs/*.el) is formatted separately with Emacs, never with lisp-fmt.
LISP_SOURCES := lisp/logo.lisp $(sort $(wildcard lisp/logo/*.lisp)) \
  logo-main.lisp $(TESTS)
ELISP_SOURCES := $(sort $(wildcard emacs/*.el))
# bin/logo has no .sh extension, so name it explicitly (find '*.sh'
# would miss it).
SHELL_SOURCES := bin/logo
MD_SOURCES := $(sort $(wildcard *.md docs/*.md))

# lisp-fmt ships with Ditty as a runnable script (it does not provide a
# library, so `(require 'lisp-fmt)` fails). It is installed into the XDG
# data dir ($XDG_DATA_HOME/ditty/lisp, default ~/.local/share/ditty/lisp,
# or /usr/local/share + /usr/share) alongside the ditty binary. The
# first existing candidate wins; override with
# `make format LISP_FMT=/path/to/lisp-fmt.lisp`.
XDG_DATA_HOME ?= $(HOME)/.local/share
LISP_FMT ?= $(firstword $(wildcard \
  $(XDG_DATA_HOME)/ditty/lisp/lisp-fmt.lisp \
  $(HOME)/.local/share/ditty/lisp/lisp-fmt.lisp \
  /usr/local/share/ditty/lisp/lisp-fmt.lisp \
  /usr/share/ditty/lisp/lisp-fmt.lisp))

.PHONY: check run format format-check clean help

check: ## Run the test suite
	@for t in $(TESTS); do \
		echo "== $$t"; \
		DITTY_LISP_PATH="$(LISP_PATH)" $(DITTY) "$$t" || exit 1; \
	done
	@echo "All tests passed."

run: ## Run an example: make run EXAMPLE=examples/star.logo
	@DITTY_LISP_PATH="$(LISP_PATH)" $(DITTY) logo-main.lisp -- $(EXAMPLE)

tui: ## Launch the interactive TUI
	@DITTY_LISP_PATH="$(LISP_PATH)" $(DITTY) logo-main.lisp

format: ## Format all sources in place (per-type formatters)
	@if [ -z "$(LISP_FMT)" ]; then \
		echo "lisp-fmt not found. Searched the XDG data dirs and"; \
		echo "/usr/local/share + /usr/share (where an installed Ditty puts it)."; \
		echo "Install Ditty, or pass LISP_FMT=/path/to/lisp-fmt.lisp"; exit 1; \
	fi
	@echo "Formatting Ditty Lisp with lisp-fmt ($(LISP_FMT))..."
	@$(DITTY) "$(LISP_FMT)" -- -i $(LISP_SOURCES)
	@if command -v emacs >/dev/null 2>&1; then \
		echo "Formatting Emacs Lisp with emacs (indent-region)..."; \
		emacs --batch --eval '(dolist (f (list $(foreach f,$(ELISP_SOURCES),"$(f)"))) (find-file f) (indent-region (point-min) (point-max)) (save-buffer))' 2>/dev/null; \
	else \
		echo "emacs not found - skipping Elisp formatting." >&2; \
	fi
	@if command -v shfmt >/dev/null 2>&1; then \
		echo "Formatting shell scripts with shfmt..."; \
		shfmt -w $(SHELL_SOURCES); \
	else \
		echo "shfmt not found - skipping shell script formatting." >&2; \
	fi
	@if command -v prettier >/dev/null 2>&1; then \
		echo "Formatting Markdown with prettier..."; \
		prettier --write $(MD_SOURCES) >/dev/null; \
	else \
		echo "prettier not found - skipping Markdown formatting." >&2; \
	fi

format-check: ## Verify all sources are formatter-clean (no changes)
	@if [ -z "$(LISP_FMT)" ]; then \
		echo "lisp-fmt not found (see make format)"; exit 1; \
	fi
	@status=0; \
	for f in $(LISP_SOURCES); do \
		if ! $(DITTY) "$(LISP_FMT)" -- "$$f" | cmp -s - "$$f"; then \
			echo "NOT FORMATTED: $$f (run: make format)"; status=1; \
		fi; \
	done; \
	if command -v emacs >/dev/null 2>&1; then \
		for f in $(ELISP_SOURCES); do \
			tmp=$$(mktemp); cp $$f $$tmp; \
			emacs --batch --eval "(find-file \"$$tmp\") (indent-region (point-min) (point-max)) (save-buffer)" >/dev/null 2>&1; \
			cmp -s $$f $$tmp || { echo "NOT FORMATTED: $$f (run: make format)"; status=1; }; \
			rm -f $$tmp; \
		done; \
	else \
		echo "emacs not found - skipping Elisp check." >&2; \
	fi; \
	if command -v shfmt >/dev/null 2>&1; then \
		for f in $(SHELL_SOURCES); do \
			if [ -n "$$(shfmt -d $$f)" ]; then \
				echo "NOT FORMATTED: $$f (run: make format)"; status=1; \
			fi; \
		done; \
	else \
		echo "shfmt not found - skipping shell script check." >&2; \
	fi; \
	if command -v prettier >/dev/null 2>&1; then \
		prettier --check $(MD_SOURCES) >/dev/null 2>&1 || { echo "NOT FORMATTED: some Markdown (run: make format)"; status=1; }; \
	else \
		echo "prettier not found - skipping Markdown check." >&2; \
	fi; \
	if [ $$status -eq 0 ]; then echo "All sources are formatter-clean."; fi; \
	exit $$status

clean: ## Remove generated artefacts
	rm -f /tmp/logo-*.out

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'
