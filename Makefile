# aura-glass — development and maintenance Makefile
.POSIX:
.PHONY: all test check doctor lint install-hooks clean help

SHELL := /usr/bin/env bash
JOBS ?= $(shell nproc 2>/dev/null || echo 4)

all: test

test:
	@echo "==> Running Aura Glass test suite (-j $(JOBS))..."
	@./tools/check-all.sh -j $(JOBS)

check:
	@echo "==> Running pre-commit validation..."
	@./tools/hooks/pre-commit

doctor:
	@./bin/aura-glass-doctor

lint:
	@echo "==> Validating shell syntax..."
	@bash -n $$(find . -type f \( -name '*.sh' -o -name '*.bash' -o -path './bin/*' -o -path './tools/hooks/*' \))
	@echo "==> Validating python syntax..."
	@python3 -m py_compile $$(find . -type f -name '*.py')
	@echo "    ✓ all syntax checks passed"

install-hooks:
	@./tools/install-hooks.sh

clean:
	@echo "==> Cleaning temporary files..."
	@find . -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name '*.pyc' -delete 2>/dev/null || true
	@echo "    ✓ clean completed"

help:
	@echo "Aura Glass developer commands:"
	@echo "  make test           run all test suites in parallel"
	@echo "  make check          run staged git pre-commit checks"
	@echo "  make doctor         run system health and environment diagnostics"
	@echo "  make lint           check shell and python syntax across the repository"
	@echo "  make install-hooks  install git pre-commit hooks"
	@echo "  make clean          remove python bytecode and temporary caches"
