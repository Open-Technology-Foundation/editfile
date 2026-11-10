# Makefile - Install editfile
# BCS1212 compliant

PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
COMPDIR ?= /etc/bash_completion.d
DESTDIR ?=

# This Makefile, and its directory (trailing slash). Sources are anchored to it
# so that 'make -f /path/to/Makefile install' works from any directory and
# never picks up a like-named file from there; the check after install is run
# through the same Makefile for the same reason.
makefile := $(abspath $(lastword $(MAKEFILE_LIST)))
srcdir   := $(dir $(makefile))

.PHONY: all install uninstall check test mutation help

all: help

# A staged install (DESTDIR set) always gets the completion; a direct one only
# where the system has a completion directory
install:
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(srcdir)editfile $(DESTDIR)$(BINDIR)/editfile
	@if [ -n "$(DESTDIR)" ] || [ -d $(COMPDIR) ]; then \
	  install -d $(DESTDIR)$(COMPDIR) && \
	  install -m 644 $(srcdir)editfile.bash_completion $(DESTDIR)$(COMPDIR)/editfile; \
	fi
	@if [ -z "$(DESTDIR)" ]; then $(MAKE) --no-print-directory -f $(makefile) check; fi

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/editfile
	rm -f $(DESTDIR)$(COMPDIR)/editfile

check:
	@command -v editfile >/dev/null 2>&1 || { echo 'editfile: NOT FOUND (check PATH)'; exit 1; }
	@echo 'editfile: OK'

test:
	bash $(srcdir)tests/test_regressions.sh </dev/null

# Slow (minutes): breaks one behaviour at a time and checks that the tests notice
mutation:
	bash $(srcdir)tests/mutate.sh </dev/null

help:
	@echo 'Usage: make [target] [VARIABLE=value ...]'
	@echo ''
	@echo 'Targets:'
	@echo '  install     Install to $(PREFIX)'
	@echo '  uninstall   Remove installed files'
	@echo '  check       Verify installation'
	@echo '  test        Run the regression suite'
	@echo '  mutation    Check that the suite catches deliberate breaks (slow)'
	@echo '  help        Show this message'
	@echo ''
	@echo 'Variables:'
	@echo '  PREFIX      $(PREFIX)'
	@echo '  BINDIR      $(BINDIR)'
	@echo '  COMPDIR     $(COMPDIR)'
	@echo '  DESTDIR     staging root for packaging (empty: install directly)'
	@echo ''
	@echo 'Install from GitHub:'
	@echo '  git clone https://github.com/Open-Technology-Foundation/editfile.git'
	@echo '  cd editfile && sudo make install'
