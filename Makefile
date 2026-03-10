# Makefile - Install editfile
# BCS1212 compliant

PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
COMPDIR ?= /etc/bash_completion.d
DESTDIR ?=

.PHONY: all install uninstall check test help

all: help

install:
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 editfile $(DESTDIR)$(BINDIR)/editfile
	@if [ -d $(DESTDIR)$(COMPDIR) ]; then \
	  install -m 644 .bash_completion $(DESTDIR)$(COMPDIR)/editfile; \
	fi
	@if [ -z "$(DESTDIR)" ]; then $(MAKE) --no-print-directory check; fi

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/editfile
	rm -f $(DESTDIR)$(COMPDIR)/editfile

check:
	@command -v editfile >/dev/null 2>&1 \
	  && echo 'editfile: OK' \
	  || echo 'editfile: NOT FOUND (check PATH)'

test:
	@for t in tests/test_*.sh; do bash "$$t" || exit 1; done

help:
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@echo '  install     Install to $(PREFIX)'
	@echo '  uninstall   Remove installed files'
	@echo '  check       Verify installation'
	@echo '  test        Run test suite'
	@echo '  help        Show this message'
	@echo ''
	@echo 'Install from GitHub:'
	@echo '  git clone https://github.com/Open-Technology-Foundation/editfile.git'
	@echo '  cd editfile && sudo make install'
