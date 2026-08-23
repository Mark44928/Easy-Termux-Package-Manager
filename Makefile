# Easy Termux Package Manager — developer tasks
# Termux: pkg install make shellcheck  (make is not preinstalled)
# All targets work from any cwd; paths are relative to this Makefile.

PREFIX ?= /data/data/com.termux/files/usr
BIN    := $(PREFIX)/bin/pkg-manager

SHELL_SCRIPTS := manager.sh install.sh tests/run-tests.sh $(wildcard tests/fakebin/*)

.PHONY: help run test lint check install uninstall clean

help: ## Show available targets
	@printf 'Easy Termux Package Manager — make targets:\n\n'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

run: ## Launch the app (text mode: GUM_ENABLED=0 make run)
	bash manager.sh

test: ## Run the full scenario suite (130 tests, ~2 min)
	bash tests/run-tests.sh

lint: ## bash -n + shellcheck on every shell script
	@set -e; for f in $(SHELL_SCRIPTS); do bash -n "$$f"; done
	@shellcheck --shell=bash --severity=style $(SHELL_SCRIPTS)
	@echo "lint OK"

check: lint test ## lint + test

install: ## Install to PREFIX/bin/pkg-manager via install.sh
	bash install.sh

uninstall: ## Remove the installed binary (keeps ~/ config/log/favs)
	rm -f "$(BIN)"
	@echo "Removed $(BIN)"

clean: ## Delete test artifacts (tests/tmp)
	rm -rf tests/tmp
