# editfile Makefile
SCRIPT        = editfile
VERSION       = $(shell grep -m1 "VERSION=" $(SCRIPT) | cut -d"'" -f2)
PREFIX        = /usr/local
BINDIR        = $(PREFIX)/bin
COMPLETIONDIR = /etc/bash_completion.d
DESTDIR       =

FILETYPE_REPO = https://github.com/Open-Technology-Foundation/filetype.git

.PHONY: help install uninstall test check check-deps install-deps

help:
	@echo "editfile v$(VERSION)"
	@echo ""
	@echo "Targets:"
	@echo "  install       Install editfile and bash completion"
	@echo "  uninstall     Remove editfile and bash completion"
	@echo "  test          Run test suite"
	@echo "  check         Run shellcheck on editfile"
	@echo "  check-deps    Check optional validators and python modules"
	@echo "  install-deps  Install filetype package dependency"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX=$(PREFIX)  DESTDIR=$(DESTDIR)"

install:
	@if ! command -v editcmd >/dev/null 2>&1; then \
	  echo "Warning: filetype package not found (editcmd missing)"; \
	  echo "  editfile requires the filetype package to function"; \
	  echo "  Run 'make install-deps' to install it"; \
	fi
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(SCRIPT) $(DESTDIR)$(BINDIR)/$(SCRIPT)
	@if [ -d $(DESTDIR)$(COMPLETIONDIR) ]; then \
	  install -m 644 .bash_completion $(DESTDIR)$(COMPLETIONDIR)/$(SCRIPT); \
	  echo "Installed bash completion to $(DESTDIR)$(COMPLETIONDIR)/$(SCRIPT)"; \
	else \
	  echo "Skipped bash completion ($(COMPLETIONDIR) not found)"; \
	fi
	@echo "Installed $(SCRIPT) to $(DESTDIR)$(BINDIR)/$(SCRIPT)"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(SCRIPT)
	rm -f $(DESTDIR)$(COMPLETIONDIR)/$(SCRIPT)
	@echo "Removed $(SCRIPT) from $(DESTDIR)$(BINDIR)"

test:
	@for t in tests/test_*.sh; do \
	  echo "Running $$t..."; \
	  bash "$$t" || exit 1; \
	done

check:
	shellcheck $(SCRIPT)

check-deps:
	@echo "Validators:"
	@for v in jq yamllint xmllint shellcheck php tidy python3; do \
	  if command -v $$v >/dev/null 2>&1; then \
	    echo "  ✓ $$v"; \
	  else \
	    echo "  ✗ $$v (not installed)"; \
	  fi; \
	done
	@echo ""
	@echo "Python modules:"
	@if command -v python3 >/dev/null 2>&1; then \
	  for m in yaml tomli toml; do \
	    if python3 -c "import $$m" 2>/dev/null; then \
	      echo "  ✓ $$m"; \
	    else \
	      echo "  ✗ $$m (not installed)"; \
	    fi; \
	  done; \
	else \
	  echo "  python3 not available"; \
	fi
	@echo ""
	@echo "Filetype package:"
	@if command -v editcmd >/dev/null 2>&1; then \
	  echo "  ✓ editcmd"; \
	else \
	  echo "  ✗ editcmd (run 'make install-deps')"; \
	fi
	@if command -v filetype >/dev/null 2>&1; then \
	  echo "  ✓ filetype"; \
	else \
	  echo "  ✗ filetype (run 'make install-deps')"; \
	fi

install-deps:
	@if command -v editcmd >/dev/null 2>&1 && command -v filetype >/dev/null 2>&1; then \
	  echo "filetype package already installed"; \
	  exit 0; \
	fi
	@echo "Installing filetype package..."
	$(eval TMPDIR := $(shell mktemp -d))
	git clone --quiet $(FILETYPE_REPO) $(TMPDIR)/filetype
	cd $(TMPDIR)/filetype && sudo ./install.sh
	rm -rf $(TMPDIR)
	@echo "filetype package installed"
